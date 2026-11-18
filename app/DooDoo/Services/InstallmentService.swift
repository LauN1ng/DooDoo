import Foundation
import SwiftData

/// 分期计划的写入入口（M3-2）。
///
/// **它动余额**（2026-11-13 口径统一起）。计划里的债必须进 `currentBalance`——
/// 余额是唯一真相，分期不再靠第二套派生去补金额，否则「我欠」永远看不见这笔债。
///
/// **怎么动：2026-11-17 起改成落一条可见的债务流水**（`.adjustment`）。
///
/// 之前是 `LedgerService.adjustAccountBalance(to: currentBalance - due)`，
/// 也就是**反推 `initialBalance`**。这条路有两个致命问题，用户 11-17 真机撞上了：
///
/// 1. **和「建卡时填的欠款」叠加**。用户在新建账户里填的 9,000 是「这张卡现在一共欠多少」，
///    那 9,000 里本来就已经包含未还的分期；再录分期又把 3,000 减一次 → 12,000。
///    两个入口写同一个数，却互不知情。
/// 2. **变化没有时间点**。改 `initialBalance` 等于「从开天辟地起就欠这么多」，
///    所以走势曲线原地下移（看不出今天多了 3,000），也无法回答「这 12,000 怎么来的」。
///
/// 改成流水之后：余额 = 期初 + Σ流水 恒成立；每一笔债在账户详情里能找到出处；
/// 录错了能删那一条；删计划能级联删流水。
///
/// 三条跳过入账的情形（都意味着「这笔债已经在我账上了」）：
/// - `createdFromEntry`：记一笔里建的，那条全额 `expense` 已入账（PRD 9.5.6）
/// - `debtAlreadyInBalance`：用户勾了「这笔债已在账户欠款里」——存量补录的主路径
/// - `remainingDue` 为 nil 或 ≤ 0：没有金额可入
@MainActor
enum InstallmentService {

    /// 债务登记流水的备注前缀。账户详情据此把这批流水标成「分期登记」。
    static let debtNotePrefix = "分期登记 · "

