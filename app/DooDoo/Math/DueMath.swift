import Foundation

/// 一期待还的钱。
///
/// 刻意**不引用** `InstallmentPeriod`：Math 层是纯函数，不碰 SwiftData（见 `Math/README.md`
/// 硬规则），单测才能在内存里造任意账单。视图层负责把模型转成这个值。
struct DueEntry: Equatable, Sendable {
    /// 单位：元。这一期应还总额。
    let amount: Decimal

    /// 这一期的还款日。
    let dueDate: Date

    /// 已还。已还的期不进「本月要还」。
    let isPaid: Bool

    init(amount: Decimal, dueDate: Date, isPaid: Bool = false) {
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
    }
}

/// 某张卡本期账单。**目前还没有数据源**（`BillStatement` 未建，见 PROGRESS 下一步 2），
/// 先把口径留好：接上账单时只需把这里填上，上层一行都不用改。
struct BillDue: Equatable, Sendable {
    /// 单位：元。账单上「本期应还」。
    let amount: Decimal

    /// 这一期的还款日。逾期判断靠它。
    let dueDate: Date
}

/// 一张卡「本月要还」的结论。**每张卡只会有一个。**
struct AccountDue: Equatable, Sendable {
    /// 这个数是**从哪来的**。同时也是「为什么不会再被加一次」的证据——
    /// 只有 `.bill` 就只能有账单，只有 `.installment` 就只能有分期。
    enum Source: Equatable, Sendable {
        /// 本期账单（含账单里已经并进去的分期）。
        case bill
        /// 分期到期（因为没有本期账单，才退回这里）。
        case installment
    }

    /// 单位：元。这张卡本月要还的钱。
    let amount: Decimal

    let source: Source

    /// 参与合计的笔数：账单卡恒为 1；分期卡为未还的期数。
    let itemCount: Int

    /// 未还条目里**最早**的还款日。逾期时它就是逾期那笔的日期。
    let nearestDueDate: Date?

    /// 逾期笔数。
    let overdueCount: Int

    /// 最早那笔逾期了多少天（正数）。没逾期为 0。
    let overdueDays: Int

    var isOverdue: Bool { overdueCount > 0 }
}

/// 整组的合计。
///
/// **只有一条合法路径**：`Σ 各卡 AccountDue.amount`。不存在「Σ账单 + Σ分期」这个入口，
/// 因为 `AccountDue` 每卡只有一个（见上面 `Source`）。
struct DueGroup: Equatable, Sendable {
    /// 单位：元。整组本月要还。
    let total: Decimal

    /// 有几张卡本月要还。
    let accountCount: Int

    /// 合计几笔。
    let itemCount: Int

    /// 未还条目里最早的还款日。
    let nearestDueDate: Date?

    let overdueCount: Int
    let overdueDays: Int

    var isOverdue: Bool { overdueCount > 0 }
}

/// 资产页 2.4 那一行明细的文案。
///
/// 拆成两段是因为逾期那段要**单独标红**（`AccountGroupView` 里用两个 `Text` 拼），
/// 而整行仍是 9.5pt 单行不换行——不做横幅之后，逾期唯一的可见位置就在这儿。
struct DueLine: Equatable, Sendable {
    /// `本月要还 693.67 · 3 笔 · 最近 11/14`
    ///
    /// 有逾期时末尾改成 `· 逾期 1 笔`（不再说「最近」，因为最近那笔就是逾期那笔，
    /// 说「最近 08/21」等于把逾期藏进一个中性词里）。
    let text: String

    /// ` · 逾期 1 笔 82 天`。无逾期为 `nil`。
    let overdueText: String?
}

/// 「本月要还」的计算口径（资产页规格 2.4 / PRD 9.4）。
///
/// ## 铁律：每张卡只出一个数，账单优先，**绝不相加**
///
/// 「本月要还」的账单金额里**本来就含**分期那一部分（分期每期的钱是并进当期账单的）。
/// 所以 Σ账单 + Σ分期 会把分期算两遍：
///
/// ```
/// 错误：Σ账单 2,742.00 + Σ分期 693.67 = 3,435.67   ← 多出来的正好是三张卡的分期部分
/// 正确：Σ各卡 dueAmount（有账单取账单，无账单取分期）= 2,742.00
/// ```
///
/// 这个错误在账户详情页已经犯过一次（第八节），这里是同一口径在资产页的落地。
/// 代码里把「相加」这条路**根本堵死**：`accountDue` 返回的是单值，不是两个数的容器。
///
/// ## 窗口：本月及以前，不含未来月
///
/// 一条待还属于「本月要还」当且仅当 `dueDate < 下月 1 号`（且未还）。
/// 这么定是因为逾期必须算进来——8 月该还而没还的钱，不会因为到了 11 月就消失；
/// 如果按「本月 1 号 ≤ dueDate < 下月 1 号」卡死，逾期那笔会从界面上蒸发。
enum DueMath {
    // MARK: - 单卡

