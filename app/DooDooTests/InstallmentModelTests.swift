import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 分期模型的口径（M3）：剩余期数、剩余总额、年化路径选择、逾期判断。
@MainActor
struct InstallmentModelTests {
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

    @Test("剩余期数与已还清判定")
    func remainingPeriods() {
        let plan = Installment(
            key: "e招贷", name: "e招贷", totalPeriods: 24, paidPeriods: 7,
            perPeriodAmount: dec("442.50"), nextDueDate: day(2026, 12, 10)
        )
        #expect(plan.remainingPeriods == 17)
        #expect(plan.isSettled == false)

        plan.paidPeriods = 24
        #expect(plan.remainingPeriods == 0)
        #expect(plan.isSettled)
        #expect(plan.remainingTotal == 0)

        // 已还数超过总期数（数据异常）不能算出负数
        plan.paidPeriods = 30
        #expect(plan.remainingPeriods == 0)
    }

    @Test("剩余总额走纯函数，与逐期展开的合计一致")
    func remainingTotalMatchesPeriods() {
        let plan = Installment(
            key: "花呗", name: "花呗分期", totalPeriods: 12, paidPeriods: 3,
            perPeriodAmount: dec("120.03"), firstPeriodAmount: dec("120.06"),
            lastPeriodAmount: dec("120.00"), nextDueDate: day(2026, 12, 25)
        )
        let periods = plan.futurePeriods(calendar: calendar)
        let sum = periods.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(periods.count == 9)
        #expect(plan.remainingTotal == sum)
    }

    @Test("有剩余应还就以它为准，不再用「每期 × 期数」凑")
    func remainingDueWins() {
        // 除不尽的情况：每期 203.35 × 9 = 1830.15，但账单写 1830.17（末期 203.37）
        let plan = Installment(
            key: "招行", name: "招行账单分期", totalPeriods: 12, paidPeriods: 3,
            perPeriodAmount: dec("203.35"), remainingDue: dec("1830.17"),
            nextDueDate: day(2026, 11, 25)
        )
        #expect(plan.remainingTotal == dec("1830.17"))
        let periods = plan.futurePeriods(calendar: calendar)
        #expect(periods.count == 9)
        #expect(periods.reduce(Decimal(0)) { $0 + $1.amount } == dec("1830.17"))
        #expect(periods.last?.amount == dec("203.37"))
    }

    @Test("年化只走整笔口径：「剩余本金」不再参与，含利息才是输入")
    func estimatedAnnualRateUsesWholeLoan() {
        // 花呗 PRD 9.5.3 例子：12 期 × 120.03、含利息 110.56 → ≈15%
        let withInterest = Installment(
            key: "花呗", name: "花呗分期", totalPeriods: 12, paidPeriods: 0,
            perPeriodAmount: dec("120.03"), totalInterest: dec("110.56"),
            nextDueDate: day(2026, 12, 25)
        )
        let rate = withInterest.estimatedAnnualRate
        #expect(rate != nil)
        #expect(abs(NSDecimalNumber(decimal: rate!).doubleValue - 15.0) <= 0.3)

        // 招行真实账单（用户 11-11 回传）：12 期 × 203.35、含利息 176.99
        // 平息法：名义 7.82%、真实 14.13%，正好翻倍
        let cmb = Installment(
            key: "招行", name: "招行账单分期", totalPeriods: 12, paidPeriods: 3,
            perPeriodAmount: dec("203.35"), remainingDue: dec("1830.15"),
            totalInterest: dec("176.99"), nextDueDate: day(2026, 11, 25)
        )
        let cmbRate = cmb.estimatedAnnualRate
        #expect(cmbRate != nil)
        #expect(abs(NSDecimalNumber(decimal: cmbRate!).doubleValue - 14.13) <= 0.05)

        // 只填「剩余本金」不再能算出年化——那个字段账单上没有，
        // 用户填进来的必然是含息的「剩余应还」，一填就撞成「零息 0.0%」
        let principalOnly = Installment(
            key: "e招贷", name: "e招贷", totalPeriods: 24, paidPeriods: 7,
            perPeriodAmount: dec("442.50"), remainingPrincipal: dec("6670.20"),
            nextDueDate: day(2026, 12, 10)
        )
        #expect(principalOnly.estimatedAnnualRate == nil)

        // 什么都没有：不猜
        let bare = Installment(
            key: "抖音", name: "抖音月付", totalPeriods: 12, paidPeriods: 0,
            perPeriodAmount: dec("100"), nextDueDate: day(2026, 12, 15)
        )
        #expect(bare.estimatedAnnualRate == nil)
    }

    @Test("减免单独存一栏，不混进每期金额（PRD 9.5.6 三层拆分）")
    func rebateIsSeparate() {
        let plan = Installment(
            key: "贴息", name: "消费贷", totalPeriods: 6, paidPeriods: 0,
            perPeriodAmount: dec("83.19"), totalInterest: dec("17.27"),
            totalRebate: dec("0.57"), nextDueDate: day(2026, 12, 20)
        )
        // 减免不参与剩余总额：那是已经优惠掉的，不是还要还的钱
        #expect(plan.remainingTotal == dec("83.19") * 6)
        #expect(plan.totalRebate == dec("0.57"))
    }

    @Test("期数逾期判断：还款日当天不算逾期，第二天才算")
    func periodOverdue() {
        let period = InstallmentPeriod(
            installmentKey: "e招贷", index: 1, dueDate: day(2026, 12, 10),
            amount: dec("442.50")
        )
        // 还款日当天
        #expect(period.isOverdue(on: day(2026, 12, 10), calendar: calendar) == false)
        #expect(period.daysUntilDue(from: day(2026, 12, 10), calendar: calendar) == 0)
        // 提前 3 天
        #expect(period.isOverdue(on: day(2026, 12, 7), calendar: calendar) == false)
        #expect(period.daysUntilDue(from: day(2026, 12, 7), calendar: calendar) == 3)
        // 逾期 2 天
        #expect(period.isOverdue(on: day(2026, 12, 12), calendar: calendar))
        #expect(period.daysUntilDue(from: day(2026, 12, 12), calendar: calendar) == -2)

        // 已还的期不参与逾期判断
        period.paidAt = day(2026, 12, 9)
        #expect(period.isPaid)
        #expect(period.isOverdue(on: day(2027, 3, 1), calendar: calendar) == false)
    }

    @Test("期表能落库并按时还日期读回")
    func periodPersists() throws {
        let context = try makeContext()
        context.insert(InstallmentPeriod(
            installmentKey: "花呗", index: 1, dueDate: day(2026, 12, 25), amount: dec("120.03")
        ))
        context.insert(InstallmentPeriod(
            installmentKey: "花呗", index: 2, dueDate: day(2027, 1, 25), amount: dec("120.03")
        ))
        try context.save()

        let all = try context.fetch(FetchDescriptor<InstallmentPeriod>())
        #expect(all.count == 2)
        #expect(all.filter { $0.installmentKey == "花呗" }.count == 2)
        #expect(all.allSatisfy { $0.isPaid == false })
    }
}
