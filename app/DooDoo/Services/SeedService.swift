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

        // (天数偏移, 时刻, 商户, 分类名, 账户名, 金额字符串)
        let rows: [(Int, Int, Int, String, String, String, String)] = [
            (0, 12, 10, "好利来", "吃", "花呗", "32.00"),
            (0, 12, 40, "地铁", "行", "建行5044", "4.00"),
            (0, 13, 5, "麦富迪猫粮", "情", "白条", "129.00"),
            (0, 8, 20, "星巴克", "吃", "花呗", "28.00"),
            (0, 18, 30, "滴滴", "行", "招行8857", "19.50"),
            (0, 12, 0, "工作午餐", "吃", "微信", "26.00"),
            (0, 20, 15, "日用补货", "穿", "余额宝", "63.00"),
            (0, 21, 40, "手游充值", "乐", "花呗", "30.00"),
            (1, 9, 5, "星巴克", "吃", "花呗", "28.00"),
            (1, 19, 20, "滴滴", "行", "招行8857", "19.50"),
            (2, 15, 45, "麦富迪猫粮", "情", "白条", "129.00"),
            (3, 10, 30, "好利来", "吃", "花呗", "26.00"),
            (3, 8, 50, "地铁", "行", "建行5044", "4.00"),
            (5, 18, 0, "朋友聚餐", "吃", "微信", "186.00"),
            (5, 20, 30, "电影票", "乐", "花呗", "76.00"),
            (6, 22, 10, "打车回家", "行", "滴滴", "33.00"),
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
