import SwiftUI

/// 资产页的一组：组头（名称 + N 个 · 合计 + ＋）+ 卡堆 + 右侧汇总 + 卡堆下方一行。
///
/// 几何照 `资产页规格冻结-v1.0.md` 2.3 / 2.4 / 2.5。
struct AccountGroupView: View {
    let title: String
    let totalLabel: String
    let accounts: [Account]
    /// 单位：元，已带正负（欠款为负）。
    let total: Decimal
    let isLiability: Bool
    /// 明细行，为空时不占位（M2a 还没有「本月要还」的数据）。
    let detail: String?
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
            Text("\(accounts.count) 个 · \(MoneyMath.money(total))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
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
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isLiability ? Palette.expense : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.sub)
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
