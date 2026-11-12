import SwiftUI
import SwiftData

/// 资产页的三组。规格只定义信用/储蓄两组，M2a 补「借款」——
/// 否则父母的 20,000 不在任何界面上出现，总览的「我欠」会对不上明细。
enum AssetGroup: String, Identifiable, CaseIterable {
    case credit
    case savings
    case loan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credit: "信用"
        case .savings: "储蓄"
        case .loan: "借款"
        }
    }

    var totalLabel: String {
        switch self {
        case .credit: "欠款合计"
        case .savings: "余额合计"
        case .loan: "借款合计"
        }
    }

    var isLiability: Bool { self != .savings }

    var defaultKind: AccountKind {
        switch self {
        case .credit: .credit
        case .savings: .savings
        case .loan: .loan
        }
    }

    func matches(_ kind: AccountKind) -> Bool {
        switch self {
        case .credit: kind == .credit
        case .savings: kind == .savings || kind == .cash
        case .loan: kind == .loan
        }
    }
}

/// 资产页（收起态 + 明细浮层）。
///
/// 数值全部来自 SwiftData 与 `Math/` 的纯函数；这里只负责摆位置。
/// 聚合结果缓存在 `@State`，`body` 不遍历流水（AGENTS 7.5）。
struct AssetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Account.sortOrder)]) private var accounts: [Account]
    /// 分期计划与期表：信用组「本月要还」的唯一数据源（账单未建，见 PROGRESS 下一步 1）。
    @Query private var installments: [Installment]
    @Query private var periods: [InstallmentPeriod]
    @Query private var settings: [AppSettings]

    @State private var openGroup: AssetGroup?
    @State private var range: NetWorthRange = .year
    @State private var editingAccount: Account?
    @State private var creatingGroup: AssetGroup?

    @State private var mine: Decimal = 0
    @State private var owe: Decimal = 0
    @State private var series: [NetWorthPoint] = []
    /// 信用组明细行（`本月要还 …`），聚合在 `refreshDue` 里算一次。
    @State private var dueLine: DueLine?
    /// 账户 → 逾期天数，浮层里把那行的「较上月」换成「逾期 N 天」。
    @State private var overdueDays: [PersistentIdentifier: Int] = [:]

    var body: some View {
        ZStack {
            page
            if let group = openGroup {
                GroupOverlay(
                    title: group.title,
                    accounts: accounts(in: group),
                    isLiability: group.isLiability,
                    overdueDays: overdueDays,
                    onClose: { withAnimation(.easeOut(duration: 0.2)) { openGroup = nil } },
                    onSelect: { account in editingAccount = account }
                )
            }
        }
        .task {
            // 直接进资产页时也要保证种子在（首页可能还没被打开过）
            try? SeedService.prepare(context: context)
            refresh()
        }
        .onChange(of: range) { refresh() }
        .onChange(of: accounts.count) { refresh() }
        .onChange(of: accounts.map(\.currentBalance)) { refresh() }
        .onChange(of: periods.count) { refresh() }
        .onChange(of: periods.map(\.amount)) { refresh() }
        .onChange(of: installments.count) { refresh() }
        .onChange(of: settings.map(\.overdueAlertEnabled)) { refresh() }
        .sheet(item: $editingAccount) { account in
            AccountEditor(account: account, defaultKind: account.kind)
        }
        .sheet(item: $creatingGroup) { group in
            AccountEditor(account: nil, defaultKind: group.defaultKind)
        }
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                NetWorthCard(
                    mine: mine,
                    owe: owe,
                    mineDelta: AccountDelta.percent(current: mine, previous: series.first?.mine ?? mine),
                    oweDelta: AccountDelta.percent(current: owe, previous: series.first?.owe ?? owe),
                    points: series,
                    range: $range
                )

                if accounts.isEmpty {
                    emptyState
                } else {
                    ForEach(AssetGroup.allCases) { group in
                        let list = accounts(in: group)
                        if !list.isEmpty {
                            AccountGroupView(
                                title: group.title,
                                totalLabel: group.totalLabel,
                                accounts: list,
                                total: list.reduce(Decimal.zero) { $0 + $1.currentBalance },
                                isLiability: group.isLiability,
                                // 只有信用组有「本月要还」；储蓄/借款没有还款日这个概念。
                                detail: group == .credit ? dueLine : nil,
                                onOpen: { open(group) },
                                onAdd: { creatingGroup = group }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("还没有账户")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink2)
            Text("先建一张卡或一个钱包，资产才算得出来。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Button {
                creatingGroup = .savings
            } label: {
                Text("新建账户")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func accounts(in group: AssetGroup) -> [Account] {
        accounts.filter { group.matches($0.kind) }
    }

    private func open(_ group: AssetGroup) {
        withAnimation(.easeOut(duration: 0.22)) { openGroup = group }
    }

    /// 只在数据结构变化时算一次，结果留在 `@State`。
    private func refresh() {
        let snapshots = accounts.map { AccountSnapshot(kind: $0.kind, balance: $0.currentBalance) }
        mine = NetWorth.mine(snapshots)
        owe = NetWorth.owe(snapshots)

        let ledgers = accounts.map { account in
            AccountLedger(
                kind: account.kind,
                initial: account.initialBalance,
                entries: account.transactions
                    .filter { $0.deletedAt == nil }
                    .map { LedgerPoint(date: $0.date, delta: LedgerService.effect(of: $0)) }
            )
        }
        series = NetWorthSeries.points(ledgers, at: NetWorthSeries.dates(for: range))

        refreshDue()
    }

    /// 信用组「本月要还」与每张卡的逾期天数。
    ///
    /// 口径只有一条：**每张卡产出一个 `AccountDue`**（`DueMath` 保证账单与分期
    /// 不会被相加），组里再 Σ 一次。整组的数字和那行明细都从这一个结果出，
    /// 不存在第二套算法——详情页第八节踩过的「Σ账单 + Σ分期」在这里没有入口。
    ///
    /// 目前账单（`BillStatement`）还没有数据源，所以每张卡都走分期到期；
    /// 接上账单时只需给 `DueMath.accountDue(bill:)` 填值，这里一行都不用改。
    private func refreshDue() {
        let creditAccounts = accounts.filter { $0.kind == .credit }
        guard !creditAccounts.isEmpty else {
            dueLine = nil
            overdueDays = [:]
            return
        }

        // 期表只记 `installmentKey`，先把它折回账户。
        var accountOfPlan: [String: Account] = [:]
        for installment in installments {
            if let account = installment.account { accountOfPlan[installment.key] = account }
        }

        var entriesByAccount: [PersistentIdentifier: [DueEntry]] = [:]
        for period in periods {
            guard let account = accountOfPlan[period.installmentKey] else { continue }
            entriesByAccount[account.persistentModelID, default: []].append(
                DueEntry(amount: period.amount, dueDate: period.dueDate, isPaid: period.paidAt != nil)
            )
        }

        let today = Date.now
        var dues: [AccountDue] = []
        var days: [PersistentIdentifier: Int] = [:]

        for account in creditAccounts {
            guard let due = DueMath.accountDue(
                installments: entriesByAccount[account.persistentModelID] ?? [],
                today: today
            ) else { continue }
            dues.append(due)
            if due.isOverdue { days[account.persistentModelID] = due.overdueDays }
        }

        dueLine = DueMath.group(dues).map { DueMath.line($0) }
        overdueDays = days

        // 「逾期标红」关掉时，红字与浮层天数一起收掉。
        // 只关一半的话开关形同虚设（浮层还在标红），用户会认为开关坏了。
        // 金额不受影响——开关管的是「提醒」，不是「口径」。
        if settings.first?.overdueAlertEnabled == false {
            dueLine = dueLine.map { DueLine(text: $0.text, overdueText: nil) }
            overdueDays = [:]
        }
    }
}

#Preview {
    AssetsView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, AppSettings.self], inMemory: true)
}
