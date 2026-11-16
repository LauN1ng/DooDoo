import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 二级分类的「按大类分桶记忆」（2026-11-16 用户定案，方案 A）。
///
/// 门禁原话（真机反馈）：**「选中二级分类后再切换大类，上一个大类会切回默认图标」**。
/// 根因是 `subKey` 曾是全局单值、`selectTop` 换类时又把它清空——两处叠加，上一类的
/// 选择在切换那一刻就没了。现在读写都落到 `subKeyByTop[topKey]`。
///
/// 这组用例锁三件事，缺一条这个 bug 就会以别的形状回来：
/// 1. **切走再切回**，二级还在，且切走的那一格仍然显示它（`shownByTop`）；
/// 2. `subKey` 是桶的视图而不是另一份数据——写 `subKey` 必须落到桶里，
///    否则又变成「格子里显示咖啡、保存时却是一级」的两处分叉；
/// 3. **切类型整桶清空**：支出与收入是两套分类树，串过去会记错类。
@MainActor
struct CategoryMemoryTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self, Installment.self,
                InstallmentPeriod.self, BillStatement.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// 只造够用的分类：两个支出一级（各带一个二级）+ 一个收入一级。
    /// 全量 51 个在这里没有额外价值，反而让断言看不出重点。
    ///
    /// 类型名一律写全 `DooDoo.Category`：测试模块里这个名字有二义性，裸写
    /// 只在部分位置（返回类型、泛型参数）才报错，先例见 `EntryFlowTests.swift:163`。
    private func seed(in context: ModelContext) throws {
        let rows: [DooDoo.Category] = [
            DooDoo.Category(key: "food", parentKey: nil, name: "吃", iconName: "ForkAndKnifeWithPlate",
                            emoji: "🍰", sortOrder: 0, isIncome: false, tintHex: "#FFF1E6"),
            DooDoo.Category(key: "food.coffee", parentKey: "food", name: "咖啡", iconName: "HotBeverage",
                            emoji: "☕️", sortOrder: 100, isIncome: false, tintHex: "#FFF1E6"),
            DooDoo.Category(key: "food.lunch", parentKey: "food", name: "午餐", iconName: "CookedRice",
                            emoji: "🍱", sortOrder: 101, isIncome: false, tintHex: "#FFF1E6"),

            DooDoo.Category(key: "wear", parentKey: nil, name: "穿", iconName: "Necktie",
                            emoji: "👕", sortOrder: 1, isIncome: false, tintHex: "#FDF1EA"),
            DooDoo.Category(key: "wear.top", parentKey: "wear", name: "上衣", iconName: "TShirt",
                            emoji: "👕", sortOrder: 110, isIncome: false, tintHex: "#FDF1EA"),

            DooDoo.Category(key: "salary", parentKey: nil, name: "工资", iconName: "MoneyBag",
                            emoji: "💰", sortOrder: 10, isIncome: true, tintHex: "#EAF6F1"),
        ]
        rows.forEach { context.insert($0) }
        context.insert(Account(name: "钱包", kind: .savings, initialBalance: 0))
        try context.save()
    }

    private func makeViewModel() throws -> (EntryViewModel, ModelContext) {
        let context = try makeContext()
        try seed(in: context)
        let vm = EntryViewModel()
        vm.load(context: context)
        return (vm, context)
    }

    private func category(_ key: String, in vm: EntryViewModel) throws -> DooDoo.Category {
        try #require(vm.categories.first { $0.key == key })
    }

    @Test("切到别的大类再切回来，二级还在")
    func keepsSubAcrossTopSwitch() throws {
        let (vm, _) = try makeViewModel()
        let food = try category("food", in: vm)
        let wear = try category("wear", in: vm)
        let coffee = try category("food.coffee", in: vm)

        vm.selectTop(food)
        vm.selectSub(coffee)
        #expect(vm.subKey == "food.coffee")

        vm.selectTop(wear)
        // 「穿」自己还没选过，所以它没有二级——但它不该把「吃」的抹掉。
        #expect(vm.subKey == nil)
        #expect(vm.subKeyByTop["food"] == "food.coffee")

        vm.selectTop(food)
        #expect(vm.subKey == "food.coffee", "切回来必须还是咖啡")
    }

    @Test("切走的那一格仍然显示它记着的二级（shownByTop）")
    func showsRememberedSubForInactiveTop() throws {
        let (vm, _) = try makeViewModel()
        let food = try category("food", in: vm)
        let wear = try category("wear", in: vm)
        let coffee = try category("food.coffee", in: vm)

        vm.selectTop(food)
        vm.selectSub(coffee)
        vm.selectTop(wear)

        // 当前停在「穿」，「吃」那格仍然显示咖啡——这是方案 A 的可见结果。
        #expect(vm.shownByTop["food"]?.key == "food.coffee")
        // 没选过二级的「穿」显示大类自己，不能凭空带出个二级。
        #expect(vm.shownByTop["wear"]?.key == "wear")
    }

    @Test("写 subKey 落在桶里，不是另存一份")
    func subKeyWritesIntoBucket() throws {
        let (vm, _) = try makeViewModel()
        let food = try category("food", in: vm)
        vm.selectTop(food)

        vm.subKey = "food.lunch"
        #expect(vm.subKeyByTop["food"] == "food.lunch")
        #expect(vm.subKey == "food.lunch")

        // 置 nil 只摘掉当前大类那一条，别的类不受影响。
        vm.selectSub(try category("food.coffee", in: vm))
        vm.subKey = nil
        #expect(vm.subKeyByTop["food"] == nil)
        #expect(vm.subKey == nil)
    }

    @Test("切换收入/支出清空全部记忆")
    func clearsAllOnTypeSwitch() throws {
        let (vm, _) = try makeViewModel()
        let food = try category("food", in: vm)

        vm.selectTop(food)
        vm.selectSub(try category("food.coffee", in: vm))
        #expect(vm.subKeyByTop.isEmpty == false)

        vm.setType(.income)
        #expect(vm.subKeyByTop.isEmpty, "支出与收入是两套分类树，不能串")

        vm.setType(.expense)
        #expect(vm.subKeyByTop.isEmpty)
        #expect(vm.subKey == nil)
    }

    @Test("selectedCategory 跟着桶走：有二级用二级，没有用一级")
    func selectedCategoryFollowsBucket() throws {
        let (vm, _) = try makeViewModel()
        let food = try category("food", in: vm)
        let wear = try category("wear", in: vm)

        vm.selectTop(food)
        vm.selectSub(try category("food.coffee", in: vm))
        #expect(vm.selectedCategory?.key == "food.coffee")

        // 「穿」没有二级记忆 → 落库必须是一级，不能沿用「吃」的咖啡。
        vm.selectTop(wear)
        #expect(vm.selectedCategory?.key == "wear")
    }
}
