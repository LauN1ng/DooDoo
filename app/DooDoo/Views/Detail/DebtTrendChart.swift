import SwiftUI

/// 欠款走势图（`账户详情页规格冻结-v1.0.md` 第四节）。
///
/// 几何按规格：高 118pt、通栏、线 1.8pt、面积墨色 8.5% → 0% 渐变、
/// 末点白底双圈。**逾期红点没做**——它要求「逾期起点」这个日期，
/// 而曲线是流水口径、账单不在曲线上，红点会落在一条没有账单信息的线上，
/// 容易误读。等账单与流水口径合并后再补。
///
/// 2026-11-16 精致化（用户反馈「折线不够精致」）：
/// - 折线改 Catmull-Rom 平滑，硬拐角消失；
/// - 左右各留 6pt 内距，线不再直接磕到卡片边缘；
/// - 底部加 1pt 基线，让曲线有一条"地面"可以落；
/// - 末点改成双圈（白底 + 主色内点）。
///
/// 2026-11-16 再改：点位换算与平滑**搬到 `TrendGeometry`**，资产页顶部双线
/// 与这里共用同一套（用户裁定"两页要是一种画法"）。本文件只剩"单线 + 面积 + 图注"
/// 这件详情页独有的事。
struct DebtTrendChart: View {
    let points: [DebtTrendPoint]
    /// 线 / 面积 / 末点的主色。**由账户类型决定**：储蓄与现金走绿（我有），
    /// 信用与借款走红（我欠）。2026-11-18 起不再用墨色——用户定案「折线不是黑的」。
    var tone: Color = Palette.ink

    var body: some View {
        GeometryReader { geo in
            let positions = TrendGeometry.positions(
                points.map { $0.debt.trendValue },
                in: geo.size
            )
            ZStack(alignment: .bottom) {
                TrendGeometry.areaPath(positions, height: geo.size.height)
                    .fill(
                        LinearGradient(
                            colors: [tone.opacity(0.10), tone.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 基线：1pt、只到 12% 透明，够读出"零"在哪，不抢曲线的视线。
                Rectangle()
                    .fill(Palette.ink.opacity(0.12))
                    .frame(height: 1)

                TrendGeometry.smoothPath(positions)
                    .stroke(tone, style: TrendGeometry.strokeStyle)

                if let last = positions.last {
                    TrendGeometry.endpoint(at: last, color: tone, bed: Palette.card)
                }
            }
        }
        .frame(height: 118)
    }
}
