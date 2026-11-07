import Foundation
import SwiftData

/// 全局设置。v1 只有两项，都在设置页（PRD 9.15）。
///
/// 单条记录：App 启动时取第一条，没有就建一条默认值。
@Model
final class AppSettings {
    /// 收支配色偏好：`true` = 收入绿 / 支出红（默认）。仅影响展示，不影响任何账务。
    var incomeGreenExpenseRed: Bool

    /// 逾期预警开关：`true` = 显示 App 内横幅。
    /// PRD 明确**只做 App 内横幅，不做系统通知**，所以这里没有通知权限相关字段。
    var overdueBannerEnabled: Bool

    /// 最后修改时间。
    var updatedAt: Date

    init(
        incomeGreenExpenseRed: Bool = true,
        overdueBannerEnabled: Bool = true,
        updatedAt: Date = .now
    ) {
        self.incomeGreenExpenseRed = incomeGreenExpenseRed
        self.overdueBannerEnabled = overdueBannerEnabled
        self.updatedAt = updatedAt
    }
}
