import SwiftUI

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

    private var expenseTotal: Decimal {
        DayMath.expenseTotal(items.map {
            TxFigure(kind: $0.kind, amount: $0.amount, date: $0.date, fee: $0.fee)
        })
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
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.months[max((components.month ?? 1) - 1, 0)])
                    .font(.system(size: 11))
                    .tracking(0.9)
                    .foregroundStyle(Palette.sub)

                Text(String(format: "%02d", components.day ?? 1))
                    .font(.system(size: 32, weight: .semibold))
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
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.expense)
                }
            }
        }
    }

    /// 记账行（B2 空分类位）：42 空槽 + 「记一笔」，与流水行同构。
    ///
    /// 每张日卡都带这一行——翻到 11/6 点它，记的就是 11/6 的账（补记历史日）。
    private var addRow: some View {
        Button { onAdd(day) } label: {
            HStack(spacing: 12) {
                Text("＋")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.sub)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Palette.pillOn)
                    )

                Text("记一笔")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink2)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("记一笔")
    }

    private var dayLabel: String {
        if isToday { return "今天" }
        let weekday = components.weekday ?? 1
        return Self.weekdays[max(min(weekday - 1, 6), 0)]
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Text("没花钱的一天 :)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.faint)
                Text("左滑可以看更早的")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        TxRowView(transaction: item)
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
