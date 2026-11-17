import SwiftUI

/// 暖白磨砂（2026-11-18 定案，与资产页浮层同一材质）。
///
/// **材质 = `.ultraThinMaterial` + `Palette.page` 42%。**
/// 那层暖白不能省：系统材质本身偏中性冷灰，不叠暖白的话同一个 App 里
/// 会出现冷暖两种玻璃，看起来像两个产品。
///
/// 使用纪律（`pending/磨砂材质应用面-2026-11-18.md`）：
/// - **背后必须有东西可以透**——玻璃是"看穿一层"的语言，铺在纯页底上没有意义；
/// - **一屏最多一层**，两层叠一起会互相糊；
/// - 玻璃只承担"层"，不承担"色"：不要用它给按钮或选中态提供颜色。
struct GlassPanel<S: Shape>: ViewModifier {
    let shape: S
    /// 暖白不透明度。默认 0.42，与 `GroupOverlay` 一致。
    var strength: Double = 0.42

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Palette.page.opacity(strength))
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.white.opacity(0.66), lineWidth: 0.5)
            }
        }
    }
}

extension View {
    /// 把这一块变成暖白磨砂（内部局部使用，例如详情页「本月要还」条）。
    func glassPanel<S: Shape>(_ shape: S, strength: Double = 0.42) -> some View {
        modifier(GlassPanel(shape: shape, strength: strength))
    }

    /// 把 sheet 的底板换成暖白磨砂，让用户看穿到下面那一屏。
    ///
    /// 用在「录入面板」这一类**盖在内容上**的层；不要用在纯色底的容器上。
    func glassSheet() -> some View {
        presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Palette.page.opacity(0.42))
            }
        }
    }
}
