import Foundation

/// 一期账单的快照（脱离 SwiftData，方便单测）。
///
/// 从 `CardDebt.swift` 搬来（2026-11-13）：`CardDebt` 已废弃，但
/// `DetailMath` 的「本期消费 / 本月要还」仍需要这两个不可变快照。
/// **它们只是数据搬运，不参与「我欠」的任何计算**——欠款口径见 `CreditDebt`。
struct DebtBill: Sendable, Equatable {
    /// 单位：元。本期应还。
    let dueAmount: Decimal
    /// 本期还款日。
    let dueDate: Date
    /// 已还清。
    let isPaid: Bool

    init(dueAmount: Decimal, dueDate: Date, isPaid: Bool) {
        self.dueAmount = dueAmount
        self.dueDate = dueDate
        self.isPaid = isPaid
    }
}

/// 一期分期的快照。
struct DebtPeriod: Sendable, Equatable {
    /// 单位：元。这一期应还（含息）。
    let amount: Decimal
    /// 这一期的还款日。
    let dueDate: Date
    /// 已还。
    let isPaid: Bool
    /// 这一期所属的计划是**在「记一笔」里跟消费一起建的**（M3-10）。
    ///
    /// 该字段在 2026-11-13 口径统一后**只作说明**：欠款不再读期表，
    /// 所以没有任何金额计算依赖它。保留是为了兼容既有调用点，后续清理时可删。
    let isCoveredByBalance: Bool

    init(amount: Decimal, dueDate: Date, isPaid: Bool, isCoveredByBalance: Bool = false) {
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
        self.isCoveredByBalance = isCoveredByBalance
    }
}
