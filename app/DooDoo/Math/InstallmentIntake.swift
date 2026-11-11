import Foundation

/// 存量分期的录入换算（M3-2，PRD 9.5.2 / 9.5.4）。
///
/// 表单只让用户填**账单上看得见的**三个数（剩余期数、每期金额、下一期还款日），
/// 而模型要的是 `totalPeriods` + `paidPeriods`。这两者的换算、批量进度、
/// 还款日推算都放在这里，纯函数、可单测（AGENTS 7.3）。
///
/// 为什么不把这些散在 ViewModel 里：58 笔存量录入是这阶段最容易出错的路径
/// （填错一个数就得重录），换算必须能被单测钉住，而不是靠手点验证。
enum InstallmentIntake {

    // MARK: - 剩余期数 → total / paid

    /// 期数换算结果。
    struct Periods: Equatable, Sendable {
        /// 总期数（含已还）。
        let total: Int
        /// 已还期数。
        let paid: Int
        /// 剩余期数 = `total - paid`，不小于 0。
        var remaining: Int { max(0, total - paid) }
    }

    /// 剩余期数 +（可选）总期数 → 模型的 `totalPeriods` / `paidPeriods`。
    ///
    /// PRD 9.5.2 的必填只有「剩余期数」，所以这里是主路径：
    ///
    /// - `total == nil` → 全部算未来期（`total = remaining`、`paid = 0`）。
    ///   界面会显示「剩 7 期」而不是「第 6/12 期」——用户没填总期数就不该猜，
    ///   猜错会让「已还 6 期」这种话变成假信息。
    /// - `total != nil` → `paid = total - remaining`，用于复述账单原话「第 6/12 期」。
    ///
    /// 边界：
    /// - `remaining <= 0` → `(0, 0)`，已还清（不该出现在存量录入里，由校验先拦）
    /// - `total < remaining`（填错，如剩 12 期却把总共写成 6）→ 退回 `total = remaining`。
    ///   宁可少显示历史进度，也不要算出负的已还期数——负数会污染「第 x/y 期」和进度条
    static func periods(remaining: Int, total: Int?) -> Periods {
        guard remaining > 0 else { return Periods(total: 0, paid: 0) }
        guard let total, total >= remaining else {
            return Periods(total: remaining, paid: 0)
        }
        return Periods(total: total, paid: total - remaining)
    }

    // MARK: - 账单把「本金 + 利息」拆两行

    /// 账单把剩余待还拆成「本金 / 利息」两行时，合成一个**含息的剩余应还**。
    ///
    /// 招行 e招贷 的账单页就是这么给的：`剩余待入账金额` 下面分
    /// `本金 6,670.93` + `利息 851.57`，而真实每期扣款是
    /// `442.50 × 17 = 7,522.50`——正好是两行之和。App 只需要一个数，
    /// 以前这一加得用户在 App 外自己算，抄错一行就少算 851.57。
    ///
    /// **合的是现金流，不是本息拆分。** 合出来的 7,522.50 当作「我要还多少」记账，
    /// 逐期本金/利息不入库（PRD 9.5 口径：欠款按含息总额记）。
    ///
    /// 边界：
    /// - `principal` 为空或 ≤ 0 → `nil`（校验层该拦，不产出 0 元应还）
    /// - `interest` 为空 → 视为 0（零息分期确实存在）
    /// - `interest < 0` → `nil`（负数没有意义，不静默取绝对值）
    static func includedTotal(principal: Decimal?, interest: Decimal?) -> Decimal? {
        guard let principal, principal > 0 else { return nil }
        let extra = interest ?? 0
        guard extra >= 0 else { return nil }
        return principal + extra
    }

    // MARK: - 批量进度

    /// 还差几笔。已录超过目标时按 0（不要显示「还差 −3 笔」）。
    ///
    /// `target <= 0` 视为「没设目标」，同样返回 0——界面据此隐藏进度条。
    static func batchRemaining(target: Int, done: Int) -> Int {
        guard target > 0 else { return 0 }
        return max(0, target - max(0, done))
    }

    // MARK: - 按账单日推还款日

    /// 由账户的还款日（`Account.dueDay`，如 25）推出**下一个**还款日。
    ///
    /// 58 笔花呗分期的还款日是同一个，让用户每笔都手选日期是纯浪费——
    /// 账户里已经有 `dueDay` 了就带出来。
    ///
    /// 规则：
    /// - 本月的 `dueDay` **还没过或就是今天** → 用本月（当天还来得及还）
    /// - 本月已过 → 用下月
    /// - `dueDay` 超出当月天数（如 31 落在 2 月）→ 落到当月最后一天，
    ///   不溢出到下月 3 号（信用卡账单日的真实行为）
    /// - `dueDay` 为空或不在 1...31 → 退回 `today` 当天零点，由用户自己选
    static func defaultDueDate(
        dueDay: Int?,
        from today: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: today)
        guard let dueDay, (1...31).contains(dueDay) else { return start }
        guard let thisMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: start)
        ) else { return start }

        for offset in 0...1 {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: thisMonth),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
            else { continue }
            let day = min(dueDay, daysInMonth)
            guard let candidate = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
                  candidate >= start
            else { continue }
            return calendar.startOfDay(for: candidate)
        }
        return start
    }

    // MARK: - 批量录入口径的本地存储

    /// 「还剩几笔要录」的目标笔数存在 `UserDefaults`，不进 SwiftData。
    ///
    /// 理由：这是**一次导入过程的进度**，不是账本数据。放模型里会给
    /// `AppSettings` 加字段（AGENTS 6.2 的 2.0 档，且老库迁移多一个风险点），
    /// 而这个数字丢了最多是重新点一次「设目标」。
    enum Batch {
        static let targetKey = "installment.batch.target"

        /// 默认目标：PRD 附录 B 记的存量在读分期是 58 笔（花呗 3/6/12 期 + 招行信用卡 3 期）。
        /// 预填它只是省一次输入，界面上可随时改。
        static let defaultTarget = 58

        static var target: Int {
            let stored = UserDefaults.standard.object(forKey: targetKey) as? Int
            return stored ?? defaultTarget
        }

        static func setTarget(_ value: Int) {
            UserDefaults.standard.set(max(0, value), forKey: targetKey)
        }
    }
}
