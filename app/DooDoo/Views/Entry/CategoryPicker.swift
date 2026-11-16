import SwiftUI
import UIKit

/// 分类选择：一级贴纸行 + 二级浮层（记一笔规格冻结 **v2.4** 第六节）。
///
/// 2026-11-16 第三次重画，三条改动：
/// 1. **一级选中态换成「纯物理抬起」**（V1，用户当日从七版里选定）：
///    `scale 1.22` + 上移 6pt + 投影加重到 `.26`，未选中图标压到 80% 不透明。
///    去掉 v2.2 那圈「从图标平均色吸出来」的径向光晕——实测那张色表跟图标对不上
///    （`吃` 是银紫餐具却给了紫光，叠上去整格发紫；`住` 给了黄绿 `#E1F77C`，
///    在暖白 `#F7F5F1` 上几乎不可见），强度又只有 `.28`，等于白加。
///    **一个彩色都不引入**：区分靠「谁被拿起来、谁还贴在纸上」。
/// 2. **未选中也让一步**（80% 不透明）。只放大选中的那个推不动眼睛——
///    同屏 8 个里只变一个，得逐个比大小；两头一起动，选中才跳出来。
/// 3. **每格显示自己那一类记着的二级**（问题 3 方案 A）：`shownByTop` 由
///    `EntryViewModel` 按大类分桶算好，选过「咖啡」的「吃」格切走再切回来还是咖啡。
///    这里不再自己判断「只有当前选中才配显示二级」。
///
/// 语言分工（为什么分类和账户不能共用一套选中态，见 `entry-selection-2026-11-16.html`）：
/// - 分类：**物理抬起**——同屏只有一个选中，用高度表达；
/// - 账户：**亮度与前后**——卡面自带品牌色，再叠光会脏，见 `AccountCardStrip`；
/// - 二级：**字**——同屏 8~10 个一起放大会像彩纸屑，所以只放大 + 加粗、不抬起。
struct CategoryPicker: View {
    let tops: [Category]
    let subs: [Category]
    let topKey: String
    let subKey: String?
    let showingSub: Bool
    /// 每个一级 key → 该格当前该显示的分类（二级或大类自己）。见 `EntryViewModel.shownByTop`。
    let shownByTop: [String: Category]

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
        // 抬起 6pt + 投影比 44pt 的格子大，默认会被滚动视图裁成一条边。
        // 这里只放开裁剪、不动布局（iOS 17+），溢出的部分正是「贴纸浮起来」的影子。
        .scrollClipDisabled()
    }

    private func topItem(_ category: Category) -> some View {
        // 选中态看「是不是当前这一族」，内容看「这一族自己记着什么」——
        // 两件事分开，所以切走的大类仍显示它上次选的二级，但不显得被选中。
        let selected = category.key == topKey
        let shown = shownByTop[category.key] ?? category

        return VStack(spacing: 5) {
            // ZStack 两层作用：一是让图标的 `id` 变化能触发 transition（直接放在
            // VStack 里会硬切），二是换字时两版文字叠在同一格，不会把行高撑成 26。
            ZStack {
                categoryIcon(shown, size: topIconSize)
                    .shadow(
                        color: .black.opacity(selected ? 0.26 : 0.10),
                        radius: selected ? 4.5 : 0.75,
                        x: 0,
                        y: selected ? 3.5 : 0.5
                    )
                    .id(shown.key)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
            .frame(width: topTile, height: topTile)
            // 未选中让一步。只放大选中的那个推不动眼睛，两头一起动才跳得出来。
            .opacity(selected ? 1 : 0.80)
            .scaleEffect(selected ? 1.22 : 1)
            .offset(y: selected ? -6 : 0)
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
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selected)
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
