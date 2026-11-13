import Foundation

/// 账单周期与账期归属（M3-10，PRD 9.7 补录 / 第八节 `Transaction.billPeriod`）。
///
/// 只回答一个问题：**这一笔消费归到哪一期账单**。
/// 循环类账户（花呗、白条、信用卡）的周期是「每月 15 日到次月 14 日」这种跨月的段，
/// 而账期名用**周期止所在月**——花呗 10/15–11/14 这一期叫 `2026-11`，11/25 还
/// （与 `BillStatement.period` 同一口径）。
///
/// 为什么不放在视图里现算：`EntryView` 原来那句 `"账单期 \(start)/15–\(end) · 计入下月"`
/// 把周期止日号写死成 15、把「下月」写死成固定文案，换个账单日就是错的。
/// 凭据要能单测（AGENTS 7.3），所以做成纯函数。
///
/// 边界：
/// - `cycleStartDay` 为空或不在 1...31 → 没有周期信息，账期退回「发生日所在月」，
///   `start` / `end` 为 `nil`（界面只写「计入 11 月」）
/// - 日号超出当月天数（31 落在 2 月）→ 落到当月最后一天，不溢出到下月
/// - 还款日的判断：`dueDay` 大于周期止的日号 → 同一个月的 `dueDay`；
///   小于等于 → 次月（账单日 5 号、还款日 23 号这种，账期 7 月的还款日在 8 月）
enum BillCycleMath {

    /// 一笔消费落的那一期账单。
    struct Cycle: Equatable, Sendable {
        /// 账期名，`2026-11`。**不是还款日所在月**，是周期止所在月。
        let period: String
        /// 周期起，如 2026-10-15。没有周期信息时为 `nil`。
        let start: Date?
        /// 周期止，如 2026-11-14。
        let end: Date?
        /// 还款日，如 2026-11-25。账户没填 `dueDay` 时为 `nil`。
        let dueDate: Date?

        /// 有完整周期才能写出「10/15–11/14」这种区间。
        var hasRange: Bool { start != nil && end != nil }
    }

    // MARK: - 账期文本

