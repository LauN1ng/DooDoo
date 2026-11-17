import SwiftUI

/// 全局取色表。
///
/// **M4 2026-11-16 第三次重校**：底色回到规格原本的**暖白 `#F7F5F1`**。
///
/// 上一版（同日）为对齐 Copilot Money / HeyCost 实机截图，把底改成中性灰白 `#F6F6F6`。
/// 用户看真机后连否两轮（「灰白背景但主题色不确定」→「换成灰白色首页看着更不对了」），
/// 根因是 `#F6F6F6` 与白卡只差 3.1 L*，等于没换；同时把 `#F7F5F1` 这套「纸 / 卡 / 玻璃 / 线」
/// 的材质语言换成了四档互相撞车的冷灰（`#F6F6F6` / `#E9E9E9` / `#F0F0F2` / `#EFEFF1`）。
///
/// 现在的规则（`资产页规格冻结-v1.0` 第 47 行、`美术资源交付-11-06` 第 40 行原本就这么写）：
/// - 层次靠**叠**（描边 + 投影 + 层厚），不靠灰阶；全屏只留一种浅色底；
/// - 灰色只承担文字，不再用来当容器底（`slot` 收窄到输入框一类真正需要一个「坑」的地方）。
enum Palette {
    static let page = Color(hex: 0xF7F5F1)
    static let card = Color.white
    static let ink = Color(hex: 0x1D1D1F)
    static let ink2 = Color(hex: 0x5F5F66)
    static let sub = Color(hex: 0x6E6E76)     // 白卡 5.05:1 / 页底 4.62:1
    static let faint = Color(hex: 0x9A9AA2)   // 只用于装饰，不承载信息
    /// 白卡描边（纸的边）。不是分隔线——分隔线见 `Palette.hairline`。
    static let line = Color(hex: 0xECE7DE)
    /// 列表 / 卡片内部的 1px 分隔。比 `line` 淡，避免每行都像一道刻痕。
    static let hairline = Color(hex: 0x1D1C1A).opacity(0.06)
    static let expense = Color(hex: 0xA8332B)
    static let income = Color(hex: 0x1F7A52)
    static let tabBed = Color(hex: 0xEDE9E1)

    /// **不再是图标槽底色**（2026-11-16 第二次定案：贴纸不垫纸）。
    /// 只留给真正需要「凹下去」的容器：输入框、进度条轨道、tab 段底。
    static let slot = Color(hex: 0xF0EDE6)

    // 资产页
    static let pillOn = Color(hex: 0xE9E4D9)
    // 2026-11-18 配色终版（D 方案）：界面层不再有主题色，蓝/橙退场——
    // 「我有」曲线改绿、「我欠」曲线改红，与数据层同一支；两条都是实线。
    static let mine = Color(hex: 0x1F7A52)   // 「我有」曲线
    static let owe = Color(hex: 0xA8332B)    // 「我欠」曲线
    static let mineDot = Color(hex: 0x1F7A52)
    static let oweDot = Color(hex: 0xA8332B)
    /// 逾期专用亮红（D-a）：比数据红 `expense` 更亮一档，一屏只允许它出现。
    static let overdraft = Color(hex: 0xD03A2E)
    static let overdraftBed = Color(hex: 0xFDECEC)

    // MARK: - D 方案的纸与边（2026-11-18）

    /// 选中态 / 内嵌块的纸底。不是新色——它就是原来 `pillOn` 的暖米。
    static let paper = Color(hex: 0xE9E4D9)
    /// 次按钮描边。
    static let btnEdge = Color(hex: 0xD6CFC0)
    /// 主按钮描边：比次按钮深一档、粗一档（1.5pt）。
    static let btnEdgeStrong = Color(hex: 0xC9C0AE)

    // MARK: - 消费评分四档

    /// 档位色**只给文字和占位符用**，不铺底、不描边（2026-11-16 定案：
    /// 评分位的颜色全部由徽章素材自己提供，界面不再叠一层重点色）。
    /// 四档在浅底上的对比度：夯 5.9:1 / 飘 6.2:1 / 拉 7.8:1 / NPC 4.6:1，均过 AA。
    static func gradeTint(_ grade: SpendGrade) -> Color {
        switch grade {
        case .hang: Color(hex: 0xB01D42)
        case .piao: Color(hex: 0x1A64B8)
        case .la: Color(hex: 0x5A31C0)
        case .npc: Color(hex: 0x7A7A80)
        }
    }

    /// 未评分空位的中性灰。用的是 NPC 档的色相，但只出 44% 透明度——
    /// 它承载的是「这里可以填」而不是「已经选了 NPC」。
    static let gradeVacant = Color(hex: 0x7A7A80)

    /// 备注卡里隔开评分位的那条竖虚线（比分隔线 `line` 深一档，才看得出是「断」的）。
    static let dividerDash = Color(hex: 0xDBD6CC)

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
