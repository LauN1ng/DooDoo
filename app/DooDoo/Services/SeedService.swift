import Foundation
import SwiftData

/// 首次启动写入演示数据，并按版本号重建。
///
/// 账户清单照 `assets/brands/brands.json` 与 PRD 3.1 的真实画像（8 储蓄 + 9 信用 + 1 借款）；
/// 目标余额照资产页原型（信用合计 −28,466.00、储蓄合计 3,120.00、父母借款 −20,000）。
///
/// **这不是用户数据**：记一笔做好后由用户覆盖。改动种子结构时把 `currentSeedVersion` +1，
/// 老库会在启动时清空重建（M1 期间用户没有任何录入入口，重建是安全的）。
@MainActor
enum SeedService {
    static let currentSeedVersion = 2

    /// 首页与资产页启动时调这一个：版本迁移 → 补图标 → 重算余额。
    static func prepare(context: ModelContext, calendar: Calendar = .current) throws {
        let settings = try ensureSettings(context)
        if settings.seedVersion < currentSeedVersion {
            try wipeDemoData(context)
            try seedV2(context, calendar: calendar)
            settings.seedVersion = currentSeedVersion
            settings.updatedAt = .now
            try context.save()
        }
        try backfillIcons(context)
        try LedgerService.recalculateAll(in: context)
    }

    // MARK: - 版本迁移

    private static func ensureSettings(_ context: ModelContext) throws -> AppSettings {
        let all = try context.fetch(FetchDescriptor<AppSettings>())
        if let first = all.first { return first }
        let settings = AppSettings(seedVersion: 0)
        context.insert(settings)
        try context.save()
        return settings
    }

