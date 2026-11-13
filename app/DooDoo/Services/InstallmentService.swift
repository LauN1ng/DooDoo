import Foundation
import SwiftData

/// 分期计划的写入入口（M3-2）。
///
/// **它动余额**（2026-11-13 口径统一起）。计划里的债必须进 `currentBalance`——
/// 余额是唯一真相，分期不再靠第二套派生去补金额，否则「我欠」永远看不见这笔债。
///
/// 唯一例外是 `createdFromEntry`：那种计划由「记一笔」的全额 `expense` 入账，
/// 这里再入一次就是双份。
///
/// 仍然遵守 AGENTS 7.2：改余额一律走 `LedgerService`，本文件不直接赋值。
///
/// 建计划时顺手把未来每一期落库（PRD 9.5.4）：已还的历史只存汇总，
/// 未来逐期存，因为任意一期都可能被账单改正（9.5.5）。
@MainActor
enum InstallmentService {

    /// 建一张分期计划，并展开未来逐期。
    ///
    /// 参数全部来自 `InstallmentIntake` 的换算结果，这里不重新解释业务口径。
    ///
    /// - `totalPeriods` / `paidPeriods`：由 `InstallmentIntake.periods(remaining:total:)` 得来
    /// - `remainingDue`：账单上的「分期剩余应还」，**金额的权威来源**。给了它，
    ///   期表按它摊平、余数落首期
    /// - `lastPeriodAmount`：账单最后一期的金额（选填）。给了它，期表改走
    ///   `splitEndingAt` 反推中间各期，末期用真值——末期抵了减免的账单只有这条路算得准
    /// - `remainingInterest`：账单把利息单列时的**剩余期**利息（e招贷 851.57）。
    ///   给了它，年化改走剩余口径（见 `Installment.estimatedAnnualRate`），不吃整笔公式
    /// - `createdFromEntry`：这张计划是不是在「记一笔」里跟消费一起建的（M3-10）。
    ///   那种计划的消费已按全额记了 `expense`，**所以这里不再重复入账**。
    ///   语义在 2026-11-13 口径统一时反转：从「我欠别算我」变成「我已经入过账了」
    /// - `iconName`：列表展示用，默认 `Receipt`（bundle 里的 Fluent3D PNG 名）
    ///
    /// 边界：`remaining <= 0` 时仍建计划但**不生成期表**（已还清的历史分期，
    /// 保留它是为了账户详情里还能看到这张表）。
    @discardableResult
    static func insert(
        name: String,
        account: Account?,
        totalPeriods: Int,
        paidPeriods: Int,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        remainingDue: Decimal? = nil,
        totalInterest: Decimal? = nil,
        remainingInterest: Decimal? = nil,
        totalRebate: Decimal? = nil,
        nextDueDate: Date,
        createdFromEntry: Bool = false,
        iconName: String = "Receipt",
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> Installment {
        let plan = Installment(
            key: UUID().uuidString,
            name: name,
            account: account,
            totalPeriods: max(0, totalPeriods),
            paidPeriods: max(0, min(paidPeriods, max(0, totalPeriods))),
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount,
            remainingDue: remainingDue,
            totalInterest: totalInterest,
            remainingInterest: remainingInterest,
            totalRebate: totalRebate,
            nextDueDate: calendar.startOfDay(for: nextDueDate),
            createdFromEntry: createdFromEntry,
            iconName: iconName
        )
        context.insert(plan)
        try generateFuturePeriods(for: plan, calendar: calendar, in: context)

        // 债务入账（2026-11-13）：把「剩余应还」写进账户余额。
        //
        // 为什么必须有这一步：欠款 = max(0, −余额)，分期若只登记不入账，
        // 详情页看得见 3,852.15 的期表，资产页却说欠 0。
        //
        // 为什么 `createdFromEntry` 跳过：那种消费已按 PRD 9.5.6 记了**全额** `expense`，
        // 余额里已经有了；再入一次会让 1,440.39 变成 2,880.78。
        if !createdFromEntry, let account, let due = plan.remainingDue, due > 0 {
            try LedgerService.adjustAccountBalance(
                account,
                to: account.currentBalance - due,
                in: context
            )
        }

        try context.save()
        return plan
    }

    /// 把库里已存在、但从未入账的分期计划一次性计入余额（2026-11-13 口径切换的迁移）。
    ///
    /// 切换前分期只记「欠多少、什么时候还」，金额靠 `CardDebt` 事后补；切换后欠款只读余额，
    /// 所以这批计划必须补一次入账，否则它们成为僵尸数据——期表在，金额不在。
    ///
    /// - 幂等：跑完在 `UserDefaults` 写标记，重复调用直接返回 0。
    /// - `createdFromEntry` 跳过（消费全额已在余额里）。
    /// - 同卡多笔计划先求和再一次入账，避免每笔都触发一次全表重算。
    ///
    /// 返回受影响的账户数。
    @discardableResult
    static func backfillDebtBaseline(in context: ModelContext) throws -> Int {
        let flag = "doodoo.creditDebt.backfill.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return 0 }

        let plans = try context.fetch(FetchDescriptor<Installment>())
        var owedByAccount: [PersistentIdentifier: Decimal] = [:]
        for plan in plans where !plan.createdFromEntry {
            guard plan.remainingDue != nil, plan.remainingTotal > 0 else { continue }
            guard let account = plan.account else { continue }
            owedByAccount[account.persistentModelID, default: 0] += plan.remainingTotal
        }

        var affected = 0
        for account in try context.fetch(FetchDescriptor<Account>()) {
            guard let owed = owedByAccount[account.persistentModelID], owed > 0 else { continue }
            try LedgerService.adjustAccountBalance(
                account,
                to: account.currentBalance - owed,
                in: context
            )
            affected += 1
        }

        UserDefaults.standard.set(true, forKey: flag)
        if affected > 0 { try context.save() }
        return affected
    }

    /// 给「记一笔里跟消费一起建」的分期补上 `Transaction.installmentKey`。
    ///
    /// M3-10 建计划时没把 key 写回那条全额消费流水，于是账户详情页的「本期消费」
    /// 把分期本金全额也算了一笔——白条那屏 5,999 的分期让「本期消费 6,049.00」
    /// 与「本月分期 533.33」并排，两列相加没有任何意义（规格 8.1 要求不含分期本金）。
    ///
    /// 匹配是**严格的**，宁可漏补也不误标：
    /// - 同账户、`kind == .expense`、未软删、还没绑过任何计划
    /// - 金额等于该计划的**当前剩余总额**（没有还款时就是原始全额）
    /// - 日期与 `createdAt` 同一天
    /// - 候选必须**恰好一笔**，否则跳过
    ///
    /// 已经还过款的计划匹配不上（剩余总额变小了），会原样留着——那种情况下
    /// 「本期消费」仍会多算一笔本金，但不至于把无关消费标成分期。
    static func backfillEntryPrincipalKeys(in context: ModelContext) throws -> Int {
        let flag = "doodoo.entryPrincipalKeys.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return 0 }

        let plans = try context.fetch(FetchDescriptor<Installment>()).filter(\.createdFromEntry)
        guard !plans.isEmpty else {
            UserDefaults.standard.set(true, forKey: flag)
            return 0
        }

        let txs = try context.fetch(FetchDescriptor<Transaction>())
        var linked = Set(txs.compactMap(\.installmentKey))
        let calendar = Calendar.current
        var affected = 0

        for plan in plans where !linked.contains(plan.key) {
            guard let account = plan.account else { continue }
            let target = plan.remainingTotal
            guard target > 0 else { continue }
            let createdDay = calendar.startOfDay(for: plan.createdAt)

            let candidates = txs.filter { tx in
                tx.deletedAt == nil
                    && tx.kind == .expense
                    && tx.installmentKey == nil
                    && tx.account?.persistentModelID == account.persistentModelID
                    && tx.amount == target
                    && calendar.startOfDay(for: tx.date) == createdDay
            }
            // 同一天同金额买了两笔一样的，就分不清哪笔是分期的——不猜。
            guard candidates.count == 1, let tx = candidates.first else { continue }
            tx.installmentKey = plan.key
            linked.insert(plan.key)
            affected += 1
        }

        UserDefaults.standard.set(true, forKey: flag)
        if affected > 0 { try context.save() }
        return affected
    }

    /// 把 M3-2 时期误填进 `remainingPrincipal` 的「剩余应还」搬到 `remainingDue`。
    ///
    /// M3-2 的表单有「剩余本金」一栏，但账单上根本没有这个数——用户 11-11 把
    /// 「分期剩余应还 1830.15」填了进去，而 `203.35 × 9` 恰好也是 `1830.15`，
    /// 于是年化被判成「零息」输出 0.0%。
    ///
    /// M3-3 改了表单，那条老数据还挂着旧字段：
    /// - 年化已经自愈（`estimatedAnnualRate` 不再读 `remainingPrincipal`）
    /// - 但剩余总额仍按「每期 × 期数 + 首期差额」算，跟账单差几分钱
    ///
    /// 这里按计划幂等搬一次：只要 `remainingDue` 为空、`remainingPrincipal` 有值，
    /// 就视为用户当时抄的就是剩余应还。
    ///
    /// 为什么这个假定安全：`remainingPrincipal` 只在存量录入界面出现过，而那一栏的
    /// 占位文案是「账单上的欠款」——用户唯一的填法就是抄「剩余应还」。
    /// 零息分期（本金恰好等于还款总额）搬过去也等价，不会产出错误数字。
    ///
    /// 同时清掉 `firstPeriodAmount`：旧表单里填的是**历史**第 1 期（如 203.43），
    /// 它不该再覆盖未来第一期——未来每期现在由 `remainingDue` 摊平得出。
    ///
    /// 返回搬迁的计划数；`0` 表示没有需要搬的（可重复调用）。
    @discardableResult
    static func migrateLegacyRemainingPrincipal(
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> Int {
        let plans = try context.fetch(FetchDescriptor<Installment>())
        var migrated = 0
        for plan in plans where plan.remainingDue == nil {
            guard let principal = plan.remainingPrincipal, principal > 0 else { continue }
            plan.remainingDue = principal
            plan.remainingPrincipal = nil
            plan.firstPeriodAmount = nil
            // 旧表单的「末期金额」语义不明（可能是整笔末期，也可能是历史某期），
            // M3-5 起这个字段会被当真值用，所以老数据一律清掉——期表回到均摊，
            // 与迁移前行为一致，不引入新数字。
            plan.lastPeriodAmount = nil
            migrated += 1
            try generateFuturePeriods(for: plan, calendar: calendar, in: context)
        }
        if migrated > 0 { try context.save() }
        return migrated
    }

    /// 按计划的「剩余期数 + 下一期还款日 + 每期金额」展开未来逐期，写进 `InstallmentPeriod`。
    ///
    /// **可重复调用**（重新生成）：
    /// - 用户手工改过的那几期（`isManualOverride`）**保留不动**——那是照账单改的，
    ///   重新生成不该抹掉（PRD 9.5.5）
    /// - 其余旧的自动期先删再生，避免同一期出现两条
    ///
    /// 返回写入的期数。
    @discardableResult
    static func generateFuturePeriods(
        for plan: Installment,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> Int {
        let existing = try periods(for: plan.key, in: context)
        let overridden = existing.filter(\.isManualOverride)

        // 自动生成的那些先删掉：重建比「逐条比对」简单，且期数最多几十条。
        for period in existing where !period.isManualOverride {
            context.delete(period)
        }

        let takenIndexes = Set(overridden.map(\.index))
        let fresh = plan.futurePeriods(calendar: calendar)
            .filter { !takenIndexes.contains($0.index) }

        for period in fresh {
            context.insert(InstallmentPeriod(
                installmentKey: plan.key,
                index: period.index,
                dueDate: period.dueDate,
                amount: period.amount
            ))
        }
        // 删改要立刻落盘：调用方紧接着可能再读期表（重新生成、单测），
        // 挂起的 delete 在同一上下文里读回来的行为不保证是「已删」。
        try context.save()
        return fresh.count
    }

    /// 某张计划的全部期（按 index 升序）。
    ///
    /// 用内存过滤而不是 `#Predicate`：期表规模是「计划数 × 期数」，几十到几百条，
    /// 且只在新建设计时调一次；`#Predicate` 宏在本工作区无法编译验证（同
    /// `LedgerService.softDelete` 的取舍）。
    static func periods(for installmentKey: String, in context: ModelContext) throws -> [InstallmentPeriod] {
        try context.fetch(FetchDescriptor<InstallmentPeriod>())
            .filter { $0.installmentKey == installmentKey }
            .sorted { $0.index < $1.index }
    }

    /// 已录入的分期笔数，用于「还差 N 笔」。
    ///
    /// 直接数库里的计划，不另存一个计数器——两套计数迟早分叉。
    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Installment>())
    }

    /// 最近录入的那张计划挂的账户，作为下一笔的默认账户（快速连录「保留上一条账户」）。
    ///
    /// 58 笔花呗分期基本都挂同一张卡，让用户每笔重选 58 次纯浪费。
    /// 没有历史时返回 `nil`，由调用方退回第一张信用/借款卡。
    static func mostRecentAccount(in context: ModelContext) throws -> Account? {
        let plans = try context.fetch(
            FetchDescriptor<Installment>(sortBy: [SortDescriptor(\Installment.createdAt, order: .reverse)])
        )
        return plans.first { $0.account != nil }?.account
    }
}