    /// 建一张分期计划，并展开未来逐期。
    ///
    /// 参数全部来自 `InstallmentIntake` 的换算结果，这里不重新解释业务口径。
    ///
    /// - `totalPeriods` / `paidPeriods`：由 `InstallmentIntake.periods(remaining:total:)` 得来
    /// - `remainingDue`：账单上的「分期剩余应还」，**金额的权威来源**。给了它，
    ///   期表按它摊平、余数落首期
    /// - `totalAmount`：账单上的「分期总额」（花呗 1,440.39）。选填——给了它，
    ///   「整笔」与「已还」就是账单真值；不给则按「每期 × 已还 + 剩余应还」推算并标「约」
    ///   （首期有零头时会差几分，推不出来）
    /// - `lastPeriodAmount`：账单最后一期的金额（选填）。给了它，期表改走
    ///   `splitEndingAt` 反推中间各期，末期用真值——末期抵了减免的账单只有这条路算得准
    /// - `remainingInterest`：账单把利息单列时的**剩余期**利息（e招贷 851.57）。
    ///   给了它，年化改走剩余口径（见 `Installment.estimatedAnnualRate`），不吃整笔公式
    /// - `createdFromEntry`：这张计划是不是在「记一笔」里跟消费一起建的（M3-10）。
    ///   那种计划的消费已按全额记了 `expense`，**所以这里不再重复入账**。
    ///   语义在 2026-11-13 口径统一时反转：从「我欠别算我」变成「我已经入过账了」
    /// - `debtAlreadyInBalance`：用户明确表示**这笔债已经包含在账户现有欠款里**了
    ///   （2026-11-17 新增）。存量补录的主路径：建卡时填的「欠款」是账单上的总额，
    ///   里面本来就有未还分期，再入一次就是双计。勾了它 = 只登记计划、不碰余额。
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
        totalAmount: Decimal? = nil,
        totalInterest: Decimal? = nil,
        remainingInterest: Decimal? = nil,
        totalRebate: Decimal? = nil,
        nextDueDate: Date,
        createdFromEntry: Bool = false,
        debtAlreadyInBalance: Bool = false,
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
            totalAmount: totalAmount,
            totalInterest: totalInterest,
            remainingInterest: remainingInterest,
            totalRebate: totalRebate,
            nextDueDate: calendar.startOfDay(for: nextDueDate),
            createdFromEntry: createdFromEntry,
            iconName: iconName
        )
        context.insert(plan)
        try generateFuturePeriods(for: plan, calendar: calendar, in: context)

        // 债务入账（2026-11-17 改：落一条可见流水，不再反推 initialBalance）
        //
        // 为什么必须有这一步：欠款 = max(0, −余额)，分期若只登记不入账，
        // 详情页看得见期表，资产页却说欠 0。
        //
        // 为什么是 `.adjustment` 而不是改 initialBalance：余额是派生值，
        // 任何改动都必须有一条流水作为出处，否则「我欠」的构成无从回溯、
        // 走势曲线也没有时间点（见本文件顶部注释里的两条真机事故）。
        if !createdFromEntry, !debtAlreadyInBalance,
           let account, let due = plan.remainingDue, due > 0 {
            try LedgerService.insert(
                amount: due,
                kind: .adjustment,
                date: plan.createdAt,
                note: debtNotePrefix + plan.name,
                account: account,
                installmentKey: plan.key,
                in: context
            )
        }

        try context.save()
        return plan
    }

    /// 把 2026-11-13 那一版「分期入账」从 `initialBalance` 里拆出来，改记成流水。
    ///
    /// **为什么必须迁移**：11-13 版把 `remainingDue` 直接减进 `initialBalance`，
    /// 等于「从开天辟地起这张卡就多欠这么多」。迁到流水之后：
    /// - 余额**不变**（`initial += due` 与新增的 −due 流水正好抵消，用户不会看到数字跳）
    /// - 但构成变得可解释：期初欠款 + 分期登记，各占一行
    /// - 走势曲线也终于有时间点了
    ///
    /// **它不负责去重**。如果那笔债本来就在用户填的期初欠款里（本次真机事故的形态），
    /// 拆出来之后总额仍然是「期初 + 分期」——只是现在用户能看见这两块，
    /// 由他自己判断期初该填多少（重填一次「欠款」就会把差额吸收回 `initialBalance`）。
    /// 自动去重就是猜，猜错等于替他改账。
    ///
    /// 幂等：`UserDefaults` 标记 + 逐计划检查是否已有对应流水（双保险，
    /// 因为标记一旦被清掉就会重复加 `initialBalance`）。
    ///
    /// 返回被迁移的计划数。
    @discardableResult
    static func migrateDebtToRows(in context: ModelContext) throws -> Int {
        let flag = "doodoo.installmentDebt.rows.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return 0 }

        let plans = try context.fetch(FetchDescriptor<Installment>())
        guard !plans.isEmpty else {
            UserDefaults.standard.set(true, forKey: flag)
            return 0
        }

        // 已经带债务流水的计划不再动（新装的库走 `insert` 写的就是流水）。
        let booked = Set(
            try context.fetch(FetchDescriptor<Transaction>())
                .filter { $0.deletedAt == nil && $0.kind == .adjustment }
                .compactMap(\.installmentKey)
        )

        var migrated = 0
        for plan in plans where !plan.createdFromEntry {
            guard !booked.contains(plan.key) else { continue }
            guard plan.remainingDue != nil, plan.remainingTotal > 0 else { continue }
            guard let account = plan.account else { continue }

            let amount = plan.remainingTotal
            // 还回旧版误减进期初的那一份，再补一条等额的流水：余额净变化为 0。
            account.initialBalance += amount
            try LedgerService.insert(
                amount: amount,
                kind: .adjustment,
                date: plan.createdAt,
                note: debtNotePrefix + plan.name,
                account: account,
                installmentKey: plan.key,
                in: context
            )
            migrated += 1
        }

        // `initialBalance` 被直接改过，必须整体重算一次，
        // 否则 `currentBalance` 与「期初 + Σ流水」会分叉。
        if migrated > 0 {
            try LedgerService.recalculateAll(in: context)
        }
        UserDefaults.standard.set(true, forKey: flag)
        return migrated
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
