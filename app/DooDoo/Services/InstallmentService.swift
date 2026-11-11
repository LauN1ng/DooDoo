import Foundation
import SwiftData

/// 分期计划的写入入口（M3-2）。
///
/// **它不动余额**——分期是一张还款时间表，真正动钱的是挂在上面的 `.repayment`
/// 流水（走 `LedgerService`）。两条路径别混：AGENTS 7.2 说的「余额只能由
/// `LedgerService` 写」，指的是钱；这里只写「欠多少、什么时候还」。
///
/// 建计划时顺手把未来每一期落库（PRD 9.5.4）：已还的历史只存汇总，
/// 未来逐期存，因为任意一期都可能被账单改正（9.5.5）。
@MainActor
enum InstallmentService {

    /// 建一张分期计划，并展开未来逐期。
    ///
    /// 参数全部来自 `InstallmentIntake` 的换算结果，这里不重新解释业务口径。
    ///
    /// - `totalPeriods` / `paidPeriods`：由 `InstallmentIntake.periods(remaining:total:)` 得来
    /// - `iconName`：列表展示用，默认 `Receipt`（bundle 里的 Fluent3D PNG 名）
    ///
    /// 边界：`remaining <= 0` 时仍建计划但**不生成期表**（已还清的历史分期，
    /// 保留它是为了账户详情里还能看到这张表）。
    @discardableResult
    static func insert(
        name: String,
        account: Account?,
        totalPeriods: Int,
        paidPeriods: Int,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        remainingPrincipal: Decimal? = nil,
        totalInterest: Decimal? = nil,
        totalRebate: Decimal? = nil,
        nextDueDate: Date,
        iconName: String = "Receipt",
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> Installment {
        let plan = Installment(
            key: UUID().uuidString,
            name: name,
            account: account,
            totalPeriods: max(0, totalPeriods),
            paidPeriods: max(0, min(paidPeriods, max(0, totalPeriods))),
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount,
            remainingPrincipal: remainingPrincipal,
            totalInterest: totalInterest,
            totalRebate: totalRebate,
            nextDueDate: calendar.startOfDay(for: nextDueDate),
            iconName: iconName
        )
        context.insert(plan)
        try generateFuturePeriods(for: plan, calendar: calendar, in: context)
        try context.save()
        return plan
    }

    /// 按计划的「剩余期数 + 下一期还款日 + 每期金额」展开未来逐期，写进 `InstallmentPeriod`。
    ///
    /// **可重复调用**（重新生成）：
    /// - 用户手工改过的那几期（`isManualOverride`）**保留不动**——那是照账单改的，
    ///   重新生成不该抹掉（PRD 9.5.5）
    /// - 其余旧的自动期先删再生，避免同一期出现两条
    ///
    /// 返回写入的期数。
    @discardableResult
    static func generateFuturePeriods(
        for plan: Installment,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> Int {
        let existing = try periods(for: plan.key, in: context)
        let overridden = existing.filter(\.isManualOverride)

        // 自动生成的那些先删掉：重建比「逐条比对」简单，且期数最多几十条。
        for period in existing where !period.isManualOverride {
            context.delete(period)
        }

        let takenIndexes = Set(overridden.map(\.index))
        let fresh = plan.futurePeriods(calendar: calendar)
            .filter { !takenIndexes.contains($0.index) }

        for period in fresh {
            context.insert(InstallmentPeriod(
                installmentKey: plan.key,
                index: period.index,
                dueDate: period.dueDate,
                amount: period.amount
            ))
        }
        // 删改要立刻落盘：调用方紧接着可能再读期表（重新生成、单测），
        // 挂起的 delete 在同一上下文里读回来的行为不保证是「已删」。
        try context.save()
        return fresh.count
    }

    /// 某张计划的全部期（按 index 升序）。
    ///
    /// 用内存过滤而不是 `#Predicate`：期表规模是「计划数 × 期数」，几十到几百条，
    /// 且只在新建设计时调一次；`#Predicate` 宏在本工作区无法编译验证（同
    /// `LedgerService.softDelete` 的取舍）。
    static func periods(for installmentKey: String, in context: ModelContext) throws -> [InstallmentPeriod] {
        try context.fetch(FetchDescriptor<InstallmentPeriod>())
            .filter { $0.installmentKey == installmentKey }
            .sorted { $0.index < $1.index }
    }

    /// 已录入的分期笔数，用于「还差 N 笔」。
    ///
    /// 直接数库里的计划，不另存一个计数器——两套计数迟早分叉。
    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Installment>())
    }

    /// 最近录入的那张计划挂的账户，作为下一笔的默认账户（快速连录「保留上一条账户」）。
    ///
    /// 58 笔花呗分期基本都挂同一张卡，让用户每笔重选 58 次纯浪费。
    /// 没有历史时返回 `nil`，由调用方退回第一张信用/借款卡。
    static func mostRecentAccount(in context: ModelContext) throws -> Account? {
        let plans = try context.fetch(
            FetchDescriptor<Installment>(sortBy: [SortDescriptor(\Installment.createdAt, order: .reverse)])
        )
        return plans.first { $0.account != nil }?.account
    }
}
