import Foundation
import Testing

@testable import DooDoo

/// 转账双金额与还款余额的边界（PRD 9.8）。纯函数，不碰数据库。
struct TransferMathTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test("手续费 = 转出 − 到账")
    func feeNormal() {
        #expect(TransferMath.fee(amount: dec("1000"), received: dec("999.90")) == dec("0.10"))
    }

    @Test("无手续费时差额为 0")
    func feeZero() {
        #expect(TransferMath.fee(amount: dec("1000"), received: dec("1000")) == 0)
    }

    @Test("到账大于转出：按 0 处理，不产生负手续费")
    func feeNegativeInput() {
        #expect(TransferMath.fee(amount: dec("999.90"), received: dec("1000")) == 0)
    }

    @Test("转出为 0 时手续费为 0")
    func feeZeroAmount() {
        #expect(TransferMath.fee(amount: 0, received: 0) == 0)
    }

    @Test("大额也能精确到分")
    func feeLargeAmount() {
        let fee = TransferMath.fee(amount: dec("123456.78"), received: dec("123456.28"))
        #expect(fee == dec("0.50"))
    }

    @Test("校验：到账不能大于转出")
    func validation() {
        #expect(TransferMath.isValid(amount: dec("1000"), received: dec("999.90")))
        #expect(!TransferMath.isValid(amount: dec("1000"), received: dec("1000.01")))
        #expect(!TransferMath.isValid(amount: 0, received: 0))
        #expect(!TransferMath.isValid(amount: dec("1000"), received: dec("-1")))
        #expect(TransferMath.validationMessage(amount: 0, received: 0) != nil)
        #expect(TransferMath.validationMessage(amount: dec("1000"), received: dec("999.90")) == nil)
    }

    @Test("还款后剩余欠款：正常、还清、超额")
    func remainingDebt() {
        // 欠 3,217.42，还 3,000 → 还剩 217.42
        #expect(TransferMath.remainingDebt(balance: dec("-3217.42"), repay: dec("3000")) == dec("217.42"))
        // 还清
        #expect(TransferMath.remainingDebt(balance: dec("-3217.42"), repay: dec("3217.42")) == 0)
        // 超额还款 → 0（多还的部分由账户余额变正体现）
        #expect(TransferMath.remainingDebt(balance: dec("-3217.42"), repay: dec("3300")) == 0)
        // 本来就没欠款
        #expect(TransferMath.remainingDebt(balance: dec("100"), repay: dec("50")) == 0)
    }

    @Test("还款后余额：还清为 0，多还为正是")
    func balanceAfterRepay() {
        #expect(TransferMath.balanceAfterRepay(balance: dec("-3217.42"), repay: dec("3217.42")) == 0)
        #expect(TransferMath.balanceAfterRepay(balance: dec("-3217.42"), repay: dec("3300")) == dec("82.58"))
    }
}
