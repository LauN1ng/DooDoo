import Foundation
import SwiftData

/// **启动时只做两件事**：保证内置分类存在、把旧版本遗留的数据升级到当前口径。
/// 从 v5 起**不写入任何业务数据**——不建账户、不建流水。
///
/// 历史：M1 时期这里铺过 18 个账户 + 16 笔流水，那是为了在没有录入入口的阶段
/// 看卡片与列表效果。2026-11-17 用户要求「从 0 开始体验全部功能」，种子整体下线。
@MainActor
enum SeedService {
    /// v5：**空库启动**（2026-11-17）。
    ///
    /// 用户原话「不对账户信息也清除，我从 0 开始体验全部功能」——他要走一遍
    /// 「资产页新建账户 → 记第一笔」的完整流程，所以账户与流水都不再预置。
    /// 唯一保留的是 51 个内置分类（`ensureBuiltInCategories` 负责），
    /// 因为没有分类就没有图标可选，记一笔会直接空着。
    ///
    /// v4：去掉演示流水，保留账户。
    /// v3：分类改两级（一级 10 + 二级 51），流水挂到二级。
    static let currentSeedVersion = 5

    /// 首页与资产页启动时调这一个：版本迁移 → 补图标 → 补缺失分类 → 重算余额。
    static func prepare(context: ModelContext, calendar: Calendar = .current) throws {
        let settings = try ensureSettings(context)
        if settings.seedVersion < currentSeedVersion {
            // 升级到 v5 的库：清掉旧种子留下的账户 / 流水 / 分期 / 账单，
            // 让用户从空白开始。分类由下面的 `ensureBuiltInCategories` 重建。
            try wipeDemoData(context)
            settings.seedVersion = currentSeedVersion
            settings.updatedAt = .now
            try context.save()
        }
        try backfillIcons(context: context)
        try ensureBuiltInCategories(context: context)
        try LedgerService.recalculateAll(in: context)
        // M3-3：老分期把「剩余应还」误存在「剩余本金」里，搬回来。
        // **必须排在债务迁移之前**——迁移按 `remainingDue` 算金额；
        // 先搬字段，才有数可迁。
        try InstallmentService.migrateLegacyRemainingPrincipal(calendar: calendar, in: context)
        // 2026-11-17：11-13 版把分期债直接减进 `initialBalance`，与建卡时填的欠款叠加、
        // 且没有时间点。这里把它拆成可见的「分期登记」流水（余额净变化为 0）。
        // 排在符号归一之前——迁移后这些卡余额仍是负的，`normalizeLiabilitySigns`
        // 不会把它们当成「正余额异常」再翻一次符号。幂等标记在方法内部。
        try InstallmentService.migrateDebtToRows(in: context)
        try normalizeLiabilitySigns(context: context)
        // M3-10 遗留：记一笔建的分期没把 key 写回那条全额消费流水，
        // 「本期消费」因此把分期本金全额也算进去了（白条 5,999）。
        // 它只补一个流水标记，不碰余额，排最后即可。
        try InstallmentService.backfillEntryPrincipalKeys(in: context)
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
        if let first = all.first {
            migrateAccentIfNeeded(first, context: context)
            return first
        }
        let settings = AppSettings(seedVersion: 0)
        context.insert(settings)
        try context.save()
        return settings
    }

    /// 一次性迁移：把旧默认主色 `ink` 换成 `green`（2026-11-16）。
    ///
    /// 用户在 M4 之前从没进设置页选过主色，`ink` 只是属性默认值被写进了库；
    /// 而记一笔界面「黑色太多」正是这个默认值造成的。标记放 `UserDefaults`，
    /// 幂等执行一次，之后用户若主动选回「墨」不会被再改。
    private static func migrateAccentIfNeeded(_ settings: AppSettings, context: ModelContext) {
        let key = "didMigrateAccentInkToGreen"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard settings.accentId == "ink" else { return }
        settings.accentId = AccentStyle.green.rawValue
        try? context.save()
    }

    private static func wipeDemoData(_ context: ModelContext) throws {
        // 依赖方先删：分期期表 → 分期 → 账单 → 流水 → 分类 → 账户。
        // v4 起清理范围补上了分期与账单——旧版只删后三个，库里若有分期计划会
        // 留下指向已删账户的悬空关系。
        try context.delete(model: InstallmentPeriod.self)
        try context.delete(model: Installment.self)
        try context.delete(model: BillStatement.self)
        try context.delete(model: Transaction.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.save()
    }

    // MARK: - 工具


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
    /// `sortOrder` 取 `builtIn` 下标（与 `Category.builtIn` 的顺序一致），
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
