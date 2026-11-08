import Foundation
import SwiftData

/// 首次启动写入演示数据。
///
/// 数据取自 `design/current/home-v1.0.html` 的 7 天样例（金额、商户、分类、账户都照抄），
/// 日期按「今天」相对生成，保证首页永远有 7 天可翻。
///
/// **这不是用户数据**：只是为了 M1 能看见东西。记一笔做好后由用户覆盖，
/// 到时候在设置页给一个「清除演示数据」的入口（未做，记在 PROGRESS）。
@MainActor
enum SeedService {
    /// 首页启动时调这一个就够：先补种子，再修老数据的图标。
    static func prepare(context: ModelContext) throws {
        try seedIfNeeded(context: context)
        try backfillIcons(context: context)
    }

    /// 老版本装过的库没有 Fluent3D 图标名，这里按分类与商户名补齐，
    /// 免得升级后仍然显示系统 emoji。
    static func backfillIcons(context: ModelContext) throws {
        var dirty = false

        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories where category.iconName.isEmpty {
            if let spec = Category.builtIn.first(where: { $0.name == category.name }) {
                category.iconName = spec.icon
                dirty = true
            }
        }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        for tx in transactions where tx.iconName == nil {
            if let note = tx.note, let icon = noteIcons[note] {
                tx.iconName = icon
            } else {
                tx.iconName = tx.category?.iconName
            }
            dirty = true
        }

        if dirty { try context.save() }
    }

    /// 演示数据里「商户名 → 图标」，取自 `home-v1.0.html`。
    private static let noteIcons: [String: String] = [
        "好利来": "Croissant",
        "地铁": "LightRail",
        "麦富迪猫粮": "Cat",
        "星巴克": "HotBeverage",
        "滴滴": "Taxi",
        "工作午餐": "BentoBox",
        "日用补货": "ShoppingBags",
        "手游充值": "GameDie",
        "朋友聚餐": "BentoBox",
        "电影票": "GameDie",
        "打车回家": "Taxi",
    ]

    static func seedIfNeeded(context: ModelContext, calendar: Calendar = .current) throws {
        let existing = try context.fetchCount(FetchDescriptor<Category>())
        guard existing == 0 else { return }

        let categories = makeCategories(context: context)
        let accounts = makeAccounts(context: context)

        let today = calendar.startOfDay(for: .now)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        }

        func at(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = day(offset)
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        // (天数偏移, 时刻, 商户, 分类名, 账户名, 金额, Fluent3D 图标名)
        // 图标按「这一笔是什么」选，不是按分类——照抄 home-v1.0.html 的配图。
        let rows: [(Int, Int, Int, String, String, String, String, String)] = [
            (0, 12, 10, "好利来", "吃", "花呗", "32.00", "Croissant"),
            (0, 12, 40, "地铁", "行", "建行5044", "4.00", "LightRail"),
            (0, 13, 5, "麦富迪猫粮", "情", "白条", "129.00", "Cat"),
            (0, 8, 20, "星巴克", "吃", "花呗", "28.00", "HotBeverage"),
            (0, 18, 30, "滴滴", "行", "招行8857", "19.50", "Taxi"),
            (0, 12, 0, "工作午餐", "吃", "微信", "26.00", "BentoBox"),
            (0, 20, 15, "日用补货", "穿", "余额宝", "63.00", "ShoppingBags"),
            (0, 21, 40, "手游充值", "乐", "花呗", "30.00", "GameDie"),
            (1, 9, 5, "星巴克", "吃", "花呗", "28.00", "HotBeverage"),
            (1, 19, 20, "滴滴", "行", "招行8857", "19.50", "Taxi"),
            (2, 15, 45, "麦富迪猫粮", "情", "白条", "129.00", "Cat"),
            (3, 10, 30, "好利来", "吃", "花呗", "26.00", "Croissant"),
            (3, 8, 50, "地铁", "行", "建行5044", "4.00", "LightRail"),
            (5, 18, 0, "朋友聚餐", "吃", "微信", "186.00", "BentoBox"),
            (5, 20, 30, "电影票", "乐", "花呗", "76.00", "GameDie"),
            (6, 22, 10, "打车回家", "行", "滴滴", "33.00", "Taxi"),
        ]

        for row in rows {
            let date = at(row.0, row.1, row.2)
            try LedgerService.insert(
                amount: decimal(row.6),
                kind: .expense,
                date: date,
                note: row.3,
                account: accounts[row.5],
                category: categories[row.4],
                iconName: row.7,
                in: context
            )
        }

        try context.save()
    }

    /// `Decimal(string:)` 比 `Decimal(Double)` 精确：后者会把 19.5 变成 19.499999…
    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func makeCategories(context: ModelContext) -> [String: Category] {
        var map: [String: Category] = [:]
        for (index, item) in Category.builtIn.enumerated() {
            let isIncome = item.name == "工资" || item.name == "其他收入"
            let category = Category(
                name: item.name,
                iconName: item.icon,
                emoji: item.emoji,
                sortOrder: index,
                isIncome: isIncome,
                tintHex: item.tint
            )
            context.insert(category)
            map[item.name] = category
        }
        return map
    }

    private static func makeAccounts(context: ModelContext) -> [String: Account] {
        let specs: [(String, AccountKind)] = [
            ("花呗", .credit),
            ("建行5044", .savings),
            ("白条", .credit),
            ("招行8857", .credit),
            ("微信", .savings),
            ("余额宝", .savings),
            ("滴滴", .savings),
        ]
        var map: [String: Account] = [:]
        for (name, kind) in specs {
            let account = Account(name: name, kind: kind)
            context.insert(account)
            map[name] = account
        }
        return map
    }
}
