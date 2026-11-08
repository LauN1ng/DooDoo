import SwiftUI

/// 日卡堆：一叠纸，最上面那张是当前这天。
///
/// 几何照 `首页规格冻结-v1.0.md` 3.2：
/// 层厚恒定 10、可见层封顶 4（3 条边）、前卡底距屏 `max(34, 8 + 10×(N−1))`、
/// 卡高 `720 − (前卡底距屏 − 8)`。这里用父视图给的高度代替固定的 720，方便适配机型。
struct DeckView: View {
    let days: [(day: Date, items: [Transaction])]
    @Binding var index: Int

    @GestureState private var dragX: CGFloat = 0

    private static let rotations: [Double] = [-1.0, 0.9, -1.3]
    private static let offsets: [CGFloat] = [-5, 4, -4]
    private static let swipeThreshold: CGFloat = 90

    /// 卡片左右内距。规格写的是 16（按 390pt 设计稿量的），
    /// 但真机是 402~440pt 宽，16pt 的占比变小、看着像贴边，端侧先放 20。
    /// 已登记到 `首页规格冻结-v1.0.md` 第七节的端侧可调项。
    private static let sideInset: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let visible = min(max(days.count - 1, 0), 3)
            let frontBottom = max(34, 8 + CGFloat(10 * visible)) - 8
            let cardHeight = max(proxy.size.height - frontBottom, 220)

            ZStack(alignment: .bottom) {
                // 从最深的往后画，保证前卡盖在上面
                ForEach(Array(stride(from: visible, through: 0, by: -1)), id: \.self) { depth in
                    card(depth: depth, cardHeight: cardHeight, frontBottom: frontBottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: index)
            .gesture(swipe)
        }
    }

    @ViewBuilder
    private func card(depth: Int, cardHeight: CGFloat, frontBottom: CGFloat) -> some View {
        let dayIndex = index + depth
        if dayIndex >= 0, dayIndex < days.count {
            let entry = days[dayIndex]
            if depth == 0 {
                DayCardView(
                    day: entry.day,
                    items: entry.items,
                    isToday: Calendar.current.isDateInToday(entry.day)
                )
                .frame(height: cardHeight)
                .padding(.horizontal, DeckView.sideInset)
                .padding(.bottom, frontBottom)
                .offset(x: dragX)
                .rotationEffect(.degrees(Double(dragX / 110)), anchor: .bottom)
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
                .zIndex(10)
            } else {
                sheet
                    .frame(height: cardHeight)
                    .padding(.horizontal, DeckView.sideInset)
                    .padding(.bottom, frontBottom - CGFloat(10 * depth))
                    .offset(x: Self.offsets[(depth - 1) % Self.offsets.count])
                    .rotationEffect(
                        .degrees(Self.rotations[(depth - 1) % Self.rotations.count]),
                        anchor: .bottom
                    )
                    .zIndex(Double(10 - depth))
            }
        }
    }

    /// 后层只画纸边，不渲染内容（规格 3.4）。
    private var sheet: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.11), lineWidth: 1)
            )
            .shadow(color: Palette.ink.opacity(0.06), radius: 4, x: 0, y: 4)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragX) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -Self.swipeThreshold, index < max(days.count - 1, 0) {
                    index += 1          // 左滑：看更早
                } else if value.translation.width > Self.swipeThreshold, index > 0 {
                    index -= 1          // 右滑：回到更近
                }
            }
    }
}
