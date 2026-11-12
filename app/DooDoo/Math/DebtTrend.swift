import Foundation

/// 走势图上的一个点：某一天的欠款（正数）。
struct DebtTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    /// 单位：元。该时点的欠款，已取正。
    let debt: Decimal
    var id: Date { date }
}

/// 单卡欠款走势（账户详情页规格第四节）。
///
/// **数据来源是流水，不是账单与分期**。规格原文：「近 12 个月月末欠款余额
/// （派生值，来自流水）」。所以这条曲线的末点通常**小于**顶部那个欠款——
/// 顶部含未记账单与分期（`CardDebt`），曲线只认已记的流水。
/// 这个差额必须在图注里说清楚，否则用户会以为两处打架。
enum DebtTrend {
    /// 给定时点，算出该卡在每个时点的欠款。
    ///
    /// 余额为正（多还了钱）时欠款记 0，不画负欠款——走势图画的是「欠多少」，
    /// 负值在那条线下面没有意义。
    static func points(ledger: AccountLedger, at dates: [Date]) -> [DebtTrendPoint] {
        dates.map { date in
            let balance = NetWorthSeries.balance(of: ledger, at: date)
            return DebtTrendPoint(date: date, debt: balance < 0 ? -balance : 0)
        }
    }
}
