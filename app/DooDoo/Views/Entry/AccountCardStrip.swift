import SwiftUI

/// 记一笔的账户横滑卡组。
///
/// 两档尺寸（记一笔规格冻结 v1.0 第三节）：
/// - 大卡 158×100 圆角 16：支出 / 收入的账户、还款的被还卡、转账的双卡
/// - 小卡 112×72 圆角 13：还款的扣款卡
///
/// 选中态 = 2pt 墨色描边 + 不透明；未选中 = 66% 不透明 + 缩到 0.95。
struct AccountCardStrip: View {
    let accounts: [Account]
    @Binding var selection: Account?
    var compact: Bool = false

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
                    .strokeBorder(selected ? Palette.ink : .clear, lineWidth: 2)
            )
            .opacity(selected ? 1 : 0.66)
            .scaleEffect(selected ? 1 : 0.95)
            .animation(.easeOut(duration: 0.15), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { selection = account }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel(account.displayShortName)
    }

    private func isSelected(_ account: Account) -> Bool {
        selection?.persistentModelID == account.persistentModelID
    }
}
