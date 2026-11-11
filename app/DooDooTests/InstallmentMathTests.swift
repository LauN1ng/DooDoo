import Foundation
import Testing

@testable import DooDoo

/// 分期展开与年化反算（M3 门禁）。
///
/// 用例数字全部取自 PRD 附录的真实账单，不自己编（AGENTS 7.3）：
/// - 验收标准 3：e招贷，反算年化应≈16.4%，与招行公布的 16.43% 相差 <0.5%
/// - 9.5.3 例子：花呗每期 120.03 × 12 期、含利息 110.56 → 真实年化 ≈15%
@MainActor
struct InstallmentMathTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func approx(_ value: Decimal?, _ expected: Double, tolerance: Double = 0.5) -> Bool {
        guard let value else { return false }
        return abs(NSDecimalNumber(decimal: value).doubleValue - expected) <= tolerance
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    // MARK: - 年化反算

    @Test("e招贷校准基准：9,000 / 24 期 / 16.43%")
    func impliedRateMatchesEZhaoDai() {
        // 9,000 元 24 期、招行公布 16.43% 的等额本息月供是 442.52
        let rate = InstallmentMath.impliedAnnualRate(
            periods: 24,
            perPeriodAmount: dec("442.52"),
            presentValue: dec("9000")
        )
        // PRD 验收 3：与 16.43% 相差 < 0.5
        #expect(approx(rate, 16.43, tolerance: 0.5))
    }

    @Test("花呗真实账单：每期 120.03 × 12 期，含利息 110.56 → ≈15%")
    func impliedRateMatchesHuabei() {
        let rate = InstallmentMath.impliedAnnualRate(
            periods: 12,
            perPeriodAmount: dec("120.03"),
            totalInterest: dec("110.56")
        )
        // PRD 9.5.3 原文写的「真实年化 ≈ 15%」
        #expect(approx(rate, 15.0, tolerance: 0.3))
    }

    @Test("只剩 17 期时按剩余本金反算，仍对齐 16.4%")
    func impliedRateOnRemainingPeriods() {
        // 验收 3 的场景：录入「每期 442.50 × 17 期」，剩余本金 6,670.20
        let rate = InstallmentMath.impliedAnnualRate(
            periods: 17,
            perPeriodAmount: dec("442.50"),
            presentValue: dec("6670.20")
        )
        #expect(approx(rate, 16.4, tolerance: 0.5))
    }

    @Test("年化返回值是百分数，不是小数率")
    func impliedRateUnitIsPercent() {
        let rate = InstallmentMath.impliedAnnualRate(
            periods: 24, perPeriodAmount: dec("442.52"), presentValue: dec("9000"))
        #expect(rate != nil)
        let double = NSDecimalNumber(decimal: rate!).doubleValue
        // 16.43 而不是 0.1643。返回小数率会让展示层漏 ×100，显示成「0.2%」。
        #expect(double > 1)
        #expect(approx(rate, 16.43, tolerance: 0.5))
    }

