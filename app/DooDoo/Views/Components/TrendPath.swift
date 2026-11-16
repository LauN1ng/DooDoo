import SwiftUI

/// 走势折线的**唯一**几何实现。
///
/// 2026-11-16 用户裁定「资产页与详情页是两种画法，要统一成详情页那种」。
/// 统一不能靠两边各抄一遍——抄完下次改又会分叉。所以点位换算、Catmull-Rom 平滑、
/// 面积路径全部收在这里，`NetWorthCard`（资产页顶部双线）与 `DebtTrendChart`
/// （详情页单线）都只调这里。**改画法只改这一个文件。**
///
/// 共同参数（即"详情页那套"）：
/// - 线 **1.8pt**、圆头圆角；
/// - 左右 6pt / 上下 8pt 内距，线端点不压容器边界；
/// - Catmull-Rom 转三次贝塞尔的**平滑曲线**（tension 0.18）；
/// - 全平数据落在**垂直居中**，不贴底也不贴顶。
enum TrendGeometry {
    /// 平滑系数。越大越弯，0 等于折线；0.18 是"看得出是曲线、又不会飞出数据范围"的值。
    static let tension: CGFloat = 0.18

    /// 线宽。两页共用，别再各写 1.6 / 1.8。
    static let lineWidth: CGFloat = 1.8

    /// 折线统一的描边样式。
    static var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    /// 把一列数值摊成点位（整数索引等距，不按日期加权）。
    ///
    /// - 每条序列**各自**按自身 min/max 归一到满高：走势图看的是"形状"，
    ///   小波动也要看得出方向，所以资产页的「我有 / 我欠」两条线不共用纵轴。
    /// - 全平（max == min）时所有点落 0.5，即垂直居中。
    static func positions(
        _ values: [CGFloat],
        in size: CGSize,
        horizontalInset: CGFloat = 6,
        verticalInset: CGFloat = 8
    ) -> [CGPoint] {
        guard values.count > 1 else { return [] }

        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let isFlat = maxValue == minValue
        let span = isFlat ? 1 : (maxValue - minValue)

        let usableHeight = max(size.height - verticalInset * 2, 0)
        let usableWidth = max(size.width - horizontalInset * 2, 0)
        let step = usableWidth / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let ratio = isFlat ? 0.5 : (value - minValue) / span
            return CGPoint(
                x: horizontalInset + step * CGFloat(index),
                y: verticalInset + usableHeight * (1 - ratio)
            )
        }
    }

    /// Catmull-Rom 转三次贝塞尔。首尾用端点自身作虚拟邻居，曲线不会在两端甩出去。
    static func smoothPath(_ positions: [CGPoint], tension: CGFloat = TrendGeometry.tension) -> Path {
        var path = Path()
        guard positions.count > 1 else { return path }

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

    /// 曲线 + 落到容器底边的闭合路径，用于面积渐变。
    static func areaPath(_ positions: [CGPoint], height: CGFloat) -> Path {
        var path = smoothPath(positions)
        guard let first = positions.first, let last = positions.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }

    /// 末点：白底圈 + 同色实心内点。让人一眼看到「现在在哪」。
    static func endpoint(at point: CGPoint, color: Color, bed: Color) -> some View {
        Circle()
            .fill(bed)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 1))
            .overlay(
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
            )
            .position(point)
            .shadow(color: color.opacity(0.18), radius: 3, x: 0, y: 1)
    }
}

extension Decimal {
    /// 折线换算用的 CGFloat。
    var trendValue: CGFloat { CGFloat(truncating: self as NSDecimalNumber) }
}
