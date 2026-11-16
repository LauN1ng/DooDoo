import SwiftUI
import UIKit

/// 分类选择：一级贴纸行 + 二级浮层（记一笔规格冻结 **v2.2** 第六节）。
///
/// 2026-11-16 第二次重画，四条改动：
/// 1. **一级去掉 52pt 色槽**，图标 32 → 36 直接落在纸面上，带 `0 1 1.5 .10` 微影
///    （贴纸要「放在纸上」，少了这层影就变成「印在纸上」的平面图标）。
///    槽宽 44 仍保留为布局框与命中区，只是不再绘制。
/// 2. **选中 = 抬起**：`scale 1.12` + 上移 2pt + 投影加重，另加一圈**弱档散射**
///    （图标主色径向光晕 `.28`，色表见 `CategoryGlow`）。不用描边、不用主色底。
/// 3. **选完二级后，一级行里被选中那一格直接换成二级的图标和名字**——
///    选「咖啡」，「吃」这一格就显示咖啡图标 + 「咖啡」。原来那行「已选 吃 › 早餐」删掉，
///    它是在替一个本可以直接呈现的结果做旁白。
/// 4. 二级浮层去掉 42pt 圆底，图标 26 → 30，选中 `scale 1.16` + 标签转墨 600；
///    行距 10 → 14（省下来的 14pt 还回行距，八个抽屉不挤在一起更好点）。
///
/// 语言分工（为什么分类和账户不能共用一套选中态，见 `m4-selection-2026-11-16.html`）：
/// - 分类：**光**——同屏只有一个选中，可以用光指示；
/// - 账户：**层次**——卡面自带品牌色，再叠光会脏，改用亮度与前后关系；
/// - 二级：**字**——同屏 8~10 个一起亮会像彩纸屑，所以只放大 + 加粗。
struct CategoryPicker: View {
    let tops: [Category]
    let subs: [Category]
    let topKey: String
    let subKey: String?
    let showingSub: Bool

    let onSelectTop: (Category) -> Void
    let onSelectSub: (Category) -> Void
    let onCollapse: () -> Void

    /// 一级格子的布局框 / 命中区。图标 36 居中，四周留 4——44 是 HIG 的命中下限。
    private let topTile: CGFloat = 44
    /// 一级列宽。比布局框宽 8，让相邻贴纸之间留出「散落」的呼吸，不至于连成一条。
    private let topWidth: CGFloat = 52
    private let topIconSize: CGFloat = 36
    private let subIconSize: CGFloat = 30

    /// 浮层相对一级行顶部的偏移。一级行高 = 44 + 5 + 13 + 上下各 2，浮层再压 6pt。
    private let subPanelOffset: CGFloat = 72

    /// 分类图标：Fluent3D PNG 优先，缺图退回 `emoji` 字符。
    ///
    /// 不用 `Image(category.iconName)` 直接查名：`iconName` 可能为空串（老库未回填完），
    /// 空名会让 SwiftUI 在控制台刷 "No image named '' found" 并画一个占位框。
    @ViewBuilder
    private func categoryIcon(_ category: Category, size: CGFloat) -> some View {
        if !category.iconName.isEmpty, let image = UIImage(named: category.iconName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(category.emoji)
                .font(.system(size: size * 0.78))
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            topRow

            if showingSub, !subs.isEmpty {
                subPanel
                    .offset(y: subPanelOffset)
                    .zIndex(3)
            }
        }
        .zIndex(showingSub ? 5 : 0)
    }

    /// 当前选中的二级。`subs` 已经是当前一级下的集合，所以查得到就必然属于这一格。
    private var selectedSub: Category? {
        guard let subKey else { return nil }
        return subs.first { $0.key == subKey }
    }

    // MARK: - 一级

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tops) { category in
                    topItem(category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        // 70pt 的散射光晕比 44pt 的格子大，默认会被滚动视图裁成一条边。
        // 这里只放开裁剪、不动布局（iOS 17+），溢出的部分正是「光渗到纸面上」的效果。
        .scrollClipDisabled()
    }

    private func topItem(_ category: Category) -> some View {
        let selected = category.key == topKey
        // v2.2：选中的那一格显示二级结果；没选二级（或不是当前一级）就还显示大类自己。
        let shown = (selected ? selectedSub : nil) ?? category

        return VStack(spacing: 5) {
            ZStack {
                if selected {
                    // 散射色取**一级**的 key，不取 shown——二级图标色相五花八门，
                    // 跟着换会让同一格的光每次切二级就跳一次色。
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    CategoryGlow.color(for: category.key).opacity(0.85),
                                    CategoryGlow.color(for: category.key).opacity(0),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: CategoryGlow.fadeRadius
                            )
                        )
                        .frame(width: CategoryGlow.diameter, height: CategoryGlow.diameter)
                        .opacity(CategoryGlow.opacity)
                        .transition(.opacity)
                }

                categoryIcon(shown, size: topIconSize)
                    .shadow(
                        color: .black.opacity(selected ? 0.22 : 0.10),
                        radius: selected ? 4.5 : 0.75,
                        x: 0,
                        y: selected ? 3 : 0.5
                    )
                    .id(shown.key)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
            .frame(width: topTile, height: topTile)
            .scaleEffect(selected ? 1.12 : 1)
            .offset(y: selected ? -2 : 0)
            // 内容替换（大类 ⇄ 二级）单独走一条动画，不跟选中态的弹簧混在一起。
            .animation(.easeOut(duration: 0.20), value: shown.key)

            ZStack {
                Text(shown.name)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Palette.ink : Palette.sub)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                    .id(shown.key)
                    .transition(.opacity)
            }
            .frame(height: 13)
            .animation(.easeOut(duration: 0.20), value: shown.key)
        }
        .frame(width: topWidth)
        .contentShape(Rectangle())
        .onTapGesture { onSelectTop(category) }
        .animation(.easeOut(duration: 0.18), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        // 读屏时把「属于哪一类」补回去——格子换字之后，视觉上靠位置记得住，读屏记不住。
        .accessibilityLabel(shown.key == category.key ? shown.name
                                                      : "\(category.name)，\(shown.name)")
    }

    // MARK: - 二级

    private var subPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(topName) · 具体是哪一笔")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Button("收起") { onCollapse() }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5),
                spacing: 14
            ) {
                ForEach(subs) { category in
                    subItem(category)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        )
        .padding(.horizontal, 14)
    }

    private var topName: String {
        tops.first { $0.key == topKey }?.name ?? "分类"
    }

    private func subItem(_ category: Category) -> some View {
        let selected = category.key == subKey
        return VStack(spacing: 5) {
            categoryIcon(category, size: subIconSize)
                .shadow(
                    color: .black.opacity(selected ? 0.16 : 0.08),
                    radius: selected ? 3.5 : 0.6,
                    x: 0,
                    y: selected ? 2 : 0.4
                )
                .frame(height: subIconSize)
                .scaleEffect(selected ? 1.16 : 1)

            Text(category.name)
                .font(.system(size: 10))
                .foregroundStyle(selected ? Palette.ink : Palette.ink2)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
        }
        // 没有圆底了，热区全靠这一层：整格 60×48 都能点，不必精确戳到图标。
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .onTapGesture { onSelectSub(category) }
        .animation(.easeOut(duration: 0.18), value: selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