    /// `2026-11`。传日期只取年月。
    static func periodText(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 2026, parts.month ?? 1)
    }

    /// 账期的月份，`2026-11` → `11 月`。界面短文案用。
    static func monthLabel(_ period: String) -> String {
        guard let month = monthNumber(period) else { return period }
        return "\(month) 月"
    }

    /// 账期的月份数字，解析失败返回 `nil`。
    static func monthNumber(_ period: String) -> Int? {
        let parts = period.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        return month
    }

    /// 账期前后平移，`("2026-11", 1)` → `2026-12`。格式非法返回 `nil`。
    static func shift(_ period: String, months: Int, calendar: Calendar = .current) -> String? {
        guard let base = monthStart(period: period, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: base)
        else { return nil }
        return periodText(for: moved, calendar: calendar)
    }

    // MARK: - 周期归属

    /// 发生日 → 它属于哪一期账单。
    static func cycle(
        for date: Date,
        cycleStartDay: Int?,
        cycleEndDay: Int?,
        dueDay: Int?,
        calendar: Calendar = .current
    ) -> Cycle {
        let fallback = periodText(for: date, calendar: calendar)
        guard let startDay = normalized(cycleStartDay) else {
            // 没有账单周期：账期只能退回「发生日所在月」，还款日照 `dueDay` 落在同月。
            let due = dueDate(inPeriod: fallback, dueDay: dueDay, cycleEndDay: cycleEndDay, calendar: calendar)
            return Cycle(period: fallback, start: nil, end: nil, dueDate: due)
        }

        let month = monthStart(of: date, calendar: calendar)
        let dayOfMonth = calendar.component(.day, from: date)
        // 日号还没到本月的起算日 → 这一笔在上个月开始的那个周期里
        let base = dayOfMonth >= startDay
            ? month
            : (calendar.date(byAdding: .month, value: -1, to: month) ?? month)
        let start = day(inMonthOf: base, day: startDay, calendar: calendar)
        let nextBase = calendar.date(byAdding: .month, value: 1, to: base) ?? base
        let nextStart = day(inMonthOf: nextBase, day: startDay, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: -1, to: nextStart).map {
            calendar.startOfDay(for: $0)
        }
        // 账期名 = 周期止所在月（花呗 10/15–11/14 → 2026-11）
        let period = periodText(for: end ?? start, calendar: calendar)
        // 账户没填周期止时，用算出来的周期止日号判断还款日跨不跨月
        let endDay = normalized(cycleEndDay) ?? end.map { calendar.component(.day, from: $0) }
        let due = dueDate(inPeriod: period, dueDay: dueDay, cycleEndDay: endDay, calendar: calendar)
        return Cycle(period: period, start: start, end: end, dueDate: due)
    }

    /// 归属行那句说明：`账单期 10/15–11/14 · 计入 11 月`。
    /// 没有周期信息时给 `nil`，由调用方退回「计入 11 月」。
    static func caption(_ cycle: Cycle, calendar: Calendar = .current) -> String? {
        guard let start = cycle.start, let end = cycle.end else { return nil }
        let head = calendar.dateComponents([.month, .day], from: start)
        let tail = calendar.dateComponents([.month, .day], from: end)
        let startText = "\(head.month ?? 0)/\(head.day ?? 0)"
        let endText = "\(tail.month ?? 0)/\(tail.day ?? 0)"
        return "账单期 \(startText)–\(endText) · 计入 \(monthLabel(cycle.period))"
    }

    /// 某一期账单的还款日（账期名 + `dueDay` → 日期）。
    ///
    /// 给「首期还款日」的默认值用：分期第一期的到期日应当跟着**这一笔落在的那一期**
    /// 走，而不是「今天之后最近的一个 dueDay」——11/20 的消费算进 `2026-12`，
    /// 首期就是 12/25，不是 11/25。
    ///
    /// 边界：账期格式非法或没填 `dueDay` → `nil`，调用方退回按 `dueDay` 推。
    static func dueDate(
        for period: String,
        dueDay: Int?,
        cycleEndDay: Int? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        dueDate(inPeriod: period, dueDay: dueDay, cycleEndDay: cycleEndDay, calendar: calendar)
    }

    // MARK: - 私有

    private static func normalized(_ value: Int?) -> Int? {
        guard let value, (1...31).contains(value) else { return nil }
        return value
    }

    /// 该日期所在月的 1 号 00:00。
    private static func monthStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// `2026-11` → 2026-11-01。格式非法返回 `nil`。
    private static func monthStart(period: String, calendar: Calendar = .current) -> Date? {
        let parts = period.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// 某个月的第 n 天（当天零点）。超出当月天数时取最后一天。
    private static func day(inMonthOf base: Date, day target: Int, calendar: Calendar = .current) -> Date {
        let month = monthStart(of: base, calendar: calendar)
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        let clamped = min(max(target, 1), days)
        return calendar.date(byAdding: .day, value: clamped - 1, to: month) ?? month
    }

    /// 账期内的还款日。
    ///
    /// 还款日通常晚于周期止（花呗 14 号结账、25 号还），落在账期同月；
    /// 但也存在「账单日 5 号、还款日 23 号」这种，`dueDay` 比周期止的日号小，
    /// 那笔还款其实在下个月——按 `dueDay > 周期止日号` 判断，不做特例表。
    private static func dueDate(
        inPeriod period: String,
        dueDay: Int?,
        cycleEndDay: Int?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let dueDay = normalized(dueDay),
              let base = monthStart(period: period, calendar: calendar)
        else { return nil }
        let monthBase: Date
        if let endDay = normalized(cycleEndDay), dueDay <= endDay {
            monthBase = calendar.date(byAdding: .month, value: 1, to: base) ?? base
        } else {
            monthBase = base
        }
        return day(inMonthOf: monthBase, day: dueDay, calendar: calendar)
    }
}
