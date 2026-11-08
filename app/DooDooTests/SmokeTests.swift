import Testing
import SwiftData
import Foundation
@testable import DooDoo

/// 工程与模型的冒烟测试：证明「能编、能存、口径没跑偏」。
/// 真正涉及钱的分期/年化用例属于 M2/M3，且必须取自 PRD 附录真实账单。
@MainActor
struct SmokeTests {
    @Test("RootTab 只有三段，顺序固定")
    func rootTabs() {
        #expect(RootTab.allCases.map(\.title) == ["流水", "资产", "设置"])
    }

    @Test("AppSettings 默认值符合 PRD")
    func settingsDefaults() {
        let s = AppSettings()
        #expect(s.overdueAlertEnabled == true)
        #expect(s.currencyCode == "CNY")
        #expect(s.incomeColor == .green)
        #expect(s.expenseColor == .red)
    }

    @Test("内存容器能写入并读回流水")
    func inMemoryStore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self, AppSettings.self,
            configurations: config
        )
        let context = ModelContext(container)

        let account = Account(name: "花呗", kind: .credit)
        let category = Category(name: "吃", emoji: "🍰", sortOrder: 0, isIncome: false, tintHex: "#FFF1E6")
        context.insert(account)
        context.insert(category)
        context.insert(
            Transaction(
                amount: Decimal(string: "32.00")!,
                kind: .expense,
                date: .now,
                note: "好利来",
                account: account,
                category: category
            )
        )
        try context.save()

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.first?.amount == Decimal(string: "32.00"))
        #expect(all.first?.category?.name == "吃")
        #expect(all.first?.account?.name == "花呗")
    }
}

/// 按天分组与当日合计的口径测试。
@MainActor
struct DayMathTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test("同一天的多笔归到一组，跨天分开")
    func groupByDay() {
        let items = [
            TxFigure(kind: .expense, amount: 32, date: date(2026, 11, 8, 9)),
            TxFigure(kind: .expense, amount: 4, date: date(2026, 11, 8, 18)),
            TxFigure(kind: .expense, amount: 26, date: date(2026, 11, 7, 12)),
        ]
        let groups = DayMath.groupByDay(items, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].items.count == 2)
        #expect(groups[1].items.count == 1)
    }

    @Test("支出合计只算 expense，还款与转账不进")
    func expenseTotal() {
        let items = [
            TxFigure(kind: .expense, amount: Decimal(string: "32.00")!, date: date(2026, 11, 8)),
            TxFigure(kind: .repayment, amount: Decimal(string: "525.72")!, date: date(2026, 11, 8)),
            TxFigure(kind: .transfer, amount: Decimal(string: "1000")!, date: date(2026, 11, 8)),
            TxFigure(kind: .income, amount: Decimal(string: "6476")!, date: date(2026, 11, 8)),
        ]
        #expect(DayMath.expenseTotal(items) == Decimal(string: "32.00"))
        #expect(DayMath.incomeTotal(items) == Decimal(string: "6476"))
    }

    @Test("最近 7 天窗口：长度 7、第一天是今天、窗口外被丢弃")
    func window() {
        let now = date(2026, 11, 8, 15)
        let starts = DayMath.recentDayStarts(7, endingAt: now, calendar: calendar)
        #expect(starts.count == 7)
        #expect(calendar.isDate(starts[0], inSameDayAs: now))

        let items = [
            TxFigure(kind: .expense, amount: 1, date: date(2026, 11, 8)),
            TxFigure(kind: .expense, amount: 2, date: date(2026, 11, 2)),   // 第 7 天，在窗口内
            TxFigure(kind: .expense, amount: 3, date: date(2026, 11, 1)),   // 窗口外
        ]
        let window = DayMath.window(items, days: 7, endingAt: now, calendar: calendar)
        #expect(window.count == 7)
        #expect(window[0].items.count == 1)
        #expect(window[6].items.count == 1)
        #expect(window.reduce(0) { $0 + $1.items.count } == 2)
    }

    @Test("金额格式化：两位小数 + 千分位")
    func money() {
        #expect(MoneyMath.money(Decimal(string: "12345.6")!) == "12,345.60")
        #expect(MoneyMath.signed(Decimal(string: "32")!, kind: .expense) == "−¥32.00")
        #expect(MoneyMath.signed(Decimal(string: "6476")!, kind: .income) == "+¥6,476.00")
    }
}
