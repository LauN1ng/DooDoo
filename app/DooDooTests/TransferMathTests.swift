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
        let expected = dec("0.50")
        #expect(fee == expected)
    }

    @Test("校验：到账不能大于转出")
    func validation() {
        // 断言里只放简单比较：复杂表达式塞进 `#expect` 会让类型检查器在宏展开后
        // 处理一个很大的泛型树，Swift Testing 在个别版本上会直接崩（CI 只报编译任务名）。
        let okCase = TransferMath.isValid(amount: dec("1000"), received: dec("999.90"))
        let overReceived = TransferMath.isValid(amount: dec("1000"), received: dec("1000.01"))
        let zeroAmount = TransferMath.isValid(amount: 0, received: 0)
        let negativeReceived = TransferMath.isValid(amount: dec("1000"), received: dec("-1"))

        let messageForZero = TransferMath.validationMessage(amount: 0, received: 0)
        let messageForOk = TransferMath.validationMessage(amount: dec("1000"), received: dec("999.90"))

        #expect(okCase)
        #expect(overReceived == false)
        #expect(zeroAmount == false)
        #expect(negativeReceived == false)
        #expect(messageForZero != nil)
        #expect(messageForOk == nil)
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
