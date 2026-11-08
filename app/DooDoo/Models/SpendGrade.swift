import Foundation

/// 消费评分四档（PRD 9.13）。**只对 `kind == .expense` 有效**。
///
/// `nil` = 未评分，**不等于 `.npc`**：用户「判定它是 NPC」和「忘了打分」必须分得开，
/// 否则「这个月还有 60 笔没评」这类提醒和夯拉比例都会被污染。
enum SpendGrade: String, Codable, CaseIterable, Sendable {
    case hang   // 夯：花得值
    case piao   // 飘：有点冲动
    case la     // 拉：后悔
    case npc    // NPC：不得不花，不是最低分

    var title: String {
        switch self {
        case .hang: "夯"
        case .piao: "飘"
        case .la: "拉"
        case .npc: "NPC"
        }
    }

    /// 界面上跟标题一起显示。emoji 只是兜底，正式图标走 Fluent3D。
    var emoji: String {
        switch self {
        case .hang: "🔥"
        case .piao: "🍃"
        case .la: "🫠"
        case .npc: "😐"
        }
    }
}
