import Foundation
import Observation
import SwiftData

/// 存量分期快速连录的状态与校验（M3-2，M3-3 改为「抄 3 个数」）。
///
/// **不碰 SwiftData 写入**——建计划交给 `InstallmentService`（AGENTS 7.4）。
///
/// 这个 ViewModel 的存在理由只有一个：**58 笔录入要像流水线**。
/// 所以它在每笔存完后故意**只清一半**：
/// - 清掉：名称、剩余应还、期数、含利息、减免（每笔都不一样，留着只会填错）
/// - 留着：账户、还款日（58 笔花呗分期基本共用同一张卡同一天，重选 58 次纯浪费）
///
/// M3-3 的字段收敛（用户 11-11 反馈「录入有点累」+「全部都填了也算不准」）：
/// 原来要填 8 个框，其中 3 个是账单上不存在的陷阱：
/// - **剩余本金**：账单只有含息的「剩余应还」，用户填进去就撞上「现值 = 总还款额」→ 年化 0.0%
/// - **首期/末期金额**：用户填的是历史第 1 期（203.43），而未来 9 期都是 203.35，差 0.08
///
/// 现在只填 4 个数：**剩余应还 / 剩余期数 / 总共几期 / 含利息**。
/// 每期金额由「剩余应还 ÷ 期数」派生（余数自动落末期），还款日由账户带出。
/// 派生值全部走 `InstallmentMath` / `InstallmentIntake` 的纯函数，这里不重复算钱。
@MainActor
@Observable
final class InstallmentEntryViewModel {
    /// `nonisolated` 理由同 `EntryViewModel`：视图要在 `@State` 属性初始化器里直接 new。
    nonisolated init() {}

    // MARK: - 输入

    /// 计划名，如「花呗分期 · AirPods」。留空时按「账户名 分期」兜底。
    var name: String = ""

    /// 账单上的「分期剩余应还」，如 1830.15。**金额的唯一权威来源**。
    var remainingDueText: String = ""

    /// 剩余期数（PRD 9.5.2 必填）。文本原样保存，解析走整数路径。
    var remainingText: String = ""
    /// 总期数。填了才能显示「第 4/12 期」，也是年化整笔口径的分母。
    var totalText: String = ""

    /// 账单上的「含利息」，如 176.99。年化的唯一输入，不填就没有年化。
    var interestText: String = ""

    /// 已享减免（国家贴息等）。只做记录，不参与任何计算——
    /// 那是已经优惠掉的钱，不是还要还的钱。
    var rebateText: String = ""
    var showingAdvanced = false

    /// 下一期还款日（必填，但由账户 `dueDay` 自动带出）。
    var dueDate: Date = .now

    /// 挂在哪张卡上。分期必然属于信用/借款账户。
    var account: Account?

    var errorMessage: String?

    // MARK: - 数据

    private(set) var accounts: [Account] = []

    /// 已录入的分期笔数（数库，不另存计数器）。
    private(set) var doneCount = 0

    /// 目标笔数，存 `UserDefaults`（导入进度，不是账本数据）。
    private(set) var target = InstallmentIntake.Batch.target

    // MARK: - 派生

    private static func integer(_ text: String) -> Int {
        // 只取前导数字：数字键盘偶尔会带进小数点或空格，别让它把整笔判成 0。
        let digits = text.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private static func optionalDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return MoneyMath.decimal(trimmed)
    }

    var remainingDue: Decimal { MoneyMath.decimal(remainingDueText) }

    var remainingPeriods: Int { Self.integer(remainingText) }

    var totalPeriods: Int? {
        let value = Self.integer(totalText)
        return value > 0 ? value : nil
    }

    /// 期数换算（剩余期数为主，总期数选填）。
    var periods: InstallmentIntake.Periods {
        InstallmentIntake.periods(remaining: remainingPeriods, total: totalPeriods)
    }

    /// 均摊结果：`perPeriod` 是前 n−1 期，`lastPeriod` 吸收余数。
    /// 没填剩余应还或期数时为 `nil`，界面显示占位。
    var split: InstallmentMath.Split? {
        InstallmentMath.splitEvenly(total: remainingDue, count: periods.remaining)
    }

    /// 每期金额 = 剩余应还 ÷ 剩余期数（向下到分）。
    /// **只读**——账单上的每期金额本来就是这么除出来的，让用户手填只会填出矛盾。
    var perPeriodAmount: Decimal { split?.perPeriod ?? 0 }

    /// 末期金额。与每期相同则为 `nil`，界面上不用多写一句「末期 ¥203.35」。
    var lastPeriodAmount: Decimal? {
        guard let split, split.lastPeriod != split.perPeriod else { return nil }
        return split.lastPeriod
    }

    /// 剩余总额。有剩余应还就是它本身，跟账单逐字一致。
    var previewRemainingTotal: Decimal {
        InstallmentMath.remainingTotal(
            count: periods.remaining,
            perPeriodAmount: perPeriodAmount,
            remainingDue: remainingDue
        )
    }

    /// 年化反算（估算，只展示）。**只走整笔口径**，与 `Installment.estimatedAnnualRate` 一致：
    ///
    ///     现值 = 每期 × 总期数 − 含利息
    ///
    /// **必须显式填了「总共几期」才算**。没填时 `periods.total` 会退化成剩余期数，
    /// 拿它当整笔分母就等于「假设这是一笔全新分期」——用户明明还剩 9 期，
    /// 却报成「9 期整笔」的年化（14.13% 会被报成 18% 上下），比不报更误导。
    /// 所以这里用 `totalPeriods` 而不是 `periods.total`。
    var previewAnnualRate: Decimal? {
        guard let total = totalPeriods, total > 1, perPeriodAmount > 0 else { return nil }
        guard let interest = Self.optionalDecimal(interestText), interest > 0 else { return nil }
        return InstallmentMath.impliedAnnualRate(
            periods: total,
            perPeriodAmount: perPeriodAmount,
            totalInterest: interest
        )
    }

