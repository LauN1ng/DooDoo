import Foundation

/// 分期展开与年化反算（M3，PRD 9.5）。
///
/// 纯函数，不碰 SwiftData、不写余额（AGENTS 7.3）。
/// **反算年化只作展示**，标注「估算」，不参与任何账务计算（AGENTS 7.1）。
enum InstallmentMath {

    /// 未来的一期。
    struct Period: Equatable, Sendable {
        /// 第几期，从 1 开始。1 = **下一期**，不是历史第一期（历史只存汇总，见 PRD 9.5.4）。
        let index: Int
        /// 这一期的还款日。
        let dueDate: Date
        /// 单位：元。这一期应还。
        let amount: Decimal
        /// 是否末期。余数/贴息通常落在这里。
        let isLast: Bool
    }

    // MARK: - 逐期展开

    /// 展开未来每一期。
    ///
    /// 输入：剩余期数、下一期还款日、每期金额、可选的首期与末期金额。
    /// 这里的「首期」指**剩余期里的第一期**——存量录入时用户只知道「下一期什么时候还、
    /// 还多少」，不知道也不关心历史第一期。
    ///
    /// 输出：`count` 个 `Period`，日期按月递增，金额按「首期覆盖 → 标准额 → 末期覆盖」取值。
    ///
    /// 边界：
    /// - `count <= 0` → 空数组（已还清）
    /// - `count == 1` → 一期，既是首期也是末期；**首期金额优先**，末期被忽略
    /// - 还款日在月末（如 31 日）→ 用 `Calendar` 的月份加法，2 月自动落到 28/29，
    ///   不会溢出到 3 月（日历年加法的正确行为）
    static func futurePeriods(
        count: Int,
        nextDueDate: Date,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        calendar: Calendar = .current
    ) -> [Period] {
        guard count > 0 else { return [] }
        return (1...count).map { index in
            let dueDate = calendar.date(byAdding: .month, value: index - 1, to: nextDueDate) ?? nextDueDate
            let isLast = (index == count)
            let amount: Decimal
            if index == 1, let first = firstPeriodAmount {
                amount = first
            } else if isLast, let last = lastPeriodAmount {
                amount = last
            } else {
                amount = perPeriodAmount
            }
            return Period(index: index, dueDate: dueDate, amount: amount, isLast: isLast)
        }
    }

    /// 剩余总额 = 未来各期之和。
    ///
    /// 不能简单用「每期 × 期数」：首期/末期与标准额不同时，
    /// 那样算出来的「剩余应还」会和账单对不上——这是用户最先发现不对劲的地方。
    ///
    /// 边界：`count <= 0` → 0。
    static func remainingTotal(
        count: Int,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil
    ) -> Decimal {
        guard count > 0 else { return 0 }
        var total = perPeriodAmount * Decimal(count)
        if let first = firstPeriodAmount { total += first - perPeriodAmount }
        if count > 1, let last = lastPeriodAmount { total += last - perPeriodAmount }
        return total
    }

    // MARK: - 年化反算

    /// 反算真实年化（估算，PRD 9.5.3）——**已知现值**的版本。
    ///
    /// 每期金额 `A` 为年金、现值 `PV` 为剩余本金，二分求解月利率 `r` 使
    ///
    ///     PV = A × (1 − (1 + r)^−n) / r
    ///
    /// **返回值单位是百分数**：`16.43` 表示 16.43%，不是 0.1643。
    /// 之所以不返回小数率：这个值唯一的用途就是拼进「年化 16.4%」这句话，
    /// 返回小数会让每个调用点都得记得 ×100，漏一次就显示成「0.2%」。
    ///
    /// 优先用这个而不是从总利息倒推：账单上给了「剩余本金」就直接用，
    /// 比「每期 × 期数 − 总利息」准——后者在只剩部分期数时会把整笔的利息错摊到剩余期上。
    ///
    /// 为什么用二分不用牛顿法：这里只要 3 位有效数字的展示值，二分 80 次绰绰有余，
    /// 且 `f(r)` 在 (0, 1) 上单调，不会像牛顿法那样在 `r → 0` 附近被导数值放大跳出区间。
    ///
    /// 内部用 `Double`：这只是一个展示用的估算值。AGENTS 7.1「金额一律 Decimal」管的是钱，
    /// 不是利率求解；求解过程用 Decimal 反而没法做幂运算。
    ///
    /// 边界：
    /// - `periods <= 1` 或 `perPeriodAmount <= 0` → `nil`：一期就还完，年化没有意义
    /// - `presentValue <= 0` → `nil`，数据异常
    /// - `presentValue >= A × n` → **0**（现值不小于总还款额，即零息或负息）
    /// - 根不在 (0, 1] 内（月利率 > 100%，年化 > 1200%）→ `nil`
    static func impliedAnnualRate(
        periods: Int,
        perPeriodAmount: Decimal,
        presentValue: Decimal
    ) -> Decimal? {
        guard periods > 1, perPeriodAmount > 0, presentValue > 0 else { return nil }

        let n = Double(periods)
        let a = NSDecimalNumber(decimal: perPeriodAmount).doubleValue
        let pv = NSDecimalNumber(decimal: presentValue).doubleValue
        // 现值不小于总还款额 = 平台一分利息没收，年化就是 0，不是「算不出来」。
        guard pv < a * n else { return 0 }

        func f(_ r: Double) -> Double {
            if r < 1e-12 { return a * n - pv }        // r → 0 的极限，避免除零
            return a * (1 - pow(1 + r, -n)) / r - pv
        }

        var low = 0.0
        var high = 1.0
        guard f(low) > 0, f(high) < 0 else { return nil }

        for _ in 0..<80 {
            let mid = (low + high) / 2
            if f(mid) > 0 { low = mid } else { high = mid }
        }

        // 月利率 × 12 = 年化小数率，再 × 100 转百分数（见上方「返回值单位」）
        var annual = Decimal(((low + high) / 2) * 12 * 100)
        var rounded = Decimal()
        // 保留 4 位小数：展示到小数点后 1 位（如 16.4%）时不会再被二次舍入带偏。
        NSDecimalRound(&rounded, &annual, 4, .plain)
        return rounded
    }

    /// 反算真实年化（估算）——**只有总利息**的版本。
    ///
    /// 按 PRD 9.5.3 原文：「以「本金 = 每期金额 × 期数 − 总利息」为现值」。
    /// 账单上没给剩余本金、只给了「含利息 110.56」这类数字时走这条。
    ///
    /// 返回单位同 `presentValue` 版本：**百分数**，`15.01` 表示 15.01%。
    ///
    /// 边界：
    /// - `totalInterest <= 0` → **0**（免息分期，年化就是 0）
    /// - 其余同 `presentValue` 版本
    static func impliedAnnualRate(
        periods: Int,
        perPeriodAmount: Decimal,
        totalInterest: Decimal
    ) -> Decimal? {
        guard periods > 1, perPeriodAmount > 0 else { return nil }
        if totalInterest <= 0 { return 0 }
        let pv = perPeriodAmount * Decimal(periods) - totalInterest
        return impliedAnnualRate(periods: periods, perPeriodAmount: perPeriodAmount, presentValue: pv)
    }
}
