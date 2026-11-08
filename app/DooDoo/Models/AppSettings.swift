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
        case .ink: 0x1D1C1A
        case .green: 0x2FB344
        case .blue: 0x4A6CF7
        case .orange: 0xE09B2D
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
    var accentId: String = AccentStyle.ink.rawValue

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
