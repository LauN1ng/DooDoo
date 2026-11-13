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

    /// 我欠多少钱 = Σ 每张负债卡 `max(0, −余额)`。
    ///
    /// **逐卡取正后求和**，不能先求和再取正：那样一张卡的溢缴（正余额）会抵掉
    /// 另一张卡的欠款——旧的实现就是这么错的，导致顶部「我欠」的标题与它自己的
    /// 走势线用了两种口径。现在两者同源（`CreditDebt`）。
    static func owe(_ accounts: [AccountSnapshot]) -> Decimal {
        CreditDebt.owe(balances: accounts.filter { $0.kind.isLiability }.map(\.balance))
    }

    /// 净资产 = 我有 − 我欠。
    static func net(_ accounts: [AccountSnapshot]) -> Decimal {
        mine(accounts) - owe(accounts)
    }
}
