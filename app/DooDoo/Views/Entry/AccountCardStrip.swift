import SwiftUI
import SwiftData

/// 记一笔的账户横滑卡组。
///
/// 两档尺寸（记一笔规格冻结 v1.0 第三节）：
/// - 大卡 158×100 圆角 16：支出 / 收入的账户、还款的被还卡、转账的双卡
/// - 小卡 112×72 圆角 13：还款的扣款卡
///
/// 选中态 = **亮度 + 前后层次**（2026-11-16 第二次改，见 `m4-selection-2026-11-16.html`）。
///
/// 为什么不和分类选择器共用「放大 + 散射」：卡面自己就是品牌色，再叠一层彩光只会显脏；
/// 而且这一排是**同一个东西的不同张**（都是卡），靠「谁站在前面」表达选中，
/// 比靠「谁亮起来」更符合实物。所以这里一个彩色都不用：
/// - 未选：`colorMultiply(0.90)` 压暗 + 缩到 0.94 + 下沉 3pt（压回堆里）；
/// - 选中：原亮度 + 放大 1.04 + `0 10 18 .22` 投影（站到前面）。
///
/// 不用描边：卡面自带 0.5pt 白色高光边（`CardFace` 第一层），再加一圈线会和它打架。
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
            .colorMultiply(selected ? .white : Color(white: 0.90))
            .scaleEffect(selected ? 1.04 : 0.94)
            .offset(y: selected ? 0 : 3)
            .shadow(
                color: .black.opacity(selected ? 0.22 : 0.06),
                radius: selected ? 18 : 6,
                x: 0,
                y: selected ? 10 : 2
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { selection = account }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel(account.displayShortName)
    }

    private func isSelected(_ account: Account) -> Bool {
        selection?.persistentModelID == account.persistentModelID
    }
}
