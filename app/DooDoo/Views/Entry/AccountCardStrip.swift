import SwiftUI
import SwiftData

/// 记一笔的账户横滑卡组。
///
/// 两档尺寸（记一笔规格冻结 v1.0 第三节）：
/// - 大卡 158×100 圆角 16：支出 / 收入的账户、还款的被还卡、转账的双卡
/// - 小卡 112×72 圆角 13：还款的扣款卡
///
/// 选中态 = **亮度 + 前后层次**（2026-11-16 第三次改，见 `entry-shadow-dash-2026-11-16.html`）。
///
/// 为什么不和分类选择器共用「放大 + 散射」：卡面自己就是品牌色，再叠一层彩光只会显脏；
/// 而且这一排是**同一个东西的不同张**（都是卡），靠「谁站在前面」表达选中，
/// 比靠「谁亮起来」更符合实物。所以这里一个彩色都不用：
/// - 未选：`colorMultiply(0.90)` 压暗 + 缩到 0.94 + 下沉 3pt（压回堆里）；
/// - 选中：原亮度 + 放大 1.04 + **双层投影**（贴地 `0 2 3 .22` + 环境 `0 12 22 .13`）。
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
        // **必须放开裁剪**（2026-11-16 第五轮真机反馈）。
        // 选中卡的环境影是 `shadow(radius: 22, y: 12)`，向上要 10pt、向下要 34pt 空间，
        // 而这里垂直内距只有 2pt——上下两半影子全被滚出视图的边界切掉，
        // 只剩左右两侧那 16pt 内距里的部分活下来。用户看到的「阴影在左边」
        // 就是这条切边，不是阴影方向错了。`CategoryPicker` 的一级行早就有这行。
        .scrollClipDisabled()
    }

    private func card(_ account: Account) -> some View {
        let selected = isSelected(account)
        return CardFace(account: account, size: size)
            .colorMultiply(selected ? .white : Color(white: 0.90))
            .scaleEffect(selected ? 1.04 : 0.94)
            .offset(y: selected ? 0 : 3)
            // **两层影子，缺一层就浮不起来**（2026-11-16 第五轮真机反馈第 3 条：
            // 「要想浮起来重点是下面那层的阴影」）。
            //
            // 单层 `0 10 18 .22` 的问题实测过：从真机截图上量卡底边往下 1pt 处的亮度是 184
            // （底色 230），到 8pt 就淡到 213——**只有一团散开的雾，底边没有一条贴地的实影**。
            // 影子是从卡片「外扩」出去的，不是「落在下面的」，所以看着像印在纸上洇开，
            // 不像离地。
            //
            // 两层分工：贴地那层小而硬（半径 3、只算卡片轮廓本身），负责勾出
            // 「卡片边缘离开纸面」这条线；环境那层大而软（半径 22、偏移 12）负责距离感。
            // 同一个对比页量到：加贴地层后底边 1pt 处 199 → 164，底边立刻有了硬边。
            .shadow(
                color: .black.opacity(selected ? 0.22 : 0.03),
                radius: selected ? 3 : 2,
                x: 0,
                y: selected ? 2 : 1
            )
            .shadow(
                color: .black.opacity(selected ? 0.13 : 0.05),
                radius: selected ? 22 : 6,
                x: 0,
                y: selected ? 12 : 2
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
