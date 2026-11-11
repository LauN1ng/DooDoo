import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 存量分期写入链路（M3-2）：建计划 → 展开未来期 → 连录时保留账户。
@MainActor
struct InstallmentServiceTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self,
            Installment.self, InstallmentPeriod.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - 建计划 + 展开期表

    @Test("建一笔花呗分期：计划与未来期表同时落库")
    func insertGeneratesPeriods() throws {
        let context = try makeContext()
        let card = Account(name: "花呗", kind: .credit, dueDay: 25)
        context.insert(card)
        try context.save()

        // PRD 9.5.3 的花呗例子：每期 120.03、12 期、含利息 110.56，还剩 9 期
        let plan = try InstallmentService.insert(
            name: "花呗分期 · AirPods",
            account: card,
            totalPeriods: 12,
            paidPeriods: 3,
            perPeriodAmount: dec("120.03"),
            totalInterest: dec("110.56"),
            nextDueDate: day(2026, 11, 25),
            calendar: calendar,
            in: context
        )

        #expect(plan.remainingPeriods == 9)
        #expect(plan.remainingTotal == dec("1080.27"))

        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(periods.count == 9)
        #expect(periods.first?.dueDate == day(2026, 11, 25))
        // 按月递增，跨年也不能错位
        #expect(periods[2].dueDate == day(2027, 1, 25))
        #expect(periods.last?.dueDate == day(2027, 7, 25))
        let allPaidCount = periods.filter { $0.isPaid }.count
        #expect(allPaidCount == 0)
        #expect(periods.allSatisfy { $0.amount == dec("120.03") })
    }

    @Test("首期/末期金额覆盖标准额，期表跟着变")
    func insertWithFirstAndLastAmount() throws {
        let context = try makeContext()
        let plan = try InstallmentService.insert(
            name: "京东白条",
            account: nil,
            totalPeriods: 4,
            paidPeriods: 0,
            perPeriodAmount: dec("100.00"),
            firstPeriodAmount: dec("100.50"),
            lastPeriodAmount: dec("98.50"),
            nextDueDate: day(2026, 12, 1),
            calendar: calendar,
            in: context
        )

        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(periods.map(\.amount) == [dec("100.50"), dec("100.00"), dec("100.00"), dec("98.50")])
        // 剩余总额要把首末差额算进去：400 + 0.5 − 1.5
        #expect(plan.remainingTotal == dec("399.00"))
    }

    @Test("剩余期数为 0：只建计划，不生成期表")
    func settledPlanHasNoPeriods() throws {
        let context = try makeContext()
        let plan = try InstallmentService.insert(
            name: "已结清的老分期",
            account: nil,
            totalPeriods: 6,
            paidPeriods: 6,
            perPeriodAmount: dec("50.00"),
            nextDueDate: day(2026, 11, 20),
            calendar: calendar,
            in: context
        )
        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(plan.isSettled)
        #expect(periods.isEmpty)
    }

    // MARK: - 重新生成

    @Test("重复生成不会产生重复期，手工改过的那期保留")
    func regenerateKeepsManualOverride() throws {
        let context = try makeContext()
        let plan = try InstallmentService.insert(
            name: "招行分期",
            account: nil,
            totalPeriods: 3,
            paidPeriods: 0,
            perPeriodAmount: dec("82.67"),
            nextDueDate: day(2026, 11, 20),
            calendar: calendar,
            in: context
        )

        // 照账单把第 2 期改成 80.00（招行余数落位只有账单知道）
        let periods = try InstallmentService.periods(for: plan.key, in: context)
        let second = try #require(periods.first(where: { $0.index == 2 }))
        second.amount = dec("80.00")
        second.isManualOverride = true
        try context.save()

        try InstallmentService.generateFuturePeriods(for: plan, calendar: calendar, in: context)

        let after = try InstallmentService.periods(for: plan.key, in: context)
        #expect(after.count == 3)
        let keptIndex2 = after.first(where: { $0.index == 2 })
        let rebuiltIndex1 = after.first(where: { $0.index == 1 })
        #expect(keptIndex2?.amount == dec("80.00"))
        #expect(keptIndex2?.isManualOverride == true)
        #expect(rebuiltIndex1?.isManualOverride == false)
    }

    // MARK: - 连录

    @Test("快速连录：录完只清这笔独有字段，账户与还款日留到下一笔")
    func viewModelKeepsAccountForNextEntry() throws {
        let context = try makeContext()
        let card = Account(name: "花呗", kind: .credit, dueDay: 25)
        context.insert(card)
        try context.save()

        let vm = InstallmentEntryViewModel()
        vm.load(context: context)
        #expect(vm.account?.name == "花呗")
        // 还款日由账户 dueDay 带出，不用手选
        #expect(calendar.component(.day, from: vm.dueDate) == 25)

        vm.remainingText = "9"
        vm.totalText = "12"
        vm.perPeriodText = "120.03"
        vm.interestText = "110.56"
        vm.name = "花呗分期 · AirPods"
        #expect(vm.save(in: context))

        #expect(vm.errorMessage == nil)
        #expect(vm.doneCount == 1)
        // 清掉的
        #expect(vm.name.isEmpty)
        #expect(vm.remainingText.isEmpty)
        #expect(vm.totalText.isEmpty)
        #expect(vm.perPeriodText.isEmpty)
        #expect(vm.interestText.isEmpty)
        // 留着的
        #expect(vm.account?.name == "花呗")
        #expect(calendar.component(.day, from: vm.dueDate) == 25)

        // 库里的计划口径正确：第 4/12 期起，未来 9 期
        let plans = try context.fetch(FetchDescriptor<Installment>())
        #expect(plans.count == 1)
        #expect(plans.first?.totalPeriods == 12)
        #expect(plans.first?.paidPeriods == 3)
        #expect(plans.first?.name == "花呗分期 · AirPods")
    }

    @Test("校验：没选卡、期数为 0、金额为 0 都存不进去")
    func validationBlocksBadInput() throws {
        let context = try makeContext()
        let vm = InstallmentEntryViewModel()
        vm.load(context: context)

        // 没有负债账户 → account 为 nil
        #expect(vm.validationMessage == "先选一张卡")
        #expect(vm.save(in: context) == false)

        let card = Account(name: "花呗", kind: .credit)
        context.insert(card)
        try context.save()
        vm.load(context: context)

        #expect(vm.validationMessage == "剩余期数要大于 0")
        vm.remainingText = "6"
        #expect(vm.validationMessage == "每期金额要大于 0")
        vm.perPeriodText = "0"
        #expect(vm.validationMessage == "每期金额要大于 0")
        vm.perPeriodText = "50"
        #expect(vm.canSave)

        // 选填项填了非法值也要拦
        vm.firstText = "0"
        #expect(vm.validationMessage == "首期金额要大于 0")
        vm.firstText = ""
        vm.rebateText = "-1"
        #expect(vm.validationMessage == "减免不能是负数")
        vm.rebateText = ""

        #expect(vm.save(in: context))
        let saved = try InstallmentService.count(in: context)
        #expect(saved == 1)
    }

    @Test("预览与落库口径一致：剩余总额、年化都走纯函数")
    func previewMatchesPersistedPlan() throws {
        let context = try makeContext()
        let vm = InstallmentEntryViewModel()
        vm.load(context: context)
        let card = Account(name: "e招贷", kind: .loan, dueDay: 10)
        context.insert(card)
        try context.save()
        vm.load(context: context)
        vm.selectAccount(card)

        // PRD 验收 3：e招贷每期 442.50 × 17 期，剩余本金 6,670.20 → 年化 ≈16.4%
        vm.remainingText = "17"
        vm.perPeriodText = "442.50"
        vm.principalText = "6670.20"

        let previewRate = try #require(vm.previewAnnualRate)
        #expect(abs(NSDecimalNumber(decimal: previewRate).doubleValue - 16.4) <= 0.5)
        #expect(vm.previewRemainingTotal == dec("7522.50"))

        #expect(vm.save(in: context))
        let plan = try #require(try context.fetch(FetchDescriptor<Installment>()).first)
        #expect(plan.estimatedAnnualRate == previewRate)
        #expect(plan.remainingTotal == dec("7522.50"))
        #expect(plan.remainingPrincipal == dec("6670.20"))
    }
}
