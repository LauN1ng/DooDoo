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
    /// 这一期所属的计划是**在「记一笔」里跟消费一起建的**（M3-10）。
    ///
    /// 那种计划的消费按全额记了 `expense`，欠款已经在账户余额里了，
    /// 再加一遍就是双份（见 `Installment.createdFromEntry`）。
    /// 默认 `false`：存量计划与所有老调用点行为不变。
    let isCoveredByBalance: Bool

    init(amount: Decimal, dueDate: Date, isPaid: Bool, isCoveredByBalance: Bool = false) {
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
        self.isCoveredByBalance = isCoveredByBalance
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

/// 「我欠」的口径（PRD 9.4 / 9.3；显示层派生，**2026-11-12 用户定案「相加」**）。
///
/// ## 为什么不能直接用账户余额
///
/// `Account.currentBalance` 是**流水**的派生值（PRD 9.11）。而信用卡的真实用法是
/// 「消费在平台 App 里看、月底出一期账单」，这些消费流水往往没有逐笔记进本 App——
/// 于是余额停在 0，界面就会说「我不欠钱，但这个月要还 435.41」。自相矛盾。
///
/// ## 两个来源相加
///
/// ```
/// 欠款 = 余额欠额 + 账期欠款
/// 余额欠额 = max(0, −balance)                      ← 记了流水的那部分
/// 账期欠款 = 未还账单 + 账单覆盖日之后的分期未还期    ← 只录了账单/分期的那部分
/// ```
///
/// **为什么相加而不是取 max**：max 的副作用是「记一笔信用消费，欠款一动不动」——
/// 分期总额通常远大于余额，新记的消费永远落在小的那一侧，被吞掉。
/// 2026-11-12 用户真机反馈「记一笔选信用账户，浮层和详情都不更新」，就是这么来的。
///
/// **代价（已确认接受）**：同一笔消费如果既记了流水、又把它的分期录进来了，
/// 会算两遍，欠款偏高。用户当前用法是「信用卡几乎不记流水，只录分期」，
/// 重复的情形很少；真要精确得靠账单周期分层，留到有需要时再说。
///
/// **例外：记一笔新建的分期不参与账期那一项**（2026-11-13，M3-10）。
/// 那种计划在创建时已经按 PRD 9.5.6 记了一条**全额** `expense`，
/// 欠款已经在 `balance` 里；若再加一次未还期，1,440.39 的平板会显示成 2,880.78。
/// 判据是 `Installment.createdFromEntry`，不是「余额有没有变」——
/// 后者会被还款流水、溢缴等情况带偏。存量计划（`false`）保持上面那套相加逻辑。
///
/// ## 账期内部仍然绝不重复
///
/// 相加只发生在「余额」与「账期」之间。账期内部，本期到期的分期已经并进本期账单
/// （PRD 8.1 恒等式），所以只算**账单覆盖日之后**的期——全加会把本期分期算两遍。
/// 这条和「本月要还」（PRD 9.12，账单与分期二选一）是同一个约束在不同口径下的体现。
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
                // 记一笔新建的分期：消费全额已进余额，这里再加就是双份（M3-10）。
                guard !period.isCoveredByBalance else { return false }
                guard let coverage else { return true }   // 没有任何账单：所有未还期都算
                return calendar.startOfDay(for: period.dueDate) > coverage
            }
            .reduce(Decimal.zero) { $0 + $1.amount }

        return balanceOwe + unpaidBills + uncoveredPeriods
    }

    /// 一组负债卡的合计（正数，单位元）。
    ///
    /// 边界：空数组返回 0——「我欠 0.00」是合法的（真的一分不欠）。
    static func owe(_ cards: [CardDebtInput], calendar: Calendar = .current) -> Decimal {
        cards.reduce(Decimal.zero) { $0 + owe($1, calendar: calendar) }
    }
}