    /// 年化缺失时的一句话说明，说清**缺哪一个数**而不是笼统一句「填更多」。
    var annualRateHint: String? {
        guard previewAnnualRate == nil else { return nil }
        if remainingDue <= 0 { return "填「剩余应还」和「剩余期数」就能算出每期金额。" }
        if totalPeriods == nil { return "再填「总共几期」，就能算这笔分期的真实年化。" }
        if Self.optionalDecimal(interestText) == nil { return "再填「含利息」，就能算这笔分期的真实年化。" }
        return nil
    }

    /// 还差几笔（目标 − 已录，不小于 0）。没设目标时为 0。
    var batchRemaining: Int {
        InstallmentIntake.batchRemaining(target: target, done: doneCount)
    }

    /// 顶部进度文案。
    var progressText: String {
        guard target > 0 else { return "已录 \(doneCount) 笔" }
        if batchRemaining == 0 { return "目标 \(target) 笔已录完" }
        return "还差 \(batchRemaining) 笔"
    }

    /// 存不下来时的提示。`nil` = 可以存。
    ///
    /// 「总共几期 < 剩余期数」直接拦而不是静默回退：那是填错了，
    /// 回退会让「第 4/12 期」显示成一个假进度。
    var validationMessage: String? {
        if account == nil { return "先选一张卡" }
        if remainingDue <= 0 { return "填一下账单上的「剩余应还」" }
        if remainingPeriods <= 0 { return "剩余期数要大于 0" }
        if let total = totalPeriods, total < remainingPeriods {
            return "总共 \(total) 期比剩余 \(remainingPeriods) 期还少，检查一下"
        }
        if perPeriodAmount <= 0 { return "算不出每期金额，检查剩余应还和期数" }
        if let interest = Self.optionalDecimal(interestText), interest < 0 { return "含利息不能是负数" }
        if let rebate = Self.optionalDecimal(rebateText), rebate < 0 { return "减免不能是负数" }
        return nil
    }

    var canSave: Bool { validationMessage == nil }

    /// 落库时用的名字：留空就按账户兜底，不拦用户。
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let base = account?.displayShortName ?? ""
        return base.isEmpty ? "分期" : "\(base) 分期"
    }

    /// 主按钮文案：带上「还剩几笔」比「录下这笔」更像流水线。
    var primaryTitle: String {
        guard target > 0, batchRemaining > 1 else { return "录下这笔" }
        return "录下这笔 · 还剩 \(batchRemaining - 1) 笔"
    }

    // MARK: - 载入与默认值

    func load(context: ModelContext) {
        do {
            let all = try context.fetch(
                FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.sortOrder)])
            )
            // 分期只挂在负债类账户上：储蓄卡没有「分期」这回事。
            accounts = all.filter { $0.kind.isLiability }
            doneCount = try InstallmentService.count(in: context)
        } catch {
            errorMessage = "读取账户失败：\(error.localizedDescription)"
        }
        target = InstallmentIntake.Batch.target

        if account == nil {
            // 优先沿用上一笔挂的卡，其次第一张信用/借款卡。
            account = (try? InstallmentService.mostRecentAccount(in: context)) ?? accounts.first
        }
        if let account {
            dueDate = InstallmentIntake.defaultDueDate(dueDay: account.dueDay)
        }
    }

    /// 换卡：还款日跟着那张卡的 `dueDay` 走（不同卡还款日不同）。
    func selectAccount(_ newAccount: Account) {
        account = newAccount
        dueDate = InstallmentIntake.defaultDueDate(dueDay: newAccount.dueDay)
    }

    func setTarget(_ value: Int) {
        target = max(0, value)
        InstallmentIntake.Batch.setTarget(target)
    }

    // MARK: - 保存

    /// 写入一笔分期。返回是否成功——成功时视图只弹一条回执，**不关闭面板**，
    /// 因为下一个动作是继续录下一笔。
    @discardableResult
    func save(in context: ModelContext) -> Bool {
        errorMessage = nil
        guard let message = validationMessage else {
            return persist(in: context)
        }
        errorMessage = message
        return false
    }

    private func persist(in context: ModelContext) -> Bool {
        guard let account else {
            errorMessage = "先选一张卡"
            return false
        }
        let p = periods
        // 没填总期数就别存含利息：那时分不清它指的是整笔的利息还是剩余期的利息，
        // 模型层会拿 totalPeriods（= 剩余期数）去算，得出一个自己不认的数字。
        // 宁可不存，由界面提示补「总共几期」——PRD 9.5.3「不猜假利率」。
        let hasTotalPeriods = totalPeriods != nil
        do {
            try InstallmentService.insert(
                name: resolvedName,
                account: account,
                totalPeriods: p.total,
                paidPeriods: p.paid,
                perPeriodAmount: perPeriodAmount,
                remainingDue: remainingDue,
                totalInterest: hasTotalPeriods ? Self.optionalDecimal(interestText) : nil,
                totalRebate: Self.optionalDecimal(rebateText),
                nextDueDate: dueDate,
                in: context
            )
            doneCount = (try? InstallmentService.count(in: context)) ?? (doneCount + 1)
            resetKeepingContext()
            return true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 连录的关键：只清这笔独有的东西，账户与还款日留给下一笔。
    private func resetKeepingContext() {
        name = ""
        remainingDueText = ""
        remainingText = ""
        totalText = ""
        interestText = ""
        rebateText = ""
        showingAdvanced = false
        errorMessage = nil
    }
}
