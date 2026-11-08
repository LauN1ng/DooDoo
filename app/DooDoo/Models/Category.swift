import Foundation
import SwiftData

/// 分类：**一级 8 类支出 + 2 类收入，每个一级下带二级子类**（PRD v2.3 · 3.1.2）。
///
/// 层级用 `key` / `parentKey` 两个字符串表达，**不用 SwiftData 自引用关系**：
/// 自引用 + inverse 的删除规则与迁移推断都容易出错，而内置分类本来就不许改名删除。
/// 查子类：`filter { $0.parentKey == parent.key }`。
///
/// 统计口径：所有汇总按**一级**算，二级只影响录入精度与流水行展示。
@Model
final class Category {
    // 标识由 SwiftData 的 `persistentModelID` 提供，不自己声明 `id`。

    /// 稳定标识。一级 `food`，二级 `food.breakfast`。
    /// 后加字段必须带默认值，否则老库迁移直接抛错。
    var key: String = ""

    /// 二级指向一级的 key；一级为 nil。
    var parentKey: String?

    var name: String

    /// Fluent3D emoji 的资源名（bundle 里的 PNG，不带扩展名），例 `"Croissant"`。
    /// 二级复用父类的图标——bundle 里只有 14 张图，39 个子类各配一张不现实。
    var iconName: String = ""

    /// 兜底字符。图片资源缺失时才用，正常不显示。
    var emoji: String

    /// 排序，小的在前。同一父类下按此排。
    var sortOrder: Int

    /// 收入类（工资 / 其他收入及其子类）为 true。
    var isIncome: Bool

    /// 图标底色，十六进制。二级沿用父类底色。
    var tintHex: String

    /// 该分类上次使用的评分档位（PRD 9.13 规则 3），记一笔时自动带出。
    /// 存 raw 值而不是枚举：SwiftData 对可选枚举的迁移更挑剔。
    var defaultGradeRaw: String?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(
        key: String = "",
        parentKey: String? = nil,
        name: String,
        iconName: String,
        emoji: String,
        sortOrder: Int,
        isIncome: Bool,
        tintHex: String,
        defaultGradeRaw: String? = nil
    ) {
        self.key = key
        self.parentKey = parentKey
        self.name = name
        self.iconName = iconName
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isIncome = isIncome
        self.tintHex = tintHex
        self.defaultGradeRaw = defaultGradeRaw
    }
}

extension Category {
    /// 是否一级分类。
    var isTopLevel: Bool { parentKey == nil }

    /// 评分记忆（`nil` = 该分类没有默认档位）。
    var defaultGrade: SpendGrade? {
        get { defaultGradeRaw.flatMap { SpendGrade(rawValue: $0) } }
        set { defaultGradeRaw = newValue?.rawValue }
    }
}

extension Category {
    /// 内置分类的一条规格。父与子用同一结构，靠 `parentKey` 区分层级。
    struct BuiltIn: Sendable {
        let key: String
        let parentKey: String?
        let name: String
        let icon: String
        let emoji: String
        let tint: String
        let isIncome: Bool
    }

