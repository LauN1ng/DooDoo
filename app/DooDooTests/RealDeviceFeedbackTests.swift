import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 2026-11-09 首轮真机反馈的回归测试：#1 新流水时间戳、#8 负债账户余额符号、
/// #9 手续费输入。手势方向（#2）与二级分类回显（#7）属交互，靠真机复看截图。
@MainActor
struct RealDeviceFeedbackTests {
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

    // MARK: - #1 新的一笔不该排在日卡最下面

    @Test("今天记一笔用当前时刻，不再落到 00:00")
    func entryTimestampToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12, minute: 19, second: 7
        ))!
        let dayStart = calendar.startOfDay(for: now)
        #expect(DayMath.entryTimestamp(for: dayStart, now: now, calendar: calendar) == now)
    }

    @Test("补记昨天：日期不变，时分秒取当前")
    func entryTimestampPastDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12, minute: 19, second: 7
        ))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8))!
        let result = DayMath.entryTimestamp(for: yesterday, now: now, calendar: calendar)
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: result
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 8)
        #expect(parts.hour == 12)
        #expect(parts.minute == 19)
        #expect(parts.second == 7)
    }

    // MARK: - #8 负债账户「欠款正数」录入 + 旧数据纠正

    @Test("旧数据纠正：+600 的信用账户改成 −600，且重复执行不翻转")
    func liabilitySignNormalized() throws {
        let context = try makeContext()
        let credit = Account(name: "白条", kind: .credit, initialBalance: dec("600"))
        let savings = Account(name: "工资卡", kind: .savings, initialBalance: dec("1200"))
        context.insert(credit)
        context.insert(savings)
        try context.save()
        try LedgerService.recalculateAll(in: context)

        try SeedService.normalizeLiabilitySigns(context: context)
        #expect(credit.currentBalance == dec("-600"))
        #expect(credit.initialBalance == dec("-600"))
        #expect(savings.currentBalance == dec("1200"), "储蓄账户不受影响")

        try SeedService.normalizeLiabilitySigns(context: context)
        #expect(credit.currentBalance == dec("-600"), "幂等：不能翻回 +600")
    }

    @Test("纠正后还款页能带出欠款 600.00，主按钮不再禁用")
    func repaymentAfterSignFix() throws {
        let context = try makeContext()
        let savings = Account(name: "工资卡", kind: .savings, initialBalance: dec("5000"))
        let credit = Account(name: "白条", kind: .credit, initialBalance: dec("600"))
        context.insert(savings)
        context.insert(credit)
        try context.save()
        try LedgerService.recalculateAll(in: context)
        try SeedService.normalizeLiabilitySigns(context: context)

        let vm = EntryViewModel()
        vm.load(context: context)
        vm.setType(.repayment)
        #expect(vm.amountText == "600.00", "默认带出欠款总额")
        #expect(vm.canSave, "还款主按钮不再被禁用")
    }

    @Test("多还款产生的正余额（溢缴）是合法状态，不能被纠正翻回欠款")
    func overpaymentNotFlipped() throws {
        let context = try makeContext()
        let savings = Account(name: "工资卡", kind: .savings, initialBalance: dec("5000"))
        let credit = Account(name: "白条", kind: .credit, initialBalance: dec("-600"))
        context.insert(savings)
        context.insert(credit)
        try context.save()
        try LedgerService.recalculateAll(in: context)
        try LedgerService.insert(
            amount: dec("682.58"), kind: .repayment, date: .now,
            account: savings, toAccount: credit, in: context
        )
        #expect(credit.currentBalance == dec("82.58"))

        try SeedService.normalizeLiabilitySigns(context: context)
        #expect(credit.currentBalance == dec("82.58"), "有还款流水的正余额是溢缴，不纠正")
    }

    // MARK: - #9 PRD 9.8「直接填手续费」这一路

    @Test("填手续费 0.10：到账自动反算为 999.90")
    func feeInputDrivesReceived() {
        let vm = EntryViewModel()
        vm.setType(.transfer)
        vm.setAmountText("1000")
        vm.setFeeText("0.10")
        #expect(vm.received == dec("999.90"))
        #expect(vm.fee == dec("0.10"))
        #expect(vm.receivedText == "999.90")
    }

    @Test("填到账 999.00：手续费自动反算为 1.00")
    func receivedInputDrivesFee() {
        let vm = EntryViewModel()
        vm.setType(.transfer)
        vm.setAmountText("1000")
        vm.setReceivedText("999.00")
        #expect(vm.feeText == "1.00")
        #expect(vm.fee == dec("1.00"))
    }

    @Test("改转出金额：按最后一次编辑的字段保持另一边")
    func amountChangeKeepsLastEditedField() {
        let vm = EntryViewModel()
        vm.setType(.transfer)
        vm.setAmountText("1000")
        vm.setFeeText("0.10")
        vm.setAmountText("2000")
        #expect(vm.feeText == "0.10", "手续费固定")
        #expect(vm.received == dec("1999.90"))

        vm.setReceivedText("1990.00")
        #expect(vm.feeText == "10.00", "改为到账优先后手续费重算")
        vm.setAmountText("3000")
        #expect(vm.received == dec("1990.00"))
        #expect(vm.fee == dec("1010.00"))
    }

    @Test("手续费大于转出金额时校验拦住")
    func feeLargerThanAmountRejected() {
        let vm = EntryViewModel()
        vm.setType(.transfer)
        vm.setFeeText("0.10")
        vm.setAmountText("0.05")
        #expect(vm.validationMessage == "手续费不能大于转出金额")
    }
}
