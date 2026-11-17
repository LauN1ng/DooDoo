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

    /// 记一笔面板。`entryDay` 记住是从哪一天的卡打开的——补记历史日靠它。
    @State private var showingEntry = false
    @State private var entryDay = Date.now

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
        DeckView(days: cards, index: $index, onAdd: { day in
            entryDay = day
            showingEntry = true
        })
        .padding(.bottom, 8)
        .background(Palette.page)
        .sheet(isPresented: $showingEntry) {
            EntryView(initialDate: entryDay)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
        .task {
            // 首次启动铺演示数据（已有分类就跳过），并给老数据补 Fluent3D 图标
            try? SeedService.prepare(context: context)
        }
        // 卡数会随「今天第一笔流水 / 删空某一天」变化，索引必须跟着收，
        // 否则 `DeckView` 会拿着越界的 index 渲染一张空卡。
        .onChange(of: cards.count) { _, count in
            if index > max(count - 1, 0) { index = max(count - 1, 0) }
        }
    }

    /// 窗口内的天（新的在前）。
    ///
    /// **只让「有流水的天」和「今天」成卡**（2026-11-17 修）。
    /// 旧实现是「窗口内只要有任意一天有流水，就返回整个 7 天窗口」，
    /// 于是记下第一笔的瞬间，首页从 1 张卡跳成 7 张（前卡 + 3 层纸边，
    /// 左右滑还有 6 个完全空白的日卡）——用户原话「原本只有一张卡片的首页
    /// 记一笔之后就变成了卡片堆」。空白天没有内容可看，不成卡。
    ///
    /// 今天永远留一张：那是「记一笔」的入口，空着也要在。
    private var cards: [(day: Date, items: [Transaction])] {
        let window = DayMath.windowed(rows, days: 7, dateOf: { $0.date })
        guard !window.isEmpty else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let kept = window.filter { !$0.items.isEmpty || calendar.isDate($0.day, inSameDayAs: today) }
        return kept.isEmpty ? Array(window.prefix(1)) : kept
    }

    /// 日卡里只放真正的流水。
    ///
    /// 分期债务登记（`.adjustment`，如「分期登记 · 京东白条」）不是「今天花了什么」，
    /// 它在账户详情里看构成——AGENTS 的第一条底线是「首页第一眼是今天的流水」，
    /// 把一笔账本调整混进去会让日卡的支出合计与行长对不上。
    private var rows: [Transaction] {
        transactions.filter { $0.kind != .adjustment }
    }
}

#Preview {
    FlowView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self], inMemory: true)
}
