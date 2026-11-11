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
/// 现在只填 4 个必填项：**剩余应还 / 剩余期数 / 总共几期 / 含利息**，
/// 外加 1 个选填的**末期金额**（M3-5）。
/// 每期金额由「剩余应还 ÷ 期数」派生（余数自动落**首期**），还款日由账户带出。
///
/// M3-5 为什么要补那个选填框：账单利息其实是**按期均分**的（平息）——
/// 496.65 分 6 期的票面息是 3.38 + 3.36 × 5 = 20.18；末期只收 0.83，是因为
/// **退款 60 元本金按同一费率（4.2129%）同步减了 2.53 元息，且全抵在末期**
/// （20.18 − 2.53 = 17.65，末期 79.83 + 0.83 = 80.66）。
/// 所以「末期偏小」不是利息分布规律，而是**一笔减免落在一期上**——落在哪一期、
/// 减多少，账单只写结果不写推导。所以「总额 ÷ 期数」只是算术平均，
/// 跟账单末期差 1.9 元。**给定总额和期数，减免落期是欠定的**——再多算法也只能猜。
/// 账单上末期金额是明写的，抄一个数就能反推出中间各期（见 `InstallmentMath.splitEndingAt`），
/// 五张真实账单逐分复现。不填则退回均摊，行为与 M3-4 完全一致。
/// **M3-6 补的那一格**：有些账单（招行 e招贷）把「剩余待入账」拆成
/// `本金 6,670.93` + `利息 851.57` 两行，而 App 只要一个含息的合计
/// （`442.50 × 17 = 7,522.50`）。以前这一加要用户在 App 外自己按计算器，
/// 抄错一行就少算 851.57。现在打开「账单把利息单列了」，填两格、合计自动出，
/// 利息顺带喂给年化——**不拆本息入库，也不把利息算成支出**。
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

    /// 账单上的「分期剩余应还」，如 1830.15。**金额的唯一权威来源**。
    var remainingDueText: String = ""

    /// 剩余期数（PRD 9.5.2 必填）。文本原样保存，解析走整数路径。
    var remainingText: String = ""
    /// 总期数。填了才能显示「第 4/12 期」，也是年化整笔口径的分母。
    var totalText: String = ""

    /// 账单上的「含利息」，如 176.99。年化的唯一输入，不填就没有年化。
    var interestText: String = ""

    /// 账单最后一期的金额（选填）。
    ///
    /// 末期跟其他期不一样，只有一种成因：**退款 / 贴息抵在最后一期**（花呗就是这么抵的）。
    /// 496.65 分 6 期：末期 80.66，中间全是 83.19，差的 2.53 就是 60 元退款同步减掉的息。
    /// 填了这个数，中间各期就由「(剩余应还 − 末期) ÷ (期数 − 1)」反推，
    /// 不再用算术平均——这是唯一能把这类账单算准的路子（见 `InstallmentMath.splitEndingAt`）。
    /// 不填则退回均摊，跟 M3-4 行为完全一致。
    var lastPeriodText: String = ""

    /// 账单是否把「剩余待还」拆成了**本金 + 利息**两行（招行 e招贷 那种）。
    ///
    /// 关掉时只看 `remainingDueText`（一个含息合计），跟 M3-5 完全一样。
    /// 打开时看 `principalText` + `interestPartText`，合计由
    /// `InstallmentIntake.includedTotal` 加出来——用户不用再去 App 外按计算器。
    /// 连录时**保留**这个开关（同一种账单往往连着好几笔，理由同账户与还款日）。
    var splitsInterest = false

    /// 单位：元。账单上的「剩余待入账 · 本金」，如 6,670.93。仅 `splitsInterest` 时有意义。
    var principalText: String = ""

    /// 单位：元。账单上的「剩余待入账 · 利息」，如 851.57。仅 `splitsInterest` 时有意义。
    var interestPartText: String = ""

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

    /// 用户填的「本金」那格。空或非正数为 `nil`。
    var principalInput: Decimal? {
        guard let value = Self.optionalDecimal(principalText), value > 0 else { return nil }
        return value
    }

    /// 用户填的「利息」那格。空为 `nil`（零息分期），负数原样返回由校验层拦。
    var interestInput: Decimal? { Self.optionalDecimal(interestPartText) }

    /// 单位：元。**含息的**剩余应还——金额的唯一权威来源。
    ///
    /// 两条路径：
    /// - 账单只给一个合计（花呗/白条/信用卡分期）→ 直接用它
    /// - 账单拆成「本金 + 利息」两行（招行 e招贷）→ 两格相加（`InstallmentIntake.includedTotal`）
    ///
    /// 合的是现金流：7,522.50 = 17 × 442.50，跟账单上那行「每期 442.50」对得上。
    /// **不拆本息入库**——逐期本金/利息是账单内部的事，App 只记「一共要还多少」。
    var remainingDue: Decimal {
        if splitsInterest {
            return InstallmentIntake.includedTotal(principal: principalInput, interest: interestInput) ?? 0
        }
        return MoneyMath.decimal(remainingDueText)
    }

    /// 年化用的利息。
    ///
    /// 拆两栏时取上面那格「利息」——**不要求用户再在次卡里抄一遍**；
    /// 否则同一个数字填两个框，迟早填出不一致。
    var resolvedInterest: Decimal? {
        splitsInterest ? interestInput : Self.optionalDecimal(interestText)
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

    /// 用户填的末期金额。空或非正数时为 `nil`。
    var lastPeriodInput: Decimal? {
        guard let value = Self.optionalDecimal(lastPeriodText), value > 0 else { return nil }
        return value
    }

    /// 各期金额。两条路径：
    /// - 填了末期金额 → `splitEndingAt` 反推中间各期（**账单真值优先**，末期抵了减免也算得准）
    /// - 没填 → `splitEvenly` 均摊、余数落首期（M3-4 的默认行为）
    ///
    /// 末期金额 ≥ 剩余应还时 `splitEndingAt` 返 `nil`，这里会退到均摊——
    /// 界面靠 `validationMessage` 先把矛盾拦下来，不让它悄悄退回。
    var split: InstallmentMath.Split? {
        let count = periods.remaining
        if let last = lastPeriodInput {
            return InstallmentMath.splitEndingAt(total: remainingDue, count: count, last: last)
                ?? InstallmentMath.splitEvenly(total: remainingDue, count: count)
        }
        return InstallmentMath.splitEvenly(total: remainingDue, count: count)
    }

    /// 是否走了「末期按账单」这条路（界面据此换文案）。
    var isUsingLastPeriod: Bool { split?.lastPeriod != split?.perPeriod }

    /// 每期金额 = 剩余应还 ÷ 剩余期数（向下到分）。
    /// **只读**——账单上的每期金额本来就是这么除出来的，让用户手填只会填出矛盾。
    var perPeriodAmount: Decimal { split?.perPeriod ?? 0 }

    /// 首期金额（**未来第一期**）。与其余各期相同则为 `nil`，界面上不用多写一句。
    ///
    /// 零头落首期是照账单校准的：15.34 ÷ 3 → 5.12 / 5.11 / 5.11，首期多 1 分
    /// （用户 11-11 给的两张白条账单，见 `InstallmentMath.splitEvenly`）。
    var firstPeriodAmount: Decimal? {
        guard let split, split.firstPeriod != split.perPeriod else { return nil }
        return split.firstPeriod
    }

    /// 剩余总额。有剩余应还就是它本身，跟账单逐字一致。
    var previewRemainingTotal: Decimal {
        InstallmentMath.remainingTotal(
            count: periods.remaining,
            perPeriodAmount: perPeriodAmount,
            remainingDue: remainingDue
        )
    }

    /// 整笔总额（约）= 已还部分 + 剩余应还。
    ///
    /// 只在**显式填了**「总共几期」时给——没填就没有分母，拿剩余期数乘出来
    /// 等于「假设这是一笔全新分期」，跟用户手上那张已经还了几期的账单差很远。
    ///
    /// 为什么是「已还 × 每期 + 剩余应还」而不是「每期 × 总期数」：后者会把
    /// 剩余应还里那个首期零头摊掉（1830.17 ÷ 9 的首期是 203.37，乘回去只剩 203.35）。
    /// 前者**一期都没还时等于剩余应还本身，跟账单逐字一致**；已还过的情况下，
    /// 差的也只是历史那几期的几分钱零头，所以标「约」。
    var previewGrandTotal: Decimal? {
        guard let total = totalPeriods, total > 1, perPeriodAmount > 0 else { return nil }
        return perPeriodAmount * Decimal(periods.paid) + previewRemainingTotal
    }

    /// 年化用的每期金额。
    ///
    /// 填了末期金额时**必须换用整笔平均**：此时 `perPeriodAmount` 是中间各期的真值
    /// （496.65 那笔是 83.19），末期只有 80.66；拿 83.19 算年化会得到 14.28%，
    /// 而整笔平均 82.775 才是 12.53%。年化是整笔口径，要的就是平均数。
    private var perPeriodForRate: Decimal {
        guard isUsingLastPeriod, let total = totalPeriods, total > 0 else { return perPeriodAmount }
        let paid = Decimal(periods.paid)
        return (paid * perPeriodAmount + previewRemainingTotal) / Decimal(total)
    }

    /// 年化反算（估算，只展示）。与 `Installment.estimatedAnnualRate` 一致，分两条：
    ///
    /// **默认走整笔口径**：
    ///
    ///     现值 = 每期 × 总期数 − 含利息
    ///
    /// **必须显式填了「总共几期」才算**。没填时 `periods.total` 会退化成剩余期数，
    /// 拿它当整笔分母就等于「假设这是一笔全新分期」——用户明明还剩 9 期，
    /// 却报成「9 期整笔」的年化（14.13% 会被报成 18% 上下），比不报更误导。
    /// 所以这里用 `totalPeriods` 而不是 `periods.total`。
    ///
    /// **账单拆两栏时改走剩余口径**：此时利息本身是「剩余期」的，而
    /// 「剩余应还 − 剩余利息 = 剩余本金」是账单给的真值，三个数自洽，
    /// 不需要总期数。用整笔公式反而把 6,670.93 的本金按 24 期折，报成 8.2%。
    var previewAnnualRate: Decimal? {
        guard perPeriodAmount > 0 else { return nil }
        // 账单拆两栏（e招贷）：利息是**剩余期**的，年化走剩余口径。
        // 剩余应还 − 剩余利息 = 剩余本金（6,670.93），配剩余期数 17 → 16.43%。
        // 这时不需要「总共几期」——三个数本身已经自洽；硬套整笔公式反而会报成 8.2%。
        if splitsInterest {
            guard let interest = interestInput, interest > 0, periods.remaining > 1 else { return nil }
            return InstallmentMath.impliedAnnualRate(
                periods: periods.remaining,
                perPeriodAmount: perPeriodAmount,
                totalInterest: interest
            )
        }
        guard let total = totalPeriods, total > 1 else { return nil }
        guard let interest = resolvedInterest, interest > 0 else { return nil }
        return InstallmentMath.impliedAnnualRate(
            periods: total,
            perPeriodAmount: perPeriodForRate,
            totalInterest: interest
        )
    }

    /// 年化缺失时的一句话说明，说清**缺哪一个数**而不是笼统一句「填更多」。
    var annualRateHint: String? {
        guard previewAnnualRate == nil else { return nil }
        if remainingDue <= 0 {
            return splitsInterest
                ? "填「本金」和「剩余期数」就能算出每期金额。"
                : "填「剩余应还」和「剩余期数」就能算出每期金额。"
        }
        if splitsInterest {
            if periods.remaining <= 1 { return "剩余期数要大于 1 期才能反算年化。" }
            return "再填上面那格「利息」，就能算这笔分期的真实年化。"
        }
        if totalPeriods == nil { return "再填「总共几期」，就能算这笔分期的真实年化。" }
        if resolvedInterest == nil { return "再填「含利息」，就能算这笔分期的真实年化。" }
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
        // 拆两栏时先看两格本身，再说合计——否则用户看到的是「剩余应还」不对，
        // 却不知道该改哪一格。
        if splitsInterest {
            if principalInput == nil { return "填一下账单上的「本金」" }
            if let interest = interestInput, interest < 0 { return "利息不能是负数" }
        }
        if remainingDue <= 0 { return "填一下账单上的「剩余应还」" }
        if remainingPeriods <= 0 { return "剩余期数要大于 0" }
        if let total = totalPeriods, total < remainingPeriods {
            return "总共 \(total) 期比剩余 \(remainingPeriods) 期还少，检查一下"
        }
        // 末期金额是选填，但填了就必须自洽：末期 ≥ 剩余应还 时中间期不存在，
        // splitEndingAt 会返 nil 并静默退回均摊——那等于用户白填一遍，所以在这里拦。
        if !lastPeriodText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let last = lastPeriodInput else { return "末期金额要大于 0" }
            if last >= remainingDue {
                return "末期 ¥\(MoneyMath.money(last)) 不小于剩余应还，检查一下是不是抄错了栏"
            }
        }
        if perPeriodAmount <= 0 { return "算不出每期金额，检查剩余应还和期数" }
        if let interest = resolvedInterest, interest < 0 { return "含利息不能是负数" }
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
        //
        // 拆两栏的利息是**剩余期**口径（e招贷 851.57），一律不走 `totalInterest`——
        // 那个字段是整笔语义，套上去会把 16.43% 报成 8.2%。改存 `remainingInterest`。
        let hasTotalPeriods = totalPeriods != nil
        do {
            try InstallmentService.insert(
                name: resolvedName,
                account: account,
                totalPeriods: p.total,
                paidPeriods: p.paid,
                perPeriodAmount: perPeriodAmount,
                lastPeriodAmount: lastPeriodInput,
                remainingDue: remainingDue,
                totalInterest: splitsInterest ? nil : (hasTotalPeriods ? resolvedInterest : nil),
                remainingInterest: splitsInterest ? resolvedInterest : nil,
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
    ///
    /// `splitsInterest` 也留着——58 笔里同一种账单形态往往连着好几笔，
    /// 每笔重按一次开关是纯浪费。金额三格必须清，否则下一笔会带着上一笔的数。
    private func resetKeepingContext() {
        name = ""
        remainingDueText = ""
        principalText = ""
        interestPartText = ""
        remainingText = ""
        totalText = ""
        interestText = ""
        lastPeriodText = ""
        rebateText = ""
        showingAdvanced = false
        errorMessage = nil
    }
}
