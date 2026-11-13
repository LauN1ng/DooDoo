import Foundation
import Testing

@testable import DooDoo

/// 账期归属的口径（M3-10）。
///
/// 关心的只有一件事：**这一笔消费算进哪一期账单**。
/// 校准样本用真实账户形态：花呗 10/15–11/14 这一期叫 `2026-11`，11/25 还
/// （与 `BillStatement.period` 的注释同一口径）。
struct BillCycleMathTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// 当天零点（与 `BillCycleMath` 内部算出的日期同一时点，直接比较相等即可）。
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func cycle(_ date: Date, start: Int? = 15, end: Int? = 14, due: Int? = 25) -> BillCycleMath.Cycle {
        BillCycleMath.cycle(
            for: date,
            cycleStartDay: start,
            cycleEndDay: end,
            dueDay: due,
            calendar: calendar
        )
    }

    // MARK: - 周期归属

    @Test("花呗 11/05 的消费算进 2026-11（周期 10/15–11/14）")
    func beforeCycleStart() {
        let c = cycle(day(2026, 11, 5))
        #expect(c.period == "2026-11")
        #expect(c.start == day(2026, 10, 15))
        #expect(c.end == day(2026, 11, 14))
        #expect(c.dueDate == day(2026, 11, 25))
        #expect(BillCycleMath.caption(c, calendar: calendar) == "账单期 10/15–11/14 · 计入 11 月")
    }

    @Test("账单日当天算新一期：11/15 的消费进 2026-12，还款日 12/25")
    func onCycleStart() {
        let c = cycle(day(2026, 11, 15))
        #expect(c.period == "2026-12")
        #expect(c.start == day(2026, 11, 15))
        #expect(c.end == day(2026, 12, 14))
        #expect(c.dueDate == day(2026, 12, 25))
    }

    @Test("周期最后一天还在本期：11/14 仍是 2026-11")
    func onCycleEnd() {
        #expect(cycle(day(2026, 11, 14)).period == "2026-11")
        #expect(cycle(day(2026, 11, 16)).period == "2026-12")
    }

    @Test("跨年：12/20 的消费进 2027-01")
    func acrossYear() {
        let c = cycle(day(2026, 12, 20))
        #expect(c.period == "2027-01")
        #expect(c.start == day(2026, 12, 15))
        #expect(c.end == day(2027, 1, 14))
    }

    @Test("没有账单周期：账期退回发生日所在月，不给区间")
    func withoutCycleInfo() {
        let c = cycle(day(2026, 11, 5), start: nil, end: nil, due: nil)
        #expect(c.period == "2026-11")
        #expect(c.start == nil)
        #expect(c.end == nil)
        #expect(c.dueDate == nil)
        #expect(c.hasRange == false)
        #expect(BillCycleMath.caption(c, calendar: calendar) == nil)
    }

    @Test("31 号账单日落在 2 月：起点取当月最后一天，周期止随之往前一天")
    func clampedToShortMonth() {
        // 1/31 起的那一期，下一次起算落在 2/28（2 月没有 31 号）→ 周期止 2/27
        let feb = cycle(day(2026, 2, 20), start: 31, end: 30, due: 25)
        #expect(feb.start == day(2026, 1, 31))
        #expect(feb.end == day(2026, 2, 27))
        #expect(feb.period == "2026-02")

        // 闰年同样只落到当月最后一天（2/29），不会溢出到 3 月
        let leap = cycle(day(2028, 2, 20), start: 31, end: 30, due: 25)
        #expect(leap.start == day(2028, 1, 31))
        #expect(leap.end == day(2028, 2, 28))
    }

    @Test("还款日早于周期止：落到次月（账单日 24、还款日 10）")
    func dueDateInNextMonth() {
        let c = cycle(day(2026, 11, 5), start: 25, end: 24, due: 10)
        // 周期 10/25–11/24，账期 2026-11，还款日在 12/10
        #expect(c.start == day(2026, 10, 25))
        #expect(c.end == day(2026, 11, 24))
        #expect(c.dueDate == day(2026, 12, 10))
    }

    // MARK: - 账期文本

    @Test("账期前后平移")
    func shift() {
        #expect(BillCycleMath.shift("2026-11", months: 1, calendar: calendar) == "2026-12")
        #expect(BillCycleMath.shift("2026-12", months: 1, calendar: calendar) == "2027-01")
        #expect(BillCycleMath.shift("2026-01", months: -1, calendar: calendar) == "2025-12")
        #expect(BillCycleMath.shift("2026-13", months: 1, calendar: calendar) == nil)
        #expect(BillCycleMath.shift("乱写", months: 1, calendar: calendar) == nil)
    }

    @Test("账期月份与标签")
    func labels() {
        #expect(BillCycleMath.periodText(for: day(2026, 11, 13), calendar: calendar) == "2026-11")
        #expect(BillCycleMath.monthLabel("2026-11") == "11 月")
        #expect(BillCycleMath.monthLabel("2027-01") == "1 月")
        #expect(BillCycleMath.monthNumber("2026-11") == 11)
        #expect(BillCycleMath.monthNumber("2026-00") == nil)
    }
}
