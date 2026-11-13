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
    /// v3：分类改两级（一级 10 + 二级 51），流水挂到二级。
    static let currentSeedVersion = 3

    /// 首页与资产页启动时调这一个：版本迁移 → 补图标 → 补缺失分类 → 重算余额。
    static func prepare(context: ModelContext, calendar: Calendar = .current) throws {
        let settings = try ensureSettings(context)
        if settings.seedVersion < currentSeedVersion {
            try wipeDemoData(context)
            try seedV3(context, calendar: calendar)
            settings.seedVersion = currentSeedVersion
            settings.updatedAt = .now
            try context.save()
        }
        try backfillIcons(context: context)
        try ensureBuiltInCategories(context: context)
        try LedgerService.recalculateAll(in: context)
        // M3-3：老分期把「剩余应还」误存在「剩余本金」里，搬回来。
        // **必须排在 backfill 之前**——2026-11-13 起分期要入账，而 backfill 只认
        // `remainingDue`；先搬字段，才有东西可入。
        try InstallmentService.migrateLegacyRemainingPrincipal(calendar: calendar, in: context)
        // 2026-11-13 口径切换：库里已存在的分期一次性计入余额。
        // 排在符号归一之前——入账后这些卡余额变负，`normalizeLiabilitySigns`
        // 就不会把它们当成「正余额异常」再翻一次符号。幂等标记在方法内部。
        try InstallmentService.backfillDebtBaseline(in: context)
        try normalizeLiabilitySigns(context: context)
    }

    /// 数据修复（2026-11-09 真机反馈 #8，推荐方案 A）。
    ///
    /// 早期 `AccountEditor` 把「欠 600」存成 `currentBalance = +600`，于是还款页
    /// `maxDebt` 取 0、金额带出 0.00、主按钮一直禁用。语义上信用 / 借款账户的
    /// 欠款必须为负（见 `Account.currentBalance` 注释），所以把正余额的负债账户
    /// 校准到它的相反数。
    ///
    /// - 必须走 `LedgerService.adjustAccountBalance`：`currentBalance` 是派生值，
    ///   直接赋值会在下一次 `recalculateAll` 被覆盖（AGENTS 7.2）。
    /// - 幂等：纠正后余额为负，下次启动不再命中，不需要额外的版本标记。
    /// - 边界 1：0 不纠正（已还清）；储蓄 / 现金账户不动。
    /// - 边界 2：**多还款产生的正余额（溢缴）是合法状态**（见
    ///   `TransferMath.balanceAfterRepay`），不能翻回欠款。这类账户必然有未软删的
    ///   还款流水，用「有没有还款流水」区分，不加持久化标记、不改数据模型。
    ///   只有存在疑似错误账户时才扫一次流水表，正常启动零额外开销。
    static func normalizeLiabilitySigns(context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let suspicious = accounts.filter { $0.kind.isLiability && $0.currentBalance > 0 }
        guard !suspicious.isEmpty else { return }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let repaidIDs = Set(
            transactions
                .filter { $0.kind == .repayment && $0.deletedAt == nil }
                .compactMap { $0.toAccount?.persistentModelID }
        )

        for account in suspicious where !repaidIDs.contains(account.persistentModelID) {
            try LedgerService.adjustAccountBalance(
                account,
                to: -account.currentBalance,
                in: context
            )
        }
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

    /// (天数偏移, 时, 分, 商户, 分类 key, 账户短名对应的账户名, 金额, 图标)
    /// 分类 key 是**二级**（`food.coffee`）——流水挂二级，一级由 `parentKey` 反查。
    private typealias SeedTx = (Int, Int, Int, String, String, String, String, String)

    private static let seedTransactions: [SeedTx] = [
        (0, 12, 10, "好利来", "food.snack", "花呗", "32.00", "Croissant"),
        (0, 12, 40, "地铁", "transport.metro", "建设银行储蓄卡 5044", "4.00", "Metro"),
        (0, 13, 5, "麦富迪猫粮", "social.pet", "京东白条", "129.00", "CatFace"),
        (0, 8, 20, "星巴克", "food.coffee", "花呗", "28.00", "HotBeverage"),
        (0, 18, 30, "滴滴", "transport.taxi", "招商银行信用卡 8857", "19.50", "Taxi"),
        (0, 12, 0, "工作午餐", "food.lunch", "微信余额", "26.00", "CookedRice"),
        (0, 20, 15, "日用补货", "wear.top", "余额宝", "63.00", "TShirt"),
        (0, 21, 40, "手游充值", "fun.game", "花呗", "30.00", "Joystick"),
        (1, 9, 5, "星巴克", "food.coffee", "花呗", "28.00", "HotBeverage"),
        (1, 19, 20, "滴滴", "transport.taxi", "招商银行信用卡 8857", "19.50", "Taxi"),
        (2, 15, 45, "麦富迪猫粮", "social.pet", "京东白条", "129.00", "CatFace"),
        (3, 10, 30, "好利来", "food.breakfast", "花呗", "26.00", "Bread"),
        (3, 8, 50, "地铁", "transport.metro", "建设银行储蓄卡 5044", "4.00", "Metro"),
        (5, 18, 0, "朋友聚餐", "food.dinner", "微信余额", "186.00", "SteamingBowl"),
        (5, 20, 30, "电影票", "fun.movie", "花呗", "76.00", "FilmFrames"),
        (6, 22, 10, "打车回家", "transport.taxi", "支付宝余额", "33.00", "Taxi"),
    ]

    private static func seedV3(_ context: ModelContext, calendar: Calendar) throws {
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

    /// 建内置分类，返回 `key → Category`（父与子一次建完，顺序即 `builtIn` 数组顺序）。
    private static func makeCategories(context: ModelContext) -> [String: Category] {
        var map: [String: Category] = [:]
        for (index, item) in Category.builtIn.enumerated() {
            let category = Category(
                key: item.key,
                parentKey: item.parentKey,
                name: item.name,
                iconName: item.icon,
                emoji: item.emoji,
                sortOrder: index,
                isIncome: item.isIncome,
                tintHex: item.tint
            )
            context.insert(category)
            map[item.key] = category
        }
        return map
    }

    /// 老库补齐：分类缺 key / 图标时按内置规格回填；流水缺图标时按商户名或分类回填。
    ///
    /// M1 时期建的分类没有 `key`，这里按名字找回（优先匹配一级，避免「红包」这类同名二级误配）。
    /// - 2026-11-10 起同时负责**图标改版对齐**：内置分类按 `key` 直接对齐 `builtIn`
    ///   的图标与底色，老库里还指向退役图标的流水改挂到所属分类的新图标
    ///   （v1 分类不可改名/删除，覆盖是安全的；`retiredIcons` 之外的按笔图标保留）。
    static func backfillIcons(context: ModelContext) throws {
        var dirty = false

        let specs = Dictionary(uniqueKeysWithValues: Category.builtIn.map { ($0.key, $0) })
        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories {
            // 有 key 的直接按规格对齐（M1b 之后建的库都走这条）
            if !category.key.isEmpty, let spec = specs[category.key] {
                if category.iconName != spec.icon { category.iconName = spec.icon; dirty = true }
                if category.tintHex != spec.tint { category.tintHex = spec.tint; dirty = true }
                continue
            }

            // M1 时期没有 key：按名字找回（优先匹配一级，避免「红包」这类同名二级误配）
            guard let spec = Category.builtIn.first(where: { $0.parentKey == nil && $0.name == category.name })
                    ?? Category.builtIn.first(where: { $0.name == category.name }) else { continue }
            if category.key.isEmpty {
                category.key = spec.key
                category.parentKey = spec.parentKey
            }
            if category.iconName != spec.icon { category.iconName = spec.icon }
            if category.tintHex != spec.tint { category.tintHex = spec.tint }
            dirty = true
        }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        for tx in transactions {
            if tx.iconName == nil {
                if let note = tx.note, let icon = noteIcons[note] {
                    tx.iconName = icon
                } else {
                    tx.iconName = tx.category?.iconName
                }
                dirty = true
            } else if let name = tx.iconName, retiredIcons.contains(name) {
                tx.iconName = tx.category?.iconName
                dirty = true
            }
        }

        if dirty { try context.save() }
    }

    /// 补建老库缺失的内置分类（2026-11-11）。
    ///
    /// 背景：`2e78a16` 把二级从 48 加到 51（新增 `home.water` 住/水费、
    /// `transport.plane` 行/飞机、`transport.ship` 行/轮船），但 `currentSeedVersion`
    /// **没有跟着 +1**。老库 `seedVersion == 3` 不满足 `< currentSeedVersion`，
    /// 于是跳过 `seedV3`；而 `backfillIcons` 只对齐**已有**分类的图标与底色，不创建新条目。
    /// 结果是覆盖安装后「住」下面没有「水费」、「行」下面没有「飞机」「轮船」——
    /// 同一个 App，老库比新装少三个二级分类槽位。
    ///
    /// 为什么不升 `currentSeedVersion` 让它重建：升版本会走 `wipeDemoData`
    /// 清空全部流水与账户。M2b 起用户已在真机记真实账目，重建会丢账。
    /// 这里只按 `key` 补缺失项，幂等，重复调用无副作用。
    ///
    /// `sortOrder` 取 `builtIn` 下标（与 `makeCategories` 同一口径），
    /// 保证补进去的分类落在正确位置，而不是排到父类末尾。
    ///
    /// 顺序约束：必须在 `backfillIcons` **之后**调用。M1 老库的分类没有 `key`，
    /// 要先由 `backfillIcons` 按名字补出 `key`，否则这里会把它们全判成缺失、重复插入一份。
    static func ensureBuiltInCategories(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Category>())
        let existingKeys = Set(existing.map(\.key).filter { !$0.isEmpty })
        guard existingKeys.count < Category.builtIn.count else { return }

        var inserted = false
        for (index, item) in Category.builtIn.enumerated() where !existingKeys.contains(item.key) {
            context.insert(Category(
                key: item.key,
                parentKey: item.parentKey,
                name: item.name,
                iconName: item.icon,
                emoji: item.emoji,
                sortOrder: index,
                isIncome: item.isIncome,
                tintHex: item.tint
            ))
            inserted = true
        }
        if inserted { try context.save() }
    }

    /// 2026-11-10 换图标后不再作为分类默认值的 5 张。
    /// 老库的流水若还指着它们，启动时改挂到所属分类的新图标；图片本身仍留在包里兜底。
    private static let retiredIcons: Set<String> = ["BentoBox", "Cat", "GameDie", "House", "ShoppingBags"]

    /// 演示数据里「商户名 → 图标」，取自 `home-v1.0.html`。
    private static let noteIcons: [String: String] = [
        "好利来": "Croissant",
        "地铁": "Metro",
        "麦富迪猫粮": "CatFace",
        "星巴克": "HotBeverage",
        "滴滴": "Taxi",
        "工作午餐": "CookedRice",
        "日用补货": "TShirt",
        "手游充值": "Joystick",
        "朋友聚餐": "SteamingBowl",
        "电影票": "FilmFrames",
        "打车回家": "Taxi",
    ]
}
