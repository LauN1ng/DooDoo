import Foundation

/// 卡详情指标区的三个数（账户详情页规格 3.1）。
struct DetailMetrics: Equatable, Sendable {
    /// 单位：元。欠款（正数）。口径在 `CardDebt`。
    let owe: Decimal

    /// 单位：元。本期账单应还。`nil` = 这期还没录账单。
    let billDue: Decimal?

    /// 单位：元。本月到期的分期合计（未还的期）。
    let monthInstallment: Decimal

    /// 单位：元。本月要还——**账单优先**，没账单才用分期（PRD 9.12）。
    /// 本期账单已还时为 `nil`：白条不该继续催。
    let monthDue: Decimal?

    /// 本月要还那笔的还款日。
    let monthDueDate: Date?

    /// 单位：元。本期消费。
    ///
    /// - **有本期账单**：账单 − 本月到期分期（规格 8.1 恒等式）。
    /// - **没账单**：本月这张卡记下的支出流水合计（用户 2026-11-12 真机回传
    ///   「本期消费对不上」——花呗有 56.00 流水，这一列却显示「—」）。
    /// - 两者都没有：`nil`，界面显示「—」而不是编一个 0——
    ///   「本期消费 0.00」会被读成「这期没花钱」，是一种误导。
    let consumed: Decimal?

    /// 逾期天数，取最久的那笔。0 = 没逾期。
    let overdueDays: Int
}

/// 一笔消费流水的最小快照，供 `DetailMath.periodSpend` 过滤。
///
/// 只带三个判断依据：金额、账期归属、是不是分期本金。
struct SpendEntry: Sendable, Equatable {
    let amount: Decimal
    /// `Transaction.billPeriod`，形如 `2026-11`。`nil` = 没记过账期。
    let billPeriod: String?
    /// `Transaction.installmentKey != nil`：这笔是某张分期计划的**本金全额**。
    let isInstallmentPrincipal: Bool
    let date: Date

    init(amount: Decimal, billPeriod: String?, isInstallmentPrincipal: Bool, date: Date) {
        self.amount = amount
        self.billPeriod = billPeriod
        self.isInstallmentPrincipal = isInstallmentPrincipal
        self.date = date
    }
}

/// 卡详情的数值口径。纯函数，不碰 SwiftData。
///
/// 唯一容易错的地方是 8.2 那条：**「本月要还」直接取账单金额，不得由消费与分期反推**。
/// 分期到期额本来就已并入当期账单，反推会把分期算两遍（1,115.03 → 1,564.70）。
enum DetailMath {
    /// 「本期消费」的流水口径（2026-11-13 用户定案 A）。
    ///
    /// **只算当前账期内、不含分期本金的消费。**
    ///
    /// 为什么必须排除分期本金：规格 8.1 的恒等式是
    /// `本期账单 = 本期消费 + 本月到期分期`。一笔 5,999 的 12 期分期，
    /// 在本期账单里只贡献 499.99，本金 5,999 摊在未来 12 个月。若把本金全额
    /// 算进「本期消费」，白条那屏会变成「本期消费 6,049 + 本月分期 533.33」，
    /// 两列相加没有任何意义，还会让人以为这月要还 6,582。
    ///
    /// 边界：
    /// - 有账期名：只认 `billPeriod == period` 的流水（同一账期内补记也算进来）
    /// - 账期名缺失（老数据 / 账户没填账单周期）：退回「自然月」，
    ///   否则这一列会永远显示 0
    static func periodSpend(
        _ entries: [SpendEntry],
        period: String?,
        today: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        entries
            .filter { entry in
                guard !entry.isInstallmentPrincipal else { return false }
                if let period, let own = entry.billPeriod { return own == period }
                return calendar.isDate(entry.date, equalTo: today, toGranularity: .month)
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// - Parameters:
    ///   - owe: 该卡欠款（正数），由 `CardDebt` 在调用方算好。
    ///   - bills: 该卡全部账单（含已还的历史期）。
    ///   - periods: 该卡全部未结清分期的期。
    /// - Parameters:
    ///   - monthSpend: 本月这张卡的支出流水合计（没有账单时，「本期消费」用它）。
    static func metrics(
        owe: Decimal,
        bills: [DebtBill],
        periods: [DebtPeriod],
        monthSpend: Decimal = 0,
        today: Date,
        calendar: Calendar = .current
    ) -> DetailMetrics {
        // 本期账单：落在本月窗口内的最新一笔。已还的也算——账单金额是既成事实，
        // 三列照样要显示它；只有「本月要还」白条会因为它已还而不再催。
        let currentBill = bills
            .filter { DueMath.isDueInThisMonth($0.dueDate, today: today, calendar: calendar) }
            .max { $0.dueDate < $1.dueDate }

        let unpaidThisMonth = periods.filter {
            !$0.isPaid && DueMath.isDueInThisMonth($0.dueDate, today: today, calendar: calendar)
        }
        let monthInstallment = unpaidThisMonth.reduce(Decimal.zero) { $0 + $1.amount }

        // 8.2：有账单就只认账单，不拿「消费 + 分期」反推。
        let monthDue: Decimal?
        if let currentBill {
            monthDue = currentBill.isPaid ? nil : currentBill.dueAmount
        } else if monthInstallment > 0 {
            monthDue = monthInstallment
        } else {
            monthDue = nil
        }
        let monthDueDate = monthDue == nil
            ? nil
            : (currentBill?.dueDate ?? unpaidThisMonth.map(\.dueDate).min())

        // 本期消费：有账单走「账单 − 本月分期」（8.1）；没账单就用本月实际支出流水。
        // 账单比分期还小时视为数据异常，取 0，绝不显示负数消费。
        let consumed: Decimal?
        if let currentBill {
            let rest = currentBill.dueAmount - monthInstallment
            consumed = rest > 0 ? rest : 0
        } else if monthSpend > 0 {
            consumed = monthSpend
        } else {
            consumed = nil
        }

        let overdueDays = bills
            .filter { !$0.isPaid }
            .map { bill -> Int in
                let due = calendar.startOfDay(for: bill.dueDate)
                let now = calendar.startOfDay(for: today)
                guard due < now else { return 0 }
                return calendar.dateComponents([.day], from: due, to: now).day ?? 0
            }
            .max() ?? 0

        return DetailMetrics(
            owe: owe,
            billDue: currentBill?.dueAmount,
            monthInstallment: monthInstallment,
            monthDue: monthDue,
            monthDueDate: monthDueDate,
            consumed: consumed,
            overdueDays: overdueDays
        )
    }

    /// 往期账单：**不含本期、也不含未来期**（规格第五节，本期已由三列 + 白条回答；
    /// 未来期是还没出账的，列出来只会让人以为已经欠了）。
    /// 按还款日倒序，逾期项留在列表里。
    static func pastBills(
        _ bills: [DebtBill],
        today: Date,
        calendar: Calendar = .current
    ) -> [DebtBill] {
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start
        return bills
            .filter { bill in
                guard let monthStart else { return true }
                return calendar.startOfDay(for: bill.dueDate) < monthStart
            }
            .sorted { $0.dueDate > $1.dueDate }
    }
}
