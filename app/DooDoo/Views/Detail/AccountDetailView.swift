import SwiftUI
import SwiftData

/// 账户详情（`账户详情页规格冻结-v1.0.md`；规格第十一节 3 把「储蓄 / 现金 / 借款
/// 账户的详情页形态」列为未锁定，本文件按 2026-11-16 用户定案补齐三种形态）。
///
/// **形态：全屏层 + 卡面放大，不是 sheet**（2026-11-16 用户定案，对应
/// `docs/design/pending/M4九条视觉反馈-2026-11-16.md` 第 8 条 / 4.2）：
/// 点浮层明细行的卡面 → 同一张卡靠 `matchedGeometryEffect` 长到顶部居中位，
/// 卡片落定后其余区块依次淡入；关闭是沿原路飞回，不是 dismiss。
///
/// **这一层必须挂在 `RootView` 的 ZStack 里**：资产页在 `VStack { 页头; 内容 }` 的
/// 内容区，挂在它内部的浮层到不了页头与状态栏，卡面就飞不到屏幕顶部。
///
/// 三种形态（用户 2026-11-16 定案）：
/// - **信用**：三列 + 额度条 + 本月要还白条 → 欠款走势 → 往期账单 → 分期 → 流水
/// - **借款**：欠款 + 走势。**没有**往期账单 / 分期 / 流水——借款没有账单周期，
///   用户原话「这是不需要的」
/// - **储蓄 / 现金**：余额 + 本月收支 + 余额走势 + 流水
///
/// 数值全部走 `Math/` 的纯函数（`CreditDebt` / `DetailMath` / `DueMath`），这里只摆位置。
struct AccountDetailView: View {
    let account: Account
    /// 与浮层明细行卡面共用的命名空间。卡面从行内长到顶部，靠的就是同一个 id + 这个空间。
    let cardSpace: Namespace.ID
    /// 点返回：由调用方摘掉这一层，卡面在同一事务里飞回明细行。
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var allBills: [BillStatement]
    @Query private var allInstallments: [Installment]
    @Query private var allPeriods: [InstallmentPeriod]
    @Query private var allAccounts: [Account]

    @State private var route: DetailRoute?
    @State private var editingAccount: Account?
    /// 走势图的区间，默认 1 年（规格第四节）。放在这里而不是走势组件内部：
    /// 换区间要重算 `trendPoints`，状态藏在组件里外面就拿不到新数据。
    @State private var trendRange: NetWorthRange = .year
    /// 本月还款：选扣款卡。
    @State private var showingRepayPicker = false
    @State private var repayError: String?

    /// 两段式入场：卡面先飞（①），落定后其余区块才展开（②）。
    /// 分开两个状态，是因为「卡片放大」和「信息展开」是两件事——
    /// 同时开始会退化成普通淡入，用户就看不到「卡片先过去」这一下。
    @State private var backdropIn = false
    @State private var revealed = false

    var body: some View {
        ZStack(alignment: .top) {
            // 页面底先淡入：卡面飞行的那 0.4 秒里，底下还留着浮层，
            // 卡片落定后本页才真正接管整屏。直接不透明会出现「卡片跳到一个已经换掉的背景上」。
            Palette.page
                .opacity(backdropIn ? 1 : 0)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    let m = metrics
                    header(m.overdueDays)
                    content(m)
                }
                .padding(.horizontal, 16)
                // 顶部 52：让开左上角的返回按钮。卡面居中，两者不抢位置。
                .padding(.top, 52)
                .padding(.bottom, 40)
            }

