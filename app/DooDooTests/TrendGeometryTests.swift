import Foundation
import Testing
import SwiftUI

@testable import DooDoo

/// 走势折线几何的门禁（`TrendGeometry`）。
///
/// 这个文件存在的理由：2026-11-16 之前资产页与详情页是**两套画法**
/// （资产页逐点 `addLine`、1.6pt、贴边；详情页平滑、1.8pt、6pt 内距）。
/// 用户裁定统一后，两条线共用一份几何——这里的断言就是"别又分叉"的保险。
@Suite("TrendGeometry")
struct TrendGeometryTests {
    private let size = CGSize(width: 320, height: 56)

    @Test("左右内距各 6pt：首尾点不压容器边界")
    func respectsHorizontalInset() {
        let points = TrendGeometry.positions([1, 2, 3], in: size)
        #expect(points.count == 3)
        #expect(points[0].x == 6)
        #expect(points[2].x == size.width - 6)
        // 等距：中间点正好在中间。
        #expect(abs(points[1].x - size.width / 2) < 0.001)
    }

    @Test("上下内距各 8pt：最高点与最低点都在可用区内")
    func respectsVerticalInset() {
        let points = TrendGeometry.positions([0, 100], in: size)
        // 最大值在上（y 小），最小值在下（y 大）。
        #expect(points[0].y == size.height - 8)
        #expect(points[1].y == 8)
    }

    @Test("全平数据垂直居中，既不许贴底也不许贴顶")
    func flatSeriesIsCentered() {
        // 旧资产页实现是 0.5（居中）、旧详情页是 0（贴底），两页曾不一致。
        for value in [0, 1_000, -2_500] {
            let v = CGFloat(value)
            let points = TrendGeometry.positions([v, v], in: size)
            #expect(points[0].y == size.height / 2)
            #expect(points[1].y == size.height / 2)
        }
    }

    @Test("点数不足两个不出图，也不崩")
    func degenerateInput() {
        #expect(TrendGeometry.positions([], in: size).isEmpty)
        #expect(TrendGeometry.positions([42], in: size).isEmpty)
    }

    @Test("平滑曲线必须穿过每个数据点：终点等于最后一个点")
    func smoothPathEndsOnLastPoint() {
        let points = TrendGeometry.positions([10, 40, 25, 60], in: size)
        let path = TrendGeometry.smoothPath(points)
        let end = path.currentPoint ?? .zero
        #expect(abs(end.x - points[3].x) < 0.001)
        #expect(abs(end.y - points[3].y) < 0.001)
    }

    @Test("面积路径闭合到容器底边，容得下渐变填充")
    func areaPathClosesToBottom() {
        let points = TrendGeometry.positions([10, 40, 25], in: size)
        let area = TrendGeometry.areaPath(points, height: size.height)
        let bounds = area.boundingRect
        #expect(abs(bounds.maxY - size.height) < 0.001)
        // 面积不能比曲线更宽：左边界就是首点 x。
        #expect(abs(bounds.minX - points[0].x) < 0.001)
    }

    @Test("单调上升的序列，y 必须单调下降（屏幕坐标）")
    func monotonicDirection() {
        let points = TrendGeometry.positions([1, 2, 3, 4, 5], in: size)
        for i in 1..<points.count {
            #expect(points[i].y < points[i - 1].y)
        }
    }
}
