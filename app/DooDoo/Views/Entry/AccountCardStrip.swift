import SwiftUI
import SwiftData

/// 记一笔的账户横滑卡组。
///
/// 两档尺寸（记一笔规格冻结 v1.0 第三节）：
/// - 大卡 158×100 圆角 16：支出 / 收入的账户、还款的被还卡、转账的双卡
/// - 小卡 112×72 圆角 13：还款的扣款卡
///
/// 选中态 = 2pt 主色描边 + 外发光（2026-11-16 从墨色描边改），未选中 = 82% 不透明 + 缩到 0.96。
struct AccountCardStrip: View {
    let accounts: [Account]
    @Binding var selection: Account?
    var compact: Bool = false

    @Query private var settingsList: [AppSettings]

    private var accentStyle: AccentStyle { settingsList.first?.accent ?? .green }

    private var size: CardFace.Size { compact ? .entryCompact : .entry }
    private var radius: CGFloat { compact ? 13 : 16 }
    private var spacing: CGFloat { compact ? 9 : 10 }
    private var sideInset: CGFloat { compact ? 14 : 16 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(accounts) { account in
                    card(account)
                }
            }
            .padding(.horizontal, sideInset)
            .padding(.vertical, 2)
        }
    }

    private func card(_ account: Account) -> some View {
        let selected = isSelected(account)
        return CardFace(account: account, size: size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // 2026-11-16：选中不再压 2pt 墨色描边（用户反馈"黑色太多"），
                    // 改成主色描边 + 轻微外发光；未选中由 0.66 提到 0.82，
                    // 免得整排卡都像被禁用。
                    .strokeBorder(selected ? Palette.accent(accentStyle) : Palette.ink.opacity(0.06),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: selected ? Palette.accent(accentStyle).opacity(0.22) : .clear,
                    radius: 8, x: 0, y: 4)
            .opacity(selected ? 1 : 0.82)
            .scaleEffect(selected ? 1 : 0.96)
            .animation(.easeOut(duration: 0.18), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { selection = account }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel(account.displayShortName)
    }

    private func isSelected(_ account: Account) -> Bool {
        selection?.persistentModelID == account.persistentModelID
    }
}
