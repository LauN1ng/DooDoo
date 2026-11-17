import Foundation

/// 一笔流水对某账户余额的影响，带发生时间。
struct LedgerPoint: Sendable, Equatable {
    let date: Date
    let delta: Decimal
}

/// 单个账户的完整账本视图：初始余额 + 全部流水影响。脱离 SwiftData。
struct AccountLedger: Sendable {
    let kind: AccountKind
    let initial: Decimal
    let entries: [LedgerPoint]

    /// 账户创建日（`Account.createdAt`）。**早于这一天的时点，这个账户还不存在。**
    ///
    /// 2026-11-17 修「初始化折线起点不对」时加的。此前 `initial` 被无条件算进
    /// 每一个历史采样点，于是「今天刚建的卡、今天填的欠款 25,148」在走势图上
    /// 表现为「一周前就已经欠着 25,148」——曲线是一条平线，起点是当前值。
    /// 更糟的是分期入账走 `adjustAccountBalance` 改的也是 `initial`，
    /// 所以录完分期整条曲线**原地下移**，看不出任何变化。
    ///
    /// `nil` 表示调用方没给（单测构造），退化成旧行为——不锚定创建日。
    let createdAt: Date?

    init(kind: AccountKind, initial: Decimal, entries: [LedgerPoint], createdAt: Date? = nil) {
        self.kind = kind
        self.initial = initial
        self.entries = entries
        self.createdAt = createdAt
    }
}

/// 走势图上的一个点。
struct NetWorthPoint: Sendable, Equatable, Identifiable {
    let date: Date
    let mine: Decimal
    let owe: Decimal
    var id: Date { date }
}

/// 顶部总览卡的 5 段区间。
enum NetWorthRange: String, CaseIterable, Sendable, Identifiable {
    case week
    case month
    case quarter
    case thisYear
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "1周"
        case .month: "1月"
        case .quarter: "3月"
        case .thisYear: "今年"
        case .year: "1年"
        }
    }
}

/// 净资产走势。纯函数：给定各账户的初始余额与流水，回推任意时点的「我有 / 我欠」。
///
/// 为什么是回推而不是正推：`currentBalance` 已经由 `LedgerService` 算好，
/// 任一时点的值 = 当前值 − 该时点之后所有流水的影响，这样不会和余额算法打架。
enum NetWorthSeries {
    /// 某账户在 `date` 时点的余额。
    ///
    /// **创建日之前返回 0**（2026-11-17 修）：账户在 `createdAt` 那天才存在，
    /// 它的期初余额不该被搬到更早的日期上。没有这一条，走势图会把今天才填的
    /// 25,148.82 画成「一周前就欠着」，起点就错了。
    ///
    /// 比较用 `startOfDay(createdAt)`：创建**当天**整天都算已存在（余额 = 期初 + 当天流水），
    /// 否则今天上午建的卡要到明天才出现在曲线上。
    static func balance(
        of ledger: AccountLedger,
        at date: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        if let createdAt = ledger.createdAt,
           date < calendar.startOfDay(for: createdAt) {
            return 0
        }
        return ledger.entries.reduce(ledger.initial) { partial, point in
            point.date <= date ? partial + point.delta : partial
        }
    }

    /// 给定采样日期，算出每个点的「我有 / 我欠」。
    ///
    /// 复杂度 O(点数 × 流水数)；一年 12 点 × 几百笔 = 几千次加法，可忽略。
    static func points(_ ledgers: [AccountLedger], at dates: [Date]) -> [NetWorthPoint] {
        dates.map { date in
            let snapshots = ledgers.map { ledger in
                AccountSnapshot(kind: ledger.kind, balance: balance(of: ledger, at: date))
            }
            return NetWorthPoint(
                date: date,
                mine: NetWorth.mine(snapshots),
                owe: NetWorth.owe(snapshots)
            )
        }
    }

    /// 区间对应的采样日期，**从旧到新**。
    ///
    /// - `1周` = 7 个点按天；`1月` = 30 个点按天；`3月` = 12 个点按周；
    /// - `今年` = 从 1 月 1 日到本月，按月；`1年` = 12 个点按月。
    static func dates(
        for range: NetWorthRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .week:
            return (0..<7).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }
        case .month:
            return (0..<30).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }
        case .quarter:
            return (0..<12).reversed().compactMap {
                calendar.date(byAdding: .day, value: -7 * $0, to: today)
            }
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
            var dates: [Date] = []
            var cursor = start
            while cursor <= today {
                dates.append(cursor)
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            if let last = dates.last, !calendar.isDate(last, inSameDayAs: today) {
                dates.append(today)
            }
            return dates
        case .year:
            return (0..<12).reversed().compactMap {
                calendar.date(byAdding: .month, value: -$0, to: today)
            }
        }
    }
}
