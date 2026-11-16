import SwiftUI

/// 欠款走势图（`账户详情页规格冻结-v1.0.md` 第四节）。
///
/// 几何按规格：高 118pt、通栏、线 1.8pt、面积墨色 8.5% → 0% 渐变、
/// 末点白底空心描边 1.8pt。**逾期红点没做**——它要求「逾期起点」这个日期，
/// 而曲线是流水口径、账单不在曲线上，红点会落在一条没有账单信息的线上，
/// 容易误读。等账单与流水口径合并后再补。
///
/// 2026-11-16 精致化（用户反馈「折线不够精致」）：
/// - 折线改 **Catmull-Rom 平滑**：原来逐点 `addLine`，首尾相接处是硬拐角，
///   数据点少时像一条斜杠；
/// - 左右各留 6pt 内距，线不再直接磕到卡片边缘；
/// - 底部加 1pt 基线，让曲线有一条"地面"可以落；
/// - 末点改成双圈（白底 + 主色内点），比原来的空心环更容易看见端点在哪。
struct DebtTrendChart: View {
    let points: [DebtTrendPoint]

    /// 上下各留一点余量，线不要贴边。
    private let verticalInset: CGFloat = 8
    /// 左右内距：线端点不要压到容器边界。
    private let horizontalInset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let positions = layout(in: geo.size)
            ZStack(alignment: .bottom) {
                areaPath(positions, height: geo.size.height)
                    .fill(
                        LinearGradient(
                            colors: [Palette.ink.opacity(0.085), Palette.ink.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 基线：1pt、只到 12% 透明，够读出"零"在哪，不抢曲线的视线。
                Rectangle()
                    .fill(Palette.ink.opacity(0.12))
                    .frame(height: 1)

                linePath(positions)
                    .stroke(
                        Palette.ink,
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )

                if let last = positions.last {
                    Circle()
                        .fill(Palette.card)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Palette.ink.opacity(0.18), lineWidth: 1))
                        .overlay(
                            Circle()
                                .fill(Palette.ink)
                                .frame(width: 4.5, height: 4.5)
                        )
                        .position(last)
                        .shadow(color: Palette.ink.opacity(0.12), radius: 3, x: 0, y: 1)
                }
            }
        }
        .frame(height: 118)
    }

    // MARK: - 几何

    private func layout(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else { return [] }

        let debts = points.map { CGFloat(truncating: $0.debt as NSDecimalNumber) }
        let maxDebt = debts.max() ?? 0
        let minDebt = debts.min() ?? 0
        // 全平的一条线（都欠一样多）时，给一个 1 元的最小跨度，避免除零。
        let span = max(maxDebt - minDebt, 1)

        let usableHeight = size.height - verticalInset * 2
        let usableWidth = size.width - horizontalInset * 2
        let step = usableWidth / CGFloat(points.count - 1)

        return points.enumerated().map { index, point in
            let value = CGFloat(truncating: point.debt as NSDecimalNumber)
            let ratio = (value - minDebt) / span
            let y = verticalInset + usableHeight * (1 - ratio)
            let x = horizontalInset + step * CGFloat(index)
            return CGPoint(x: x, y: y)
        }
    }

    /// Catmull-Rom 转三次贝塞尔。`tension` 越大越弯，0 等于折线；
    /// 0.18 是"看得出是曲线、又不会飞出数据范围"的常用值。
    private func linePath(_ positions: [CGPoint]) -> Path {
        var path = Path()
        guard positions.count > 1 else { return path }

        let tension: CGFloat = 0.18
        path.move(to: positions[0])

        for i in 0..<(positions.count - 1) {
            let p0 = positions[max(i - 1, 0)]
            let p1 = positions[i]
            let p2 = positions[i + 1]
            let p3 = positions[min(i + 2, positions.count - 1)]

            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension,
                y: p1.y + (p2.y - p0.y) * tension
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension,
                y: p2.y - (p3.y - p1.y) * tension
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func areaPath(_ positions: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(positions)
        guard let first = positions.first, let last = positions.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}
