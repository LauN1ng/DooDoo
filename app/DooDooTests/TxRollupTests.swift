import Foundation
import Testing
import UIKit

@testable import DooDoo

/// 转账与手续费的**显示行**合并（2026-11-11 用户定：手续费不单独占一行）。
///
/// 用假类型而不是真 `Transaction`：合并规则是纯逻辑，不该为了测它去搭 `ModelContext`。
struct TxRollupTests {
    private struct Fake: Equatable {
        let name: String
        let kind: TransactionKind
        let group: String?
    }

    private func rows(_ items: [Fake]) -> [TxRollup<Fake>] {
        TxRollup.rows(items, kindOf: { $0.kind }, groupOf: { $0.group })
    }

    @Test("转账 + 手续费合成一行")
    func transferWithFeeMerges() {
        let items = [
            Fake(name: "手续费", kind: .expense, group: "g1"),
            Fake(name: "转账", kind: .transfer, group: "g1"),
        ]
        let result = rows(items)

        #expect(result.count == 1)
        #expect(result.first?.primary.name == "转账")
        #expect(result.first?.fees.map(\.name) == ["手续费"])
    }

    @Test("无手续费的转账还是一行，fees 为空")
    func transferWithoutFee() {
        let items = [Fake(name: "转账", kind: .transfer, group: nil)]
        let result = rows(items)

        #expect(result.count == 1)
        #expect(result.first?.fees.isEmpty == true)
    }

    @Test("顺序跟随主行：手续费那一行消失，不影响邻居次序")
    func orderFollowsPrimary() {
        let items = [
            Fake(name: "咖啡", kind: .expense, group: nil),
            Fake(name: "手续费", kind: .expense, group: "g1"),
            Fake(name: "转账", kind: .transfer, group: "g1"),
            Fake(name: "工资", kind: .income, group: nil),
        ]
        let result = rows(items)

        #expect(result.map(\.primary.name) == ["咖啡", "转账", "工资"])
    }

    @Test("孤儿手续费（找不到对应转账）保留成一行，不吞掉真实扣款")
    func orphanFeeKept() {
        // 跨 7 天窗口时可能出现：转账落在窗口外、手续费落在窗口内。
        let items = [Fake(name: "手续费", kind: .expense, group: "g9")]
        let result = rows(items)

        #expect(result.count == 1)
        #expect(result.first?.primary.name == "手续费")
        #expect(result.first?.fees.isEmpty == true)
    }

    @Test("同组多条手续费全部挂上，一条都不丢")
    func multipleFeesAttach() {
        let items = [
            Fake(name: "手续费A", kind: .expense, group: "g1"),
            Fake(name: "转账", kind: .transfer, group: "g1"),
            Fake(name: "手续费B", kind: .expense, group: "g1"),
        ]
        let result = rows(items)

        #expect(result.count == 1)
        #expect(result.first?.fees.count == 2)
    }

    @Test("不是手续费的支出不受影响（没 groupID 的照常出行）")
    func plainExpenseUnaffected() {
        let items = [
            Fake(name: "午饭", kind: .expense, group: nil),
            Fake(name: "转账", kind: .transfer, group: "g1"),
            Fake(name: "手续费", kind: .expense, group: "g1"),
        ]
        let result = rows(items)

        #expect(result.map(\.primary.name) == ["午饭", "转账"])
    }

    @Test("空输入不炸")
    func emptyInput() {
        #expect(rows([]).isEmpty)
    }

    @Test("转账行的图标 CurrencyExchange 必须在包里（防哪天被删）")
    func transferIconShips() {
        // 转账没有分类，图标借的是手续费分类那张（`Category` 里 misc.fee 的 icon）。
        // 这张图丢了，转账行会重新退成「•」。
        #expect(UIImage(named: "CurrencyExchange") != nil)
    }
}