    /// 一张卡本月要还多少。
    ///
    /// - 有账单（`bill != nil` 且金额 > 0）：**只**返回账单金额，`installments` 一根手指都不碰。
    /// - 没账单：返回本月及以前未还的分期期数之和。
    /// - 两者皆空、或金额为 0：返回 `nil`，界面不占位（不显示「本月要还 0.00」）。
    ///
    /// 边界：账单金额为 0 视为「没有账单」，退回分期——0 元的账单是无效输入，
    /// 让它挡住真实的分期金额会少显示一笔要还的钱。
    static func accountDue(
        bill: BillDue? = nil,
        installments: [DueEntry] = [],
        today: Date,
        calendar: Calendar = .current
    ) -> AccountDue? {
        if let bill, bill.amount > 0 {
            let billIsOverdue = isOverdue(dueDate: bill.dueDate, isPaid: false, today: today, calendar: calendar)
            return AccountDue(
                amount: bill.amount,
                source: .bill,
                itemCount: 1,
                nearestDueDate: bill.dueDate,
                overdueCount: billIsOverdue ? 1 : 0,
                overdueDays: billIsOverdue ? overdueDays(dueDate: bill.dueDate, today: today, calendar: calendar) : 0
            )
        }

        let candidates = installments.filter { entry in
            !entry.isPaid && isDueInWindow(entry.dueDate, today: today, calendar: calendar)
        }
        guard !candidates.isEmpty else { return nil }

        let total = candidates.reduce(Decimal.zero) { $0 + $1.amount }
        guard total > 0 else { return nil }

        // 变量名不要跟静态方法 `overdueDays(dueDate:today:calendar:)` 撞车——
        // `let overdueDays = overdueDays(...)` 会解析到「自身初始化表达式里的自身」而报错。
        let overdueEntries = candidates.filter {
            isOverdue(dueDate: $0.dueDate, isPaid: $0.isPaid, today: today, calendar: calendar)
        }
        let maxOverdueDays = overdueEntries
            .map { overdueDays(dueDate: $0.dueDate, today: today, calendar: calendar) }
            .max() ?? 0

        return AccountDue(
            amount: total,
            source: .installment,
            itemCount: candidates.count,
            nearestDueDate: candidates.map(\.dueDate).min(),
            overdueCount: overdueEntries.count,
            overdueDays: maxOverdueDays
        )
    }

    // MARK: - 整组

    /// 整组合计。**输入就是每张卡唯一的那个 `AccountDue`**，所以这里只有一种加法。
    ///
    /// 边界：空数组、或合计为 0 → `nil`（整组没人在本月要还，明细行不占位）。
    static func group(_ dues: [AccountDue]) -> DueGroup? {
        guard !dues.isEmpty else { return nil }
        let total = dues.reduce(Decimal.zero) { $0 + $1.amount }
        guard total > 0 else { return nil }

        return DueGroup(
            total: total,
            accountCount: dues.count,
            itemCount: dues.reduce(0) { $0 + $1.itemCount },
            nearestDueDate: dues.compactMap(\.nearestDueDate).min(),
            overdueCount: dues.reduce(0) { $0 + $1.overdueCount },
            overdueDays: dues.map(\.overdueDays).max() ?? 0
        )
    }

    // MARK: - 文案

    /// 资产页 2.4 的明细行：`本月要还 693.67 · 3 笔 · 最近 11/14`。
    ///
    /// `text` 里**不含**逾期那段，逾期单独放在 `overdueText` 里由视图拼红字。
    /// 有逾期时 `text` 也不再说「最近」——最近那笔就是逾期那笔，
    /// 「最近 08/21」这种说法等于把问题藏进一个中性词里。
    static func line(_ due: DueGroup, calendar: Calendar = .current) -> DueLine {
        var text = "本月要还 \(MoneyMath.money(due.total)) · \(due.itemCount) 笔"

        guard due.isOverdue else {
            if let nearest = due.nearestDueDate {
                text += " · 最近 \(monthDay(nearest, calendar: calendar))"
            }
            return DueLine(text: text, overdueText: nil)
        }

        let overdue = due.overdueDays > 0
            ? " · 逾期 \(due.overdueCount) 笔 \(due.overdueDays) 天"
            : " · 逾期 \(due.overdueCount) 笔"
        return DueLine(text: text, overdueText: overdue)
    }

    // MARK: - 日期规则

    /// 是否落在「本月要还」的窗口：`dueDate < 下月 1 号 00:00`。
    ///
    /// 含逾期（早于本月），不含未来月。日历换算失败时退回「不晚于今天」，
    /// 宁可漏掉月末那两天，也不要把未来一整年都算成「本月要还」。
    static func isDueInWindow(_ dueDate: Date, today: Date, calendar: Calendar = .current) -> Bool {
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
              let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else {
            return calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: today)
        }
        return calendar.startOfDay(for: dueDate) < nextMonthStart
    }

    /// 逾期：过了还款日还没还。按**自然日**比较，还款日当天不算逾期（PRD 9.7）。
    static func isOverdue(
        dueDate: Date,
        isPaid: Bool,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isPaid else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: today)
    }

    /// 逾期天数（正数）。还款日当天为 0，未逾期也为 0。
    static func overdueDays(dueDate: Date, today: Date, calendar: Calendar = .current) -> Int {
        let due = calendar.startOfDay(for: dueDate)
        let now = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: due, to: now).day ?? 0
        return max(0, days)
    }

    /// `11/14`。补零到两位，和 PRD 里的 `11/08` 一致。
    static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d/%02d", parts.month ?? 0, parts.day ?? 0)
    }
}
