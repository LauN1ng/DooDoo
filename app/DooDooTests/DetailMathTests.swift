import Foundation
import Testing

@testable import DooDoo

/// 卡详情指标区的口径门禁（账户详情页规格 3.1 / 8.1 / 8.2）。
///
/// 用规格 8.4 的真实数据做锚：账单 1,115.03、本月分期 449.67、本期消费 **665.36**。
/// 只要 `consumed` 能复现 665.36，就说明「账单 − 分期」这条反推写对了；
/// 而「本月要还」必须直接取 1,115.03，不是 1,115.03 + 449.67。
@MainActor
struct DetailMathTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private var today: Date { date(2026, 11, 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private var currentBill: DebtBill {
        DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)
    }

    /// 规格 8.4：本月分期 3 笔 128.00 + 216.67 + 105.00 = 449.67。
    private var currentPeriods: [DebtPeriod] {
        [
            DebtPeriod(amount: dec("128.00"), dueDate: date(2026, 11, 22), isPaid: false),
            DebtPeriod(amount: dec("216.67"), dueDate: date(2026, 11, 22), isPaid: false),
            DebtPeriod(amount: dec("105.00"), dueDate: date(2026, 11, 22), isPaid: false),
        ]
    }

    @Test("本期消费 = 本期账单 − 本月到期分期，复现规格 8.4 的 665.36")
    func consumedMatchesSpec() {
        let m = DetailMath.metrics(
            owe: dec("3120.00"),
            bills: [currentBill],
            periods: currentPeriods,
            today: today,
            calendar: calendar
        )

        #expect(m.billDue == dec("1115.03"))
        #expect(m.monthInstallment == dec("449.67"))
        #expect(m.consumed == dec("665.36"))
    }

    @Test("本月要还直接取账单金额，不由消费与分期加总")
    func monthDueTakesBillDirectly() {
        let m = DetailMath.metrics(
            owe: dec("3120.00"),
            bills: [currentBill],
            periods: currentPeriods,
            today: today,
            calendar: calendar
        )

        #expect(m.monthDue == dec("1115.03"))
        #expect(m.monthDueDate == date(2026, 11, 22))
        // 8.2 禁止的算法
        #expect(m.monthDue != dec("1564.70"))
    }

    @Test("本期账单已还时白条不再催")
    func paidBillStopsReminding() {
        let paid = DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: true)
        let m = DetailMath.metrics(
            owe: dec("2000.00"),
            bills: [paid],
            periods: currentPeriods,
            today: today,
            calendar: calendar
        )

        #expect(m.monthDue == nil)
        // 账单金额是既成事实，三列照旧显示
        #expect(m.billDue == dec("1115.03"))
    }

    @Test("没有账单时本月要还退回分期，本期消费显示为 nil 而不是 0")
    func noBillFallsBackToInstallments() {
        let m = DetailMath.metrics(
            owe: dec("2806.35"),
            bills: [],
            periods: currentPeriods,
            today: today,
            calendar: calendar
        )

        #expect(m.monthDue == dec("449.67"))
        #expect(m.monthDueDate == date(2026, 11, 22))
        #expect(m.consumed == nil)
        #expect(m.billDue == nil)
    }

    @Test("没有账单时，本期消费用本月支出流水（真机回传「对不上」的那条）")
    func noBillUsesMonthSpend() {
        let m = DetailMath.metrics(
            owe: dec("3400.25"),
            bills: [],
            periods: currentPeriods,
            monthSpend: dec("56.00"),
            today: today,
            calendar: calendar
        )

        #expect(m.consumed == dec("56.00"))
        #expect(m.billDue == nil)
        // 本月要还仍退回分期，不受本期消费影响
        #expect(m.monthDue == dec("449.67"))
    }

    @Test("没有账单也没有流水时，本期消费是 nil 而不是 0")
    func noBillNoSpendIsNil() {
        let m = DetailMath.metrics(
            owe: 0,
            bills: [],
            periods: [],
            monthSpend: 0,
            today: today,
            calendar: calendar
        )

        #expect(m.consumed == nil)
    }

    @Test("账单比本月分期还小时，本期消费取 0，不显示负数")
    func negativeConsumedClampedToZero() {
        let smallBill = DebtBill(dueAmount: dec("300.00"), dueDate: date(2026, 11, 22), isPaid: false)
        let m = DetailMath.metrics(
            owe: dec("300.00"),
            bills: [smallBill],
            periods: currentPeriods,
            today: today,
            calendar: calendar
        )

        #expect(m.consumed == 0)
    }

    @Test("逾期天数取最久的那笔")
    func overdueDaysTakesMax() {
        let m = DetailMath.metrics(
            owe: dec("1627.83"),
            bills: [
                currentBill,
                DebtBill(dueAmount: dec("512.80"), dueDate: date(2026, 8, 22), isPaid: false),
            ],
            periods: [],
            today: today,
            calendar: calendar
        )

        #expect(m.overdueDays == 82)
    }

    @Test("往期账单列表不含本期")
    func pastBillsExcludeCurrent() {
        let bills = [
            currentBill,
            DebtBill(dueAmount: dec("512.80"), dueDate: date(2026, 8, 22), isPaid: false),
            DebtBill(dueAmount: dec("980.00"), dueDate: date(2026, 10, 22), isPaid: true),
        ]

        let past = DetailMath.pastBills(bills, today: today, calendar: calendar)

        #expect(past.count == 2)
        // 倒序：10 月在前
        #expect(past.first?.dueDate == date(2026, 10, 22))
        #expect(past.contains { $0.dueDate == date(2026, 11, 22) } == false)
    }
}
