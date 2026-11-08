import Foundation

/// 一笔流水的「钱视图」。刻意不依赖 SwiftData，方便单测。
struct TxFigure: Equatable, Sendable {
    let kind: TransactionKind
    let amount: Decimal
    let date: Date

    init(kind: TransactionKind, amount: Decimal, date: Date) {
        self.kind = kind
        self.amount = amount
        self.date = date
    }
}

/// 按天分组与当日合计。纯函数，没有状态。
enum DayMath {
    /// 取某个时刻所在自然日的 00:00，作为分组的 key。
    static func dayStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 支出合计。只算 `kind == .expense`——还款、转账、调整都不进消费统计（PRD 9.1）。
    static func expenseTotal(_ items: [TxFigure]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + ($1.kind.countsAsExpense ? $1.amount : 0) }
    }

    /// 收入合计。
    static func incomeTotal(_ items: [TxFigure]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + ($1.kind == .income ? $1.amount : 0) }
    }

    /// 按自然日分组，**新的在前**；同一天内保持传入顺序（调用方已按时间倒序）。
    ///
    /// 边界：空数组返回空数组；跨月、跨年由 `Calendar` 处理；同一天的多笔归到同组。
    static func groupByDay(_ items: [TxFigure], calendar: Calendar = .current) -> [(day: Date, items: [TxFigure])] {
        guard !items.isEmpty else { return [] }
        var order: [Date] = []
        var map: [Date: [TxFigure]] = [:]
        for item in items {
            let key = dayStart(item.date, calendar: calendar)
            if map[key] == nil {
                map[key] = []
                order.append(key)
            }
            map[key]?.append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// 最近 `count` 个自然日的起点，**新的在前**（含 `endingAt` 当天）。
    ///
    /// 用于首页 7 天窗口：`recentDayStarts(7, endingAt: .now)` 返回今天、昨天…… 共 7 天。
    static func recentDayStarts(
        _ count: Int,
        endingAt date: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        let today = dayStart(date, calendar: calendar)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    /// 通用版本：按「取日期」把任意元素排进最近 `count` 天的窗口，新的在前。
    ///
    /// 视图层用这个（要保留 `Transaction` 对象本身），纯计算部分用下面的 `window`。
    static func windowed<T>(
        _ items: [T],
        days count: Int,
        endingAt date: Date = .now,
        calendar: Calendar = .current,
        dateOf: (T) -> Date
    ) -> [(day: Date, items: [T])] {
        let starts = recentDayStarts(count, endingAt: date, calendar: calendar)
        guard !starts.isEmpty else { return [] }
        let allowed = Set(starts)
        var map: [Date: [T]] = [:]
        for start in starts { map[start] = [] }
        for item in items {
            let key = dayStart(dateOf(item), calendar: calendar)
            guard allowed.contains(key) else { continue }
            map[key]?.append(item)
        }
        return starts.map { ($0, map[$0] ?? []) }
    }

    /// 把「最近 count 天的流水」排成窗口：每天一个桶，没有流水的天也在（空桶），新的在前。
    ///
    /// 边界：`items` 里有窗口外的数据时会被丢弃；窗口内没数据的天返回空桶。
    static func window(
        _ items: [TxFigure],
        days count: Int,
        endingAt date: Date = .now,
        calendar: Calendar = .current
    ) -> [(day: Date, items: [TxFigure])] {
        let starts = recentDayStarts(count, endingAt: date, calendar: calendar)
        let allowed = Set(starts)
        var map: [Date: [TxFigure]] = [:]
        for start in starts { map[start] = [] }
        for item in items {
            let key = dayStart(item.date, calendar: calendar)
            guard allowed.contains(key) else { continue }
            map[key]?.append(item)
        }
        return starts.map { ($0, map[$0] ?? []) }
    }
}
