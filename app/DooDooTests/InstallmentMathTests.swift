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

    // MARK: - 总额均摊（M3-3）

    @Test("均摊除得尽：各期都是标准额，首期不多不少")
    func splitEvenlyExact() {
        // 招行账单：1830.15 ÷ 9 = 203.35 正好。这笔整除，测不出余数落哪一边，
        // 真正钉住「余数落首期」的是下面的 `splitEvenlyMatchesRealBills`。
        let split = InstallmentMath.splitEvenly(total: dec("1830.15"), count: 9)
        #expect(split?.perPeriod == dec("203.35"))
        #expect(split?.firstPeriod == dec("203.35"))
    }

    @Test("均摊除不尽：余数全落首期，其余各期是标准额")
    func splitEvenlyRemainder() {
        // 1830.17 ÷ 9 = 203.352... → 其余 203.35，首期 203.37
        let split = InstallmentMath.splitEvenly(total: dec("1830.17"), count: 9)
        #expect(split?.perPeriod == dec("203.35"))
        #expect(split?.firstPeriod == dec("203.37"))
        // 加起来一分不差
        #expect(split!.perPeriod * 8 + split!.firstPeriod == dec("1830.17"))
    }

    @Test("余数落首期：三张真实白条账单逐期复现")
    func splitEvenlyMatchesRealBills() {
        // 用户 2026-11-11 提供的两张干净样本。此前 M3-3 只校准了招行那一笔
        // （1830.15 ÷ 9 整除，余数落首期还是末期结果一样），所以把方向做反了。
        //
        // A：15.34 分 3 期 → 账单是 5.12 / 5.11 / 5.11，**首期多 1 分**。
        // 按「余数落末期」会摊成 5.11 / 5.11 / 5.12，跟账单第一行就对不上。
        let a = InstallmentMath.splitEvenly(total: dec("15.34"), count: 3)
        #expect(a?.firstPeriod == dec("5.12"))
        #expect(a?.perPeriod == dec("5.11"))
        #expect(a!.firstPeriod + a!.perPeriod * 2 == dec("15.34"))

        // B：163.02 分 6 期 → 27.17 × 6，整除，无余数可落
        let b = InstallmentMath.splitEvenly(total: dec("163.02"), count: 6)
        #expect(b?.firstPeriod == dec("27.17"))
        #expect(b?.perPeriod == dec("27.17"))
        #expect(b!.firstPeriod + b!.perPeriod * 5 == dec("163.02"))

        // A 已还 1 期后的剩余部分：10.22 分 2 期 → 5.11 / 5.11。
        // 首期那 1 分零头已经还掉了，剩余两期本来就相等。
        let rest = InstallmentMath.splitEvenly(total: dec("10.22"), count: 2)
        #expect(rest?.firstPeriod == dec("5.11"))
        #expect(rest?.perPeriod == dec("5.11"))
    }

    @Test("末期反推：四张真实账单逐分复现，含利息不均那张")
    func splitEndingAtMatchesRealBills() {
        // M3-5 的核心用例。利息并不按期均分，所以「总额 ÷ 期数」只是算术平均；
        // 末期金额账单上明写着，抄它反推中间各期，四张单全部逐分对上。
        //
        // A：15.34 / 3 期，末期 5.11 → 5.12 / 5.11 / 5.11（首期吃那 1 分）
        let a = InstallmentMath.splitEndingAt(total: dec("15.34"), count: 3, last: dec("5.11"))
        #expect(a?.firstPeriod == dec("5.12"))
        #expect(a?.perPeriod == dec("5.11"))
        #expect(a?.lastPeriod == dec("5.11"))

        // B：163.02 / 6 期，末期 27.17 → 整除，各期一致
        let b = InstallmentMath.splitEndingAt(total: dec("163.02"), count: 6, last: dec("27.17"))
        #expect(b?.perPeriod == dec("27.17"))
        #expect(b?.isEven == true)

        // C：招行 1830.15 / 9 期，末期 203.35 → 整除
        let c = InstallmentMath.splitEndingAt(total: dec("1830.15"), count: 9, last: dec("203.35"))
        #expect(c?.perPeriod == dec("203.35"))
        #expect(c?.isEven == true)

        // D：利息不均那张——496.65 分 6 期，已还 2 期后剩 330.23 / 4 期，
        // 账单是 83.19 / 83.19 / 83.19 / 80.66。均摊只能给 82.58 / 82.55 × 2 / 82.55，
        // 末期差 1.89 元；末期反推逐分复原。
        let d = InstallmentMath.splitEndingAt(total: dec("330.23"), count: 4, last: dec("80.66"))
        #expect(d?.firstPeriod == dec("83.19"))
        #expect(d?.perPeriod == dec("83.19"))
        #expect(d?.lastPeriod == dec("80.66"))
        #expect(d?.isEven == false)
        // 一分不差
        #expect(d!.firstPeriod + d!.perPeriod * 2 + d!.lastPeriod == dec("330.23"))
    }

    @Test("末期反推的边界：末期吃掉全部 / 只剩一期 / 两期")
    func splitEndingAtBoundaries() {
        // 末期 ≥ 总额 → 中间期不存在，返 nil 让界面提示，而不是产出 0 元期
        #expect(InstallmentMath.splitEndingAt(
            total: dec("100"), count: 6, last: dec("100")) == nil)
        #expect(InstallmentMath.splitEndingAt(
            total: dec("100"), count: 6, last: dec("120")) == nil)
        // 末期 ≤ 0 / 期数 ≤ 0 / 总额 ≤ 0
        #expect(InstallmentMath.splitEndingAt(total: dec("100"), count: 6, last: 0) == nil)
        #expect(InstallmentMath.splitEndingAt(total: dec("100"), count: 0, last: dec("10")) == nil)
        // 只剩一期：末期入参被忽略，一期吃掉全额
        let single = InstallmentMath.splitEndingAt(total: dec("80.66"), count: 1, last: dec("9.99"))
        #expect(single?.lastPeriod == dec("80.66"))
        #expect(single?.perPeriod == dec("80.66"))
        // 只剩两期：中间期不存在，首期 = 总额 − 末期
        let two = InstallmentMath.splitEndingAt(total: dec("170"), count: 2, last: dec("80.66"))
        #expect(two?.firstPeriod == dec("89.34"))
        #expect(two?.lastPeriod == dec("80.66"))
    }

    @Test("填了末期就按末期展开逐期，均摊不再是主路径")
    func futurePeriodsPrefersLastPeriod() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20))!
        // 496.65 那笔的剩余段：330.23 / 4 期，末期 80.66
        let periods = InstallmentMath.futurePeriods(
            count: 4,
            nextDueDate: next,
            perPeriodAmount: dec("82.55"),
            lastPeriodAmount: dec("80.66"),
            remainingDue: dec("330.23"),
            calendar: calendar
        )
        #expect(periods.count == 4)
        #expect(periods.map(\.amount) == [dec("83.19"), dec("83.19"), dec("83.19"), dec("80.66")])
        #expect(periods.reduce(Decimal(0)) { $0 + $1.amount } == dec("330.23"))
    }


    @Test("均摊的边界：一期全吃、零期或零额返回 nil")
    func splitEvenlyBoundaries() {
        let single = InstallmentMath.splitEvenly(total: dec("500"), count: 1)
        #expect(single?.perPeriod == dec("500"))
        #expect(single?.firstPeriod == dec("500"))

        #expect(InstallmentMath.splitEvenly(total: dec("500"), count: 0) == nil)
        #expect(InstallmentMath.splitEvenly(total: 0, count: 6) == nil)
        #expect(InstallmentMath.splitEvenly(total: dec("-1"), count: 6) == nil)
    }

    @Test("给了剩余应还，逐期展开就用摊平结果而不是每期金额")
    func futurePeriodsUsesRemainingDue() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let periods = InstallmentMath.futurePeriods(
            count: 9,
            nextDueDate: next,
            perPeriodAmount: dec("203.35"),
            remainingDue: dec("1830.17"),
            calendar: calendar
        )
        #expect(periods.count == 9)
        #expect(periods.dropFirst().allSatisfy { $0.amount == dec("203.35") })
        #expect(periods.first?.amount == dec("203.37"))
        #expect(periods.reduce(Decimal(0)) { $0 + $1.amount } == dec("1830.17"))
    }

    @Test("剩余应还 ≤ 0 时不参与，退回按每期金额展开")
    func futurePeriodsIgnoresNonPositiveDue() {
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let periods = InstallmentMath.futurePeriods(
            count: 3, nextDueDate: next, perPeriodAmount: dec("100"),
            remainingDue: 0, calendar: calendar
        )
        #expect(periods.allSatisfy { $0.amount == dec("100") })
    }
}
