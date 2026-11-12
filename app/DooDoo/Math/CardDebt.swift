import Foundation

/// 一期账单的快照（脱离 SwiftData，方便单测）。
struct DebtBill: Sendable, Equatable {
    /// 单位：元。本期应还。
    let dueAmount: Decimal
    /// 本期还款日。
    let dueDate: Date
    /// 已还清。
    let isPaid: Bool

    init(dueAmount: Decimal, dueDate: Date, isPaid: Bool) {
        self.dueAmount = dueAmount
        self.dueDate = dueDate
        self.isPaid = isPaid
    }
}

/// 一期分期的快照。
struct DebtPeriod: Sendable, Equatable {
    /// 单位：元。这一期应还（含息）。
    let amount: Decimal
    /// 这一期的还款日。
    let dueDate: Date
    /// 已还。
    let isPaid: Bool

    init(amount: Decimal, dueDate: Date, isPaid: Bool) {
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
    }
}

/// 一张负债卡的欠款输入。
struct CardDebtInput: Sendable, Equatable {
    /// 单位：元。账户当前余额，**欠款为负**（`Account.currentBalance`）。
    let balance: Decimal
    /// 该卡的全部账单（含已还的历史期）。
    let bills: [DebtBill]
    /// 该卡全部未结清分期的所有未还期。
    let periods: [DebtPeriod]

    init(balance: Decimal, bills: [DebtBill] = [], periods: [DebtPeriod] = []) {
        self.balance = balance
        self.bills = bills
        self.periods = periods
    }
}

/// 「我欠」的口径（PRD 9.4 / 9.3；显示层派生，**2026-11-12 用户定案**）。
///
/// ## 为什么不能直接用账户余额
///
/// `Account.currentBalance` 是**流水**的派生值（PRD 9.11）。而信用卡的真实用法是
/// 「消费在平台 App 里看、月底出一期账单」，这些消费流水往往没有逐笔记进本 App——
/// 于是余额停在 0，界面就会说「我不欠钱，但这个月要还 435.41」。自相矛盾。
///
/// 所以负债卡的欠款取**两个来源里大的那个**：
///
/// ```
/// 欠款 = max( 余额欠额, 账单未还 + 账单覆盖日之后的分期 )
/// ```
///
/// - `余额欠额 = max(0, −balance)`：流水记全了的人，这个数就是真欠款。
/// - 后一项：流水没记、但账单与分期录进来的人，这个数才是真欠款。
///
/// **两项取 max 而不是相加**，是为了防同一笔债算两遍——用户既记了消费流水、
/// 又录了同一笔分期时，相加会凭空多出一份。
///
/// ## 账单与分期为什么可以相加
///
/// 这里和「本月要还」不同。「本月要还」是**同一个账期**的到期额，账单与分期二选一，
/// 相加会把分期算两遍（PRD 9.12）。而「我欠」是**所有未还账期**的总额：
/// 本期账单里的分期部分由账单覆盖，只有**账单还款日之后**到期的分期期才是
/// 账单没管到的增量——两者互不重叠，相加不重复。
///
/// 覆盖日取**最新一期账单**的还款日，不论那期是否已还：
/// 已还的那期它同样已经把截至当天的分期都收进去了。
enum CardDebt {
    /// 一张卡欠多少（正数，单位元）。永远 ≥ 0。
    static func owe(_ card: CardDebtInput, calendar: Calendar = .current) -> Decimal {
        let balanceOwe = card.balance < 0 ? -card.balance : 0

        let unpaidBills = card.bills
            .filter { !$0.isPaid }
            .reduce(Decimal.zero) { $0 + $1.dueAmount }

        // 覆盖日 = 最新一期账单的还款日。用 startOfDay 归一，避免同一天因时分秒差异漏算。
        let coverage = card.bills
            .map { calendar.startOfDay(for: $0.dueDate) }
            .max()

        let uncoveredPeriods = card.periods
            .filter { period in
                guard !period.isPaid else { return false }
                guard let coverage else { return true }   // 没有任何账单：所有未还期都算
                return calendar.startOfDay(for: period.dueDate) > coverage
            }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let fromBooks = unpaidBills + uncoveredPeriods
        return max(balanceOwe, fromBooks)
    }

    /// 一组负债卡的合计（正数，单位元）。
    ///
    /// 边界：空数组返回 0——「我欠 0.00」是合法的（真的一分不欠）。
    static func owe(_ cards: [CardDebtInput], calendar: Calendar = .current) -> Decimal {
        cards.reduce(Decimal.zero) { $0 + owe($1, calendar: calendar) }
    }
}
