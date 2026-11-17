import SwiftUI

/// 资产页顶部总览卡（规格 2.2）：我有 / 我欠 + 56pt 双折线 + 5 段区间。
///
/// 走势是「形状」不是「读数」——不放网格、坐标轴、刻度、图例、说明文案。
///
/// 2026-11-16：画法向账户详情页看齐（用户裁定"两页要是一种画法"）——
/// 高度 44 → 56pt（规格 2.2 未锁定行预先授权"加粗或拉高到 56"），
/// 折线由硬拐角改为 `TrendGeometry` 的平滑曲线，左右各留 6pt 内距、
/// 底部加 1pt 基线、每条线末尾一个双圈末点。**面积填充不加**：
/// 两条半透明面相交会糊成一块脏色，且会暗示"我有比我欠重要"。
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
                column(title: "我有", dot: Palette.mineDot, value: mine, delta: mineDelta, tone: Palette.mine)
                column(title: "我欠", dot: Palette.oweDot, value: owe, delta: oweDelta, tone: Palette.owe)
            }

            chart
                .frame(height: 56)
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

    private func column(title: String, dot: Color, value: Decimal, delta: Decimal?, tone: Color) -> some View {
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
                // D 方案：数字直接着色 —— 绿 = 我的钱，红 = 欠的钱。
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // 涨跌**保留颜色**（2026-11-18 用户纠正）：它本身是一处颜色来源，
            // 不该被"去色"。涨红跌绿沿用数据红绿，与主体数字同源。
            Text(AccountDelta.text(delta))
                .font(.system(size: 11))
                .foregroundStyle(color(for: AccountDelta.classify(delta)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let minePoints = TrendGeometry.positions(points.map { $0.mine.trendValue }, in: size)
            let owePoints = TrendGeometry.positions(points.map { $0.owe.trendValue }, in: size)

            ZStack(alignment: .bottom) {
                // 基线：1pt、墨色 12%，与详情页同一条"地面"。
                Rectangle()
                    .fill(Palette.ink.opacity(0.12))
                    .frame(height: 1)

                TrendGeometry.smoothPath(minePoints)
                    .stroke(Palette.mine, style: TrendGeometry.strokeStyle)

                TrendGeometry.smoothPath(owePoints)
                    .stroke(Palette.owe, style: TrendGeometry.strokeStyle)

                // 末点落在两条线各自的最后一个值上，颜色跟线走，一眼看到「现在在哪」。
                if let last = minePoints.last {
                    TrendGeometry.endpoint(at: last, color: Palette.mine, bed: Palette.card)
                }
                if let last = owePoints.last {
                    TrendGeometry.endpoint(at: last, color: Palette.owe, bed: Palette.card)
                }
            }
        }
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
