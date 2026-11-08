import Foundation

/// 转账双金额与还款余额的纯函数（PRD 9.8 / 9.5）。不碰 SwiftData，可单测。
///
/// 单位一律：元。金额恒为正，方向由 `TransactionKind` 决定。
enum TransferMath {
    /// 手续费 = 转出 − 到账。
    ///
    /// - 边界：到账大于转出视为输入错误，**按 0 处理**（不产生负手续费）；
    /// - 边界：转出为 0 时也为 0；
    /// - 相等（无手续费）时为 0。
    static func fee(amount: Decimal, received: Decimal) -> Decimal {
        let diff = amount - received
        return diff > 0 ? diff : 0
    }

    /// 双金额是否合法：转出 > 0，且 0 ≤ 到账 ≤ 转出。
    static func isValid(amount: Decimal, received: Decimal) -> Bool {
        amount > 0 && received >= 0 && received <= amount
    }

    /// 校验失败时的提示；通过返回 `nil`。文案直接用于界面。
    static func validationMessage(amount: Decimal, received: Decimal) -> String? {
        if amount <= 0 { return "转出金额要大于 0" }
        if received < 0 { return "到账金额不能为负" }
        if received > amount { return "到账金额不能大于转出" }
        return nil
    }

    /// 还款后该账户还剩多少欠款（返回正数；还清或超额返回 0）。
    ///
    /// `balance` 是账户的 `currentBalance`：信用 / 借款账户欠款为负，
    /// 所以先取反成正的欠款再减本次还款。
    /// - 边界：已还清（balance ≥ 0）时返回 0；
    /// - 边界：超额还款（repay > 欠款）时返回 0，多出的部分由调用方决定是否留作正余额。
    static func remainingDebt(balance: Decimal, repay: Decimal) -> Decimal {
        let debt = -balance
        guard debt > 0 else { return 0 }
        let left = debt - repay
        return left > 0 ? left : 0
    }

    /// 还款后的账户余额（保留正负号语义：多还的部分会变成正余额）。
    ///
    /// 信用账户 `-3,217.42` 还 `3,217.42` → `0`；还 `3,300` → `82.58`（多还）。
    static func balanceAfterRepay(balance: Decimal, repay: Decimal) -> Decimal {
        balance + repay
    }
}
