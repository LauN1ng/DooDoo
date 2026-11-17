import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 分期债务的入账方式（2026-11-17 修「9,000 变 12,000」）。
///
/// 事故形态（用户真机）：
/// 1. 新建信用卡，填「欠款 9,000」——他填的是**账单上这张卡一共欠多少**，
///    里面本来就有未还的分期；
/// 2. 再去「存量分期」把那张卡上的分期抄进去（剩余应还 3,000）；
/// 3. 结果欠款变成 12,000。
///
/// 根因是同一笔债有两个互不知情的写入方：
/// - `AccountEditor.save` 把 9,000 反推进 `initialBalance`
/// - `InstallmentService.insert` 又执行 `currentBalance - 3,000`
///
/// 现在改成：
/// - **入账必须是一条可见的 `.adjustment` 流水**（有时间点、能对账、能删）
/// - 用户勾「这笔债已经在欠款里了」时**只登记计划、不碰余额**
///
/// 这一类「多入口组合」场景以前一条测试都没有，179 条单测全绿也拦不住，
/// 所以这个文件按**入口组合**来组织，不再按单个函数组织。
@MainActor
struct DebtRowTests {
    private let flag = "doodoo.installmentDebt.rows.v1"

    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self, Installment.self,
            InstallmentPeriod.self, BillStatement.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// 建卡填欠款 9,000 之后的那张卡（`initialBalance` 已被校准成 −9,000）。
    private func makeCard(owed: String, in context: ModelContext) throws -> Account {
        let card = Account(name: "京东白条", kind: .credit, initialBalance: -dec(owed), dueDay: 25)
        context.insert(card)
        try context.save()
        try LedgerService.recalculateAll(in: context)
        return card
    }

    private func plan(
        on card: Account,
        due: String,
        periods: Int,
        in context: ModelContext,
        alreadyInBalance: Bool
    ) throws -> Installment {
        try InstallmentService.insert(
            name: "京东白条 分期",
            account: card,
            totalPeriods: periods,
            paidPeriods: periods - 1,
            perPeriodAmount: dec(due),
            remainingDue: dec(due),
            nextDueDate: Date.now,
            debtAlreadyInBalance: alreadyInBalance,
            in: context
        )
    }

    // MARK: - 组合一：建卡填欠款 + 补录分期

    @Test("勾了「已在欠款里」：只登记期表，欠款不动（9,000 还是 9,000）")
    func debtAlreadyIncludedDoesNotChangeBalance() throws {
        let context = try makeContext()
        let card = try makeCard(owed: "9000", in: context)

        try plan(on: card, due: "3000", periods: 3, in: context, alreadyInBalance: true)

        #expect(card.currentBalance == dec("-9000"),
                "9,000 已经含这笔分期，再减一次就是用户看到的 12,000")
        #expect(CreditDebt.owe(balance: card.currentBalance) == dec("9000"))

