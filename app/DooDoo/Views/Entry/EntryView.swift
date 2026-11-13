import SwiftData
import SwiftUI

/// 记一笔（M1b）。四类型共用一套骨架，按 `type` 换字段。
///
/// 依据 `docs/design/spec/记一笔规格冻结-v1.0.md`：
/// 标题 → 类型分段 → 卡 → 归属 → 金额 → 类型专属字段 → 备注 → 余额预览 → 主按钮。
///
/// M2b 起包含还款与转账；**M3-10 起含内联分期开关与账期归属**
/// （支出 + 负债账户才出现分期块；信用/借款账户的归属行可切账期）。
struct EntryView: View {
    /// 打开时默认停在哪个类型。
    var initialType: TransactionKind = .expense
    /// 打开时默认用的日期（补记历史日时由日卡传入）。
    var initialDate: Date = .now

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [AppSettings]

    @State private var vm = EntryViewModel()
    @FocusState private var amountFocused: Bool
    /// 转账保存后的短回执。非 nil 时先显示 1.1 秒再关面板（真机反馈 #12）。
    @State private var receipt: String?

    init(initialType: TransactionKind = .expense, initialDate: Date = .now) {
        self.initialType = initialType
        self.initialDate = initialDate
    }

    private var accentStyle: AccentStyle { settingsList.first?.accent ?? .ink }
    private var accent: Color { Palette.accent(accentStyle) }
    private var accentWash: Color { Palette.accentWash(accentStyle) }

    /// 分段里的四个类型。`.adjustment` 不走记一笔（由余额校准生成）。
    private let entryTypes: [TransactionKind] = [.expense, .income, .repayment, .transfer]

