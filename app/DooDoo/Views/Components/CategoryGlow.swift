import SwiftUI

/// 一级分类的**散射色**表（记一笔规格冻结 v2.2 第六节）。
///
/// 选中态 = 放大 1.12 + 图标背后一圈弱档径向光晕（opacity .28）。
/// 光晕色不是手挑的：从每个一级图标的 PNG 里取非透明像素的**平均 RGB** 求色相，
/// 再统一到 S 0.50 / V 0.97，只保留色相差异——这样「吃」的紫光就是它自己那顿饭的紫，
/// 而不是另配一套主题色（脚本见 `docs/design/pending/M4九条视觉反馈-2026-11-16.md` 附录）。
///
/// **只配 10 个一级，二级沿用父级的色。** 两个理由：
/// 1. 二级切来切去时同一格的光不会跳色（弱档只有 .28，色相差异看不出，但跳变看得出来）；
/// 2. 51 个二级各配一色，迟早和素材更新对不上，而光只需要表达「这一族亮了」。
///
/// 实测八个支出图标只有四簇色相（紫 ×3、蓝 ×2、橙 ×2、黄 ×1）——素材本身如此，
/// 但同一时刻只点亮一个，不会同时出现两团同色光，所以不构成识别冲突。
enum CategoryGlow {
    private static let table: [String: UInt32] = [
        "food":        0xA87CF7,   // 262° 紫
        "wear":        0x7CA6F7,   // 220° 蓝
        "home":        0xE1F77C,   //  71° 黄绿
        "transport":   0x7CA7F7,   // 219° 蓝
        "fun":         0xF47CF7,   // 298° 品红
        "health":      0xD37CF7,   // 283° 紫
        "social":      0xF7BA7C,   //  30° 橙
        "misc":        0xF7AC7C,   //  24° 橙
        "salary":      0xF7BE7C,   //  32° 橙
        "otherIncome": 0xB77CF7,   // 269° 紫
    ]

    /// 找不到就退回中性浅灰——宁可没有光，也不要出现一团错色的光。
    static func color(for topKey: String) -> Color {
        Color(hex: table[topKey] ?? 0xD9D4CB)
    }

    /// 光晕直径：图标 36 时取 70（原型 `inset:-9px` 的等价）。
    static let diameter: CGFloat = 70
    /// 渐变收敛半径 = 直径 / 2 × 0.62（原型 `transparent 62%`）。
    static var fadeRadius: CGFloat { diameter / 2 * 0.62 }
    /// 弱档强度（用户在 .28 / .55 / .75 里选的弱档）。
    static let opacity: Double = 0.28
}
