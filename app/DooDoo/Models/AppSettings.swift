import Foundation
import SwiftData

/// 金额着色偏好（PRD 8 节）。只影响展示，不影响任何账务。
enum AmountColor: String, Codable, CaseIterable, Sendable {
    case green
    case red
    case ink

    var title: String {
        switch self {
        case .green: "绿"
        case .red: "红"
        case .ink: "墨"
        }
    }
}

/// 主色（M1b 新增，记一笔规格第九节未锁定项 1）。
/// 只影响强调色：分类选中、主按钮、转账手续费差额等；不改数据。
enum AccentStyle: String, Codable, CaseIterable, Sendable {
    case ink
    case green
    case blue
    case orange

    var title: String {
        switch self {
        case .ink: "墨"
        case .green: "绿"
        case .blue: "蓝"
        case .orange: "橙"
        }
    }

    /// 与该主色配套的浅底（选中态的 12% 透明度底），用十六进制直写。
    var hex: UInt32 {
        switch self {
        case .ink: 0x1D1D1F
        case .green: 0x3ABF58
        case .blue: 0x4A6CF7
        case .orange: 0xE09B2D
        }
    }

    /// 实底按钮用的加深版：上面四个原值的白字对比全部达不到 4.5:1。
    /// 数值全部实测（`#FFFFFF` 为底，sRGB，WCAG 2.x 相对亮度）。
    var fillHex: UInt32 {
        switch self {
        case .ink: 0x1D1D1F      // 16.83:1
        case .green: 0x1B8230    // 4.90:1（原 #1E8A32 只有 4.43，不达标）
        case .blue: 0x4364EE     // 4.89:1
        case .orange: 0x9C5F0C   // 5.18:1（原 #A9680F 只有 4.49，临界不合格）
        }
    }
}

/// 全局设置。v1 字段以 PRD 第八节为准。
@Model
final class AppSettings {
    /// 单位：元。月收入，用于月度安排。
    var monthlyIncome: Decimal

    /// 发薪日，1~31。
    var payday: Int

    /// 币种，v1 固定 "CNY"（不做多币种）。
    var currencyCode: String

    /// 逾期预警开关：`true` = 显示 App 内横幅。
    /// PRD 明确**只做 App 内横幅，不做系统通知**，所以没有通知权限相关字段。
    var overdueAlertEnabled: Bool

    /// 收入着色，默认绿。
    var incomeColorRaw: String

    /// 支出着色，默认红。
    var expenseColorRaw: String

    /// 种子数据版本。改动种子结构时 +1，启动时据此重建演示数据。
    /// 0 = M1 之前写的旧种子。
    var seedVersion: Int = 0

    /// 主色 id（`AccentStyle` 的 rawValue）。后加字段，必须有默认值。
    ///
    /// 默认值必须写字面量：`@Model` 对属性默认值要求「完全限定的字面量」，
    /// 写成 `AccentStyle.ink.rawValue` 这类属性访问在部分 Xcode 版本上会报
    /// "A default value requires a fully qualified domain named value"（`Date.now` 踩过同样的坑）。
    ///
    /// 2026-11-16 默认从 `ink` 改为 `green`：用户反馈记一笔界面黑块太多。
    var accentId: String = "green"

    var updatedAt: Date

    var incomeColor: AmountColor {
        get { AmountColor(rawValue: incomeColorRaw) ?? .green }
        set { incomeColorRaw = newValue.rawValue }
    }

    var expenseColor: AmountColor {
        get { AmountColor(rawValue: expenseColorRaw) ?? .red }
        set { expenseColorRaw = newValue.rawValue }
    }

    /// 主色。默认墨黑。
    var accent: AccentStyle {
        get { AccentStyle(rawValue: accentId) ?? .ink }
        set { accentId = newValue.rawValue }
    }

    init(
        monthlyIncome: Decimal = 0,
        payday: Int = 1,
        currencyCode: String = "CNY",
        overdueAlertEnabled: Bool = true,
        incomeColor: AmountColor = .green,
        expenseColor: AmountColor = .red,
        seedVersion: Int = 0,
        updatedAt: Date = .now
    ) {
        self.seedVersion = seedVersion
        self.monthlyIncome = monthlyIncome
        self.payday = payday
        self.currencyCode = currencyCode
        self.overdueAlertEnabled = overdueAlertEnabled
        self.incomeColorRaw = incomeColor.rawValue
        self.expenseColorRaw = expenseColor.rawValue
        self.updatedAt = updatedAt
    }
}
