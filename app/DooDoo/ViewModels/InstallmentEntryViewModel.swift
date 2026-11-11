import Foundation
import Observation
import SwiftData

/// 存量分期快速连录的状态与校验（M3-2）。
///
/// **不碰 SwiftData 写入**——建计划交给 `InstallmentService`（AGENTS 7.4）。
///
/// 这个 ViewModel 的存在理由只有一个：**58 笔录入要像流水线**。
/// 所以它在每笔存完后故意**只清一半**：
/// - 清掉：名称、期数、每期金额、选填的高级字段（每笔都不一样，留着只会填错）
/// - 留着：账户、还款日（58 笔花呗分期基本共用同一张卡同一天，重选 58 次纯浪费）
///
/// 派生值全部走 `InstallmentMath` / `InstallmentIntake` 的纯函数，这里不重复算钱。
@MainActor
@Observable
final class InstallmentEntryViewModel {
    /// `nonisolated` 理由同 `EntryViewModel`：视图要在 `@State` 属性初始化器里直接 new。
    nonisolated init() {}

    // MARK: - 输入

    /// 计划名，如「花呗分期 · AirPods」。留空时按「账户名 分期」兜底。
    var name: String = ""

    /// 剩余期数（PRD 9.5.2 必填）。文本原样保存，解析走 `MoneyMath` 的整数路径。
    var remainingText: String = ""
    /// 总期数（选填）。填了才能显示「第 6/12 期」，见 `InstallmentIntake.periods`。
    var totalText: String = ""
    /// 每期金额（必填）。
    var perPeriodText: String = ""

    /// 高级字段，默认收起：首期 / 末期 / 剩余本金 / 总利息 / 减免。
    var firstText: String = ""
    var lastText: String = ""
    var principalText: String = ""
    var interestText: String = ""
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

    var remainingPeriods: Int { Self.integer(remainingText) }

    var totalPeriods: Int? {
        let value = Self.integer(totalText)
        return value > 0 ? value : nil
    }

    /// 期数换算（剩余期数为主，总期数选填）。
    var periods: InstallmentIntake.Periods {
        InstallmentIntake.periods(remaining: remainingPeriods, total: totalPeriods)
    }

    var perPeriodAmount: Decimal { MoneyMath.decimal(perPeriodText) }

    /// 剩余总额预览（未来各期之和）。
    var previewRemainingTotal: Decimal {
        InstallmentMath.remainingTotal(
            count: periods.remaining,
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: Self.optionalDecimal(firstText),
            lastPeriodAmount: Self.optionalDecimal(lastText)
        )
    }

    /// 年化反算（估算，只展示）。期数口径与 `Installment.estimatedAnnualRate` 一致：
    /// 有剩余本金配剩余期数，只有总利息配总期数。
    var previewAnnualRate: Decimal? {
        let p = periods
        if let principal = Self.optionalDecimal(principalText), principal > 0, p.remaining > 1 {
            return InstallmentMath.impliedAnnualRate(
                periods: p.remaining,
                perPeriodAmount: perPeriodAmount,
                presentValue: principal
            )
        }
        if let interest = Self.optionalDecimal(interestText), interest > 0, p.total > 1 {
            return InstallmentMath.impliedAnnualRate(
                periods: p.total,
                perPeriodAmount: perPeriodAmount,
                totalInterest: interest
            )
        }
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
    var validationMessage: String? {
        if account == nil { return "先选一张卡" }
        if remainingPeriods <= 0 { return "剩余期数要大于 0" }
        if perPeriodAmount <= 0 { return "每期金额要大于 0" }
        if let first = Self.optionalDecimal(firstText), first <= 0 { return "首期金额要大于 0" }
        if let last = Self.optionalDecimal(lastText), last <= 0 { return "末期金额要大于 0" }
        if let principal = Self.optionalDecimal(principalText), principal <= 0 { return "剩余本金要大于 0" }
        if let interest = Self.optionalDecimal(interestText), interest < 0 { return "总利息不能是负数" }
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
        do {
            try InstallmentService.insert(
                name: resolvedName,
                account: account,
                totalPeriods: p.total,
                paidPeriods: p.paid,
                perPeriodAmount: perPeriodAmount,
                firstPeriodAmount: Self.optionalDecimal(firstText),
                lastPeriodAmount: Self.optionalDecimal(lastText),
                remainingPrincipal: Self.optionalDecimal(principalText),
                totalInterest: Self.optionalDecimal(interestText),
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
        remainingText = ""
        totalText = ""
        perPeriodText = ""
        firstText = ""
        lastText = ""
        principalText = ""
        interestText = ""
        rebateText = ""
        showingAdvanced = false
        errorMessage = nil
    }
}
