import Foundation
import SwiftData
import Testing
import UIKit

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
        // 必须排除软删除：产品代码里所有查询都要这么做（AGENTS 7.2），
        // 这里漏掉会让「软删回滚」那条用例把删掉的手续费也算进来。
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let figures = transactions
            .filter { $0.deletedAt == nil }
            .map { TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee) }
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
        // `tx.fee` 是 `Decimal?`，不能直接与 `Decimal` 比较（Optional 不参与隐式提升）。
        let fee = tx.fee ?? 0
        let savingsBalance = savings.currentBalance
        let creditBalance = credit.currentBalance
        let netSum = savingsBalance + creditBalance

        #expect(fee == dec("0.10"))
        #expect(savingsBalance == dec("4000.00"), "转账 999.90 + 手续费流水 0.10 = 共扣 1000")
        #expect(creditBalance == dec("-2217.52"), "转入账户只入账 999.90")
        #expect(netSum == dec("1782.48"), "两边余额之和比原来少 0.10，正好是手续费")
        #expect(total == dec("0.10"), "转账本金不算消费，只算那条手续费流水")
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

        // 类型名必须写全 `DooDoo.Category`：测试模块里同时导入了别的同名类型，
        // 只在泛型参数位置（`FetchDescriptor<Category>`）才会暴露二义性。
        let top = DooDoo.Category(key: "food", parentKey: nil, name: "吃", iconName: "Croissant",
                                  emoji: "🍰", sortOrder: 0, isIncome: false, tintHex: "#FFF1E6")
        let sub = DooDoo.Category(key: "food.coffee", parentKey: "food", name: "咖啡", iconName: "HotBeverage",
                                  emoji: "☕️", sortOrder: 8, isIncome: false, tintHex: "#FFF1E6")
        context.insert(top)
        context.insert(sub)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DooDoo.Category>())
        #expect(all.filter { $0.isTopLevel }.count == 1)
        #expect(all.filter { $0.parentKey == "food" }.count == 1)
        #expect(sub.isTopLevel == false)
    }

    @Test("内置分类够用：一级 10 个、二级 51 个")
    func builtInCount() {
        let tops = DooDoo.Category.builtIn.filter { $0.parentKey == nil }
        let subs = DooDoo.Category.builtIn.filter { $0.parentKey != nil }
        #expect(tops.count == 10)
        #expect(subs.count == 51)
        #expect(tops.filter { !$0.isIncome }.count == 8)
        #expect(tops.filter { $0.isIncome }.count == 2)

        // 2026-11-10 图标定案时补的三个二级：住/水费、行/飞机、行/轮船
        let added: Set<String> = ["home.water", "transport.plane", "transport.ship"]
        #expect(added.isSubset(of: Set(subs.map(\.key))))

        // 每个槽位都有图标名（2026-11-10 起二级不再复用父级图标）
        #expect(DooDoo.Category.builtIn.allSatisfy { !$0.icon.isEmpty })
    }

    @Test("老库覆盖安装：缺的三个二级分类会被补建，且可重复调用")
    func ensureBuiltInCategoriesBackfillsOldLibrary() throws {
        let context = try makeContext()

        // 模拟 11-10 之前的老库：builtIn 去掉当天新增的三个二级，共 58 条
        let added: Set<String> = ["home.water", "transport.plane", "transport.ship"]
        var index = 0
        for item in DooDoo.Category.builtIn where !added.contains(item.key) {
            context.insert(DooDoo.Category(
                key: item.key,
                parentKey: item.parentKey,
                name: item.name,
                iconName: item.icon,
                emoji: item.emoji,
                sortOrder: index,
                isIncome: item.isIncome,
                tintHex: item.tint
            ))
            index += 1
        }
        try context.save()

        let before = try context.fetch(FetchDescriptor<DooDoo.Category>())
        #expect(before.count == 58)

        try SeedService.ensureBuiltInCategories(context: context)

        let after = try context.fetch(FetchDescriptor<DooDoo.Category>())
        #expect(after.count == 61)
        #expect(added.isSubset(of: Set(after.map(\.key))))
        // 必须挂在正确父类下，否则「住」底下不会长出「水费」
        #expect(after.first { $0.key == "home.water" }?.parentKey == "home")
        #expect(after.first { $0.key == "transport.plane" }?.parentKey == "transport")
        #expect(after.first { $0.key == "transport.ship" }?.parentKey == "transport")
        // sortOrder 沿用 builtIn 下标，补进来的排在父类末尾而不是整个列表末尾
        let waterOrder = after.first { $0.key == "home.water" }?.sortOrder
        #expect(waterOrder == DooDoo.Category.builtIn.firstIndex { $0.key == "home.water" })

        // 幂等：`prepare` 每次启动都会调，重复不该多出来
        try SeedService.ensureBuiltInCategories(context: context)
        let again = try context.fetch(FetchDescriptor<DooDoo.Category>())
        #expect(again.count == 61)
    }

    @Test("分类图标都真正进了包，不会退回 emoji 兜底")
    func categoryIconsShipInBundle() throws {
        let names = Set(DooDoo.Category.builtIn.map(\.icon))
        #expect(names.count == 57)

        // 按名为空或查不到时 `CategoryPicker` 会退回 `Category.emoji`——
        // 那正是「记一笔是系统 emoji、流水是 3D 图」两套语言的来源。
        for name in names {
            #expect(UIImage(named: name) != nil, "图标 \(name) 没进包，分类页会退回 emoji")
        }
    }
}
