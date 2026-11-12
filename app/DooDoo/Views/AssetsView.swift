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
    /// 分期计划与期表、「本月要还」的账单侧数据源（PRD 9.12）。
    @Query private var installments: [Installment]
    @Query private var periods: [InstallmentPeriod]
    @Query private var bills: [BillStatement]
    @Query private var settings: [AppSettings]

    @State private var openGroup: AssetGroup?
    @State private var range: NetWorthRange = .year
    @State private var editingAccount: Account?
    @State private var creatingGroup: AssetGroup?
    /// 卡详情 sheet（account-detail-v1.0 的最小落地，见 PROGRESS M3-8）。
    @State private var detailAccount: Account?

    @State private var mine: Decimal = 0
    @State private var owe: Decimal = 0
    @State private var series: [NetWorthPoint] = []
    /// 账户 → 该卡欠多少（正数）。「我欠」与信用/借款组「欠款合计」共用这一份（见 `CardDebt`）。
    @State private var oweByAccount: [PersistentIdentifier: Decimal] = [:]
    /// 信用组明细行（`本月要还 …`），由 `AssetSummaryService` 聚合。
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
                    onSelect: { account in
                        // 负债卡点进详情页；储蓄/现金仍走编辑（规格第十一节 3：详情页只覆盖信用账户）。
                        if group.isLiability {
                            detailAccount = account
                        } else {
                            editingAccount = account
                        }
                    }
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
        .onChange(of: bills.count) { refresh() }
        .onChange(of: bills.map(\.dueAmount)) { refresh() }
        .onChange(of: bills.map(\.statusRaw)) { refresh() }
        .onChange(of: settings.map(\.overdueAlertEnabled)) { refresh() }
        .sheet(item: $editingAccount) { account in
            AccountEditor(account: account, defaultKind: account.kind)
        }
        .sheet(item: $detailAccount) { account in
            AccountDetailSheet(account: account)
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
                                total: groupTotal(group, accounts: list),
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

    /// 组头那个合计。负债组用 `CardDebt` 派生的欠额（与顶部「我欠」同源、同口径），
    /// 储蓄组仍用余额。`AccountGroupView.total` 约定「已带正负」，所以负债取负号。
    private func groupTotal(_ group: AssetGroup, accounts list: [Account]) -> Decimal {
        guard group.isLiability else {
            return list.reduce(Decimal.zero) { $0 + $1.currentBalance }
        }
        let owed = list.reduce(Decimal.zero) { sum, account in
            sum + (oweByAccount[account.persistentModelID] ?? 0)
        }
        return -owed
    }

    private func open(_ group: AssetGroup) {
        withAnimation(.easeOut(duration: 0.22)) { openGroup = group }
    }

    /// 只在数据结构变化时算一次，结果留在 `@State`。
    ///
    /// 聚合本身全在 `AssetSummaryService` 里——写在这里编译器会报
    /// `unable to type-check in reasonable time`（CI run 57/58 实测）。
    private func refresh() {
        let snapshots = accounts.map { AccountSnapshot(kind: $0.kind, balance: $0.currentBalance) }
        mine = NetWorth.mine(snapshots)

        let summary = AssetSummaryService.make(
            accounts: accounts,
            installments: installments,
            periods: periods,
            bills: bills,
            alertsEnabled: settings.first?.overdueAlertEnabled ?? true
        )
        oweByAccount = summary.oweByAccount
        owe = summary.owe
        dueLine = summary.dueLine
        overdueDays = summary.overdueDays

        let ledgers: [AccountLedger] = accounts.map { ledger(for: $0) }
        series = NetWorthSeries.points(ledgers, at: NetWorthSeries.dates(for: range))
    }

    /// 单个账户的流水账本（走势图输入）。
    private func ledger(for account: Account) -> AccountLedger {
        let entries: [LedgerPoint] = account.transactions
            .filter { $0.deletedAt == nil }
            .map { tx in
                LedgerPoint(date: tx.date, delta: LedgerService.effect(of: tx))
            }
        return AccountLedger(
            kind: account.kind,
            initial: account.initialBalance,
            entries: entries
        )
    }
}

#Preview {
    AssetsView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self], inMemory: true)
}
