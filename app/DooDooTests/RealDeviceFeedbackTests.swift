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
            for: Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, AppSettings.self,
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

    // MARK: - 真机反馈：手续费必须落到「当日支出合计」（PRD 9.1 / 9.8）

    /// 之前只测到 ViewModel 联动，没测「保存 → 落库 → 合计」这条完整链路。
    /// 真机反馈「手续费没有被当支出」就是这块没有回归保护。
    @Test("转账 1000 / 到账 999.90：手续费落库且只按手续费计入支出")
    func transferFeeCountsAsExpense() throws {
        let context = try makeContext()
        let from = Account(name: "工资卡", kind: .savings, initialBalance: dec("5000"))
        let to = Account(name: "支付宝", kind: .savings, initialBalance: dec("0"))
        context.insert(from)
        context.insert(to)
        // 手续费流水要挂到内置分类「其他 › 手续费」，真机上是 SeedService 建的，
        // 内存容器不会自动 seed，这里手动补一条（key 与 Category.builtIn 一致）。
        context.insert(Category(
            key: "misc.fee", parentKey: "misc", name: "手续费",
            iconName: "Package", emoji: "🏦", sortOrder: 99,
            isIncome: false, tintHex: "#F2F1ED"
        ))
        try context.save()

        let vm = EntryViewModel()
        vm.load(context: context)
        vm.setType(.transfer)
        vm.payer = from
        vm.target = to
        vm.setAmountText("1000")
        vm.setFeeText("0.10")
        #expect(vm.canSave)

        vm.save(in: context)

        let txs = try context.fetch(FetchDescriptor<Transaction>())
        #expect(txs.count == 2, "转账本体 + 自动生成的手续费流水（PRD 9.8）")

        let tx = try #require(txs.first { $0.kind == .transfer })
        #expect(tx.fee == dec("0.10"), "手续费必须落库，不能只活在 ViewModel 里")
        #expect(tx.receivedAmount == dec("999.90"))

        let feeTx = try #require(txs.first { $0.kind == .expense })
        #expect(feeTx.amount == dec("0.10"), "手续费是一条独立的支出流水，不是藏起来的字段")
        #expect(feeTx.account?.name == "工资卡", "手续费挂在付款方账户上")
        #expect(feeTx.category?.key == "misc.fee", "分类必须是「其他 › 手续费」")
        #expect(feeTx.groupID != nil, "必须有分组 ID，否则删转账会留下孤儿流水")
        #expect(feeTx.groupID == tx.groupID, "转账与手续费共用同一个分组")

        // 合计从库里两条一起算，不再手工拼 TxFigure——
        // 手工拼只能证明函数本身对，证明不了「保存后的数据能算对」。
        let figures = txs
            .filter { $0.deletedAt == nil }
            .map { TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee) }
        #expect(DayMath.expenseTotal(figures) == dec("0.10"), "本金 1000 不计支出，只计手续费 0.10")

        // 转账按等额走（999.90），手续费再扣 0.10，合计正好扣满 1,000。
        #expect(from.currentBalance == dec("4000"), "转出方：999.90 + 0.10 = 扣满 1000")
        #expect(to.currentBalance == dec("999.90"), "转入方到账 999.90")
    }

    @Test("转账无手续费：不增加当日支出合计")
    func transferWithoutFeeNotCounted() throws {
        let context = try makeContext()
        let from = Account(name: "工资卡", kind: .savings, initialBalance: dec("5000"))
        let to = Account(name: "支付宝", kind: .savings, initialBalance: dec("0"))
        context.insert(from)
        context.insert(to)
        try context.save()

        let vm = EntryViewModel()
        vm.load(context: context)
        vm.setType(.transfer)
        vm.payer = from
        vm.target = to
        vm.setAmountText("1000")
        vm.save(in: context)

        let all = try context.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1, "无手续费时不额外生成任何流水")
        let tx = try #require(all.first)
        #expect(tx.fee == dec("0"), "无手续费时 fee 为 0，不是 nil 也算不出支出")
        #expect(tx.groupID == nil, "无手续费不需要分组")
        #expect(DayMath.expenseTotal([
            TxFigure(kind: tx.kind, amount: tx.amount, date: tx.date, fee: tx.fee)
        ]) == dec("0"))
        #expect(from.currentBalance == dec("4000"), "无手续费时转出方只扣 1000")
        #expect(to.currentBalance == dec("1000"), "转入方全额到账")
    }

    /// 手续费是独立流水，删转账时必须连带删掉，否则付款账户会永久少掉那份手续费
    /// （余额回滚不完整，且 `recalculateAll` 之后仍然对不上）。
    @Test("删转账：手续费流水一并软删，不留孤儿")
    func softDeleteTransferCascadesFee() throws {
        let context = try makeContext()
        let from = Account(name: "工资卡", kind: .savings, initialBalance: dec("5000"))
        let to = Account(name: "支付宝", kind: .savings, initialBalance: dec("0"))
        context.insert(from)
        context.insert(to)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("1000"), kind: .transfer, date: .now,
            account: from, toAccount: to, receivedAmount: dec("999.90"), in: context
        )
        #expect(from.currentBalance == dec("4000"), "转账 999.90 + 手续费 0.10 共扣 1,000")

        try LedgerService.softDelete(tx, in: context)

        let all = try context.fetch(FetchDescriptor<Transaction>())
        let alive = all.filter { $0.deletedAt == nil }
        #expect(alive.isEmpty, "转账和它的手续费必须一起删掉")

        let figures = alive.map {
            TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee)
        }
        #expect(DayMath.expenseTotal(figures) == 0, "删除后当日支出归零")

        #expect(from.currentBalance == dec("5000"), "付款账户全额回滚（999.90 + 0.10）")
        #expect(to.currentBalance == dec("0"), "收款账户回滚")
    }
}
