import SwiftUI

/// 资产页顶部总览卡（规格 2.2）：我有 / 我欠 + 44pt 双折线 + 5 段区间。
///
/// 走势是「形状」不是「读数」——不放网格、坐标轴、刻度、图例、末端红点。
struct NetWorthCard: View {
    let mine: Decimal
    let owe: Decimal
    let mineDelta: Decimal?
    let oweDelta: Decimal?
    let points: [NetWorthPoint]
    @Binding var range: NetWorthRange

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                column(title: "我有", dot: Palette.mineDot, value: mine, delta: mineDelta)
                column(title: "我欠", dot: Palette.oweDot, value: owe, delta: oweDelta)
            }

            chart
                .frame(height: 44)
                .padding(.top, 8)

            ranges
                .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 8, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.05), radius: 11, x: 0, y: 8)
        )
    }

    private func column(title: String, dot: Color, value: Decimal, delta: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(Palette.sub)
            }
            Text(MoneyMath.money(value))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(AccountDelta.text(delta))
                .font(.system(size: 11))
                .foregroundStyle(color(for: AccountDelta.classify(delta)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                line(values: points.map(\.mine), size: size, color: Palette.mine)
                line(values: points.map(\.owe), size: size, color: Palette.owe)
            }
        }
    }

    private func line(values: [Decimal], size: CGSize, color: Color) -> some View {
        let doubles = values.map { NSDecimalNumber(decimal: $0).doubleValue }
        let minValue = doubles.min() ?? 0
        let maxValue = doubles.max() ?? 0
        let span = maxValue - minValue

        return Path { path in
            guard doubles.count > 1 else { return }
            for (index, value) in doubles.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(doubles.count - 1)
                let ratio = span == 0 ? 0.5 : (value - minValue) / span
                let y = size.height * (1 - CGFloat(ratio))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private var ranges: some View {
        HStack(spacing: 4) {
            ForEach(NetWorthRange.allCases) { item in
                Button {
                    range = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: range == item ? .semibold : .regular))
                        .foregroundStyle(range == item ? Palette.ink : Palette.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(range == item ? Palette.pillOn : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("区间 \(item.title)")
                .accessibilityAddTraits(range == item ? [.isSelected] : [])
            }
        }
    }

    private func color(for delta: DeltaClass) -> Color {
        switch delta {
        case .up: Palette.expense     // 涨：红
        case .down: Palette.income    // 跌：绿
        case .flat: Palette.sub
        }
    }
}
