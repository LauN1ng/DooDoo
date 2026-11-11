import Foundation
import Testing

@testable import DooDoo

/// 存量录入的换算口径（M3-2）：期数映射、批量进度、按账单日推还款日、输入解析。
///
/// 这些函数没有一行会碰 SwiftData，纯粹是为了让 58 笔录入能被单测钉住。
struct InstallmentIntakeTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    // MARK: - 剩余期数 → total / paid

    @Test("不填总期数时，剩余期数就是全部未来期")
    func remainingOnly() {
        let p = InstallmentIntake.periods(remaining: 7, total: nil)
        #expect(p.total == 7)
        #expect(p.paid == 0)
        #expect(p.remaining == 7)
    }

    @Test("填了总期数才能算出已还期数（第 6/12 期）")
    func withTotal() {
        let p = InstallmentIntake.periods(remaining: 7, total: 12)
        #expect(p.total == 12)
        #expect(p.paid == 5)
        #expect(p.remaining == 7)

        // 一期没还
        let fresh = InstallmentIntake.periods(remaining: 12, total: 12)
        #expect(fresh.paid == 0)
    }

    @Test("总期数填得比剩余期数还小：退回全部未来期，不算出负的已还数")
    func inconsistentTotal() {
        let p = InstallmentIntake.periods(remaining: 12, total: 6)
        #expect(p.total == 12)
        #expect(p.paid == 0)
        #expect(p.remaining == 12)
    }

    @Test("剩余期数为 0 或负数：已还清，不带已还数")
    func clearedPlan() {
        #expect(InstallmentIntake.periods(remaining: 0, total: 12) == .init(total: 0, paid: 0))
        #expect(InstallmentIntake.periods(remaining: -3, total: nil) == .init(total: 0, paid: 0))
    }

    // MARK: - 批量进度

    @Test("还差几笔：58 笔录到第 3 笔时还差 55")
    func batchProgress() {
        #expect(InstallmentIntake.batchRemaining(target: 58, done: 0) == 58)
        #expect(InstallmentIntake.batchRemaining(target: 58, done: 3) == 55)
        #expect(InstallmentIntake.batchRemaining(target: 58, done: 58) == 0)
        // 超过目标不显示负数
        #expect(InstallmentIntake.batchRemaining(target: 58, done: 61) == 0)
        // 没设目标
        #expect(InstallmentIntake.batchRemaining(target: 0, done: 5) == 0)
        // 脏数据：已录为负
        #expect(InstallmentIntake.batchRemaining(target: 10, done: -2) == 10)
    }

    // MARK: - 按账单日推还款日

    @Test("还款日在本月还没到：就用本月")
    func dueDateThisMonth() {
        // 11-11 看 25 号 → 11-25
        let due = InstallmentIntake.defaultDueDate(dueDay: 25, from: day(2026, 11, 11), calendar: calendar)
        #expect(due == day(2026, 11, 25))
    }

    @Test("还款日当天算本月，过了才滚到下月")
    func dueDateBoundary() {
        // 当天还来得及
        #expect(InstallmentIntake.defaultDueDate(dueDay: 25, from: day(2026, 11, 25), calendar: calendar)
                == day(2026, 11, 25))
        // 26 号看 25 号 → 下个月 12-25
        #expect(InstallmentIntake.defaultDueDate(dueDay: 25, from: day(2026, 11, 26), calendar: calendar)
                == day(2026, 12, 25))
    }

    @Test("还款日超出当月天数：落到当月最后一天，不溢出到下月")
    func dueDateClamped() {
        // 31 号在 2 月 → 2027-02-28
        let due = InstallmentIntake.defaultDueDate(dueDay: 31, from: day(2027, 2, 5), calendar: calendar)
        #expect(due == day(2027, 2, 28))

        // 闰年 2 月 → 29
        let leap = InstallmentIntake.defaultDueDate(dueDay: 31, from: day(2028, 2, 5), calendar: calendar)
        #expect(leap == day(2028, 2, 29))

        // 30 号在 4 月 → 4-30（不触发 clamp，但确认范围正确）
        #expect(InstallmentIntake.defaultDueDate(dueDay: 30, from: day(2027, 4, 1), calendar: calendar)
                == day(2027, 4, 30))
    }

    @Test("账户没填还款日：退回当天，不瞎猜")
    func dueDateMissing() {
        let today = day(2026, 11, 11)
        #expect(InstallmentIntake.defaultDueDate(dueDay: nil, from: today, calendar: calendar) == today)
        // 越界值同样退回当天
        #expect(InstallmentIntake.defaultDueDate(dueDay: 45, from: today, calendar: calendar) == today)
        #expect(InstallmentIntake.defaultDueDate(dueDay: 0, from: today, calendar: calendar) == today)
    }

    // MARK: - 输入解析

    @Test("金额解析走 POSIX，5.5 不会被当成 55")
    func moneyParsing() {
        #expect(MoneyMath.decimal("5.5") == Decimal(string: "5.5")!)
        #expect(MoneyMath.decimal("120.03") == Decimal(string: "120.03")!)
        #expect(MoneyMath.decimal("") == 0)
        #expect(MoneyMath.decimal("abc") == 0)
    }

    @Test("纯数字回填与百分数展示")
    func formatting() {
        #expect(MoneyMath.plain(Decimal(string: "120.03")!) == "120.03")
        #expect(MoneyMath.plain(120) == "120.00")
        // 年化返回的就是百分数，展示时不再 ×100
        #expect(MoneyMath.percent(Decimal(string: "16.4321")!) == "16.4%")
        #expect(MoneyMath.percent(15) == "15.0%")
        #expect(MoneyMath.percent(nil) == "—")
    }
}
