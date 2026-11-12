import Foundation
import Testing

@testable import DooDoo

/// 「我欠 / 欠款合计」的口径门禁（PRD 9.4 / 9.3，2026-11-12 用户定案「相加」）。
///
/// 这个文件存在的**唯一理由**是钉死两条：
/// 1. **余额与账期相加**：欠款 = 余额欠额 + 未还账单 + 未覆盖分期。取 max 会让
///    「记一笔信用消费，欠款一动不动」（分期总额通常远大于余额），用户 11-12 真机反馈过；
/// 2. **账期内部绝不重复**：本期账单里的分期由账单覆盖，只有**账单还款日之后**到期的
///    分期才另算——不分青红皂白全加，等于把本期分期算两遍。
///
/// 数字取自 `账户详情页规格冻结-v1.0.md` 8.4 与 PRD 附录的真实账单（AGENTS 7.3：不许自己编）：
/// - 招行 8857：欠款 3,120.00、本期账单 1,115.03（11/22）、本月分期 449.67（128.00 + 216.67 + 105.00）
/// - 剩余分期总额 2,806.35 → 未来期 = 2,806.35 − 449.67 = 2,356.68
@MainActor
struct CardDebtTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    /// 招行 8857 的本月分期三笔：全部在账单还款日 11/22 到期（规格第六节）。
    private var currentPeriods: [DebtPeriod] {
        [
            DebtPeriod(amount: dec("128.00"), dueDate: date(2026, 11, 22), isPaid: false),
            DebtPeriod(amount: dec("216.67"), dueDate: date(2026, 11, 22), isPaid: false),
            DebtPeriod(amount: dec("105.00"), dueDate: date(2026, 11, 22), isPaid: false),
        ]
    }

    /// 未来期：12 月起，合计 2,356.68（= 剩余 2,806.35 − 本期 449.67）。
    private var futurePeriods: [DebtPeriod] {
        [
            DebtPeriod(amount: dec("203.35"), dueDate: date(2026, 12, 22), isPaid: false),
            DebtPeriod(amount: dec("203.35"), dueDate: date(2027, 1, 22), isPaid: false),
            DebtPeriod(amount: dec("1949.98"), dueDate: date(2027, 2, 22), isPaid: false),
        ]
    }

    // MARK: - 只有分期（用户 11-12 的真实情形：信用卡没有任何流水，余额为 0）

    @Test("余额 0、只有分期时，我欠等于分期剩余总额")
    func installmentsOnlyCountsRemainingTotal() {
        let card = CardDebtInput(
            balance: 0,
            bills: [],
            periods: currentPeriods + futurePeriods
        )

        // 449.67 + 2,356.68 = 2,806.35，与规格 8.4「剩余分期总额」逐分对得上。
        #expect(CardDebt.owe(card, calendar: calendar) == dec("2806.35"))
    }

    @Test("已还的分期期不计入")
    func paidPeriodsAreSkipped() {
        var periods = currentPeriods + futurePeriods
        periods[0] = DebtPeriod(amount: dec("128.00"), dueDate: date(2026, 11, 22), isPaid: true)

        let card = CardDebtInput(balance: 0, periods: periods)

        #expect(CardDebt.owe(card, calendar: calendar) == dec("2678.35"))
    }

    // MARK: - 账单与分期的覆盖关系

    @Test("本期账单覆盖本期分期，只有账单还款日之后的分期才另算")
    func billCoversCurrentPeriods() {
        let card = CardDebtInput(
            balance: 0,
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)],
            periods: currentPeriods + futurePeriods
        )

        // 1,115.03（账单，已含本期 449.67）+ 2,356.68（12 月及以后）= 3,471.71
        #expect(CardDebt.owe(card, calendar: calendar) == dec("3471.71"))
        // 错误算法会把本期分期再加一遍：3,471.71 + 449.67 = 3,921.38
        #expect(CardDebt.owe(card, calendar: calendar) != dec("3921.38"))
    }

    @Test("账单已还但分期还有未来期时，只算未来期")
    func paidBillStillCoversCurrentPeriods() {
        let card = CardDebtInput(
            balance: 0,
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: true)],
            periods: currentPeriods + futurePeriods
        )

        #expect(CardDebt.owe(card, calendar: calendar) == dec("2356.68"))
    }

    @Test("只有当期账单、没有分期")
    func billOnly() {
        let card = CardDebtInput(
            balance: 0,
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)]
        )

        #expect(CardDebt.owe(card, calendar: calendar) == dec("1115.03"))
    }

    @Test("往期逾期账单也算欠款，不因为它过期就消失")
    func overdueBillCountsAsDebt() {
        let card = CardDebtInput(
            balance: 0,
            bills: [
                DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false),
                DebtBill(dueAmount: dec("512.80"), dueDate: date(2026, 8, 22), isPaid: false),
            ]
        )

        #expect(CardDebt.owe(card, calendar: calendar) == dec("1627.83"))
    }

    // MARK: - 余额更大时取余额（防重复计的核心）

    @Test("余额与账期相加：记一笔消费立刻体现在欠款里")
    func balanceAddsToBooks() {
        let card = CardDebtInput(
            balance: dec("-4000.00"),
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)],
            periods: currentPeriods + futurePeriods
        )

        // 4,000.00 + 1,115.03（账单）+ 2,356.68（12 月及以后的分期）= 7,471.71
        #expect(CardDebt.owe(card, calendar: calendar) == dec("7471.71"))
    }

    @Test("余额为 0 而账单分期更大时取账单分期")
    func booksWinWhenLarger() {
        let card = CardDebtInput(
            balance: 0,
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)]
        )

        #expect(CardDebt.owe(card, calendar: calendar) == dec("1115.03"))
    }

    @Test("余额为正（多还了钱）不产生负数欠款")
    func positiveBalanceIsZeroOwe() {
        let card = CardDebtInput(balance: dec("50.00"))

        #expect(CardDebt.owe(card, calendar: calendar) == 0)
    }

    // MARK: - 组合与边界

    @Test("空卡组返回 0")
    func emptyCards() {
        #expect(CardDebt.owe([], calendar: calendar) == 0)
    }

    @Test("借款账户只有余额，按余额算")
    func loanAccountUsesBalance() {
        let loan = CardDebtInput(balance: dec("-20000.00"))

        #expect(CardDebt.owe(loan, calendar: calendar) == dec("20000.00"))
    }

    @Test("组内各卡先各自算清，再相加")
    func groupSumsPerCard() {
        let cardA = CardDebtInput(
            balance: dec("-4000.00"),
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22), isPaid: false)]
        )
        let cardB = CardDebtInput(balance: 0, periods: currentPeriods + futurePeriods)
        let loan = CardDebtInput(balance: dec("-20000.00"))

        // cardA = 4,000.00 + 1,115.03 = 5,115.03；cardB = 2,806.35；loan = 20,000.00
        #expect(CardDebt.owe([cardA, cardB, loan], calendar: calendar) == dec("27921.38"))
    }

    @Test("同日不同时分秒不会漏算覆盖关系")
    func sameDayDifferentTimeStillCovered() {
        let card = CardDebtInput(
            balance: 0,
            bills: [DebtBill(dueAmount: dec("1115.03"), dueDate: date(2026, 11, 22, hour: 9), isPaid: false)],
            periods: [DebtPeriod(amount: dec("449.67"), dueDate: date(2026, 11, 22, hour: 23), isPaid: false)]
        )

        // 同一天：归入账单覆盖，不再另算
        #expect(CardDebt.owe(card, calendar: calendar) == dec("1115.03"))
    }
}
