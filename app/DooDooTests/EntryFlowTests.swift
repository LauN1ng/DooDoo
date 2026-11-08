import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 四类型写入的账务口径（M1b / M2b 门禁）。
///
/// 门禁原话（AGENTS 8.1）：
/// - 还款后本月消费统计**不变**
/// - 带手续费转账**只增加手续费那部分**
@MainActor
struct EntryFlowTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// 建一个储蓄账户 + 一个信用账户，余额分别是 5,000 和 −3,217.42。
    private func makeAccounts(in context: ModelContext) throws -> (savings: Account, credit: Account) {
        let savings = Account(name: "建行 5044", kind: .savings, initialBalance: dec("5000"))
        let credit = Account(name: "花呗", kind: .credit, initialBalance: dec("-3217.42"))
        context.insert(savings)
        context.insert(credit)
        try context.save()
        try LedgerService.recalculateAll(in: context)
        return (savings, credit)
    }

    private func dailyExpense(in context: ModelContext) throws -> Decimal {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let figures = transactions.map {
            TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee)
        }
        return DayMath.expenseTotal(figures)
    }

    @Test("支出：付款账户减少，消费统计增加")
    func expense() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        try LedgerService.insert(
            amount: dec("32.00"), kind: .expense, date: .now,
            note: "好利来", account: credit, in: context
        )

        let total = try dailyExpense(in: context)
        #expect(credit.currentBalance == dec("-3249.42"))
        #expect(total == dec("32.00"))
    }

    @Test("收入：收款账户增加，不计入消费统计")
    func income() throws {
        let context = try makeContext()
        let (savings, _) = try makeAccounts(in: context)

        try LedgerService.insert(
            amount: dec("8000.00"), kind: .income, date: .now,
            account: savings, in: context
        )

        let total = try dailyExpense(in: context)
        #expect(savings.currentBalance == dec("13000.00"))
        #expect(total == 0)
    }

    @Test("还款：两边同时动，消费统计不变")
    func repayment() throws {
        let context = try makeContext()
        let (savings, credit) = try makeAccounts(in: context)

        try LedgerService.insert(
            amount: dec("3217.42"), kind: .repayment, date: .now,
            account: savings, toAccount: credit, in: context
        )

        let total = try dailyExpense(in: context)
        #expect(credit.currentBalance == 0)
        #expect(savings.currentBalance == dec("1782.58"))
        #expect(total == 0, "还款不属于消费")
    }

    @Test("转账带手续费：只把手续费算进消费")
    func transferWithFee() throws {
        let context = try makeContext()
        let (savings, credit) = try makeAccounts(in: context)

        let tx = try LedgerService.insert(
            amount: dec("1000.00"), kind: .transfer, date: .now,
            account: savings, toAccount: credit, receivedAmount: dec("999.90"), in: context
        )

        let total = try dailyExpense(in: context)
        let fee = tx.fee
        let savingsBalance = savings.currentBalance
        let creditBalance = credit.currentBalance
        let netSum = savingsBalance + creditBalance

        #expect(fee == dec("0.10"))
        #expect(savingsBalance == dec("4000.00"), "转出账户扣本金 1000，不额外扣手续费")
        #expect(creditBalance == dec("-2217.52"), "转入账户只入账 999.90")
        #expect(netSum == dec("1782.48"), "两边余额之和比原来少 0.10，正好是手续费")
        #expect(total == dec("0.10"), "转账本金不算消费，只算手续费")
    }

    @Test("软删除：余额与统计都回滚")
    func softDeleteRollback() throws {
        let context = try makeContext()
        let (savings, credit) = try makeAccounts(in: context)

        let tx = try LedgerService.insert(
            amount: dec("1000.00"), kind: .transfer, date: .now,
            account: savings, toAccount: credit, receivedAmount: dec("999.90"), in: context
        )
        try LedgerService.softDelete(tx, in: context)

        let total = try dailyExpense(in: context)
        #expect(savings.currentBalance == dec("5000.00"))
        #expect(credit.currentBalance == dec("-3217.42"))
        #expect(total == 0)
    }

    @Test("调账后 recalculateAll 与增量写入结果一致")
    func recalculateMatchesIncremental() throws {
        let context = try makeContext()
        let (savings, credit) = try makeAccounts(in: context)

        try LedgerService.insert(
            amount: dec("120.00"), kind: .expense, date: .now,
            account: credit, in: context
        )
        try LedgerService.insert(
            amount: dec("500.00"), kind: .repayment, date: .now,
            account: savings, toAccount: credit, in: context
        )

        let incrementalCredit = credit.currentBalance
        let incrementalSavings = savings.currentBalance

        try LedgerService.recalculateAll(in: context)

        #expect(credit.currentBalance == incrementalCredit)
        #expect(savings.currentBalance == incrementalSavings)
    }

    @Test("分类有两级：子类的 parentKey 指向一级")
    func categoryHierarchy() throws {
        let context = try makeContext()

        let top = Category(key: "food", parentKey: nil, name: "吃", iconName: "Croissant",
                           emoji: "🍰", sortOrder: 0, isIncome: false, tintHex: "#FFF1E6")
        let sub = Category(key: "food.coffee", parentKey: "food", name: "咖啡", iconName: "HotBeverage",
                           emoji: "☕️", sortOrder: 8, isIncome: false, tintHex: "#FFF1E6")
        context.insert(top)
        context.insert(sub)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Category>())
        #expect(all.filter { $0.isTopLevel }.count == 1)
        #expect(all.filter { $0.parentKey == "food" }.count == 1)
        #expect(sub.isTopLevel == false)
    }

    @Test("内置分类够用：一级 10 个、二级 48 个")
    func builtInCount() {
        let tops = Category.builtIn.filter { $0.parentKey == nil }
        let subs = Category.builtIn.filter { $0.parentKey != nil }
        #expect(tops.count == 10)
        #expect(subs.count == 48)
        #expect(tops.filter { !$0.isIncome }.count == 8)
        #expect(tops.filter { $0.isIncome }.count == 2)
    }
}
