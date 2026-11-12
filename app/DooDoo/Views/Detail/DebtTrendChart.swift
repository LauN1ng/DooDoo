import SwiftUI

/// 欠款走势图（`账户详情页规格冻结-v1.0.md` 第四节）。
///
/// 几何按规格：高 118pt、通栏、线 1.8pt、面积墨色 8.5% → 0% 渐变、
/// 末点白底空心描边 1.8pt。**逾期红点没做**——它要求「逾期起点」这个日期，
/// 而曲线是流水口径、账单不在曲线上，红点会落在一条没有账单信息的线上，
/// 容易误读。等账单与流水口径合并后再补。
struct DebtTrendChart: View {
    let points: [DebtTrendPoint]

    /// 上下各留一点余量，线不要贴边。
    private let verticalInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let positions = layout(in: geo.size)
            ZStack {
                areaPath(positions, height: geo.size.height)
                    .fill(
                        LinearGradient(
                            colors: [Palette.ink.opacity(0.085), Palette.ink.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(positions)
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                if let last = positions.last {
                    Circle()
                        .fill(Palette.card)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 1.8))
                        .position(last)
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
        let step = size.width / CGFloat(points.count - 1)

        return points.enumerated().map { index, point in
            let value = CGFloat(truncating: point.debt as NSDecimalNumber)
            let ratio = (value - minDebt) / span
            let y = verticalInset + usableHeight * (1 - ratio)
            let x = step * CGFloat(index)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ positions: [CGPoint]) -> Path {
        var path = Path()
        guard let first = positions.first else { return path }
        path.move(to: first)
        for point in positions.dropFirst() {
            path.addLine(to: point)
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
