import Foundation
import Testing

@testable import DooDoo

/// 「本月要还」的口径门禁（资产页规格 2.4 / PRD 9.4）。
///
/// 这个文件存在的**唯一理由**是钉死一条：**每张卡只出一个数，账单优先，绝不相加。**
/// 数字取自 PRD 与资产页规格里的真实账单（AGENTS 7.3：不许自己编）：
/// - 信用组欠款合计 `−28,466.00`
/// - 本月要还 `2,742.00 · 3 笔 · 最近 11/08`
/// - 三张卡的分期部分合计 `693.67`（错误口径下的多出部分，`2,742.00 + 693.67 = 3,435.67`）
@MainActor
struct DueMathTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    /// 基准日固定为 2026-11-12（本轮开发日），不跟着系统时钟跑。
    private var today: Date { date(2026, 11, 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    /// 三张卡的分期到期：693.67 分三笔。
    private var installmentEntries: [DueEntry] {
        [
            DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 14)),
            DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 22)),
            DueEntry(amount: dec("231.23"), dueDate: date(2026, 11, 28)),
        ]
    }

    // MARK: - 核心：账单优先，绝不相加

    @Test("账单与分期同时存在时只取账单：2,742.00 不是 3,435.67")
    func billWinsAndNeverAddsInstallments() {
        let due = DueMath.accountDue(
            bill: BillDue(amount: dec("2742.00"), dueDate: date(2026, 11, 8)),
            installments: installmentEntries,
            today: today,
            calendar: calendar
        )

        #expect(due?.amount == dec("2742.00"))
        #expect(due?.source == .bill)
        // 相加就会变成 3,435.67——这就是账户详情页第八节修掉的那个错误。
        #expect(due?.amount != dec("3435.67"))
        #expect(due?.itemCount == 1)
    }

    @Test("账单金额为 0 视为没有账单，退回分期")
    func zeroBillFallsBackToInstallments() {
        let due = DueMath.accountDue(
            bill: BillDue(amount: 0, dueDate: date(2026, 11, 8)),
            installments: installmentEntries,
            today: today,
            calendar: calendar
        )

        #expect(due?.source == .installment)
        #expect(due?.amount == dec("693.67"))
    }

    @Test("没有账单时用分期到期合计")
    func installmentsUsedWhenNoBill() {
        let due = DueMath.accountDue(
            installments: installmentEntries,
            today: today,
            calendar: calendar
        )

        #expect(due?.amount == dec("693.67"))
        #expect(due?.source == .installment)
        #expect(due?.itemCount == 3)
        #expect(due?.nearestDueDate == date(2026, 11, 14))
        #expect(due?.isOverdue == false)
    }

    @Test("什么都没有时返回 nil，不显示「本月要还 0.00」")
    func noDataReturnsNil() {
        #expect(DueMath.accountDue(today: today, calendar: calendar) == nil)
    }

    // MARK: - 整组

    @Test("整组合计 = Σ 各卡 dueAmount，且三卡口径混用不重复")
    func groupTotalIsSumOfAccountDue() {
        let cardA = DueMath.accountDue(
            bill: BillDue(amount: dec("2742.00"), dueDate: date(2026, 11, 8)),
            installments: [DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 14))],
            today: today,
            calendar: calendar
        )
        let cardB = DueMath.accountDue(
            installments: [DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 22))],
            today: today,
            calendar: calendar
        )
        let cardC = DueMath.accountDue(
            installments: [DueEntry(amount: dec("231.23"), dueDate: date(2026, 11, 28))],
            today: today,
            calendar: calendar
        )

        let group = DueMath.group([cardA, cardB, cardC].compactMap { $0 })

        #expect(group?.total == dec("3204.45"))
        #expect(group?.accountCount == 3)
        #expect(group?.itemCount == 3)
        #expect(group?.nearestDueDate == date(2026, 11, 8))
        // 卡A 的分期被账单吸收，不能被加第二次。
        #expect(group?.total != dec("3435.67"))
    }

    @Test("空组返回 nil")
    func emptyGroupReturnsNil() {
        #expect(DueMath.group([]) == nil)
    }

    // MARK: - 窗口与逾期

    @Test("已还的期不进本月要还")
    func paidEntriesExcluded() {
        let entries = [
            DueEntry(amount: dec("500"), dueDate: date(2026, 11, 10), isPaid: true),
            DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 14)),
        ]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)

        #expect(due?.amount == dec("231.22"))
        #expect(due?.itemCount == 1)
        #expect(due?.isOverdue == false)
    }

    @Test("下个月才到期的不算本月要还")
    func futureMonthExcluded() {
        let entries = [
            DueEntry(amount: dec("231.22"), dueDate: date(2026, 11, 14)),
            DueEntry(amount: dec("999.00"), dueDate: date(2026, 12, 14)),
        ]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)

        #expect(due?.amount == dec("231.22"))
    }

    @Test("8 月逾期那笔不并进本月金额，但必须报出来")
    func overdueEntryDoesNotEnterAmount() {
        let entries = installmentEntries + [
            DueEntry(amount: dec("512.80"), dueDate: date(2026, 8, 22)),
        ]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)

        // 金额仍是本月到期的三期：逾期那笔属于 8 月账期（详情页规格 8.3）。
        #expect(due?.amount == dec("693.67"))
        #expect(due?.itemCount == 3)
        #expect(due?.nearestDueDate == date(2026, 11, 14))
        // 但不做横幅之后，红字是它唯一的可见位置——笔数与天数必须出来。
        #expect(due?.overdueCount == 1)
        #expect(due?.overdueDays == 82)
        #expect(due?.isOverdue == true)
    }

    @Test("本月内已过还款日的那笔既算金额、也算逾期")
    func overdueWithinThisMonthCountsInBoth() {
        let entries = [
            DueEntry(amount: dec("100"), dueDate: date(2026, 11, 5)),
            DueEntry(amount: dec("200"), dueDate: date(2026, 11, 25)),
        ]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)

        #expect(due?.amount == dec("300.00"))
        #expect(due?.overdueCount == 1)
        #expect(due?.overdueDays == 7)
    }

    @Test("本月没有应还、只有往期逾期时仍然产出，红字才有地方挂")
    func overdueOnlyStillProducesResult() throws {
        let entries = [DueEntry(amount: dec("512.80"), dueDate: date(2026, 8, 22))]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)
        let group = try #require(DueMath.group([due].compactMap { $0 }))
        let line = DueMath.line(group, calendar: calendar)

        #expect(due?.amount == 0)
        #expect(due?.overdueCount == 1)
        #expect(line.text == "本月没有应还")
        #expect(line.overdueText == " · 逾期 1 笔 82 天")
    }

    @Test("还款日当天不算逾期，第二天才算")
    func dueDayItselfIsNotOverdue() {
        let entries = [DueEntry(amount: dec("100"), dueDate: date(2026, 11, 12))]

        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)

        #expect(due?.isOverdue == false)
        #expect(due?.overdueDays == 0)
    }

    @Test("账单也会逾期，并给出天数")
    func billCanBeOverdue() {
        let due = DueMath.accountDue(
            bill: BillDue(amount: dec("2742.00"), dueDate: date(2026, 11, 8)),
            today: today,
            calendar: calendar
        )

        #expect(due?.isOverdue == true)
        #expect(due?.overdueCount == 1)
        #expect(due?.overdueDays == 4)
    }

    @Test("整组逾期天数取最久的那笔；往期逾期的金额不进合计")
    func groupOverdueDaysTakesMax() {
        let cardA = DueMath.accountDue(
            installments: [DueEntry(amount: dec("100"), dueDate: date(2026, 11, 1))],
            today: today,
            calendar: calendar
        )
        let cardB = DueMath.accountDue(
            installments: [DueEntry(amount: dec("200"), dueDate: date(2026, 8, 22))],
            today: today,
            calendar: calendar
        )

        let group = DueMath.group([cardA, cardB].compactMap { $0 })

        #expect(group?.overdueCount == 2)
        #expect(group?.overdueDays == 82)
        // 卡B 的 200 属于 8 月账期，只进逾期笔数、不进金额。
        #expect(group?.total == dec("100.00"))
        #expect(group?.itemCount == 1)
    }

    // MARK: - 文案

    @Test("无逾期时明细行照规格 2.4 的写法")
    func lineTextMatchesSpec() throws {
        let due = DueMath.accountDue(installments: installmentEntries, today: today, calendar: calendar)
        let group = try #require(DueMath.group([due].compactMap { $0 }))
        let line = DueMath.line(group, calendar: calendar)

        #expect(line.text == "本月要还 693.67 · 3 笔 · 最近 11/14")
        #expect(line.overdueText == nil)
    }

    @Test("有逾期时不再说「最近」，逾期单独成段好标红")
    func lineTextReplacesNearestWithOverdue() throws {
        let entries = installmentEntries + [
            DueEntry(amount: dec("512.80"), dueDate: date(2026, 8, 22)),
        ]
        let due = DueMath.accountDue(installments: entries, today: today, calendar: calendar)
        let group = try #require(DueMath.group([due].compactMap { $0 }))
        let line = DueMath.line(group, calendar: calendar)

        #expect(line.text == "本月要还 693.67 · 3 笔")
        #expect(line.overdueText == " · 逾期 1 笔 82 天")
        #expect(line.text.contains("最近") == false)
    }

    @Test("日期补零：11/08 不是 11/8")
    func monthDayIsPadded() {
        #expect(DueMath.monthDay(date(2026, 11, 8), calendar: calendar) == "11/08")
        #expect(DueMath.monthDay(date(2026, 1, 1), calendar: calendar) == "01/01")
    }
}