    /// 内置分类：一级 10 个（支出 8 + 收入 2）+ 二级 48 个（支出 39 + 收入 9）。
    ///
    /// 顺序即展示顺序：先父后子，同一父类的子类连续排列，方便种子一次性插入。
    static let builtIn: [BuiltIn] = [
        // MARK: 一级 · 支出 8 类
        .init(key: "food", parentKey: nil, name: "吃", icon: "Croissant", emoji: "🍰", tint: "#FFF1E6", isIncome: false),
        .init(key: "wear", parentKey: nil, name: "穿", icon: "TShirt", emoji: "👕", tint: "#FDF1EA", isIncome: false),
        .init(key: "home", parentKey: nil, name: "住", icon: "House", emoji: "🏠", tint: "#F1F4EA", isIncome: false),
        .init(key: "transport", parentKey: nil, name: "行", icon: "LightRail", emoji: "🚇", tint: "#EAF2FF", isIncome: false),
        .init(key: "fun", parentKey: nil, name: "乐", icon: "GameDie", emoji: "🎮", tint: "#F3EEFF", isIncome: false),
        .init(key: "health", parentKey: nil, name: "医", icon: "Pill", emoji: "💊", tint: "#EAF6F1", isIncome: false),
        .init(key: "social", parentKey: nil, name: "情", icon: "Cat", emoji: "🐱", tint: "#FBEEF4", isIncome: false),
        .init(key: "misc", parentKey: nil, name: "其他", icon: "Package", emoji: "📦", tint: "#F2F1ED", isIncome: false),

        // MARK: 二级 · 吃（8）
        .init(key: "food.breakfast", parentKey: "food", name: "早餐", icon: "Croissant", emoji: "🥐", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.lunch", parentKey: "food", name: "午餐", icon: "BentoBox", emoji: "🍱", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.dinner", parentKey: "food", name: "晚餐", icon: "BentoBox", emoji: "🍜", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.latenight", parentKey: "food", name: "夜宵", icon: "BentoBox", emoji: "🍢", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.coffee", parentKey: "food", name: "咖啡", icon: "HotBeverage", emoji: "☕️", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.drink", parentKey: "food", name: "饮料", icon: "HotBeverage", emoji: "🧋", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.snack", parentKey: "food", name: "零食", icon: "Croissant", emoji: "🍪", tint: "#FFF1E6", isIncome: false),
        .init(key: "food.grocery", parentKey: "food", name: "买菜", icon: "ShoppingBags", emoji: "🥬", tint: "#FFF1E6", isIncome: false),

        // MARK: 二级 · 穿（5）
        .init(key: "wear.top", parentKey: "wear", name: "上衣", icon: "TShirt", emoji: "👕", tint: "#FDF1EA", isIncome: false),
        .init(key: "wear.pants", parentKey: "wear", name: "裤子", icon: "TShirt", emoji: "👖", tint: "#FDF1EA", isIncome: false),
        .init(key: "wear.shoes", parentKey: "wear", name: "鞋", icon: "TShirt", emoji: "👟", tint: "#FDF1EA", isIncome: false),
        .init(key: "wear.accessory", parentKey: "wear", name: "配饰", icon: "ShoppingBags", emoji: "💍", tint: "#FDF1EA", isIncome: false),
        .init(key: "wear.haircut", parentKey: "wear", name: "理发", icon: "ShoppingBags", emoji: "💇", tint: "#FDF1EA", isIncome: false),

        // MARK: 二级 · 住（5）
        .init(key: "home.rent", parentKey: "home", name: "房租", icon: "House", emoji: "🛏", tint: "#F1F4EA", isIncome: false),
        .init(key: "home.utility", parentKey: "home", name: "水电", icon: "House", emoji: "💡", tint: "#F1F4EA", isIncome: false),
        .init(key: "home.property", parentKey: "home", name: "物业", icon: "House", emoji: "🏢", tint: "#F1F4EA", isIncome: false),
        .init(key: "home.furniture", parentKey: "home", name: "家居", icon: "House", emoji: "🪑", tint: "#F1F4EA", isIncome: false),
        .init(key: "home.repair", parentKey: "home", name: "维修", icon: "House", emoji: "🔧", tint: "#F1F4EA", isIncome: false),

        // MARK: 二级 · 行（5）
        .init(key: "transport.metro", parentKey: "transport", name: "地铁", icon: "LightRail", emoji: "🚇", tint: "#EAF2FF", isIncome: false),
        .init(key: "transport.bus", parentKey: "transport", name: "公交", icon: "LightRail", emoji: "🚌", tint: "#EAF2FF", isIncome: false),
        .init(key: "transport.taxi", parentKey: "transport", name: "打车", icon: "Taxi", emoji: "🚕", tint: "#EAF2FF", isIncome: false),
        .init(key: "transport.fuel", parentKey: "transport", name: "加油", icon: "Taxi", emoji: "⛽️", tint: "#EAF2FF", isIncome: false),
        .init(key: "transport.parking", parentKey: "transport", name: "停车", icon: "Taxi", emoji: "🅿️", tint: "#EAF2FF", isIncome: false),

        // MARK: 二级 · 乐（5）
        .init(key: "fun.movie", parentKey: "fun", name: "电影", icon: "GameDie", emoji: "🎬", tint: "#F3EEFF", isIncome: false),
        .init(key: "fun.game", parentKey: "fun", name: "游戏", icon: "GameDie", emoji: "🎮", tint: "#F3EEFF", isIncome: false),
        .init(key: "fun.party", parentKey: "fun", name: "聚会", icon: "BentoBox", emoji: "🍻", tint: "#F3EEFF", isIncome: false),
        .init(key: "fun.travel", parentKey: "fun", name: "旅行", icon: "GameDie", emoji: "✈️", tint: "#F3EEFF", isIncome: false),
        .init(key: "fun.subscription", parentKey: "fun", name: "订阅", icon: "GameDie", emoji: "📺", tint: "#F3EEFF", isIncome: false),

        // MARK: 二级 · 医（4）
        .init(key: "health.medicine", parentKey: "health", name: "药品", icon: "Pill", emoji: "💊", tint: "#EAF6F1", isIncome: false),
        .init(key: "health.clinic", parentKey: "health", name: "门诊", icon: "Pill", emoji: "🏥", tint: "#EAF6F1", isIncome: false),
        .init(key: "health.checkup", parentKey: "health", name: "体检", icon: "Pill", emoji: "🩺", tint: "#EAF6F1", isIncome: false),
        .init(key: "health.dental", parentKey: "health", name: "牙科", icon: "Pill", emoji: "🦷", tint: "#EAF6F1", isIncome: false),

        // MARK: 二级 · 情（4）
        .init(key: "social.gift", parentKey: "social", name: "礼物", icon: "Cat", emoji: "🎁", tint: "#FBEEF4", isIncome: false),
        .init(key: "social.pet", parentKey: "social", name: "宠物", icon: "Cat", emoji: "🐱", tint: "#FBEEF4", isIncome: false),
        .init(key: "social.redpacket", parentKey: "social", name: "红包", icon: "Cat", emoji: "🧧", tint: "#FBEEF4", isIncome: false),
        .init(key: "social.human", parentKey: "social", name: "人情", icon: "Cat", emoji: "🤝", tint: "#FBEEF4", isIncome: false),

        // MARK: 二级 · 其他（3）
        .init(key: "misc.fee", parentKey: "misc", name: "手续费", icon: "Package", emoji: "🏦", tint: "#F2F1ED", isIncome: false),
        .init(key: "misc.various", parentKey: "misc", name: "杂项", icon: "Package", emoji: "📦", tint: "#F2F1ED", isIncome: false),
        .init(key: "misc.fine", parentKey: "misc", name: "罚款", icon: "Package", emoji: "🚨", tint: "#F2F1ED", isIncome: false),

        // MARK: 一级 · 收入 2 类
        .init(key: "salary", parentKey: nil, name: "工资", icon: "MoneyBag", emoji: "💰", tint: "#EAF6EC", isIncome: true),
        .init(key: "otherIncome", parentKey: nil, name: "其他收入", icon: "Bank", emoji: "💵", tint: "#EAF6EC", isIncome: true),

        // MARK: 二级 · 工资（4）
        .init(key: "salary.monthly", parentKey: "salary", name: "月薪", icon: "MoneyBag", emoji: "💰", tint: "#EAF6EC", isIncome: true),
        .init(key: "salary.bonus", parentKey: "salary", name: "奖金", icon: "MoneyBag", emoji: "🏆", tint: "#EAF6EC", isIncome: true),
        .init(key: "salary.overtime", parentKey: "salary", name: "加班费", icon: "MoneyBag", emoji: "🌙", tint: "#EAF6EC", isIncome: true),
        .init(key: "salary.allowance", parentKey: "salary", name: "补贴", icon: "MoneyBag", emoji: "🧾", tint: "#EAF6EC", isIncome: true),

        // MARK: 二级 · 其他收入（5）
        .init(key: "otherIncome.redpacket", parentKey: "otherIncome", name: "红包", icon: "Bank", emoji: "🧧", tint: "#EAF6EC", isIncome: true),
        .init(key: "otherIncome.reimburse", parentKey: "otherIncome", name: "报销", icon: "Bank", emoji: "📄", tint: "#EAF6EC", isIncome: true),
        .init(key: "otherIncome.refund", parentKey: "otherIncome", name: "退款", icon: "Bank", emoji: "↩️", tint: "#EAF6EC", isIncome: true),
        .init(key: "otherIncome.interest", parentKey: "otherIncome", name: "利息", icon: "Bank", emoji: "🏦", tint: "#EAF6EC", isIncome: true),
        .init(key: "otherIncome.parttime", parentKey: "otherIncome", name: "兼职", icon: "Bank", emoji: "💼", tint: "#EAF6EC", isIncome: true),
    ]

    /// 按 key 取内置规格。
    static func builtIn(key: String) -> BuiltIn? {
        builtIn.first { $0.key == key }
    }
}
