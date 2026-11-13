import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 记一笔里的内联分期 + 账期归属（M3-10，PRD 9.5.6 / 9.7）。
///
/// 门禁要钉住三件事：
/// 1. 勾了分期 → **一条全额 `expense`** + **一张剩余期数 = 全期的计划**
/// 2. 这条消费带上账期（`billPeriod`），且默认值是按账户账单周期算的
/// 3. 「我欠」不会因为「全额消费 + 分期计划」而翻倍（`createdFromEntry` 的计划不入账）
@MainActor
struct EntryInstallmentTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
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

    /// 花呗：信用账户，账单周期 15–14，还款日 25。储蓄卡用来测「分期开关不出现」。
    private func makeAccounts(in context: ModelContext) throws -> (savings: Account, credit: Account) {
        let savings = Account(name: "建行 5044", kind: .savings, initialBalance: dec("5000"), sortOrder: 0)
        let credit = Account(
            name: "花呗", kind: .credit,
            initialBalance: dec("-1000"),
            billCycleStart: 15, billCycleEnd: 14, dueDay: 25,
            sortOrder: 1
        )
        context.insert(savings)
        context.insert(credit)
        let food = DooDoo.Category(
            key: "food", parentKey: nil, name: "吃", iconName: "Croissant",
            emoji: "🍰", sortOrder: 0, isIncome: false, tintHex: "#FFF1E6"
        )
        context.insert(food)
        try context.save()
        try LedgerService.recalculateAll(in: context)
        return (savings, credit)
    }

    /// 装一台已经停在「支出」的记一笔。
    private func makeViewModel(
        in context: ModelContext,
        account: Account,
        amount: String,
        date: Date = .now
    ) -> EntryViewModel {
        let vm = EntryViewModel()
        vm.load(context: context)
        vm.date = date
        vm.payer = account
        vm.topKey = "food"
        vm.amountText = amount
        return vm
    }

    // MARK: - 内联分期

    @Test("勾了分期：一条全额支出 + 一张 12 期计划，期表按总额摊平、余数落首期")
    func entryCreatesFullExpenseAndPlan() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: credit, amount: "1440.39", date: day(2026, 11, 5))
        vm.installmentEnabled = true
        vm.installmentPeriods = 12
        vm.installmentPerPeriodText = "120.03"
        vm.installmentFirstDue = day(2026, 12, 10)
        vm.save(in: context)

        #expect(vm.errorMessage == nil)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1, "只写一条流水，不是每期一条")
        let tx = try #require(transactions.first)
        #expect(tx.kind == .expense)
        #expect(tx.amount == dec("1440.39"), "必须记全额：只记 120.03 会让欠款少算 1,320.36")
        #expect(tx.account?.persistentModelID == credit.persistentModelID)
        #expect(credit.currentBalance == dec("-2440.39"))

        let plans = try context.fetch(FetchDescriptor<Installment>())
        #expect(plans.count == 1)
        let plan = try #require(plans.first)
        #expect(plan.totalPeriods == 12)
        #expect(plan.paidPeriods == 0, "新发生的分期，剩余期数 = 全期")
        #expect(plan.remainingPeriods == 12)
        #expect(plan.remainingDue == dec("1440.39"))
        #expect(plan.perPeriodAmount == dec("120.03"))
        #expect(plan.createdFromEntry, "记一笔建的，账期那一项不再加它")
        #expect(plan.account?.persistentModelID == credit.persistentModelID)

        let periods = try InstallmentService.periods(for: plan.key, in: context)
        #expect(periods.count == 12)
        #expect(periods.first?.amount == dec("120.06"), "分币余数落首期（与账单校准一致）")
        #expect(periods.dropFirst().allSatisfy { $0.amount == dec("120.03") })
        #expect(periods.reduce(Decimal.zero) { $0 + $1.amount } == dec("1440.39"))
        // 计划落库走 `InstallmentService` 的默认日历（`.current`），比较时也用同一个
        #expect(periods.first?.dueDate == Calendar.current.startOfDay(for: day(2026, 12, 10)))
    }

    @Test("「我欠」不翻倍：全额消费已在余额里，计划不再重复入账")
    func oweDoesNotDoubleCount() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: credit, amount: "1440.39", date: day(2026, 11, 5))
        vm.installmentEnabled = true
        vm.installmentPeriods = 12
        vm.installmentFirstDue = day(2026, 12, 10)
        vm.save(in: context)

        // 一条全额 expense 把余额从 −1,000 推到 −2,440.39；
        // 计划是 `createdFromEntry`，所以不再入账。
        #expect(credit.currentBalance == dec("-2440.39"))
        // 欠款 = 余额的负数。旧口径在这里会给出 3,880.78（余额 + 期表又加一遍）。
        #expect(CreditDebt.owe(balance: credit.currentBalance) == dec("2440.39"))
    }

    @Test("存量分期入账一次：欠款 = 余额，不需要第二套派生")
    func legacyPlanAmountsIntoBalance() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        try InstallmentService.insert(
            name: "存量分期", account: credit,
            totalPeriods: 6, paidPeriods: 0,
            perPeriodAmount: dec("200"), remainingDue: dec("1200"),
            nextDueDate: day(2026, 12, 22),
            in: context
        )

        // 建计划即入账：−1,000 − 1,200 = −2,200。这是 2026-11-13 口径统一的核心，
        // 录了分期欠款就必须变——否则「我欠」看不见这笔债。
        #expect(credit.currentBalance == dec("-2200.00"))
        #expect(CreditDebt.owe(balance: credit.currentBalance) == dec("2200.00"))
    }

    @Test("储蓄账户：不出现分期块，也不建计划")
    func savingsAccountGetsNoPlan() throws {
        let context = try makeContext()
        let (savings, _) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: savings, amount: "88.00", date: day(2026, 11, 5))
        #expect(vm.canUseInstallment == false)

        // 就算状态被外部置上（切账户后残留），保存也不该建计划
        vm.installmentEnabled = true
        vm.save(in: context)

        #expect(vm.errorMessage == nil)
        let plans = try context.fetch(FetchDescriptor<Installment>())
        #expect(plans.isEmpty)
        #expect(savings.currentBalance == dec("4912.00"))
    }

    @Test("每期 × 期数与总额差超过 1 元：拦下，不静默摊出一张对不上的表")
    func gapValidation() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: credit, amount: "1440.39", date: day(2026, 11, 5))
        vm.installmentEnabled = true
        vm.installmentPeriods = 12
        vm.installmentPerPeriodText = "100"
        #expect(vm.canSave == false)
        #expect(vm.installmentValidationMessage != nil)

        // 差几分（真实账单的除不尽）不该拦
        vm.installmentPerPeriodText = "120.03"
        #expect(vm.installmentValidationMessage == nil)
        #expect(vm.canSave)
    }

    @Test("首期还款日跟着这一笔落在的那一期走（不是「最近的 dueDay」）")
    func firstDueFollowsPeriod() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        // 11/05 → 账期 2026-11 → 11/25
        let early = makeViewModel(in: context, account: credit, amount: "100", date: day(2026, 11, 5))
        early.installmentEnabled = true
        #expect(Calendar.current.isDate(early.installmentFirstDueDate, inSameDayAs: day(2026, 11, 25)))

        // 11/20 已过账单日 → 账期 2026-12 → 首期 12/25，不是 11/25
        let late = makeViewModel(in: context, account: credit, amount: "100", date: day(2026, 11, 20))
        late.installmentEnabled = true
        #expect(Calendar.current.isDate(late.installmentFirstDueDate, inSameDayAs: day(2026, 12, 25)))

        // 手动切到下一期，首期日跟着变
        late.billPeriodOverride = "2027-01"
        #expect(Calendar.current.isDate(late.installmentFirstDueDate, inSameDayAs: day(2027, 1, 25)))
    }

    // MARK: - 账期归属

    @Test("信用账户的支出带上账期：11/05 → 2026-11")
    func expenseCarriesBillPeriod() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: credit, amount: "56.00", date: day(2026, 11, 5))
        #expect(vm.resolvedBillPeriod == "2026-11")
        vm.save(in: context)

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let tx = try #require(all.first)
        #expect(tx.billPeriod == "2026-11")
    }

    @Test("过了账单日算下一期：11/20 → 2026-12，也可以手动改回来")
    func billPeriodFollowsCycleAndOverride() throws {
        let context = try makeContext()
        let (_, credit) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: credit, amount: "56.00", date: day(2026, 11, 20))
        #expect(vm.resolvedBillPeriod == "2026-12")
        #expect(vm.billPeriodChoices == ["2026-12", "2027-01"])

        vm.billPeriodOverride = "2026-11"
        #expect(vm.resolvedBillPeriod == "2026-11")
        vm.save(in: context)

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let tx = try #require(all.first)
        #expect(tx.billPeriod == "2026-11")
    }

    @Test("储蓄账户的支出没有账期（当场扣钱，不存在账单周期）")
    func savingsExpenseHasNoPeriod() throws {
        let context = try makeContext()
        let (savings, _) = try makeAccounts(in: context)

        let vm = makeViewModel(in: context, account: savings, amount: "20.00", date: day(2026, 11, 5))
        #expect(vm.resolvedBillPeriod == nil)
        vm.save(in: context)

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let tx = try #require(all.first)
        #expect(tx.billPeriod == nil)
    }

    @Test("还款流水也标账期：发生月就是被还的那一期")
    func repaymentCarriesBillPeriod() throws {
        let context = try makeContext()
        let (savings, credit) = try makeAccounts(in: context)

        let vm = EntryViewModel()
        vm.load(context: context)
        vm.setType(.repayment)
        vm.date = day(2026, 11, 25)
        vm.payer = savings
        vm.target = credit
        vm.amountText = "500"
        vm.save(in: context)

        #expect(vm.errorMessage == nil)
        let all = try context.fetch(FetchDescriptor<Transaction>())
        let tx = try #require(all.first { $0.kind == .repayment })
        #expect(tx.billPeriod == "2026-11")
    }
}
