import SwiftUI

/// 资产页的一组：组头（名称 + ＋）+ 卡堆 + 右侧汇总 + 卡堆下方一行。
///
/// 几何照 `资产页规格冻结-v1.0.md` 2.3 / 2.4 / 2.5。
/// 组头不放账户数量：卡堆右下角的胶囊徽章已经显示，重复。
struct AccountGroupView: View {
    let title: String
    let totalLabel: String
    let accounts: [Account]
    /// 单位：元，已带正负（欠款为负）。
    let total: Decimal
    let isLiability: Bool
    /// 明细行，为空时不占位。目前只有信用组会传「本月要还」（规格 2.4）。
    /// 逾期那段单独放在 `overdueText` 里，由这里拼成红字。
    let detail: DueLine?
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 13) {
                AccountDeck(accounts: accounts, onTap: onOpen)
                summary
            }
            .padding(.horizontal, 4)

            foot
                .padding(.top, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            // 2026-11-16 用户第二次点名：组名旁边什么副标都不要。
            // 先删了「3 个 · -23,623.69」里的金额（与右侧「欠款合计」重复），
            // 再删「3 个」本身——卡堆右下角已有 count 胶囊徽章，同一屏说两遍。
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.tabBed))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增\(title)账户")
        }
        .padding(.horizontal, 4)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(totalLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.sub)
            Text(MoneyMath.money(total))
                // 22 → 20：组头是"这组多少"，比总览低一档。
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                // 2026-11-18 修 P15：原先资产组用 ink，而顶部「我有」用绿——
                // 同一个 5,968.84 在同一屏是两种颜色。现在两处同源：
                // 欠的钱红、我的钱绿。
                .foregroundStyle(isLiability ? Palette.expense : Palette.mine)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let detail {
                // 两个 Text 相加才能让逾期那一段单独标红——不做横幅之后，
                // 9.5pt 单行里这一抹红是逾期在资产页上唯一的可见位置。
                (Text(detail.text).foregroundStyle(Palette.sub)
                    + Text(detail.overdueText ?? "").foregroundStyle(Palette.expense))
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var foot: some View {
        Button(action: onOpen) {
            HStack {
                Text("点开看全部")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.sub)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