        let rows = try context.fetch(FetchDescriptor<Transaction>())
        #expect(rows.isEmpty, "勾了「已含」不该产生任何流水——期表本身就是记录")
    }

    @Test("勾掉「已在欠款里」：债真的进账，而且是可见的一条流水（9,000 → 12,000）")
    func debtNotIncludedBooksARow() throws {
        let context = try makeContext()
        let card = try makeCard(owed: "9000", in: context)

        let created = try plan(on: card, due: "3000", periods: 3, in: context, alreadyInBalance: false)

        #expect(card.currentBalance == dec("-12000"))
        // 关键是「可见且可追溯」：余额变化必须有出处，否则走势曲线没有时间点、
        // 用户也无法判断这 12,000 是怎么来的。
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.kind == .adjustment)
        #expect(row.amount == dec("3000"))
        #expect(row.installmentKey == created.key, "这条流水必须指回计划，删计划/对账都靠它")
        #expect(row.note?.hasPrefix(InstallmentService.debtNotePrefix) == true)
    }

    @Test("记一笔里建的分期仍然不入账（全额 expense 已经入过）")
    func createdFromEntryStaysSkipped() throws {
        let context = try makeContext()
        let card = try makeCard(owed: "0", in: context)

        try InstallmentService.insert(
            name: "内联分期",
            account: card,
            totalPeriods: 12,
            paidPeriods: 0,
            perPeriodAmount: dec("120"),
            remainingDue: dec("1440.39"),
            nextDueDate: Date.now,
            createdFromEntry: true,
            debtAlreadyInBalance: false,
            in: context
        )

        #expect(card.currentBalance == 0, "createdFromEntry 与 debtAlreadyInBalance 任一为真都不入账")
    }

    // MARK: - `.adjustment` 终于真的动余额

    @Test("调整流水改为真扣款：from = −amount, to = 0")
    func adjustmentFlowIsReal() {
        let tx = Transaction(amount: dec("3000"), kind: .adjustment, date: .now)
        let flow = LedgerService.flow(of: tx)
        #expect(flow.from == dec("-3000"))
        #expect(flow.to == 0)
    }

    @Test("调整流水不进消费统计")
    func adjustmentIsNotExpense() {
        #expect(TransactionKind.adjustment.countsAsExpense == false)
    }

    // MARK: - 迁移：把 11-13 版减进 initialBalance 的债拆出来

    @Test("迁移：余额不变，但构成变成「期初 + 分期登记」两条")
    func migrationSplitsInitialWithoutChangingBalance() throws {
        UserDefaults.standard.removeObject(forKey: flag)
        defer { UserDefaults.standard.removeObject(forKey: flag) }

        let context = try makeContext()
        // 模拟 11-13 版留下的状态：期初被减掉了 1,200（−1,000 − 1,200 = −2,200），
        // 但库里没有任何流水解释这 1,200。
        let card = Account(name: "花呗", kind: .credit, initialBalance: dec("-2200"), dueDay: 25)
        context.insert(card)
        try context.save()
        try LedgerService.recalculateAll(in: context)

        let created = try InstallmentService.insert(
            name: "老分期",
            account: card,
            totalPeriods: 6,
            paidPeriods: 0,
            perPeriodAmount: dec("200"),
            remainingDue: dec("1200"),
            nextDueDate: Date.now,
            debtAlreadyInBalance: true,   // 不新增流水，模拟旧库
            in: context
        )
        #expect(card.currentBalance == dec("-2200"))

        let migrated = try InstallmentService.migrateDebtToRows(in: context)

        #expect(migrated == 1)
        #expect(card.initialBalance == dec("-1000"), "期初还回被减掉的那一份")
        #expect(card.currentBalance == dec("-2200"), "余额不变——迁移只拆构成，不动钱")
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 1)
        #expect(rows.first?.installmentKey == created.key)
    }

    @Test("迁移幂等：跑第二次什么都不做")
    func migrationIsIdempotent() throws {
        UserDefaults.standard.removeObject(forKey: flag)
        defer { UserDefaults.standard.removeObject(forKey: flag) }

        let context = try makeContext()
        let card = try makeCard(owed: "1200", in: context)
        _ = try plan(on: card, due: "1200", periods: 3, in: context, alreadyInBalance: true)

        let first = try InstallmentService.migrateDebtToRows(in: context)
        let balanceAfterFirst = card.currentBalance
        let second = try InstallmentService.migrateDebtToRows(in: context)

        #expect(first == 1)
        #expect(second == 0)
        #expect(card.currentBalance == balanceAfterFirst)
    }

    @Test("已经有债务流水的计划不会被迁移重复记一次")
    func migrationSkipsBookedPlans() throws {
        UserDefaults.standard.removeObject(forKey: flag)
        defer { UserDefaults.standard.removeObject(forKey: flag) }

        let context = try makeContext()
        let card = try makeCard(owed: "0", in: context)
        // 新版 `insert` 已经写了流水，迁移必须认出来并跳过（否则 initial 会被加一次）
        _ = try plan(on: card, due: "1200", periods: 3, in: context, alreadyInBalance: false)
        #expect(card.currentBalance == dec("-1200"))

        let migrated = try InstallmentService.migrateDebtToRows(in: context)

        #expect(migrated == 0)
        #expect(card.currentBalance == dec("-1200"))
        #expect(card.initialBalance == 0)
    }
}
