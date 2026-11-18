import SwiftUI

/// 微凸纸片——无彩色体系里按钮**唯一**的"实体"语言。
///
/// 2026-11-18 用户「按钮材质不对」。上一版是「白底 + 1pt 实色描边 + 单层影」，
/// 在白卡里会被读成输入框或分隔区。原因不是边太细，而是
/// **描边表达的是"边界"，不是"可按"**；在取消所有彩色的前提下，
/// 实体感只能靠「光从上方来」：
///
/// 1. 顶白 → 底灰的一圈**渐变**描边（等于纸的厚度被光打亮）
/// 2. 贴地影 `y:1 / r:1.5`（定义轮廓贴着哪）
/// 3. 环境影 `y:6 / r:12`（定义它浮起多高）
///
/// 三层都不带颜色，所以放进 D 方案（界面无彩色）里不会引入新的色相。
struct PaperButtonBackground<S: InsettableShape>: View {
    let shape: S
    /// 主按钮传 `true`（影更深、高光更亮）；次按钮传 `false`，只留一层很轻的轮廓。
    var strong: Bool = true

    var body: some View {
        ZStack {
            shape.fill(Palette.card)
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white,
                        Palette.btnEdge.opacity(strong ? 0.9 : 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: strong ? 1.2 : 0.8
            )
        }
        .compositingGroup()
        .shadow(color: Palette.ink.opacity(strong ? 0.06 : 0.04),
                radius: 1.5, x: 0, y: 1)
        .shadow(color: Palette.ink.opacity(strong ? 0.11 : 0.06),
                radius: strong ? 12 : 8, x: 0, y: strong ? 6 : 4)
    }
}

/// 行内浅纸块——**卡内部**的按钮用它。
///
/// 卡片内部既不能用影（会变成"纸上又贴一张纸"），也不能用描边（会被读成分隔线），
/// 只能靠一块比白卡深一档的暖纸表达"这里可以点"。`paperInset` 与白卡 L* 差 7.2，
/// 在白卡上明确可见、在暖白页底上也不会糊。
struct PaperInsetBackground<S: InsettableShape>: View {
    let shape: S
    var body: some View { shape.fill(Palette.paperInset) }
}

extension View {
    /// 一键套用「微凸纸片」。整宽主按钮用默认 18，小胶囊用 11。
    func paperButton(cornerRadius: CGFloat = 18, strong: Bool = true) -> some View {
        background {
            PaperButtonBackground(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                strong: strong
            )
        }
    }

    /// 一键套用「行内浅纸块」。
    func paperInsetButton(cornerRadius: CGFloat = 12) -> some View {
        background {
            PaperInsetBackground(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}
