import Foundation
import SwiftData

/// 分类：8 类支出 + 2 类收入，v1 不支持自定义（PRD 3.1.2）。
@Model
final class Category {
    // 标识由 SwiftData 的 `persistentModelID` 提供，不自己声明 `id`。
    var name: String

    /// 展示用 emoji。M1 先用系统 emoji，M4 换成 `assets/emoji` 的 3D 贴图。
    var emoji: String

    /// 排序，小的在前。
    var sortOrder: Int

    /// 收入类（工资 / 其他收入）为 true。
    var isIncome: Bool

    /// 图标底色，十六进制。**M1 临时值**，M4 按美术资源重定。
    var tintHex: String

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(name: String, emoji: String, sortOrder: Int, isIncome: Bool, tintHex: String) {
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isIncome = isIncome
        self.tintHex = tintHex
    }
}

extension Category {
    /// 内置十类。首次启动写入，之后按 `name` 复用，不重复插。
    static let builtIn: [(name: String, emoji: String, tint: String)] = [
        ("吃", "🍰", "#FFF1E6"),
        ("穿", "👕", "#FDF1EA"),
        ("住", "🏠", "#F1F4EA"),
        ("行", "🚇", "#EAF2FF"),
        ("乐", "🎮", "#F3EEFF"),
        ("医", "💊", "#EAF6F1"),
        ("情", "🐱", "#FBEEF4"),
        ("其他", "📦", "#F2F1ED"),
        ("工资", "💰", "#EAF6EC"),
        ("其他收入", "💵", "#EAF6EC"),
    ]
}
