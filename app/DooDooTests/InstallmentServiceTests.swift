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

    // MARK: - 剩余应还摊平（M3-3）

    @Test("给了剩余应还就按它摊：每期除得尽，末期等于标准额")
    func remainingDueSplitsEvenly() throws {
        let context = try makeContext()
        // 用户 11-11 的真实账单：剩余应还 1830.15、剩 9 期 → 每期 203.35 正好
        let plan = try InstallmentService.insert(
            name: "招行账单分期",
            account: nil,
            totalPeriods: 12,
            paidPeriods: 3,
            perPeriodAmount: dec("203.35"),
            remainingDue: dec("1830.15"),
            totalInterest: dec("176.99"),
            nextDueDate: day(2026, 11, 25),
            calendar: calendar,
            in: context
        )

        // 剩余总额严格等于账单上的数，不是「每期 × 期数」算出来的近似值
        #expect(plan.remainingTotal == dec("1830.15"))

        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(periods.count == 9)
        #expect(periods.allSatisfy { $0.amount == dec("203.35") })
        #expect(periods.reduce(Decimal(0)) { $0 + $1.amount } == dec("1830.15"))
    }

    @Test("剩余应还除不尽：余数全落末期，前八期仍是标准额")
    func remainingDuePutsRemainderOnLastPeriod() throws {
        let context = try makeContext()
        // 1830.17 ÷ 9 = 203.352... → 其余各期 203.35，首期 203.37 收零头
        let plan = try InstallmentService.insert(
            name: "除不尽的账单",
            account: nil,
            totalPeriods: 9,
            paidPeriods: 0,
            perPeriodAmount: dec("203.35"),
            remainingDue: dec("1830.17"),
            nextDueDate: day(2026, 11, 25),
            calendar: calendar,
            in: context
        )

        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(periods.count == 9)
        #expect(periods.dropFirst().allSatisfy { $0.amount == dec("203.35") })
        #expect(periods.first?.amount == dec("203.37"))
        // 加起来一分不差
        #expect(periods.reduce(Decimal(0)) { $0 + $1.amount } == dec("1830.17"))
        #expect(plan.remainingTotal == dec("1830.17"))
    }

    // MARK: - 老数据迁移

    @Test("老库的「剩余本金」搬到「剩余应还」，并清掉历史首期，可重复调用")
    func migratesLegacyRemainingPrincipal() throws {
        let context = try makeContext()
        // 复现 M3-2 时代录进去的那条：用户把「剩余应还」填进了「剩余本金」，
        // 又把**历史**第 1 期 203.43 填进了「首期金额」
        let legacy = Installment(
            key: "legacy",
            name: "招行账单分期",
            totalPeriods: 12,
            paidPeriods: 3,
            perPeriodAmount: dec("203.35"),
            firstPeriodAmount: dec("203.43"),
            remainingPrincipal: dec("1830.15"),
            totalInterest: dec("176.99"),
            nextDueDate: day(2026, 11, 25)
        )
        context.insert(legacy)
        try context.save()

        // 迁之前：剩余总额被那个历史首期带偏 0.08
        #expect(legacy.remainingTotal == dec("1830.23"))

        let migrated = try InstallmentService.migrateLegacyRemainingPrincipal(calendar: calendar, in: context)
        #expect(migrated == 1)
        #expect(legacy.remainingDue == dec("1830.15"))
        #expect(legacy.remainingPrincipal == nil)
        #expect(legacy.firstPeriodAmount == nil)
        #expect(legacy.remainingTotal == dec("1830.15"))

        // 期表也跟着重建成摊平后的金额
        let periods = try InstallmentService.periods(for: "legacy", in: context)
        #expect(periods.count == 9)
        #expect(periods.allSatisfy { $0.amount == dec("203.35") })

        // 幂等：第二次没有可搬的
        #expect(try InstallmentService.migrateLegacyRemainingPrincipal(calendar: calendar, in: context) == 0)
        #expect(legacy.remainingDue == dec("1830.15"))
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

        // 新表单只填三个数：剩余应还 / 剩余期数 / 含利息（+ 总期数只为「第 x/y 期」）
        vm.remainingDueText = "1080.27"
        vm.remainingText = "9"
        vm.totalText = "12"
        vm.interestText = "110.56"
        vm.name = "花呗分期 · AirPods"
        // 每期金额是除出来的，不用手填
        #expect(vm.perPeriodAmount == dec("120.03"))
        #expect(vm.save(in: context))

        #expect(vm.errorMessage == nil)
        #expect(vm.doneCount == 1)
        // 清掉的
        #expect(vm.name.isEmpty)
        #expect(vm.remainingDueText.isEmpty)
        #expect(vm.remainingText.isEmpty)
        #expect(vm.totalText.isEmpty)
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
        #expect(plans.first?.remainingDue == dec("1080.27"))
    }

    @Test("校验：没选卡、没填剩余应还、期数为 0、总期数填反都存不进去")
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

        // 新表单第一个要填的是「剩余应还」
        #expect(vm.validationMessage == "填一下账单上的「剩余应还」")
        vm.remainingDueText = "300"
        #expect(vm.validationMessage == "剩余期数要大于 0")
        vm.remainingText = "6"
        // 300 ÷ 6 = 50，每期自动出来，不用手填
        #expect(vm.perPeriodAmount == dec("50.00"))
        #expect(vm.canSave)

        // 总期数填得比剩余期数还少 —— 那是填错了，要拦而不是静默回退
        vm.totalText = "3"
        #expect(vm.validationMessage == "总共 3 期比剩余 6 期还少，检查一下")
        vm.totalText = "6"
        #expect(vm.canSave)

        vm.rebateText = "-1"
        #expect(vm.validationMessage == "减免不能是负数")
        vm.rebateText = ""

        #expect(vm.save(in: context))
        let saved = try InstallmentService.count(in: context)
        #expect(saved == 1)
    }

    @Test("预览与落库口径一致：用户 11-11 的真实账单算出 14.13%")
    func previewMatchesPersistedPlan() throws {
        let context = try makeContext()
        let vm = InstallmentEntryViewModel()
        vm.load(context: context)
        let card = Account(name: "招商银行", kind: .credit, dueDay: 25)
        context.insert(card)
        try context.save()
        vm.load(context: context)
        vm.selectAccount(card)

        // 招行「账单分期明细详情」原文：
        // 剩余应还 1830.15 / 含利息 176.99 / 第 4 期起共 12 期 / 每期 203.35（平息法）
        // 旧版把 1830.15 填进「剩余本金」，203.35 × 9 恰好也是 1830.15，
        // 于是被判成零息输出 0.0%。新版按整笔口径算：现值 = 12 × 203.35 − 176.99
        vm.remainingDueText = "1830.15"
        vm.remainingText = "9"
        vm.totalText = "12"
        vm.interestText = "176.99"

        #expect(vm.perPeriodAmount == dec("203.35"))
        #expect(vm.previewRemainingTotal == dec("1830.15"))
        #expect(vm.periods.paid == 3)

        let previewRate = try #require(vm.previewAnnualRate)
        #expect(abs(NSDecimalNumber(decimal: previewRate).doubleValue - 14.13) <= 0.05)

        #expect(vm.save(in: context))
        let plan = try #require(try context.fetch(FetchDescriptor<Installment>()).first)
        #expect(plan.estimatedAnnualRate == previewRate)
        #expect(plan.remainingTotal == dec("1830.15"))
        #expect(plan.remainingDue == dec("1830.15"))
        // 新数据不再写那个陷阱字段
        #expect(plan.remainingPrincipal == nil)
    }

    @Test("没填总期数就不报年化，并说清缺哪个数")
    func missingTotalPeriodsSkipsAnnualRate() throws {
        let context = try makeContext()
        let vm = InstallmentEntryViewModel()
        vm.load(context: context)
        let card = Account(name: "花呗", kind: .credit, dueDay: 25)
        context.insert(card)
        try context.save()
        vm.load(context: context)

        vm.remainingDueText = "1080.27"
        vm.remainingText = "9"
        // 只填含利息、不填总期数：整笔分母缺失，不该拿 9 期冒充
        vm.interestText = "110.56"
        #expect(vm.previewAnnualRate == nil)
        #expect(vm.annualRateHint == "再填「总共几期」，就能算这笔分期的真实年化。")

        vm.totalText = "12"
        #expect(vm.previewAnnualRate != nil)
        #expect(vm.annualRateHint == nil)
    }
}
