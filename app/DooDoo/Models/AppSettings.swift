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

    var updatedAt: Date

    var incomeColor: AmountColor {
        get { AmountColor(rawValue: incomeColorRaw) ?? .green }
        set { incomeColorRaw = newValue.rawValue }
    }

    var expenseColor: AmountColor {
        get { AmountColor(rawValue: expenseColorRaw) ?? .red }
        set { expenseColorRaw = newValue.rawValue }
    }

    init(
        monthlyIncome: Decimal = 0,
        payday: Int = 1,
        currencyCode: String = "CNY",
        overdueAlertEnabled: Bool = true,
        incomeColor: AmountColor = .green,
        expenseColor: AmountColor = .red,
        updatedAt: Date = .now
    ) {
        self.monthlyIncome = monthlyIncome
        self.payday = payday
        self.currencyCode = currencyCode
        self.overdueAlertEnabled = overdueAlertEnabled
        self.incomeColorRaw = incomeColor.rawValue
        self.expenseColorRaw = expenseColor.rawValue
        self.updatedAt = updatedAt
    }
}
