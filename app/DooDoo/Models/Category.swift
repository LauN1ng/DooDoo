import Foundation
import SwiftData

/// 分类：8 类支出 + 2 类收入，v1 不支持自定义（PRD 3.1.2）。
@Model
final class Category {
    // 标识由 SwiftData 的 `persistentModelID` 提供，不自己声明 `id`。
    var name: String

    /// Fluent3D emoji 的资源名（bundle 里的 PNG，不带扩展名），例 `"Croissant"`。
    /// 取自 `assets/emoji/picked/`，见 `assets/emoji/categories.json` 的分类映射。
    ///
    /// **必须带默认值**：这是后加的字段，老数据升级时靠它填 `""`，
    /// 否则迁移会因为「新增非可选属性且无默认值」直接失败。
    var iconName: String = ""

    /// 兜底字符。图片资源缺失时才用，正常不显示。
    var emoji: String

    /// 排序，小的在前。
    var sortOrder: Int

    /// 收入类（工资 / 其他收入）为 true。
    var isIncome: Bool

    /// 图标底色，十六进制。M1 沿用原型取色，M4 按美术资源重定。
    var tintHex: String

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(name: String, iconName: String, emoji: String, sortOrder: Int, isIncome: Bool, tintHex: String) {
        self.name = name
        self.iconName = iconName
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isIncome = isIncome
        self.tintHex = tintHex
    }
}

extension Category {
    /// 内置十类。`icon` 是 Fluent3D 资源名，`emoji` 只在图片缺失时兜底。
    static let builtIn: [(name: String, icon: String, emoji: String, tint: String)] = [
        ("吃", "Croissant", "🍰", "#FFF1E6"),
        ("穿", "TShirt", "👕", "#FDF1EA"),
        ("住", "House", "🏠", "#F1F4EA"),
        ("行", "LightRail", "🚇", "#EAF2FF"),
        ("乐", "GameDie", "🎮", "#F3EEFF"),
        ("医", "Pill", "💊", "#EAF6F1"),
        ("情", "Cat", "🐱", "#FBEEF4"),
        ("其他", "Package", "📦", "#F2F1ED"),
        ("工资", "MoneyBag", "💰", "#EAF6EC"),
        ("其他收入", "Bank", "💵", "#EAF6EC"),
    ]
}
