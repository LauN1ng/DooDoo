import Foundation
import Testing

@testable import DooDoo

/// 欠款口径的门禁（2026-11-13 口径统一后重建；旧的 `CardDebtTests` 已随 `CardDebt` 删除）。
///
/// 这里钉的不只是数字，还有**两个入口的语义差异**——真机「我欠 0.00」就是
/// 把「已取正的欠额」喂给了收「余额」的那个入口。
struct CreditDebtTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test("单卡：负余额取正，零与正余额都是 0（溢缴不是负欠款）")
    func singleCard() {
        #expect(CreditDebt.owe(balance: dec("-6150")) == dec("6150"))
        #expect(CreditDebt.owe(balance: 0) == 0)
        #expect(CreditDebt.owe(balance: dec("120")) == 0)
    }

    @Test("多卡：一张卡的溢缴抵不掉另一张卡的欠款")
    func surplusDoesNotOffset() {
        // 逐卡取正后求和 = 6,150；若先求和再取正，会变成 6,030。
        let balances: [Decimal] = [dec("-6150"), dec("120")]
        #expect(CreditDebt.owe(balances: balances) == dec("6150"))
    }

    @Test("合计入口收的是已取正欠额：6,150 + 3,852.15")
    func totalOfOwed() {
        let owed: [Decimal] = [dec("6150"), dec("3852.15")]
        #expect(CreditDebt.total(ofOwed: owed) == dec("10002.15"))
    }

    /// 真机 bug 的复现：`oweByAccount` 里是正数欠额，误传给 `owe(balances:)`
    /// 会被 `max(0, −1,000)` 归零 → 顶部「我欠 0.00」而组头显示 1,000。
    /// 这条断言存在的意义：谁再改回去，CI 立刻红。
    @Test("误用会被归零——这就是「我欠 0.00」的机制")
    func misuseProducesZero() {
        let owedAsBalance: [Decimal] = [dec("1000")]
        #expect(CreditDebt.owe(balances: owedAsBalance) == 0)
        #expect(CreditDebt.total(ofOwed: owedAsBalance) == dec("1000"))
    }
}
