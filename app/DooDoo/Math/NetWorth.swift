import Foundation

/// 账户余额的轻量快照，脱离 SwiftData，方便单测。
struct AccountSnapshot: Sendable, Equatable {
    let kind: AccountKind
    /// 单位：元。储蓄为正、欠款为负。
    let balance: Decimal

    init(kind: AccountKind, balance: Decimal) {
        self.kind = kind
        self.balance = balance
    }
}

/// 净资产口径（PRD 9.4）。纯函数，没有状态。
enum NetWorth {
    /// 我有多少钱 = Σ 储蓄 + Σ 现金。
    static func mine(_ accounts: [AccountSnapshot]) -> Decimal {
        accounts
            .filter { $0.kind == .savings || $0.kind == .cash }
            .reduce(Decimal.zero) { $0 + $1.balance }
    }

    /// 我欠多少钱 = Σ 信用 + Σ 借款，**取正值**（欠款在库里是负数）。
    ///
    /// 边界：若数据异常导致求和为正，返回 0 而不是负数——「我欠 −100 元」没有意义。
    static func owe(_ accounts: [AccountSnapshot]) -> Decimal {
        let sum = accounts
            .filter { $0.kind.isLiability }
            .reduce(Decimal.zero) { $0 + $1.balance }
        return sum < 0 ? -sum : 0
    }

    /// 净资产 = 我有 − 我欠。
    static func net(_ accounts: [AccountSnapshot]) -> Decimal {
        mine(accounts) - owe(accounts)
    }
}