    var body: some View {
        VStack(spacing: 0) {
            header
            typeSegment

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fields
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay { receiptBanner }
        .task(id: receipt) {
            // 有回执就停一下再关，没有就由保存处直接 dismiss。
            guard receipt != nil else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            dismiss()
        }
        .task {
            vm.setType(initialType)
            // 真机反馈 #1：日卡给的是当天 00:00，直接用会让新流水排到日卡最底。
            // 今天用当前时刻，补记历史日把当前时分秒套到那一天。
            vm.date = DayMath.entryTimestamp(for: initialDate)
            vm.load(context: context)
            amountFocused = true
        }
    }

    // MARK: - 保存回执

    @ViewBuilder
    private var receiptBanner: some View {
        if let receipt {
            VStack {
                Spacer()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                    Text(receipt)
                        .font(.system(size: 13.5, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.ink.opacity(0.92))
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Text("记一笔")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.ink)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.ink.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var typeSegment: some View {
        HStack(spacing: 0) {
            ForEach(entryTypes, id: \.self) { kind in
                let selected = vm.type == kind
                Button {
                    vm.setType(kind)
                    amountFocused = true
                } label: {
                    Text(kind.title)
                        .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.ink : Palette.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected ? Palette.card : .clear)
                                .shadow(color: selected ? .black.opacity(0.08) : .clear,
                                        radius: 1, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.tabBed)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - 字段

    @ViewBuilder
    private var fields: some View {
        switch vm.type {
        case .expense, .income:
            AccountCardStrip(accounts: vm.payerCandidates, selection: $vm.payer)
            attribution(paying: vm.type == .expense ? "从" : "存进", account: vm.payer)
            amountRow
            installmentBlock
            CategoryPicker(
                tops: vm.topCategories,
                subs: vm.subCategories,
                topKey: vm.topKey,
                subKey: vm.subKey,
                showingSub: vm.showingSub,
                accent: accent,
                accentWash: accentWash,
                onSelectTop: { vm.selectTop($0) },
                onSelectSub: { vm.selectSub($0) },
                onCollapse: { vm.showingSub = false }
            )
            .padding(.top, 4)

            if vm.type == .expense {
                gradeRow
            }
            noteRow
            previewBox

        case .repayment:
            AccountCardStrip(accounts: vm.targetCandidates, selection: $vm.target)
            repaymentInfo
            amountRow
            Text("从哪张卡扣")
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
            AccountCardStrip(accounts: vm.payerCandidates, selection: $vm.payer, compact: true)
            noteRow
            previewBox

        case .transfer:
            // 真机反馈 #12：手续费原来排在「转出金额」之前、字号 15pt，
            // 被 20pt 转出和 26pt 到账两头夹着，用户根本看不见。
            // 现顺序改成 转出 → 到账 → 手续费，字号提到与到账同一量级。
            transferDual
            amountRow
            receivedRow
            feeRow
            noteRow
            previewBox

        case .adjustment:
            EmptyView()
        }
    }

    // MARK: - 归属行

    private func attribution(paying prefix: String, account: Account?) -> some View {
        HStack(spacing: 8) {
            Text(prefix)
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Text(account?.displayShortName ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if let account {
                attributionPill(account)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    /// 归属行右侧那枚小胶囊。
    ///
    /// - 收入：「立即到账」（真机反馈 #4，此前写成「立即扣款」）
    /// - 储蓄 / 现金：「立即扣款」
    /// - 信用 / 借款：**账期**。点开可以切到下一期——跨账单日补记、商户延迟入账时用得上，
    ///   默认值不用点（M3-10，PRD 9.7 补录）
    @ViewBuilder
    private func attributionPill(_ account: Account) -> some View {
        if vm.type == .income {
            periodPill("立即到账")
        } else if account.kind.isLiability {
            Menu {
                Button("按账单周期（默认）") { vm.billPeriodOverride = nil }
                ForEach(vm.billPeriodChoices, id: \.self) { period in
                    Button("计入 \(BillCycleMath.monthLabel(period))") {
                        vm.billPeriodOverride = period
                    }
                }
            } label: {
                periodPill(vm.billCycleCaption(for: account), showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            periodPill("立即扣款")
        }
    }

    private func periodPill(_ text: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .foregroundStyle(Palette.mine)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.mine.opacity(0.10))
        )
    }

    // MARK: - 金额

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Spacer(minLength: 0)
            Text("¥")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.faint)
            TextField("0.00", text: Binding(
                get: { vm.amountText },
                set: { vm.setAmountText($0) }
            ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 46, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .focused($amountFocused)
                .frame(maxWidth: 250)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 内联分期（M3-10，PRD 9.5.6）

    /// 勾上「分期」后：这一笔按**全额**记一条支出，同时生成一张期数表。
    ///
    /// 只在「支出 + 负债账户」上出现——储蓄卡当场扣钱，没有「以后每月还」这回事。
    /// 为什么必须记全额而不是记每期分摊额：只记 120.03 会让花呗欠款少算 1,320.36，
    /// PRD 9.3 的欠款公式当场不闭合（细节见 PRD 9.5.6）。
    @ViewBuilder
    private var installmentBlock: some View {
        if vm.canUseInstallment {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("分期")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)

                    Text(vm.installmentEnabled
                         ? "\(vm.installmentPeriods) 期 · 每期 ¥\(MoneyMath.money(vm.installmentPerPeriod))"
                         : "一次性还清")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Toggle("", isOn: $vm.installmentEnabled)
                        .labelsHidden()
                        .tint(accent)
                }

                if vm.installmentEnabled {
                    periodChips
                    perPeriodRow
                    firstDueRow

                    Text(installmentFooter)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    if let message = vm.installmentValidationMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.overdraft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }

    /// 常见期数。不给自定义输入框：真实分期就是 3 / 6 / 12 / 24 这几档，
    /// 多一个键盘字段等于每次记账多一次点击（「记账不打断」是底线之一）。
    private let installmentOptions = [3, 6, 12, 24]

    private var periodChips: some View {
        HStack(spacing: 6) {
            ForEach(installmentOptions, id: \.self) { count in
                let selected = vm.installmentPeriods == count
                Button {
                    vm.installmentPeriods = count
                } label: {
                    Text("\(count) 期")
                        .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.card : Palette.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selected ? accent : Palette.tabBed)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    /// 每期金额。留空就是自动摊平（总额 ÷ 期数，余数落首期）——
    /// 用户从付款页抄来的 120.03 填这里，与总额差几分是正常的。
    private var perPeriodRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("每期")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Spacer(minLength: 0)
            Text("¥")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.faint)
            TextField("自动 " + MoneyMath.money(vm.installmentAutoPerPeriod),
                      text: $vm.installmentPerPeriodText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: 140)
            if !vm.installmentPerPeriodText.isEmpty {
                Button {
                    vm.installmentPerPeriodText = ""
                } label: {
                    Text("自动")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.mine)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("改回自动摊平")
            }
        }
    }

    /// 首期还款日。默认按账户 `dueDay` 推下一个还款日，改过就按改的。
    private var firstDueRow: some View {
        HStack(spacing: 6) {
            Text("首期还款日")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Spacer(minLength: 0)
            DatePicker(
                "",
                selection: Binding(
                    get: { vm.installmentFirstDueDate },
                    set: { vm.installmentFirstDue = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }

    private var installmentFooter: String {
        let per = MoneyMath.money(vm.installmentPerPeriod)
        let first = MoneyMath.money(vm.installmentFirstAmount)
        let split = vm.installmentFirstAmount == vm.installmentPerPeriod
            ? "\(vm.installmentPeriods) 期 × ¥\(per)"
            : "首期 ¥\(first)，其余 \(max(1, vm.installmentPeriods - 1)) 期 × ¥\(per)"
        let total = MoneyMath.money(vm.installmentTotal)
        return "\(split)；总额 ¥\(total) 记一笔支出，之后每月还一期"
    }

    private var receivedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("到账")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Spacer(minLength: 0)
            Text("¥")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.faint)
            TextField("与转出相同", text: Binding(
                get: { vm.receivedText },
                set: { vm.setReceivedText($0) }
            ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - 评分（仅支出）

    private var gradeRow: some View {
        HStack(spacing: 7) {
            Text("值不值")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.faint)
                .padding(.trailing, 1)

            ForEach(SpendGrade.allCases, id: \.self) { grade in
                let selected = vm.grade == grade
                Button {
                    vm.grade = selected ? nil : grade
                } label: {
                    HStack(spacing: 3) {
                        // 正式徽章（Fluent 3D 字块），不用 emoji：emoji 跨设备渲染不一致，和卡面调性也打架
                        Image(grade.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(grade.title)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.card : Palette.ink2)
                    }
                    .padding(.leading, 7)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(selected ? accent : Palette.card)
                    )
                    .overlay(
                        Capsule().strokeBorder(selected ? .clear : Palette.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Button("跳过") { vm.grade = nil }
                .font(.system(size: 11))
                .foregroundStyle(Palette.faint)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 备注

    private var noteRow: some View {
        HStack {
            TextField("备注", text: $vm.note)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
            if !vm.note.isEmpty {
                Button {
                    vm.note = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - 还款专属

    private var repaymentInfo: some View {
        HStack(spacing: 8) {
            Text("本期应还")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Text("¥" + MoneyMath.money(maxDebt))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Text("不计支出")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.overdraft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.overdraftBed)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var maxDebt: Decimal {
        guard let target = vm.target else { return 0 }
        return target.currentBalance < 0 ? -target.currentBalance : 0
    }

    // MARK: - 转账专属

    private var transferDual: some View {
        HStack(alignment: .top, spacing: 6) {
            transferSlot(title: "从", account: vm.payer, candidates: vm.payerCandidates) { account in
                vm.payer = account
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .padding(.top, 44)
            transferSlot(title: "到", account: vm.target, candidates: vm.targetCandidates) { account in
                vm.target = account
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func transferSlot(
        title: String,
        account: Account?,
        candidates: [Account],
        onPick: @escaping (Account) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Palette.sub)
                .padding(.leading, 2)

            Menu {
                ForEach(candidates) { candidate in
                    Button(candidate.displayShortName) { onPick(candidate) }
                }
            } label: {
                if let account {
                    CardFace(account: account, size: .entry)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.card)
                        .frame(width: 158, height: 100)
                        .overlay(
                            Text("选择账户")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.sub)
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// PRD 9.8 允许「填到账金额」**或**「直接填手续费 0.1」两路。
    /// 首版把手续费做成只读展示（真机反馈 #9），这里补上第二个输入框。
    /// 真机反馈 #12：字号 15pt 且排在金额之前，实际没人看见——提到 17pt 并与金额左对齐。
    private var feeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("手续费")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 0)
                Text("¥")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.faint)
                TextField("0.00", text: Binding(
                    get: { vm.feeText },
                    set: { vm.setFeeText($0) }
                ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: 160)
            }
            Text("填手续费或到账，另一边自动算（= 转出 − 到账）")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    // MARK: - 余额预览

    @ViewBuilder
    private var previewBox: some View {
        VStack(spacing: 6) {
            if let payer = vm.payer, let after = vm.payerBalanceAfter {
                if vm.type == .transfer {
                    // 真机反馈 #12：原来只写「余额 ¥x」，看不出这笔在往外走。
                    previewRow(
                        label: "\(payer.displayShortName) 转出",
                        value: after,
                        delta: -vm.amount,
                        deltaTint: Palette.sub
                    )
                } else {
                    previewRow(
                        label: "记下后 · \(payer.displayShortName) \(balanceWord(payer))",
                        value: after
                    )
                }
            }
            if let target = vm.target, let after = vm.targetBalanceAfter {
                if vm.type == .transfer {
                    // 被转账户必须显式写出「到账 +¥x」，否则用户只看到一条转出记录，
                    // 会以为钱没了——数据本来是对的，缺的是这句话。
                    previewRow(
                        label: "\(target.displayShortName) \(transferInWord(target))",
                        value: after,
                        delta: vm.received,
                        deltaTint: Palette.income
                    )
                } else {
                    previewRow(
                        label: "\(target.displayShortName) \(balanceWord(target))",
                        value: after
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.ink.opacity(0.045))
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func previewRow(
        label: String,
        value: Decimal,
        delta: Decimal? = nil,
        deltaTint: Color = Palette.sub
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let delta, delta != 0 {
                Text((delta > 0 ? "+" : "−") + "¥" + MoneyMath.money(abs(delta)))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(deltaTint)
                    .lineLimit(1)
            }
            Text("¥" + MoneyMath.money(abs(value)))
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
    }

    private func balanceWord(_ account: Account) -> String {
        account.kind.isLiability ? "欠款" : "余额"
    }

    /// 转入一个账户时该用哪个词：储蓄/现金是「到账」，信用/借款是「还款」。
    private func transferInWord(_ account: Account) -> String {
        account.kind.isLiability ? "还款" : "到账"
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = vm.errorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.overdraft)
            }

            Button {
                amountFocused = false
                let text = vm.receiptText
                vm.save(in: context)
                if vm.errorMessage == nil {
                    if let text {
                        withAnimation(.easeOut(duration: 0.18)) { receipt = text }
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Text(vm.primaryTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent)
                    )
            }
            .buttonStyle(.plain)
            // 回执停留的那 1.1 秒里必须挡住主按钮，否则手快会连点记成两笔。
            .disabled(!vm.canSave || receipt != nil)
            .opacity(vm.canSave && receipt == nil ? 1 : 0.45)
            .accessibilityLabel(vm.primaryTitle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.page)
    }
}

#Preview {
    EntryView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self], inMemory: true)
}