    @Test("免息分期年化就是 0，不是「算不出来」")
    func impliedRateZeroInterest() {
        // 中移金科 6,699 / 24 期 / 免息
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 24, perPeriodAmount: dec("279.125"), totalInterest: 0) == 0)
        // 现值不小于总还款额：平台一分利息没收
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 12, perPeriodAmount: dec("120.03"), presentValue: dec("1440.36")) == 0)
    }

    @Test("反算不出来的情况一律 nil，不猜一个假利率")
    func impliedRateNilBoundaries() {
        // 只有一期：年化在数学上没有意义
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 1, perPeriodAmount: dec("442.50"), presentValue: dec("400")) == nil)
        // 期数或金额不合法
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 0, perPeriodAmount: dec("442.50"), presentValue: dec("400")) == nil)
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 12, perPeriodAmount: 0, presentValue: dec("400")) == nil)
        // 现值 ≤ 0（总利息比总还款额还大，数据错的）
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 12, perPeriodAmount: dec("100"), totalInterest: dec("1300")) == nil)
        // 月利率超过 100%（年化 > 1200%）不收
        #expect(InstallmentMath.impliedAnnualRate(
            periods: 24, perPeriodAmount: dec("1000"), presentValue: dec("1")) == nil)
    }

    // MARK: - 逐期展开

    @Test("12 期展开：日期按月递增，首期与末期金额覆盖标准额")
    func futurePeriodsHonoursFirstAndLast() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        let periods = InstallmentMath.futurePeriods(
            count: 12,
            nextDueDate: next,
            perPeriodAmount: dec("120.03"),
            firstPeriodAmount: dec("120.06"),
            lastPeriodAmount: dec("120.00"),
            calendar: calendar
        )
        #expect(periods.count == 12)
        #expect(periods.first?.amount == dec("120.06"))
        #expect(periods.last?.amount == dec("120.00"))
        // 中间 10 期都是标准额
        #expect(periods[1..<11].allSatisfy { $0.amount == dec("120.03") })
        #expect(periods.first?.isLast == false)
        #expect(periods.last?.isLast == true)

        // 第 1 期 = 12/25，第 12 期 = 次年 11/25
        let lastDate = calendar.dateComponents([.year, .month, .day], from: periods[11].dueDate)
        #expect(lastDate.year == 2027)
        #expect(lastDate.month == 11)
        #expect(lastDate.day == 25)
    }

    @Test("还款日在月末：1/31 加一个月落到 2/28，不溢出到 3 月")
    func futurePeriodsHandlesMonthEnd() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let periods = InstallmentMath.futurePeriods(
            count: 3, nextDueDate: next, perPeriodAmount: dec("100"), calendar: calendar
        )
        let feb = calendar.dateComponents([.month, .day], from: periods[1].dueDate)
        #expect(feb.month == 2)
        #expect(feb.day == 28)          // 2026 不是闰年
    }

    @Test("只剩一期时首期金额优先，末期被忽略")
    func futurePeriodsSinglePeriod() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        let periods = InstallmentMath.futurePeriods(
            count: 1, nextDueDate: next, perPeriodAmount: dec("120.03"),
            firstPeriodAmount: dec("120.06"), lastPeriodAmount: dec("120.00"), calendar: calendar
        )
        #expect(periods.count == 1)
        #expect(periods[0].amount == dec("120.06"))
        #expect(periods[0].isLast)
    }

    @Test("已还清时展开为空")
    func futurePeriodsEmptyWhenSettled() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        #expect(InstallmentMath.futurePeriods(
            count: 0, nextDueDate: next, perPeriodAmount: dec("120.03"), calendar: calendar).isEmpty)
        #expect(InstallmentMath.futurePeriods(
            count: -3, nextDueDate: next, perPeriodAmount: dec("120.03"), calendar: calendar).isEmpty)
    }

    // MARK: - 剩余总额

    @Test("剩余总额要把首期末期的差额算进去，不能直接用每期 × 期数")
    func remainingTotalAdjustsEdges() {
        // 标准算：120.03 × 3 = 360.09；首期 +0.03、末期 −0.03 相互抵消
        let same = InstallmentMath.remainingTotal(
            count: 3, perPeriodAmount: dec("120.03"),
            firstPeriodAmount: dec("120.06"), lastPeriodAmount: dec("120.00"))
        #expect(same == dec("360.09"))

        // 只有首期不同：+0.03
        let firstOnly = InstallmentMath.remainingTotal(
            count: 3, perPeriodAmount: dec("120.03"), firstPeriodAmount: dec("120.06"))
        #expect(firstOnly == dec("360.12"))

        // 只有末期不同：−0.03
        let lastOnly = InstallmentMath.remainingTotal(
            count: 3, perPeriodAmount: dec("120.03"), lastPeriodAmount: dec("120.00"))
        #expect(lastOnly == dec("360.06"))

        // 只剩一期：末期调整不生效，否则会重复扣一次
        let single = InstallmentMath.remainingTotal(
            count: 1, perPeriodAmount: dec("120.03"), lastPeriodAmount: dec("120.00"))
        #expect(single == dec("120.03"))

        #expect(InstallmentMath.remainingTotal(count: 0, perPeriodAmount: dec("120.03")) == 0)
    }
}
