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

    /// 评分的正式徽章（Asset Catalog `Grade/*`）。
    ///
    /// 素材是 `assets/grade/final/` 的 J 版：官方 Fluent 3D 字块 1:1 反解，
    /// 40pt 规格出 @2x 80 / @3x 120 两档。**只有 PNG，没有矢量**——
    /// 母版本身是 256px 位图，官方也没有粗圆 3D 汉字字模。
    var assetName: String {
        switch self {
        case .hang: "GradeHang"
        case .piao: "GradePiao"
        case .la: "GradeLa"
        case .npc: "GradeNpc"
        }
    }

    /// 纯文字环境的兜底（通知、导出、单元测试断言）。界面上一律用 `assetName`。
    var emoji: String {
        switch self {
        case .hang: "🔥"
        case .piao: "🍃"
        case .la: "🫠"
        case .npc: "😐"
        }
    }
}
