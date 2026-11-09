import SwiftUI

/// 分类选择：一级色块横滑 + 二级浮层（记一笔规格冻结 v1.0 第六节）。
///
/// - 一级：52×52 圆角 16，选中主色实底；
/// - 二级：白色卡片圆角 20，5 列 × 2 行，圆底 42，选中主色 12% 底 + 1.5pt 描边；
/// - 浮层**覆盖**下方内容（用 ZStack + offset），不推挤布局。
struct CategoryPicker: View {
    let tops: [Category]
    let subs: [Category]
    let topKey: String
    let subKey: String?
    let showingSub: Bool
    let accent: Color
    let accentWash: Color

    let onSelectTop: (Category) -> Void
    let onSelectSub: (Category) -> Void
    let onCollapse: () -> Void

    private let tile: CGFloat = 52
    private let subTile: CGFloat = 42

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                topRow
                selectedHint
            }

            if showingSub, !subs.isEmpty {
                subPanel
                    .offset(y: tile + 26)
                    .zIndex(3)
            }
        }
        .zIndex(showingSub ? 5 : 0)
    }

    /// 分类选中回显（2026-11-09 真机反馈 #7）：一级色块不随二级变化，
    /// 选完浮层收起后全屏原本没有任何地方能看出选了「咖啡」。
    /// 这里只用文字，不换图标——分类图标等 71 槽位正式映射再一起换。
    private var selectedHint: some View {
        HStack(spacing: 5) {
            Text("已选")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
            Text(selectedPath)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 3)
    }

    private var selectedPath: String {
        guard let subKey, let sub = subs.first(where: { $0.key == subKey }) else {
            return topName
        }
        return "\(topName) › \(sub.name)"
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
    }

    private func topItem(_ category: Category) -> some View {
        let selected = category.key == topKey
        return VStack(spacing: 5) {
            Text(category.emoji)
                .font(.system(size: 24))
                .frame(width: tile, height: tile)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? accent : Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? .clear : Palette.line, lineWidth: 1)
                )
                .shadow(color: selected ? accent.opacity(0.28) : .black.opacity(0.04),
                        radius: selected ? 7 : 2, x: 0, y: selected ? 4 : 1)

            Text(category.name)
                .font(.system(size: 10.5))
                .foregroundStyle(selected ? Palette.ink : Palette.sub)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
        }
        .frame(width: 56)
        .contentShape(Rectangle())
        .onTapGesture { onSelectTop(category) }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                spacing: 10
            ) {
                ForEach(subs) { category in
                    subItem(category)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
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
            Text(category.emoji)
                .font(.system(size: 21))
                .frame(width: subTile, height: subTile)
                .background(
                    Circle().fill(selected ? accentWash : Palette.page)
                )
                .overlay(
                    Circle().strokeBorder(selected ? accent : .clear, lineWidth: 1.5)
                )

            Text(category.name)
                .font(.system(size: 10))
                .foregroundStyle(selected ? Palette.ink : Palette.ink2)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onSelectSub(category) }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
