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
/// - 选中：原亮度 + 放大 1.04 + **双层落地影**（贴地 + 环境，两个都只向下，见 `CardDropShadow`）。
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
        // 落地影画在卡片的 `background` 里，向下要 11 + 14 ≈ 25pt 空间，
        // 而这里垂直内距只有 2pt——不放开裁剪，影子会被滚出视图的边界切掉。
        // `CategoryPicker` 的一级行早就有这行。
        .scrollClipDisabled()
    }

    private func card(_ account: Account) -> some View {
        let selected = isSelected(account)
        return CardFace(account: account, size: size)
            .colorMultiply(selected ? .white : Color(white: 0.90))
            .scaleEffect(selected ? 1.04 : 0.94)
            .offset(y: selected ? 0 : 3)
            // **两层落地影，都只向下**（2026-11-17 第三次反馈后从 `.shadow` 换成 `CardDropShadow`）。
            //
            // 为什么放弃 `.shadow`：它是各向同性模糊，半径多大就朝左右各铺多大，
            // 跟 `y` 偏移毫无关系。上一版 `0 15 14` 靠「偏移 > 半径」压住了顶边，
            // 但左右两侧照样各渗 14pt——暖白底上就是两条纵向灰雾，连看三轮。
            // 参数怎么调都只会「灰雾淡一点」，不会消失，所以换机制：
            // 影子做成卡片背后一块比卡片窄的形状、只保留下半段再 blur，
            // 卡片上半部两侧**一个像素的影子都没有**，影子只从腰部往下落。
            //
            // 卡面自带 0.5pt 白色高光边，轮廓不靠影子定义，所以这里敢把上半段清空。
            //
            // 两层分工不变：**贴地那层小而硬**勾出「卡片离开纸面」这条线；
            // **环境层大而软**负责距离感。后加的那层画在更下面，所以先贴地、后环境。
            .modifier(CardDropShadow(
                inset: 4,
                top: 0.80,
                blur: 3,
                drop: 3,
                opacity: selected ? 0.16 : 0,
                cornerRadius: radius
            ))
            .modifier(CardDropShadow(
                inset: selected ? 9 : 7,
                top: selected ? 0.46 : 0.60,
                blur: selected ? 14 : 6,
                drop: selected ? 11 : 3,
                opacity: selected ? 0.13 : 0.05,
                cornerRadius: radius
            ))
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
