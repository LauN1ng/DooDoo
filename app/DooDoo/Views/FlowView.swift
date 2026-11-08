import SwiftUI
import SwiftData

/// 流水（首页）。
///
/// M1 只做「看」：最近 7 天、一天一张日卡、左右滑回看。
/// **没有记账行**——记一笔的页面还没设计，按用户 2026-11-08 的决定先不做入口。
struct FlowView: View {
    @Environment(\.modelContext) private var context

    /// 只取最近 7 天、未软删的流水。冷启动不会扫全表（AGENTS 7.5）。
    @Query private var transactions: [Transaction]

    @State private var index = 0

    init() {
        let start = DayMath.recentDayStarts(7).last
            ?? Calendar.current.startOfDay(for: .now)
        _transactions = Query(
            filter: #Predicate<Transaction> { $0.deletedAt == nil && $0.date >= start },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    var body: some View {
        DeckView(days: cards, index: $index)
            .padding(.bottom, 8)
            .background(Palette.page)
            .task {
                // 首次启动铺演示数据（已有分类就跳过），并给老数据补 Fluent3D 图标
                try? SeedService.prepare(context: context)
            }
    }

    /// 窗口内的天（新的在前）。空账本时只留今天一张空卡（规格 3.1「首用只有 1 张」）。
    private var cards: [(day: Date, items: [Transaction])] {
        let window = DayMath.windowed(transactions, days: 7, dateOf: { $0.date })
        guard !window.isEmpty else { return [] }
        if window.contains(where: { !$0.items.isEmpty }) {
            return window
        }
        return Array(window.prefix(1))
    }
}

#Preview {
    FlowView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, AppSettings.self], inMemory: true)
}
