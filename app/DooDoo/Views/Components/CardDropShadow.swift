import SwiftUI

/// 只向下的「落地影」。
///
/// ## 为什么不再用 `.shadow`（2026-11-17 真机第三次反馈后的结论）
///
/// `.shadow` 的高斯模糊是**各向同性**的：半径多大，就朝上下左右四个方向各铺多大，
/// 和 `y` 偏移没有任何关系。所以「偏移 > 半径」只能压住顶边——
/// `0 15 14` 确实让卡片顶边干净了（实测顶边上方 1pt 处取到 245，等于底色），
/// 但左右两侧仍然各糊 14pt。暖白底上那两条纵向灰雾就是它，跟方向无关、跟参数也无关。
/// 三轮都在这两个数字上打转，说明这条路本身走不通：**只要用 `.shadow` 就一定带侧向外溢**。
///
/// ## 做法
///
/// 影子做成一块**独立的形状**贴在卡片背后（`.background`），再对它做三件事：
///
/// 1. `padding(.horizontal, inset)` —— 影子比卡片窄，侧向不再外扩；
/// 2. `padding(.top, 高度 × top)` —— 只保留下半段，卡片上半部两侧**零阴影**；
/// 3. `blur` + `offset(y: drop)` —— 从腰部往下渐隐，负责「离地」。
///
/// 卡片本身不透明，影子形状的顶边藏在卡面后面，外部只看得到腰部以下那一团。
/// 于是「卡顶左右角有没有灰边」这个问题从根上消失了，不用再调偏移量。
///
/// ## 代价（用它必须一起做）
///
/// 卡片顶边与左右上角不再有影子托着。白卡压在白纸上只有 1.04:1 的亮度差，
/// 轮廓会发虚。所以用它的地方**必须自带描边**（`Palette.line` 那种「纸的边」），
/// 由线定义轮廓、影子只负责离地——这才是 `Palette` 注释里
/// 「层次靠叠（描边 + 投影 + 层厚）」的完整形态。彩色卡面（`CardFace`）自带
/// 0.5pt 白色高光边，不需要额外补线。
struct CardDropShadow: ViewModifier {
    /// 影子相对卡片左右各内缩多少。取 `blur` 的 0.6 倍左右：留一点扩散感，又不外扩成灰雾。
    var inset: CGFloat
    /// 从卡片高度的这个比例往下才有影子。必须满足 `高度 × top > blur`，否则顶边会露出来。
    var top: CGFloat = 0.5
    var blur: CGFloat
    /// 向下偏移。必须小于 `blur`，否则影子会和卡片底边脱开、变成一条飘着的带子。
    var drop: CGFloat
    var opacity: Double
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.ink.opacity(opacity))
                    .padding(.horizontal, inset)
                    .padding(.top, geo.size.height * top)
                    .blur(radius: blur)
                    .offset(y: drop)
            }
            .allowsHitTesting(false)
        }
    }
}
