import SwiftUI
import UIKit

/// 一天的日卡。尺寸与字号取自 `home-v1.0.html` 快照：
/// 圆角 24、内距 20/18/16、日期 32pt、行 42×42 + 14pt/11.5pt。
///
/// M1 **不画记账行**（记一笔页面还没设计），所以卡内底部只留 16pt。
struct DayCardView: View {
    let day: Date
    let items: [Transaction]
    let isToday: Bool

    /// 点记账行时的动作，参数为这张卡代表的那一天。默认空实现，方便预览与单测。
    var onAdd: (Date) -> Void = { _ in }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    private var components: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .weekday], from: day)
    }

    /// 支出合计。仍按**全部流水**算（含手续费那条 `.expense`）：
    /// 手续费只是不单独占一行，钱还是花掉了，计入口径不能变（PRD 9.8）。
    private var expenseTotal: Decimal {
        DayMath.expenseTotal(items.map {
            TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee)
        })
    }

    /// 显示行：转账与它的手续费合成一行（`Math/TxRollup.swift`）。
    /// 头部数字与每行那枚「手续费 0.10」标签因此仍然对得上——#13 的可核对性没丢。
    private var rows: [TxRollup.Row<Transaction>] {
        TxRollup.rows(items, kindOf: { $0.kind }, groupOf: { $0.groupID })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)
                .padding(.top, 14)
                .padding(.bottom, 2)
            content
            addRow
        }
        .padding(EdgeInsets(top: 20, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    // **纸的边**（2026-11-17 第三次真机反馈）：落地影改成只从腰部往下以后，
                    // 卡顶与左右上角不再有影子托着；白卡压暖白底只有 1.04:1 的亮度差，
                    // 没有这条线轮廓就发虚。用 `Palette.line`（#ECE7DE）而不是 ink 透明度——
                    // 它是暖调的纸边、与页底同族，不会在卡顶画出一个框。
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.months[max((components.month ?? 1) - 1, 0)])
                    .font(.system(size: 11))
                    .tracking(0.9)
                    .foregroundStyle(Palette.sub)

                // 2026-11-18 权重归位：日期 32 → 22。
                // 真机实测日期字高 24pt、今日支出只有 12.3pt（16pt）——
                // 一个记账 App 里「几号」的字号是「今天花了多少钱」的两倍。
                Text(String(format: "%02d", components.day ?? 1))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()

                Text(dayLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }

            Spacer(minLength: 8)

            if expenseTotal > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("支出")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.sub)
                    Text("−¥" + MoneyMath.money(expenseTotal))
                        // 16 → 22：与日期同档。首页是门面，钱不能是全 App 最小的字。
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.expense)
                }
            }
        }
    }

    /// 记账行（B2 空分类位）：卡**内部**的行内按钮。
    ///
    /// 2026-11-16：去掉过 42pt 浅色方块，理由是有内容的那一行是「贴纸落在纸上」，
    /// 空位画灰底就成了「纸上贴一张纸」。
    /// **2026-11-18 修正**：真机实测这一行是白底 90.2%、非白仅 2.5%、上下边缘无描边——
    /// 也就是**根本不像能点**，是整屏唯一动作却最没有示能。
    ///
    /// 这里推翻 11-16 那条"纸上贴纸"的顾虑：当时担心的是 42pt 小方块像"一张小纸"，
    /// 而现在做的是一条**整宽的浅纸轨**（`paperInset`），它读作卡片底部的操作条，
    /// 不是第二张纸——iOS 列表里的 "Add row" 就是这个形态。
    /// 示能优先于材质洁癖：这条是整屏唯一的动作，用户必须先看见它。
    private var addRow: some View {
        Button { onAdd(day) } label: {
            HStack(spacing: 10) {
                Text("＋")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 42, height: 42)

                Text("记一笔")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 14)
            .paperInsetButton(cornerRadius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel("记一笔")
    }

    /// 空态（2026-11-18 用户「首页没有流水看着太空」）。
    ///
    /// 原先只有两行 11.5 / 13.5pt 灰字居中、撑满整张卡——而卡高由 `DeckView` 的
    /// `proxy.height - frontBottom` 决定（真机实测 ≈ 703.7pt），于是上下各空出约 280pt，
    /// 空态读起来像「一张没印东西的白纸」。
    ///
    /// 现在给空态一枚 3D emoji 当视觉重心（`Resources/Emoji/Cat.png`，卷毛猫——
    /// 品牌资产此前全 App 出现 0 次），主句升到 15.5pt semibold，副句解释"空"的含义，
    /// 底部留一条手势提示。emoji / 墨字 / 浅纸按钮三种材质各占一段，
    /// 剩下的留白才是呼吸，而不是空白。
    ///
    /// 顺手修了一处方向错误：原文案是「左滑可以看更早的」，而 `DeckView` 的手势是
    /// **右滑 = 翻到更早**、左滑 = 回今天。
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            if let cat = UIImage(named: "Cat") {
                Image(uiImage: cat)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
            }

            Text("没花钱的一天")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Palette.ink2)

            Text("这天没有支出，也没有收入")
                .font(.system(size: 12))
                .foregroundStyle(Palette.faint)
                .padding(.top, 5)

            // 手势提示跟这组内容一起居中，不钉在卡底。
            // 钉在底部会让"内容—提示"之间出现一段无意义的大空白，等于换了个地方继续空。
            Text("右滑可以看更早的日子")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faint)
                .padding(.top, 22)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dayLabel: String {
        if isToday { return "今天" }
        let weekday = components.weekday ?? 1
        return Self.weekdays[max(min(weekday - 1, 6), 0)]
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            // 先算一次行合并，别在 ForEach 里反复走 O(n)。
            let rows = self.rows
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        TxRowView(transaction: rows[index].primary, fees: rows[index].fees)
                    }
                }
            }
            // 底部 34pt 渐隐：最后一行不要被卡片圆角"切一刀"，同时暗示可继续滚
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