            closeButton
        }
        .task {
            withAnimation(.easeOut(duration: 0.20)) { backdropIn = true }
            // 卡面 spring 0.42 到位，300ms 后让其余信息接上（第 8 条第 4.2 节）。
            try? await Task.sleep(for: .milliseconds(300))
            revealed = true
        }
        .sheet(item: $route) { route in
            switch route {
            case .billEntry:
                BillEntrySheet(account: account)
                    .glassSheet()
            case .periods(let installment):
                PeriodEditorSheet(installment: installment)
                    .glassSheet()
            case .newInstallment:
                InstallmentEntryView(preferredAccount: account)
                    .glassSheet()
            }
        }
        .sheet(item: $editingAccount) { account in
            AccountEditor(account: account, defaultKind: account.kind)
                .glassSheet()
        }
        .confirmationDialog("从哪里扣款？", isPresented: $showingRepayPicker, titleVisibility: .visible) {
            ForEach(payerAccounts) { payer in
                Button(payer.name) { payCurrentMonth(from: payer) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("还 \(MoneyMath.money(repayAmount))：本月 \(repayablePeriods.count) 笔分期一起结清。")
        }
        .alert("记还款失败", isPresented: Binding(
            get: { repayError != nil },
            set: { if !$0 { repayError = nil } }
        )) {
            Button("知道了", role: .cancel) { repayError = nil }
        } message: {
            Text(repayError ?? "")
        }
    }

    /// 返回：卡面沿原路飞回明细行。
    ///
    /// 不用「完成」两个字——全屏层没有导航栏，左上角箭头是 iOS 唯一的返回语法。
    /// 关闭时不做淡出：`detailAccount` 一置空，卡面就在同一个事务里往回飞，
    /// 底下的浮层随即露出来，用户能看清它飞回了哪一行。
    private var closeButton: some View {
        // 用 HStack + Spacer 把它推到左边，**不是**给 Button 加 `.frame(maxWidth: .infinity)`：
        // 后者会把整条顶栏都变成命中区，点空白也会把详情关掉。
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.ink.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回账户列表")

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.top, 6)
    }

    // MARK: - 数据

    private var bills: [BillStatement] {
        allBills
            .filter { $0.account?.persistentModelID == account.persistentModelID }
            .sorted { $0.dueDate > $1.dueDate }
    }

    private var installments: [Installment] {
        allInstallments
            .filter { $0.account?.persistentModelID == account.persistentModelID }
            .sorted { $0.nextDueDate < $1.nextDueDate }
    }

    /// 某分期计划下全部期（按期号）。期表只记 `installmentKey`，得按 key 折。
    private func periods(of installment: Installment) -> [InstallmentPeriod] {
        allPeriods
            .filter { $0.installmentKey == installment.key }
            .sorted { $0.index < $1.index }
    }

    /// 单卡的账单与期数都有界（每月一期、每计划几十期），在 body 里现算不会卡；
    /// 聚合成 `@State` 反而要在 4 个 onChange 上同步，容易漏。
    ///
    /// 每个数组都单独一个 `var`：把 map/flatMap 套在构造器参数里，
    /// 编译器会报 `unable to type-check in reasonable time`（AssetsView 已踩过一次）。
    private var metrics: DetailMetrics {
        let billSnapshots = cardBills
        let periodSnapshots = cardPeriods
        // 欠款只有一条口径：余额为负即欠款（`CreditDebt`）。账单与期表不参与金额，
        // 它们分别只喂「本期消费 / 本月要还」。
        let owe = CreditDebt.owe(balance: account.currentBalance)
        return DetailMath.metrics(
            owe: owe,
            bills: billSnapshots,
            periods: periodSnapshots,
            monthSpend: monthSpend,
            today: .now
        )
    }

    private var cardBills: [DebtBill] {
        bills.map { bill in
            DebtBill(dueAmount: bill.dueAmount, dueDate: bill.dueDate, isPaid: bill.isPaid)
        }
    }

    /// 本期消费的流水：**当前账期内、不含分期本金**（规格 8.1）。
    ///
    /// 2026-11-13 真机回传：白条那屏写着「本期消费 6,049.00 · 不含分期」，
    /// 可 6,049 里含着一笔 5,999 的分期本金全额——备注与数字自己打架。
    /// 旧实现在没有账单时直接 Σ 本月全部 `expense`，既没排除分期本金，
    /// 也没有按账期归属（分期与账单分属两个期间，并排必然像没同步）。
    /// 现在改走 `DetailMath.periodSpend`，口径可单测。
    private var monthSpend: Decimal {
        let cycle = BillCycleMath.cycle(
            for: .now,
            cycleStartDay: account.billCycleStart,
            cycleEndDay: account.billCycleEnd,
            dueDay: account.dueDay
        )
        let entries: [SpendEntry] = account.transactions
            .filter { $0.deletedAt == nil && $0.kind == .expense }
            .map { tx in
                SpendEntry(
                    amount: tx.amount,
                    billPeriod: tx.billPeriod,
                    isInstallmentPrincipal: tx.installmentKey != nil,
                    date: tx.date
                )
            }
        return DetailMath.periodSpend(entries, period: cycle.period, today: .now)
    }

    private var cardPeriods: [DebtPeriod] {
        var result: [DebtPeriod] = []
        for plan in installments {
            for period in periods(of: plan) {
                let snapshot = DebtPeriod(
                    amount: period.amount,
                    dueDate: period.dueDate,
                    isPaid: period.paidAt != nil,
                    // 记一笔新建的计划：消费全额已进余额，这一期不再进「我欠」（M3-10）
                    isCoveredByBalance: plan.createdFromEntry
                )
                result.append(snapshot)
            }
        }
        return result
    }

    // MARK: - 区块

    /// 顶部只有卡面，居中。
    ///
    /// 2026-11-16 用户第 3 条：删掉卡面右边那串「招商 / 信用卡」。
    /// 卡面本身已经画了品牌名、类型、卡组织与尾号，右边那栏是同一个名字的第三次出现。
    ///
    /// 卡面下方那行是**账户名 + 编辑**：去掉了导航栏，账户名不能跟着 toolbar 一起消失
    /// （卡面写的是品牌全名「招商银行」，不是用户起的「招行 8857」），
    /// 「编辑」也就近降级成 11.5pt 文字按钮——这一层不再挂任何 bar。
    private func header(_ overdueDays: Int) -> some View {
        VStack(spacing: 10) {
            DetailHeroCard(account: account, cardSpace: cardSpace) {
                if overdueDays > 0 {
                    DetailOverdueBadge(days: overdueDays)
                }
            }

            HStack(spacing: 7) {
                Text(account.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.faint)

                Button("编辑") { editingAccount = account }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑账户")
            }
            // 外层 VStack 是 `.leading`，不给满宽这一行会贴着左边，和居中的卡面对不齐。
            .frame(maxWidth: .infinity)
            .reveal(revealed, index: 0)
        }
    }

    // MARK: - 按账户类型分发

    @ViewBuilder
    private func content(_ m: DetailMetrics) -> some View {
        switch account.kind {
        case .credit:
            creditContent(m)
        case .loan:
            loanContent(m)
        case .savings, .cash:
            savingsContent
        }
    }

    /// 信用：三列 + 额度条 + 白条 → 走势 → 往期账单 → 分期 → 流水（规格第二至七节）。
    ///
    /// 每块带 `reveal(index:)`：卡面落定后从 0 起依次展开，间隔 40ms。
    /// 顺序就是阅读顺序——先看清欠多少，再看曲线和明细。
    @ViewBuilder
    private func creditContent(_ m: DetailMetrics) -> some View {
        metricsBlock(m)
            .reveal(revealed, index: 1)
        DetailTrendBlock(
            title: "欠款走势",
            caption: "按流水折算的月末欠款。分期与账单不在曲线上——顶部欠款 = 曲线末点 + 未记账单与分期。",
            points: trendPoints,
            range: $trendRange,
            tone: Palette.owe
        )
        .reveal(revealed, index: 2)
        pastBillsSection
            .reveal(revealed, index: 3)
        installmentsSection
            .reveal(revealed, index: 4)
        flowBlock(
            note: "按时间倒序 · 还款不计入消费统计",
            emptyMonth: "这个月这张卡没有流水",
            emptyAll: "这张卡还没有流水"
        )
        .reveal(revealed, index: 5)
    }

    /// 借款：**只有欠款 + 走势**。
    ///
    /// 2026-11-16 用户原话：「亲友借款的详情页还存在往期账单、流水、分期。这是不需要的。」
    /// 借款没有账单周期（账期是信用卡的概念），也没有「本期消费」——钱是整笔借进来、
    /// 一笔笔还回去的，一个欠款数就是全部答案。
    ///
    /// **已知代价**：`.loan` 这个 kind 同时装着 e招贷这类**真带分期**的机构借款，
    /// 它的分期计划在本页看不到了（设置 → 分期的备用入口仍在）。
    /// 要真正区分「机构借款 / 亲友借款」，得先给 `Account` 加一个来源字段，
    /// 不能再靠 kind 猜——这轮按用户定案执行，不做。
    @ViewBuilder
    private func loanContent(_ m: DetailMetrics) -> some View {
        DetailHeroAmount(
            caption: "欠款",
            amount: m.owe,
            note: "含利息待还",
            tone: Palette.expense
        )
        .reveal(revealed, index: 1)
        DetailTrendBlock(
            title: "欠款走势",
            caption: "按流水折算的月末欠款余额。借入会让曲线升高，还款会让它下降。",
            points: trendPoints,
            range: $trendRange,
            tone: Palette.owe
        )
        .reveal(revealed, index: 2)
    }

    /// 储蓄 / 现金：余额 → 本月收支 → 余额走势 → 流水。
    ///
    /// 这条路径在 2026-11-16 之前根本不存在——资产页对储蓄组直接把点击接到编辑表单上
    /// （`AssetsView.onSelect` 里 `if group.isLiability` 的另一半）。
    @ViewBuilder
    private var savingsContent: some View {
        DetailHeroAmount(
            caption: "余额",
            amount: account.currentBalance,
            note: account.kind == .cash ? "手里的现金" : "可随时转出"
        )
        .reveal(revealed, index: 1)
        savingsMonthColumns
            .reveal(revealed, index: 2)
        DetailTrendBlock(
            title: "余额走势",
            caption: "按流水折算的月末余额，含转入、收款与还款。",
            points: trendPoints,
            range: $trendRange,
            tone: Palette.mine
        )
        .reveal(revealed, index: 3)
        flowBlock(
            note: "按时间倒序 · 转入与还款不计入本月支出",
            emptyMonth: "这个月这个账户没有流水",
            emptyAll: "这个账户还没有流水"
        )
        .reveal(revealed, index: 4)
    }

    /// 储蓄页的两列：这个月花掉多少、进账多少。
    ///
    /// **支出只数 `.expense`、收入只数 `.income`**：转账与还款是账户之间搬钱，
    /// 既不是花掉也不是赚到。把它们算进支出一边，同一个月的消费总额会因为
    /// 「工资卡转日常卡」翻倍，还会和首页日卡的支出合计对不上。
    private var savingsMonthColumns: some View {
        let month = savingsMonth
        return HStack(alignment: .top, spacing: 8) {
            metricColumn(
                title: "本月支出",
                value: MoneyMath.money(month.expense),
                note: "不含转账与还款",
                tone: month.expense > 0 ? Palette.ink : Palette.faint
            )
            metricColumn(
                title: "本月收入",
                value: MoneyMath.money(month.income),
                note: month.count > 0 ? "\(month.count) 笔流水" : "本月没有",
                tone: month.income > 0 ? Palette.income : Palette.faint
            )
        }
    }

    private var savingsMonth: (expense: Decimal, income: Decimal, count: Int) {
        let calendar = Calendar.current
        let monthly = flowTransactions.filter { tx in
            tx.deletedAt == nil && calendar.isDate(tx.date, equalTo: .now, toGranularity: .month)
        }
        let expense = monthly
            .filter { $0.kind == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let income = monthly
            .filter { $0.kind == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return (expense, income, monthly.count)
    }

    /// 该账户视角的全部流水。
    ///
    /// 信用页沿用 `account.transactions`——它的还款流水挂在付款卡那一侧，
    /// 本页只关心「这张卡花了多少」，合并进来会动规格第七节的脚注口径。
    /// 储蓄 / 现金必须把 `incomingTransactions` 一并算上，否则**转入的钱在流水里
    /// 根本不存在**（别人转进来、信用卡还款入账都走 toAccount 那一侧）。
    private var flowTransactions: [Transaction] {
        let own = account.transactions
        guard !account.kind.isLiability else { return own }
        let incoming = account.incomingTransactions
        guard !incoming.isEmpty else { return own }
        var seen = Set(own.map(\.persistentModelID))
        var merged = own
        for tx in incoming where seen.insert(tx.persistentModelID).inserted {
            merged.append(tx)
        }
        return merged
    }

    private func flowBlock(note: String, emptyMonth: String, emptyAll: String) -> some View {
        DetailFlowBlock(
            transactions: flowTransactions,
            footnote: note,
            emptyMonthText: emptyMonth,
            emptyAllText: emptyAll
        )
    }

    private func metricsBlock(_ m: DetailMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                metricColumn(
                    title: "欠款",
                    value: MoneyMath.money(m.owe),
                    note: account.creditLimit.map { "额度 \(MoneyMath.money($0))" } ?? "含分期与账单",
                    tone: Palette.expense
                )
                metricColumn(
                    title: "本期消费",
                    value: m.consumed.map { MoneyMath.money($0) } ?? "—",
                    note: "不含分期",
                    tone: Palette.ink
                )
                metricColumn(
                    title: "本月分期",
                    value: m.monthInstallment > 0 ? MoneyMath.money(m.monthInstallment) : "—",
                    note: monthInstallmentNote,
                    tone: Palette.ink
                )
            }
            .padding(.top, 18)

            if let limit = account.creditLimit, limit > 0 {
                limitBar(owe: m.owe, limit: limit)
                    .padding(.top, 15)
            }

            monthDueBar(m)
                .padding(.top, 10)
        }
    }

    private var monthInstallmentNote: String {
        let count = installments
            .flatMap { periods(of: $0) }
            .filter { $0.paidAt == nil && DueMath.isDueInThisMonth($0.dueDate, today: .now) }
            .count
        return count > 0 ? "\(count) 笔" : "无"
    }

    private func metricColumn(title: String, value: String, note: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 额度进度条（规格 3.2）。**不写「3,120 / 4,600」**——欠款在第一列、额度在第一列副标题，
    /// 这里再写一遍就是同一个数第三次出现（规格第九节去重清单）。
    private func limitBar(owe: Decimal, limit: Decimal) -> some View {
        let used = min(max(owe / limit, 0), 1)
        let available = limit - owe
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.line)
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: geo.size.width * CGFloat(truncating: used as NSDecimalNumber))
                }
            }
            .frame(height: 5)

            HStack {
                Text("已用 \(MoneyMath.percent(used * 100, digits: 0))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.sub)
                Spacer()
                Text("可用 \(MoneyMath.money(available > 0 ? available : 0))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
            }
        }
    }

    /// 「本月要还」白条（规格 3.3）。详情页唯一的合计落点。
    @ViewBuilder
    private func monthDueBar(_ m: DetailMetrics) -> some View {
        if let monthDue = m.monthDue {
            HStack {
                Text(monthDueCaption(m))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text(MoneyMath.money(monthDue))
                    .font(.system(size: 14.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)

                // 还款是**卡片级**动作：一次还清本月到期的所有分期。
                // 真实账单就是 11/25 还 368.70，不是一笔笔还。
                if repayAmount > 0 {
                    // D 方案：所有按钮都是白底 + 描边 + 墨字，不填色。
                    Button("还款") { showingRepayPicker = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Palette.card)
                                .overlay { Capsule().stroke(Palette.btnEdge, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            // 这里**保持白卡，不用玻璃**：它压的是暖白页底，背后没有内容可透，
            // 玻璃会与页底同色，整条"消失"。玻璃留给盖在卡面/内容上的层（sheet、回执、浮层）。
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
            )
        }
    }

    private func monthDueCaption(_ m: DetailMetrics) -> String {
        guard let date = m.monthDueDate else { return "本月要还" }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "本月要还 · \(parts.month ?? 0)/\(parts.day ?? 0) 到期"
    }

    // MARK: - 本月还款（卡片级）

    /// 本月到期、还没还的期。还款就是把这批**一次**还掉。
    private var repayablePeriods: [InstallmentPeriod] {
        var result: [InstallmentPeriod] = []
        for plan in installments {
            for period in periods(of: plan) where period.paidAt == nil {
                if DueMath.isDueInThisMonth(period.dueDate, today: .now) {
                    result.append(period)
                }
            }
        }
        return result
    }

    /// 本月还没还的那期账单（有的话它才是还款对象，金额含分期）。
    private var unpaidCurrentBill: BillStatement? {
        bills.first { DueMath.isDueInThisMonth($0.dueDate, today: .now) && !$0.isPaid }
    }

    /// 这次还款要付多少钱：**账单优先**（账单里已经含了本月分期），没账单就用分期合计。
    private var repayAmount: Decimal {
        if let unpaidCurrentBill { return unpaidCurrentBill.dueAmount }
        return repayablePeriods.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// 扣款来源只能是储蓄 / 现金——用信用卡还信用卡不是还款。
    private var payerAccounts: [Account] {
        allAccounts.filter { $0.kind == .savings || $0.kind == .cash }
    }

    /// 一次还清本月：写**一条**还款流水（不是每期一条），把本月到期的分期全标已还，
    /// 有账单就把账单也结掉，最后重算各计划的剩余应还。
    private func payCurrentMonth(from payer: Account) {
        let targets = repayablePeriods
        let bill = unpaidCurrentBill
        let total = bill?.dueAmount ?? targets.reduce(Decimal.zero) { $0 + $1.amount }
        guard total > 0 else { return }

        do {
            let tx = try LedgerService.insert(
                amount: total,
                kind: .repayment,
                date: .now,
                note: bill.map { "\($0.period) 期账单还款" } ?? "本月分期还款 \(targets.count) 笔",
                account: payer,
                toAccount: account,
                in: context
            )
            // 账期标记：「本月已还」的判断与将来撤销都靠它。
            tx.billPeriod = BillEntrySheet.periodText(for: .now)

            if let bill {
                bill.status = .paid
                bill.paidAt = .now
            }
            for period in targets {
                period.paidAt = .now
            }

            // 受影响的计划重算剩余应还，详情页顶部的「剩余」才跟得上。
            let keys = Set(targets.map(\.installmentKey))
            for plan in installments where keys.contains(plan.key) {
                let unpaid = allPeriods
                    .filter { $0.installmentKey == plan.key && $0.paidAt == nil }
                    .reduce(Decimal.zero) { $0 + $1.amount }
                plan.remainingDue = unpaid
            }

            try context.save()
        } catch {
            repayError = error.localizedDescription
        }
    }

    // MARK: - 走势（规格第四节）

    /// 曲线用**流水**口径（规格原文：派生值，来自流水）。
    /// 所以信用页的末点通常小于顶部那个欠款——差额是未记账单与分期，图注里已经写明。
    ///
    /// 走 `flowTransactions` 而不是 `account.transactions`：储蓄账户的转入在
    /// `toAccount` 那一侧，只看付款方会让曲线一路往下掉，而余额是涨的。
    private var trendPoints: [DebtTrendPoint] {
        let entries: [LedgerPoint] = flowTransactions
            .filter { $0.deletedAt == nil }
            .map { tx in
                LedgerPoint(date: tx.date, delta: LedgerService.effect(of: tx, for: account))
            }
        let ledger = AccountLedger(
            kind: account.kind,
            initial: account.initialBalance,
            entries: entries,
            // 同资产页：创建日之前该账户不存在，欠款记 0（2026-11-17 折线起点修正）
            createdAt: account.createdAt
        )
        return DebtTrend.points(ledger: ledger, at: NetWorthSeries.dates(for: trendRange))
    }

    // MARK: - 往期账单

    /// 往期账单：只取早于本月开始的那些（本期由三列 + 白条回答，未来期还没出账）。
    private var pastBills: [BillStatement] {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: .now)?.start else {
            return bills
        }
        return bills.filter { calendar.startOfDay(for: $0.dueDate) < monthStart }
    }

    private var pastBillsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("往期账单")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                let overdue = pastBills.filter { $0.isOverdue(on: .now) }.count
                Text(overdue > 0 ? "\(pastBills.count) 期 · 含逾期 \(overdue) 期" : "\(pastBills.count) 期")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.sub)

                Spacer(minLength: 8)

                Button {
                    route = .billEntry
                } label: {
                    Text("＋ 录账单")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.tabBed))
                }
                .buttonStyle(.plain)
            }

            if pastBills.isEmpty {
                DetailEmptyRow(text: "还没录过往期账单")
            } else {
                VStack(spacing: 0) {
                    ForEach(pastBills) { bill in
                        billRow(bill)
                        if bill.id != pastBills.last?.id {
                            Divider().overlay(Palette.line)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.card)
                )
            }
        }
    }

    private func billRow(_ bill: BillStatement) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bill.period) 期")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(bill.dueDateCaption(on: .now))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.sub)
            }

            Spacer(minLength: 8)

            Text(MoneyMath.money(bill.dueAmount))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)

            statusTag(bill.displayStatus(on: .now))
        }
        .padding(.vertical, 9)
    }

    private func statusTag(_ status: BillStatus) -> some View {
        let (text, color, bed) = tagStyle(status)
        return Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(bed))
    }

    private func tagStyle(_ status: BillStatus) -> (String, Color, Color) {
        switch status {
        case .pending: (status.title, Palette.ink2, Palette.pillOn)
        case .paid: (status.title, Palette.sub, Palette.line)
        case .overdue: (status.title, Palette.overdraft, Palette.overdraftBed)
        }
    }

    // MARK: - 分期

    private var installmentsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("分期")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                let total = installments.reduce(Decimal.zero) { $0 + $1.remainingTotal }
                Text("\(installments.count) 笔 · 剩余 \(MoneyMath.money(total))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.sub)

                Spacer(minLength: 8)

                Button {
                    route = .newInstallment
                } label: {
                    Text("＋ 录分期")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.tabBed))
                }
                .buttonStyle(.plain)
            }

            if installments.isEmpty {
                DetailEmptyRow(text: "这张卡没有分期")
            } else {
                VStack(spacing: 0) {
                    ForEach(installments) { plan in
                        Button {
                            route = .periods(plan)
                        } label: {
                            installmentRow(plan)
                        }
                        .buttonStyle(.plain)
                        if plan.id != installments.last?.id {
                            Divider().overlay(Palette.line)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.card)
                )
            }
        }
    }

    private func installmentRow(_ plan: Installment) -> some View {
        HStack(spacing: 10) {
            // 进度环：已还期数 / 总期数（规格第六节 34pt）。
            ZStack {
                Circle()
                    .stroke(Palette.line, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress(plan))
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(paidCount(plan))/\(plan.totalPeriods)")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("每期 \(MoneyMath.money(plan.perPeriodAmount)) · 剩 \(plan.remainingPeriods) 期")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // 右列原来只有一个「剩余总额」，和上面「本月分期 332.01 · 6 笔」并排容易被读成矛盾
            // （用户 2026-11-13：「把列表行右边显示改成本月 x / 剩余 x」）。
            VStack(alignment: .trailing, spacing: 3) {
                let due = monthDue(of: plan)
                Text("本月 \(due > 0 ? MoneyMath.money(due) : "—")")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(due > 0 ? Palette.ink : Palette.sub)
                Text("剩余 \(MoneyMath.money(plan.remainingTotal))")
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// 已还期数 = 录入时填的**历史**期数 + 期表里标了已还的期数。
    ///
    /// 只读 `paidPeriods` 会永远停在录入那一刻（用户 2026-11-12 回传「进度条恒为 2/12」）——
    /// 那个字段是照账单填的历史汇总，还款动作只写 `InstallmentPeriod.paidAt`，两边没人同步。
    /// 不动 `paidPeriods`：`remainingPeriods` 还依赖它算「还剩几期」的账单口径。
    private func paidCount(_ plan: Installment) -> Int {
        let fromPeriods = periods(of: plan).filter { $0.paidAt != nil }.count
        return min(plan.totalPeriods, plan.paidPeriods + fromPeriods)
    }

    private func progress(_ plan: Installment) -> CGFloat {
        guard plan.totalPeriods > 0 else { return 0 }
        let ratio = Double(paidCount(plan)) / Double(plan.totalPeriods)
        return CGFloat(min(max(ratio, 0), 1))
    }

    /// 这笔分期本月要还多少（只算本月到期、未还的期）。
    private func monthDue(of plan: Installment) -> Decimal {
        periods(of: plan)
            .filter { $0.paidAt == nil && DueMath.isDueInThisMonth($0.dueDate, today: .now) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}

/// 第二段入场：卡面落定后，区块按 `index` 依次淡入 + 上浮 14pt。
///
/// 用 `.animation(_:value:)` 而不是在 `.task` 里 `withAnimation`：这样每块各带自己的
/// 延迟，切换区间、切流水范围这类重绘不会把动画重放一遍（`value` 只在 `shown` 变化时触发）。
private struct Reveal: ViewModifier {
    let shown: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.easeOut(duration: 0.30).delay(Double(index) * 0.04), value: shown)
    }
}

private extension View {
    func reveal(_ shown: Bool, index: Int) -> some View {
        modifier(Reveal(shown: shown, index: index))
    }
}

/// 卡详情里会推开的两个子页（规格 11.6：这两个子页的交互 v1.0 未锁定）。
private enum DetailRoute: Identifiable {
    case billEntry
    case periods(Installment)
    case newInstallment

    var id: String {
        switch self {
        case .billEntry: "billEntry"
        case .periods(let plan): "periods-\(plan.key)"
        case .newInstallment: "newInstallment"
        }
    }
}
