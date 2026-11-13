import Foundation
import SwiftData

/// 资产页需要的一次性聚合结果。
struct AssetSummary {
    /// 账户 → 欠多少（正数）。负债账户都有值，储蓄为 0。
    let oweByAccount: [PersistentIdentifier: Decimal]
    /// 我欠合计（正数）。
    let owe: Decimal
    /// 信用组那行明细（`本月要还 …`）。
    let dueLine: DueLine?
    /// 账户 → 逾期天数，浮层里把「较上月」换成「逾期 N 天」。
    let overdueDays: [PersistentIdentifier: Int]
}

/// 资产页聚合（M3-8）。
///
/// **为什么单独一个文件**：这套聚合原来写在 `AssetsView.refresh()` 里，
/// 加了账单之后闭包叠了三层，编译器直接报
/// `unable to type-check this expression in reasonable time`（CI run 57/58）。
/// 挪出来还有个正经好处：AGENTS 7.3 要求钱相关逻辑不夹在视图里，
/// 这样它也能被单测直接调。
enum AssetSummaryService {
    static func make(
        accounts: [Account],
        installments: [Installment],
        periods: [InstallmentPeriod],
        bills: [BillStatement],
        alertsEnabled: Bool,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> AssetSummary {
        let periodsByAccount = groupPeriodsByAccount(installments: installments, periods: periods)
        let billsByAccount = groupBillsByAccount(bills: bills)

        // 「我欠」显示层派生：每张负债卡取 max(余额欠额, 未还账单 + 覆盖日之后的分期)。
        let coveredKeys = Set(installments.filter(\.createdFromEntry).map(\.key))
        var oweByAccount: [PersistentIdentifier: Decimal] = [:]
        for account in accounts where account.kind.isLiability {
            let input = debtInput(
                for: account,
                bills: billsByAccount[account.persistentModelID] ?? [],
                periods: periodsByAccount[account.persistentModelID] ?? [],
                coveredKeys: coveredKeys
            )
            oweByAccount[account.persistentModelID] = CardDebt.owe(input, calendar: calendar)
        }
        let owe = oweByAccount.values.reduce(Decimal.zero) { $0 + $1 }

        let due = dueLine(
            accounts: accounts,
            periodsByAccount: periodsByAccount,
            billsByAccount: billsByAccount,
            alertsEnabled: alertsEnabled,
            today: today,
            calendar: calendar
        )

        return AssetSummary(
            oweByAccount: oweByAccount,
            owe: owe,
            dueLine: due.line,
            overdueDays: due.overdueDays
        )
    }

    // MARK: - 分组

    /// 期表只记 `installmentKey`，先折回账户再按账户分组。
    static func groupPeriodsByAccount(
        installments: [Installment],
        periods: [InstallmentPeriod]
    ) -> [PersistentIdentifier: [InstallmentPeriod]] {
        var accountOfPlan: [String: Account] = [:]
        for installment in installments {
            if let account = installment.account { accountOfPlan[installment.key] = account }
        }
        var map: [PersistentIdentifier: [InstallmentPeriod]] = [:]
        for period in periods {
            guard let account = accountOfPlan[period.installmentKey] else { continue }
            map[account.persistentModelID, default: []].append(period)
        }
        return map
    }

    static func groupBillsByAccount(bills: [BillStatement]) -> [PersistentIdentifier: [BillStatement]] {
        var map: [PersistentIdentifier: [BillStatement]] = [:]
        for bill in bills {
            guard let account = bill.account else { continue }
            map[account.persistentModelID, default: []].append(bill)
        }
        return map
    }

    /// 单卡的欠款输入。
    ///
    /// - `coveredKeys`：在「记一笔」里跟消费一起建的计划（消费全额已进余额），
    ///   它们的期**不参与**账期那一项，否则欠款翻倍（`CardDebt` 顶部的例外说明）。
    static func debtInput(
        for account: Account,
        bills: [BillStatement],
        periods: [InstallmentPeriod],
        coveredKeys: Set<String> = []
    ) -> CardDebtInput {
        let billSnapshots: [DebtBill] = bills.map { bill in
            DebtBill(dueAmount: bill.dueAmount, dueDate: bill.dueDate, isPaid: bill.isPaid)
        }
        let periodSnapshots: [DebtPeriod] = periods
            .filter { $0.paidAt == nil }
            .map { period in
                DebtPeriod(
                    amount: period.amount,
                    dueDate: period.dueDate,
                    isPaid: false,
                    isCoveredByBalance: coveredKeys.contains(period.installmentKey)
                )
            }
        return CardDebtInput(
            balance: account.currentBalance,
            bills: billSnapshots,
            periods: periodSnapshots
        )
    }

    // MARK: - 本月要还

    private struct DueResult {
        let line: DueLine?
        let overdueDays: [PersistentIdentifier: Int]
    }

    /// 信用组「本月要还」。
    ///
    /// 口径只有一条：**每张卡产出**一个 `AccountDue`（`DueMath` 保证账单与分期
    /// 不会被相加），组里再 Σ 一次。
    private static func dueLine(
        accounts: [Account],
        periodsByAccount: [PersistentIdentifier: [InstallmentPeriod]],
        billsByAccount: [PersistentIdentifier: [BillStatement]],
        alertsEnabled: Bool,
        today: Date,
        calendar: Calendar
    ) -> DueResult {
        let creditAccounts = accounts.filter { $0.kind == .credit }
        guard !creditAccounts.isEmpty else {
            return DueResult(line: nil, overdueDays: [:])
        }

        var dues: [AccountDue] = []
        var days: [PersistentIdentifier: Int] = [:]

        for account in creditAccounts {
            // 只把未还的账单交给口径层；已还的那期不再参与金额。
            let billDues: [BillDue] = (billsByAccount[account.persistentModelID] ?? [])
                .filter { !$0.isPaid }
                .map { BillDue(amount: $0.dueAmount, dueDate: $0.dueDate) }

            let entries: [DueEntry] = (periodsByAccount[account.persistentModelID] ?? []).map { period in
                DueEntry(amount: period.amount, dueDate: period.dueDate, isPaid: period.paidAt != nil)
            }

            guard let due = DueMath.accountDue(
                bills: billDues,
                installments: entries,
                today: today,
                calendar: calendar
            ) else { continue }

            dues.append(due)
            if due.isOverdue { days[account.persistentModelID] = due.overdueDays }
        }

        var line = DueMath.group(dues).map { DueMath.line($0, calendar: calendar) }

        // 「逾期标红」关掉时，红字与浮层天数一起收掉。金额不受影响——
        // 开关管的是「提醒」，不是「口径」。
        if !alertsEnabled {
            line = line.map { DueLine(text: $0.text, overdueText: nil) }
            days = [:]
        }

        return DueResult(line: line, overdueDays: days)
    }
}
