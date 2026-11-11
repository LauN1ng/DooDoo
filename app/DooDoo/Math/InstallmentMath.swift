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
        /// 是否末期。**只用于展示/语义判断**——余数现在落首期，见 `splitEvenly`。
        let isLast: Bool
    }

    // MARK: - 总额均摊

    /// 均摊结果。`perPeriod` 是中间各期，`firstPeriod` 吸收分币余数，`lastPeriod` 默认等于标准额。
    struct Split: Equatable, Sendable {
        /// 单位：元。标准每期金额（已到分）。
        let perPeriod: Decimal
        /// 单位：元。首期金额 = 总额 − 标准额 × (n − 1)，余数全落在这里。
        ///
        /// 「首期」指**未来第一期**（下一次要还的那一期），不是整笔的历史第 1 期。
        let firstPeriod: Decimal
        /// 单位：元。末期金额。
        ///
        /// 均摊路径下等于 `perPeriod`；`splitEndingAt` 路径下是**账单给定的真值**——
        /// 利息不均分时末期往往明显偏小（496.65 分 6 期：末期利息只有 0.83）。
        let lastPeriod: Decimal

        /// 三期金额是否完全一致。一致时界面上不用多写「首期 ¥x / 末期 ¥y」。
        var isEven: Bool { firstPeriod == perPeriod && lastPeriod == perPeriod }
    }

    /// 把总额按期数均摊到分，**余数落首期**。
    ///
    /// 这是存量录入的主路径：账单只给「分期剩余应还 10.22」和「还剩 2 期」，
    /// 每期多少是**除出来**的。不用「每期 × 期数」，是因为那样遇到除不尽的账单
    /// 会一直差几分钱。
    ///
    /// **余数落首期是照账单校准出来的，不是拍脑袋**（用户 2026-11-11 提供两张干净样本）：
    ///
    /// | 账单 | 分期总额 | 期数 | 各期实际 | 首期 |
    /// |---|---|---|---|---|
    /// | 白条 A | 15.34 | 3 | 5.12 / 5.11 / 5.11 | **多 1 分** |
    /// | 白条 B | 163.02 | 6 | 27.17 × 6 | 整除，无余数 |
    ///
    /// 15.34 ÷ 3 = 5.1133…，平台把多出来的 1 分进到**首期**。按「末期吸收」
    /// 会摊成 5.11 / 5.11 / 5.12，跟账单第一行就对不上——这是 M3-3 的错，
    /// 当时只看了招行那笔（1830.15 ÷ 9 正好整除，余数落哪都一样，测不出差别）。
    ///
    /// **均摊只处理本金一侧的零头，不负责还原真实单期。** 真实账单里
    /// 每期金额 = 本金均摊 + 该期利息，而利息并不按期均分——实测 496.65 分 6 期
    /// 的利息是 3.38 / 3.36 × 4 / 0.83，末期只摊到 0.83。所以「总额 ÷ 期数」
    /// 永远只是算术平均，单期真值只能靠 `InstallmentPeriod` 的逐期手改
    /// （`isManualOverride`）还原，任何均摊公式都猜不出来。
    ///
    /// 冲减/退款不在这条链路里：它发生在**计划生成之前**（本金 539 → 扣 60 → 479，
    /// 利息 17.65 加在 479 上得 496.65），因此已经包含在传入的 `total` 里，
    /// 不需要额外输入项，也不会把差额堆到某一期。
    ///
    /// 舍入用 `.down`（向下到分）再让首期吸收差额：首期只会比标准额**多**，
    /// 不会出现「首期 5.10、后面 5.12」这种反直觉的账单。
    ///
    /// 边界：
    /// - `count <= 0` 或 `total <= 0` → `nil`（没有可摊的）
    /// - `count == 1` → 一期吃下全额
    /// - 总额小于期数×0.01（如 0.05 元分 9 期）→ 每期为 0，首期吃全额；
    ///   调用方应按「金额要大于 0」拦，不该走到这里
    static func splitEvenly(total: Decimal, count: Int) -> Split? {
        guard count > 0, total > 0 else { return nil }
        if count == 1 { return Split(perPeriod: total, firstPeriod: total, lastPeriod: total) }
        var quotient = total / Decimal(count)
        var perPeriod = Decimal()
        NSDecimalRound(&perPeriod, &quotient, 2, .down)
        let first = total - perPeriod * Decimal(count - 1)
        return Split(perPeriod: perPeriod, firstPeriod: first, lastPeriod: perPeriod)
    }

    /// 已知**末期金额**，反推中间各期（首期吸收分币余数）。M3-5 新增。
    ///
    /// 这是「利息不均分」的正解：不再让算法去猜利息怎么分布，而是让用户多抄一个数。
    /// 账单上末期金额是明写的，抄它比任何公式都准。
    ///
    /// 为什么一个数就够——四张真实账单全部逐分复现：
    ///
    /// | 账单 | 总额 | 期数 | 末期 | 反推结果 | 账单实际 |
    /// |---|---|---|---|---|---|
    /// | 白条 A | 15.34 | 3 | 5.11 | 5.12 / 5.11 / 5.11 | 一致 |
    /// | 白条 B | 163.02 | 6 | 27.17 | 27.17 × 6 | 一致 |
    /// | 招行 | 1830.15 | 9 | 203.35 | 203.35 × 9 | 一致 |
    /// | 白条 C（利息不均） | 330.23 | 4 | 80.66 | 83.19 × 3 / 80.66 | 一致 |
    ///
    /// 因为这类账单的形态就是「中间各期相等，末期因利息按实际天数或短周期而偏小」，
    /// 首期只多出除不尽的那几分钱。反推时把余数并进首期，正好复现那个零头。
    ///
    /// 边界（`nil` = 输入自相矛盾，界面该提示而不是硬算）：
    /// - `count <= 0` 或 `total <= 0` 或 `last <= 0`
    /// - `last >= total` → 末期吃掉了全部，中间期不存在
    /// - `count == 1` → 一期吃下全额，末期入参被忽略
    /// - 中间期算出 0（末期几乎等于总额）→ `nil`
    static func splitEndingAt(total: Decimal, count: Int, last: Decimal) -> Split? {
        guard count > 0, total > 0, last > 0 else { return nil }
        if count == 1 { return Split(perPeriod: total, firstPeriod: total, lastPeriod: total) }
        let middleTotal = total - last
        guard middleTotal > 0 else { return nil }
        if count == 2 { return Split(perPeriod: middleTotal, firstPeriod: middleTotal, lastPeriod: last) }
        var quotient = middleTotal / Decimal(count - 1)
        var perPeriod = Decimal()
        NSDecimalRound(&perPeriod, &quotient, 2, .down)
        guard perPeriod > 0 else { return nil }
        let first = middleTotal - perPeriod * Decimal(count - 2)
        return Split(perPeriod: perPeriod, firstPeriod: first, lastPeriod: last)
    }

    // MARK: - 逐期展开

    /// 展开未来每一期。
    ///
    /// 输入：剩余期数、下一期还款日，以及**金额的两种给法**之一：
    /// - `remainingDue`：账单上的「分期剩余应还」。给了它就以它为准，
    ///   按 `splitEvenly` 摊到每期、余数落首期（M3-3 起的默认路径）。
    ///   若同时给了 `lastPeriodAmount`，改走 `splitEndingAt` 反推中间各期，
    ///   末期用账单真值——**利息不均分的账单只有这条路能算准**。
    /// - `perPeriodAmount`（+ 可选首期/末期覆盖）：账单只给每期金额时用。
    ///
    /// 这里的「首期」指**剩余期里的第一期**——存量录入时用户只知道「下一期什么时候还、
    /// 还多少」，不知道也不关心历史第一期。
    ///
    /// 输出：`count` 个 `Period`，日期按月递增。
    ///
    /// 边界：
    /// - `count <= 0` → 空数组（已还清）
    /// - `count == 1` → 一期，既是首期也是末期；**首期金额优先**，末期被忽略
    /// - `remainingDue` 给了但 ≤ 0 → 退回按每期金额展开，不产出 0 元期
    /// - `lastPeriodAmount` ≥ `remainingDue`（末期吃掉全部）→ `splitEndingAt` 返 `nil`，
    ///   自动退回均摊，不报错也不产出 0 元期
    /// - 还款日在月末（如 31 日）→ 用 `Calendar` 的月份加法，2 月自动落到 28/29，
    ///   不会溢出到 3 月（日历年加法的正确行为）
    static func futurePeriods(
        count: Int,
        nextDueDate: Date,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        remainingDue: Decimal? = nil,
        calendar: Calendar = .current
    ) -> [Period] {
        guard count > 0 else { return [] }
        // 账单给了剩余应还就以它为准——那个数才是银行要收的钱，
        // 「每期 × 期数」只是它的近似。
        let split: Split? = remainingDue.flatMap { due in
            guard due > 0 else { return nil }
            if let last = lastPeriodAmount, last > 0 {
                return splitEndingAt(total: due, count: count, last: last)
                    ?? splitEvenly(total: due, count: count)
            }
            return splitEvenly(total: due, count: count)
        }
        return (1...count).map { index in
            let dueDate = calendar.date(byAdding: .month, value: index - 1, to: nextDueDate) ?? nextDueDate
            let isLast = (index == count)
            let amount: Decimal
            if let split {
                // 顺序有意：一期时首末期是同一期，按首期算；末期次之；余数落**首期**
                // （见 `splitEvenly` 的账单校准），不是中间期。
                if count == 1 {
                    amount = split.firstPeriod
                } else if isLast {
                    amount = split.lastPeriod
                } else if index == 1 {
                    amount = split.firstPeriod
                } else {
                    amount = split.perPeriod
                }
            } else if index == 1, let first = firstPeriodAmount {
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
    /// 优先级：
    /// 1. `remainingDue`（账单上的「分期剩余应还」）——**有就原样返回**。
    ///    用户拿这个数跟账单逐字核对，任何「算出来的近似值」都会变成疑点。
    /// 2. 没给才用「每期 × 期数 + 首末期差额」推算。
    ///
    /// 边界：`count <= 0` → 0；`remainingDue` ≤ 0 视为没给。
    static func remainingTotal(
        count: Int,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        remainingDue: Decimal? = nil
    ) -> Decimal {
        guard count > 0 else { return 0 }
        if let remainingDue, remainingDue > 0 { return remainingDue }
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