    private static func wipeDemoData(_ context: ModelContext) throws {
        // 先删流水再删账户，避免关系悬空
        try context.delete(model: Transaction.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.save()
    }

    // MARK: - 账户画像

    private struct SeedAccount {
        let name: String
        let shortName: String
        let brand: String
        let variant: Int
        let last4: String
        let kind: AccountKind
        let target: String          // 目标余额，建完后反推 initialBalance
        let limit: String?
        let originalLimit: String?
        let cycleStart: Int?
        let cycleEnd: Int?
        let dueDay: Int?
        let platform: String?
    }

    private static let seedAccounts: [SeedAccount] = [
        // 储蓄 8 个，合计 3,120.00
        .init(name: "建设银行储蓄卡 5044", shortName: "建行5044", brand: "ccb", variant: 0, last4: "5044", kind: .savings, target: "1204.30", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "建设银行"),
        .init(name: "建设银行储蓄卡 0565", shortName: "建行0565", brand: "ccb", variant: 1, last4: "0565", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "建设银行"),
        .init(name: "招商银行储蓄卡 0361", shortName: "招行0361", brand: "cmb", variant: 1, last4: "0361", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "招商银行"),
        .init(name: "招商银行储蓄卡（工资卡）", shortName: "工资卡", brand: "cmb", variant: 2, last4: "", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "招商银行"),
        .init(name: "余额宝", shortName: "余额宝", brand: "yuebao", variant: 0, last4: "", kind: .savings, target: "1915.70", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "支付宝"),
        .init(name: "支付宝余额", shortName: "支付宝", brand: "alipay", variant: 0, last4: "", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "支付宝"),
        .init(name: "微信余额", shortName: "微信", brand: "wechat", variant: 0, last4: "", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "微信支付"),
        .init(name: "京东小金库", shortName: "小金库", brand: "jdgold", variant: 0, last4: "", kind: .savings, target: "0", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: "京东"),

        // 信用 9 个，合计 −28,466.00
        .init(name: "招商银行信用卡 8857", shortName: "招行8857", brand: "cmb", variant: 0, last4: "8857", kind: .credit, target: "-3120.00", limit: "4600", originalLimit: "9000", cycleStart: 15, cycleEnd: 14, dueDay: 8, platform: "招商银行"),
        .init(name: "花呗", shortName: "花呗", brand: "huabei", variant: 0, last4: "", kind: .credit, target: "-7842.50", limit: "12000", originalLimit: nil, cycleStart: 15, cycleEnd: 14, dueDay: 25, platform: "支付宝"),
        .init(name: "花呗分期存量", shortName: "花呗分期", brand: "huabei", variant: 1, last4: "", kind: .credit, target: "-4000.00", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: 25, platform: "支付宝"),
        .init(name: "京东白条", shortName: "白条", brand: "baitiao", variant: 0, last4: "", kind: .credit, target: "-613.16", limit: "3000", originalLimit: nil, cycleStart: 16, cycleEnd: 15, dueDay: 2, platform: "京东"),
        .init(name: "白条分分卡（上海银行）", shortName: "分分卡", brand: "bosc", variant: 1, last4: "", kind: .credit, target: "-1500.00", limit: "5000", originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: 20, platform: "上海银行"),
        .init(name: "抖音月付", shortName: "抖音月付", brand: "douyin", variant: 0, last4: "", kind: .credit, target: "-1219.41", limit: "2000", originalLimit: nil, cycleStart: 16, cycleEnd: 15, dueDay: 15, platform: "抖音"),
        .init(name: "抖音放心借", shortName: "放心借", brand: "douyinloan", variant: 0, last4: "", kind: .credit, target: "-2500.00", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: 12, platform: "抖音"),
        .init(name: "e招贷（招行掌上生活）", shortName: "e招贷", brand: "ezhaodai", variant: 0, last4: "", kind: .credit, target: "-6670.93", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: 10, platform: "招商银行"),
        .init(name: "消费分期-中移金科", shortName: "中移金科", brand: "cmcc", variant: 0, last4: "", kind: .credit, target: "-1000.00", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: 18, platform: "中移金科"),

        // 借款 1 个，−20,000.00（PRD：20,000，无息，无固定期限）
        .init(name: "父母借款", shortName: "父母借款", brand: "loan-personal", variant: 0, last4: "", kind: .loan, target: "-20000.00", limit: nil, originalLimit: nil, cycleStart: nil, cycleEnd: nil, dueDay: nil, platform: nil),
    ]

    // MARK: - 流水

    /// (天数偏移, 时, 分, 商户, 分类, 账户短名对应的账户名, 金额, 图标)
    private typealias SeedTx = (Int, Int, Int, String, String, String, String, String)

    private static let seedTransactions: [SeedTx] = [
        (0, 12, 10, "好利来", "吃", "花呗", "32.00", "Croissant"),
        (0, 12, 40, "地铁", "行", "建设银行储蓄卡 5044", "4.00", "LightRail"),
        (0, 13, 5, "麦富迪猫粮", "情", "京东白条", "129.00", "Cat"),
        (0, 8, 20, "星巴克", "吃", "花呗", "28.00", "HotBeverage"),
        (0, 18, 30, "滴滴", "行", "招商银行信用卡 8857", "19.50", "Taxi"),
        (0, 12, 0, "工作午餐", "吃", "微信余额", "26.00", "BentoBox"),
        (0, 20, 15, "日用补货", "穿", "余额宝", "63.00", "ShoppingBags"),
        (0, 21, 40, "手游充值", "乐", "花呗", "30.00", "GameDie"),
        (1, 9, 5, "星巴克", "吃", "花呗", "28.00", "HotBeverage"),
        (1, 19, 20, "滴滴", "行", "招商银行信用卡 8857", "19.50", "Taxi"),
        (2, 15, 45, "麦富迪猫粮", "情", "京东白条", "129.00", "Cat"),
        (3, 10, 30, "好利来", "吃", "花呗", "26.00", "Croissant"),
        (3, 8, 50, "地铁", "行", "建设银行储蓄卡 5044", "4.00", "LightRail"),
        (5, 18, 0, "朋友聚餐", "吃", "微信余额", "186.00", "BentoBox"),
        (5, 20, 30, "电影票", "乐", "花呗", "76.00", "GameDie"),
        (6, 22, 10, "打车回家", "行", "支付宝余额", "33.00", "Taxi"),
    ]

    private static func seedV2(_ context: ModelContext, calendar: Calendar) throws {
        let categories = makeCategories(context: context)

        var accounts: [String: Account] = [:]
        for (index, spec) in seedAccounts.enumerated() {
            let account = Account(
                name: spec.name,
                kind: spec.kind,
                initialBalance: 0,
                brandId: spec.brand,
                variant: spec.variant,
                last4: spec.last4,
                networkLabel: BrandPalette.style(spec.brand).network,
                platform: spec.platform,
                shortName: spec.shortName,
                creditLimit: spec.limit.map { decimal($0) },
                originalLimit: spec.originalLimit.map { decimal($0) },
                billCycleStart: spec.cycleStart,
                billCycleEnd: spec.cycleEnd,
                dueDay: spec.dueDay,
                sortOrder: index
            )
            context.insert(account)
            accounts[spec.name] = account
        }
        try context.save()

        let today = calendar.startOfDay(for: .now)
        for row in seedTransactions {
            let day = calendar.date(byAdding: .day, value: -row.0, to: today) ?? today
            let date = calendar.date(bySettingHour: row.1, minute: row.2, second: 0, of: day) ?? day
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

        // 用目标余额反推 initialBalance——顺带把 recalculateAll 当断言跑一遍
        for spec in seedAccounts {
            guard let account = accounts[spec.name] else { continue }
            try LedgerService.adjustAccountBalance(account, to: decimal(spec.target), in: context)
        }
        try context.save()
    }

    // MARK: - 工具

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

    /// 老版本装过的库没有 Fluent3D 图标名，这里按分类与商户名补齐。
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
}
