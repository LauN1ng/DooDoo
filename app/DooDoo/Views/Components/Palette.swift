import SwiftUI

/// 全局取色表。
///
/// **M4 2026-11-16 重校**：底色从暖白 `#F7F5F1` 改为**完全中性灰白 `#F6F6F6`**，
/// 依据用户提供的 Copilot Money / HeyCost 实机截图取色（`research/refs/ref-copilot-*` 页面底
/// `#F8FAFA`、`ref-realapp-03/-04` 为 `#F4F4F4`，三家共同点是 R=G=B 中性）。
/// 旧的 `sub #A8A39A` 在白卡上只有 2.51:1，达不到 WCAG AA，这次一并拉到 4.5:1 以上。
enum Palette {
    static let page = Color(hex: 0xF6F6F6)
    static let card = Color.white
    static let ink = Color(hex: 0x1D1D1F)
    static let ink2 = Color(hex: 0x5F5F66)
    static let sub = Color(hex: 0x6E6E76)     // 白卡 5.05:1 / 页底 4.52:1
    static let faint = Color(hex: 0x9A9AA2)   // 只用于装饰，不承载信息
    static let line = Color(hex: 0xE8E8E8)
    static let expense = Color(hex: 0xC0392B)
    static let income = Color(hex: 0x2E9E6B)
    static let tabBed = Color(hex: 0xE9E9E9)

    /// 卡内图标槽 / 选中块的共用底色（第 1 条：两个界面的图标底统一成一个）。
    /// 与白卡色差 6.4%，高于「浅色容器叠白卡 低于 5% 必糊」的规格下限。
    static let slot = Color(hex: 0xF0F0F2)

    // 资产页
    static let pillOn = Color(hex: 0xF0F0F2)
    static let mine = Color(hex: 0x4C8DF6)   // 「我有」曲线
    static let owe = Color(hex: 0xE8734A)    // 「我欠」曲线
    static let mineDot = Color(hex: 0x3A9E6B)
    static let oweDot = Color(hex: 0xE8734A)
    static let overdraft = Color(hex: 0xA32D2D)
    static let overdraftBed = Color(hex: 0xFDECEC)

    /// 主色（分类选中描边、按钮实底、金额强调）。
    ///
    /// 2026-11-16 起**默认改为品牌绿**（此前默认墨黑）：用户反馈"记一笔界面黑色太多"，
    /// 黑只留给标题与金额文字，强调与选中态交给品牌色。
    static func accent(_ style: AccentStyle) -> Color {
        Color(hex: style.hex)
    }

    /// 实底按钮 / 白字场景用的**加深版**主色。
    ///
    /// 品牌亮绿 `#3ABF58` 白字只有 2.39:1、规格绿 `#2FB344` 2.74:1、橙 `#E09B2D` 2.36:1，
    /// 都达不到 4.5:1；实底一律走这一档，亮色只用于描边、小图标、进度等图形。
    static func accentFill(_ style: AccentStyle) -> Color {
        Color(hex: style.fillHex)
    }

    /// 主色的 12% 底，用于选中态（不再用实底黑块）。
    static func accentWash(_ style: AccentStyle) -> Color {
        Color(hex: style.hex).opacity(0.12)
    }
}

extension Color {
    /// `Color(hex: 0x1D1C1A)`，避免到处写 `Color(red:green:blue:)`。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// 只接受 `#RRGGBB`；解析失败退回浅灰，不崩。
    init(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self.init(hex: 0xF2F1ED)
            return
        }
        self.init(hex: value)
    }
}
