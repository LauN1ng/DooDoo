import Testing
import SwiftData
import Foundation
@testable import DooDoo

/// 净资产与环比的口径测试。数字取自 PRD 真实画像：
/// 信用合计 −28,466.00、储蓄合计 3,120.00、父母借款 −20,000。
@MainActor
struct NetWorthTests {
    private func d(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func snapshot(_ kind: AccountKind, _ value: String) -> AccountSnapshot {
        AccountSnapshot(kind: kind, balance: d(value))
    }

    @Test("我有 = 储蓄 + 现金")
    func mine() {
        let accounts = [
            snapshot(.savings, "1915.70"),
            snapshot(.savings, "1204.30"),
            snapshot(.cash, "100"),
            snapshot(.credit, "-3120.00"),
        ]
        #expect(NetWorth.mine(accounts) == d("3220.00"))
    }

    @Test("我欠 = 信用 + 借款，取正值")
    func owe() {
        let accounts = [
            snapshot(.credit, "-28466.00"),
            snapshot(.loan, "-20000.00"),
            snapshot(.savings, "3120.00"),
        ]
        #expect(NetWorth.owe(accounts) == d("48466.00"))
    }

    @Test("净资产 = 我有 − 我欠")
    func net() {
        let accounts = [
            snapshot(.savings, "3120.00"),
            snapshot(.credit, "-28466.00"),
            snapshot(.loan, "-20000.00"),
        ]
        #expect(NetWorth.net(accounts) == d("-45346.00"))
    }

    @Test("负债求和异常为正时，我欠返回 0 而不是负数")
    func oweEdgeCase() {
        #expect(NetWorth.owe([snapshot(.credit, "500")]) == 0)
    }
}

@MainActor
struct AccountDeltaTests {
    @Test("分母用上期值：3120 → 4360 是 +39.7%")
    func percentUsesPrevious() {
        let value = AccountDelta.percent(current: Decimal(string: "4360")!,
                                         previous: Decimal(string: "3120")!)
        #expect(value == Decimal(string: "39.7"))
    }

    @Test("上期为 0 时返回 nil，不假装是 0%")
    func percentZeroBase() {
        #expect(AccountDelta.percent(current: 100, previous: 0) == nil)
        #expect(AccountDelta.text(nil) == "—")
    }

    @Test("箭头与颜色类")
    func text() {
        #expect(AccountDelta.text(Decimal(string: "4.1")!) == "↗ 4.1%")
        #expect(AccountDelta.text(Decimal(string: "-28.4")!) == "↘ 28.4%")
        #expect(AccountDelta.classify(Decimal(string: "4.1")!) == .up)
        #expect(AccountDelta.classify(Decimal(string: "-28.4")!) == .down)
        #expect(AccountDelta.classify(nil) == .flat)
    }
}

@MainActor
struct NetWorthSeriesTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    @Test("时点余额 = 初始 + 该时点之前的流水")
    func balanceAtDate() {
        let ledger = AccountLedger(
            kind: .savings,
            initial: 1000,
            entries: [
                LedgerPoint(date: date(3), delta: -100),
                LedgerPoint(date: date(6), delta: 50),
            ]
        )
        #expect(NetWorthSeries.balance(of: ledger, at: date(1)) == 1000)
        #expect(NetWorthSeries.balance(of: ledger, at: date(3)) == 900)
        #expect(NetWorthSeries.balance(of: ledger, at: date(7)) == 950)
    }

    @Test("每个采样点都给出「我有 / 我欠」")
    func points() {
        let ledgers = [
            AccountLedger(kind: .savings, initial: 1000, entries: [LedgerPoint(date: date(3), delta: -200)]),
            AccountLedger(kind: .credit, initial: -500, entries: []),
        ]
        let points = NetWorthSeries.points(ledgers, at: [date(1), date(5)])
        #expect(points.count == 2)
        #expect(points[0].mine == 1000)
        #expect(points[0].owe == 500)
        #expect(points[1].mine == 800)
    }

    @Test("五个区间的点数")
    func ranges() {
        let now = date(8)
        #expect(NetWorthSeries.dates(for: .week, now: now, calendar: calendar).count == 7)
        #expect(NetWorthSeries.dates(for: .month, now: now, calendar: calendar).count == 30)
        #expect(NetWorthSeries.dates(for: .quarter, now: now, calendar: calendar).count == 12)
        #expect(NetWorthSeries.dates(for: .year, now: now, calendar: calendar).count == 12)
    }
}

/// 余额重算：这是唯一允许写 `currentBalance` 的路径。
@MainActor
struct LedgerRecalcTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Account.self, Category.self, Transaction.self, AppSettings.self,
            configurations: config
        )
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test("余额 = 初始 + 收入 − 支出，删一笔后回滚")
    func recalcAndSoftDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let account = Account(name: "建行5044", kind: .savings, initialBalance: decimal("1204.30"))
        context.insert(account)
        try context.save()

        let lunch = try LedgerService.insert(
            amount: decimal("32.00"), kind: .expense, date: .now, account: account, in: context
        )
        try LedgerService.insert(
            amount: decimal("1000.00"), kind: .income, date: .now, account: account, in: context
        )

        #expect(account.currentBalance == decimal("2172.30"))

        try LedgerService.softDelete(lunch, in: context)
        #expect(account.currentBalance == decimal("2204.30"))
    }

    @Test("还款与转账暂不影响余额（M2b 才实现）")
    func repaymentIsLeftOut() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let account = Account(name: "招行8857", kind: .credit, initialBalance: decimal("-3120.00"))
        context.insert(account)
        try context.save()

        try LedgerService.insert(
            amount: decimal("500.00"), kind: .repayment, date: .now, account: account, in: context
        )
        #expect(account.currentBalance == decimal("-3120.00"))
    }

    @Test("校准余额：反推 initialBalance，重算后正好落在目标值")
    func adjustBalance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let account = Account(name: "花呗", kind: .credit, initialBalance: 0)
        context.insert(account)
        try context.save()

        try LedgerService.insert(
            amount: decimal("220.00"), kind: .expense, date: .now, account: account, in: context
        )
        try LedgerService.adjustAccountBalance(account, to: decimal("-7842.50"), in: context)

        #expect(account.currentBalance == decimal("-7842.50"))
        #expect(account.initialBalance == decimal("-7622.50"))
    }

    @Test("recalculateAll 对无流水的账户不改动初始余额")
    func recalcKeepsInitial() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let account = Account(name: "父母借款", kind: .loan, initialBalance: decimal("-20000.00"))
        context.insert(account)
        try context.save()

        try LedgerService.recalculateAll(in: context)
        #expect(account.currentBalance == decimal("-20000.00"))
    }
}
