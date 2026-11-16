import SwiftData
import SwiftUI

/// 记一笔（M1b）。四类型共用一套骨架，按 `type` 换字段。
///
/// 依据 `docs/design/spec/记一笔规格冻结-v2.1.md`：
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
    /// 当前由自绘键盘编辑的数值字段（M4 第 5 条：系统键盘割裂，改自绘）。
    /// 不是 `@FocusState`——这些字段已经不是 `TextField` 了，聚焦由我们自己管。
    @State private var activeField: NumberField = .amount
    /// 键盘是否展开。**默认收起**（v2.1，用户 2026-11-16 定案）：
    /// 一块 242pt 的键盘常驻会把分类网格、评分、备注全推出屏幕。
    /// 收起后只占约 44pt，点金额（或上滑抓条）才拉上来。
    @State private var padOpen = false
    /// 备注仍在用系统键盘（它是文本，不是数）。它一聚焦就把自绘键盘收起来，
    /// 两块键盘同时在场会把输入区挤成一条缝。
    @FocusState private var noteFocused: Bool
    /// 转账保存后的短回执。非 nil 时先显示 1.1 秒再关面板（真机反馈 #12）。
    @State private var receipt: String?

    // MARK: - 评分位动画状态（M4 2026-11-16）

    /// 徽章是否已落位。`false` = 要么还没评分，要么正在从 0.72 弹入。
    @State private var gradeIconShown = false
    /// 档位文字是否已出现。比徽章晚 40ms，**不同步是刻意的**：先立图标再出字，
    /// 两者同帧出现会读成「一行字带个图标」，反了。
    @State private var gradeTextShown = false
    /// 果冻动画的触发计数，每次换档 +1（`keyframeAnimator` 见到新值重播一遍）。
    @State private var gradeIconTick = 0
    @State private var gradeTextTick = 0
    /// 首次评分的「空位框退场」是否还在播。播完置 false，框从此不再出现。
    @State private var gradeFrameExiting = false
    /// 空位框退场的形变量：缩到 0.18 + 透明，130ms。**没有模糊**——
    /// 模糊会让它和同时出现的徽章糊成一片，那正是「割裂」的来源。
    @State private var gradeFrameScale: CGFloat = 1
    @State private var gradeFrameOpacity: Double = 1

    /// 面板里需要数字键盘的字段。备注不在其中。
    private enum NumberField: Hashable {
        case amount, received, fee, perPeriod

        /// 收起时提示「上滑输入 ×」用的名字，跟界面上那一行标签一致。
        var title: String {
            switch self {
            case .amount: return "金额"
            case .received: return "到账"
            case .fee: return "手续费"
            case .perPeriod: return "每期金额"
            }
        }
    }

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
        // 顺序即位置：先挂页脚，再把键盘挂在它外面 → 键盘在底、主按钮在键盘正上方。
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .safeAreaInset(edge: .bottom, spacing: 0) { numberPadArea }
        .overlay { receiptBanner }
        // 备注一聚焦就把数字键盘收掉：系统键盘要占底部，两块键盘不能叠。
        .onChange(of: noteFocused) { _, focused in
            if focused, padOpen { setPad(open: false) }
        }
        // 分类切换会把档位换成该分类上次的档位（PRD 9.13 规则 3），也可能换回 nil。
        // 本视图自己点击时 `gradeFrameExiting` 已置位，这里直接让路，避免和 tapGrade 的时序打架。
        .onChange(of: vm.grade) { _, newValue in
            guard !gradeFrameExiting else { return }
            if newValue == nil {
                gradeIconShown = false
                gradeTextShown = false
                gradeFrameScale = 1
                gradeFrameOpacity = 1
            } else {
                gradeIconShown = true
                gradeTextShown = true
                gradeIconTick += 1
                gradeTextTick += 1
            }
        }
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
            activeField = .amount
            // 兜底：载入或切类型后可能已经带着档位（分类记忆），图标要直接立住，
            // 不能停在 `gradeIconShown == false` 那个「还没落位」的状态上。
            gradeIconShown = vm.grade != nil
            gradeTextShown = vm.grade != nil
        }
    }

    // MARK: - 自绘键盘

    /// 键盘坞。默认收起；点金额行、或上滑抓条把键盘拉上来，下滑 / 点抓条收起。
    ///
    /// 收起态底部只有约 44pt（抓条 + 「上滑输入金额」），把 242pt 还给内容——
    /// 分类网格、评分、备注重新回到一屏内。
    @ViewBuilder
    private var numberPadArea: some View {
        // 备注键盘在场时整块坞一起让开：只收键盘留根抓条，抓条会浮在系统键盘上，
        // 想点它还会在系统键盘上方再开一块——两块键盘同屏，正是 v2.0 想避免的。
        if !noteFocused {
            NumberPadDock(
                isOpen: padOpen,
                hint: "上滑输入\(activeField.title)",
                onToggle: { setPad(open: $0) }
            ) {
                NumberPad(
                    text: activeBinding,
                    accent: accent,
                    accentWash: accentWash
                )
            }
        }
    }

    /// 展开 / 收起。动画写在这一处，`safeAreaInset` 的高度跟着它一起变，
    /// 页面内容是被"推"上来的，不是跳一下。
    private func setPad(open: Bool) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            padOpen = open
        }
    }

    /// 键盘当前在改哪个字段。
    ///
    /// 每个 setter 都必须走 ViewModel 的方法而不是直接赋值：转账的三个数
    /// 是联动的（改转出会带动到账或手续费），绕过 setter 会让联动断掉。
    private var activeBinding: Binding<String> {
        switch activeField {
        case .amount:
            return Binding(get: { vm.amountText }, set: { vm.setAmountText($0) })
        case .received:
            return Binding(get: { vm.receivedText }, set: { vm.setReceivedText($0) })
        case .fee:
            return Binding(get: { vm.feeText }, set: { vm.setFeeText($0) })
        case .perPeriod:
            return Binding(get: { vm.installmentPerPeriodText },
                           set: { vm.installmentPerPeriodText = $0 })
        }
    }

    /// 切换正在编辑的字段，并把键盘拉上来。
    /// 备注键盘还在的话先收掉——两块键盘永不同屏。
    private func activate(_ field: NumberField) {
        activeField = field
        // 解备注焦点与开键盘放进同一个事务：坞是从"隐藏"变成"展开"整块插进来的，
        // 分两次改会先看见抓条闪一下再长出键盘。
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if noteFocused { noteFocused = false }
            padOpen = true
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
                // 回执必须让开底部那两块：键盘展开时 = 坞 254（抓条 20 + 键盘 226 + 下内距 8）
                // + 页脚 72；收起时只剩坞 44 + 页脚 72。写死一个值必然有一边被盖住。
                .padding(.bottom, padOpen ? 344 : 130)
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
                    // 切类型只是把默认字段换回金额，**不弹键盘**：
                    // 用户可能只是想看看还款/转账要填什么，不该被键盘挡一眼。
                    if noteFocused { noteFocused = false }
                    activeField = .amount
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
                onSelectTop: { vm.selectTop($0) },
                onSelectSub: { vm.selectSub($0) },
                onCollapse: { vm.showingSub = false }
            )
            .padding(.top, 4)

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

    /// 金额。46pt 是规格里的主角字号（第九节未锁定项 5：42~50 可调）。
    ///
    /// 自绘键盘上线后这里不再是 `TextField`：显示 `NumberValueText`，
    /// 整行挂点击、点哪都算「我要改金额」（行高 70 远超 44pt 命中区下限）。
    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Spacer(minLength: 0)
            Text("¥")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.faint)
            NumberValueText(
                text: vm.amountText,
                placeholder: "0.00",
                size: 46,
                weight: .bold,
                active: padOpen && activeField == .amount,
                accent: accent
            )
            .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { activate(.amount) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("金额")
        .accessibilityValue(vm.amountText.isEmpty ? "未填写" : vm.amountText)
        .accessibilityHint("用下方数字键盘输入")
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
                            Capsule().fill(selected ? Palette.accentFill(accentStyle) : Palette.tabBed)
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
            NumberValueText(
                text: vm.installmentPerPeriodText,
                placeholder: "自动 " + MoneyMath.money(vm.installmentAutoPerPeriod),
                size: 17,
                weight: .semibold,
                active: padOpen && activeField == .perPeriod,
                accent: accent
            )
            .frame(maxWidth: 150, alignment: .trailing)
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
        .contentShape(Rectangle())
        .onTapGesture { activate(.perPeriod) }
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
            NumberValueText(
                text: vm.receivedText,
                placeholder: "与转出相同",
                size: 26,
                weight: .semibold,
                active: padOpen && activeField == .received,
                accent: accent
            )
            .frame(maxWidth: 200, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture { activate(.received) }
    }

    // MARK: - 评分位（仅支出，嵌在备注卡右侧）
    //
    // 2026-11-16 定案，推翻 v2.0 的「四档 chip 并排 + 跳过」：
    // ① 只显示**一枚**徽章，位置在备注卡内、竖虚线右侧——不单独占一行；
    // ② 四档不再并排，也没有「值不值」三个字，颜色全部由徽章素材自己提供；
    // ③ 未评分不是 NPC，而是一个 21pt 虚线空位 + 加号；点一下才落第一档；
    // ④ 点过之后只在这四档里循环，**永不回到空位**（虚线消失是彻底的）。
    //
    // 几何对齐（这轮最关键的一处，别再凭感觉改）：
    // 徽章原图 80px、内容 76px、圆角约 8px → 圆角只占 11.4%，显示 22pt 时圆角 2.5pt。
    // 所以空位框必须做成 **21pt / 圆角 2.5**（不是 28 / 6.6）：尺寸和圆角都贴住徽章，
    // 徽章长满时才能把它完整盖掉。框大一圈、圆角大一倍，眼睛就会读成「一个框罩着一个图标」，
    // 那才是之前反复出现的「割裂感」的真正来源。

    /// 竖向虚线隔断。SwiftUI 没有现成的虚线直线，用 0 宽 Path 描边。
    private struct DashedRule: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }

    /// 档位文字区定宽：四档文案宽度差 13pt（「拉完了」39.6 / 「飘了」26.4），
    /// 不锁宽就会看见左侧「备注」被顶得抖一下。
    private let gradeLabelWidth: CGFloat = 46
    private let gradeBadgeSide: CGFloat = 22
    private let gradeSlotSide: CGFloat = 21

    private var gradePill: some View {
        HStack(spacing: 12) {
            DashedRule()
                .stroke(Palette.dividerDash, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: 1.2, height: 30)

            Button(action: tapGrade) {
                HStack(spacing: 6) {
                    gradeBadge
                    gradeLabel
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("消费评分")
            .accessibilityValue(vm.grade?.entryTitle ?? "未评分")
            .accessibilityHint("点一下开始评分，再点切换档位")
        }
    }

    @ViewBuilder
    private var gradeBadge: some View {
        ZStack {
            // 空位：只在「还没评分」或「首次评分的 300ms 退场」里存在
            if vm.grade == nil || gradeFrameExiting {
                gradeSlot
                    .scaleEffect(gradeFrameScale)
                    .opacity(gradeFrameOpacity)
            }
            if let grade = vm.grade {
                Image(grade.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: gradeBadgeSide, height: gradeBadgeSide)
                    // 首次落位：0.72 → 1，spring 自带 6% 过冲，和 `keyframeAnimator` 的果冻
                    // 是相乘关系（果冻此时停在静止帧，不参与）
                    .scaleEffect(gradeIconShown ? 1 : 0.72)
                    .opacity(gradeIconShown ? 1 : 0)
                    .modifier(GradeJelly(tick: gradeIconTick))
            }
        }
        .frame(width: gradeBadgeSide, height: gradeBadgeSide)
    }

    /// 空位中央的加号。用 `Shape` 而不是 `Path` 视图：`Path` 作为 View 时尺寸跟着路径走，
    /// 居中会偏；`Shape` 一定铺满交给它的 21×21 frame。
    private struct GradePlus: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let half = min(rect.width, rect.height) * 0.171  // 臂长 7.2pt / 边长 21pt
            path.move(to: CGPoint(x: c.x, y: c.y - half))
            path.addLine(to: CGPoint(x: c.x, y: c.y + half))
            path.move(to: CGPoint(x: c.x - half, y: c.y))
            path.addLine(to: CGPoint(x: c.x + half, y: c.y))
            return path
        }
    }

    /// 21pt 的空位：虚线圆角框 + 加号。两个都只出 44%/52% 的灰，
    /// 因为它表达的是「这里可以填」，不是「已经选了 NPC」。
    private var gradeSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(
                    Palette.gradeVacant.opacity(0.44),
                    style: StrokeStyle(lineWidth: 1.05, dash: [2.9, 2.6])
                )
            GradePlus()
                .stroke(
                    Palette.gradeVacant.opacity(0.52),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                )
                // 退场一开始就让加号先走（它比框更「细」，留到最后会显脏）
                .opacity(vm.grade == nil ? 1 : 0)
        }
        .frame(width: gradeSlotSide, height: gradeSlotSide)
    }

    @ViewBuilder
    private var gradeLabel: some View {
        if let grade = vm.grade {
            Text(grade.entryTitle)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(Palette.gradeTint(grade))
                .lineLimit(1)
                .frame(width: gradeLabelWidth, alignment: .leading)
                .opacity(gradeTextShown ? 1 : 0)
                .modifier(GradeTextJelly(tick: gradeTextTick))
        } else {
            Color.clear
                .frame(width: gradeLabelWidth, height: 16)
        }
    }

    /// 点评分位。
    ///
    /// - 空位 → 首次评分：加号消失 + 空位框收到 0.18 硬消失（130ms），
    ///   100ms 后徽章从 0.72 弹入，140ms 后文字弹入。两者在时间上错开，
    ///   **不存在「框和徽章各占一半」的叠加帧**。
    /// - 已有档位 → 四档顺次循环，只播果冻。
    private func tapGrade() {
        guard vm.type == .expense else { return }

        if let current = vm.grade {
            // 连点时退场还没播完，先把它收干净再换档（否则框会跟着果冻一起缩）
            if gradeFrameExiting { finishGradeFrameExit() }
            vm.grade = nextGrade(after: current)
            gradeIconTick += 1
            gradeTextTick += 1
            return
        }

        // 顺序不能反：先置「退场中」，再改档位——否则 `onChange(of: vm.grade)` 会把
        // 图标当成「分类带出的档位」直接立起来，交接动画就没了。
        gradeFrameExiting = true
        gradeIconShown = false
        gradeTextShown = false

        // 加号 70ms 先走，框紧接着 130ms 收到 0.18 消失
        withAnimation(.easeIn(duration: 0.07)) {
            vm.grade = .hang
        }
        withAnimation(.easeIn(duration: 0.13)) {
            gradeFrameScale = 0.18
            gradeFrameOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.spring(response: 0.26, dampingFraction: 0.66)) {
                gradeIconShown = true
            }
            try? await Task.sleep(for: .milliseconds(40))
            // tick 必须在这里加、不能跟 `vm.grade` 同一批改：那一刻文字视图才刚被创建，
            // `keyframeAnimator` 初始化的 trigger 就等于新值，看不到变化就不播。
            withAnimation(.easeOut(duration: 0.12)) {
                gradeTextShown = true
            }
            gradeTextTick += 1
            try? await Task.sleep(for: .milliseconds(240))
            finishGradeFrameExit()
        }
    }

    private func finishGradeFrameExit() {
        // 用无动画赋值：框已经不可见，再补一段过渡只会让它在回来的路上闪一下。
        //
        // 这里**不能**自己构造 `Transaction`：本项目 SDK 的 `Transaction` 只暴露
        // `init(backingData:)` 这个内部入口，`Transaction()` 与 `Transaction(animation:)`
        // 都会挂（CI #84 / #85 连续两次报的就是这个）。`withAnimation(nil)` 是公开 API，
        // 语义等价且不会碰内部构造器。
        withAnimation(nil) {
            gradeFrameExiting = false
            gradeFrameScale = 1
            gradeFrameOpacity = 1
        }
    }

    private func nextGrade(after grade: SpendGrade) -> SpendGrade {
        switch grade {
        case .hang: .piao
        case .piao: .la
        case .la: .npc
        case .npc: .hang
        }
    }

    // MARK: - 备注

    private var noteRow: some View {
        HStack(spacing: 10) {
            TextField("备注", text: $vm.note)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .focused($noteFocused)
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
            // 评分位只在支出时挂在备注卡里（还款/转账的备注卡不长这条虚线）
            if vm.type == .expense {
                gradePill
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        // 支出这一行要装 44pt 的评分点击区，高度按 64 走；其余类型保持原样（13 内距）。
        .padding(.vertical, vm.type == .expense ? 11 : 13)
        .frame(minHeight: vm.type == .expense ? 64 : nil)
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
                NumberValueText(
                    text: vm.feeText,
                    placeholder: "0.00",
                    size: 17,
                    weight: .semibold,
                    active: padOpen && activeField == .fee,
                    accent: accent
                )
                .frame(maxWidth: 160, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { activate(.fee) }
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

    // MARK: - 果冻动画（S1，2026-11-16 定案）

    /// 果冻的插值状态。属性一律用 `Double`：`KeyframeTrack` 对 `Double` 的支持最确定。
    private struct GradeMotionState {
        var scaleX: Double = 1
        var scaleY: Double = 1
        var rotation: Double = 0
    }

    private struct GradeTextMotionState {
        var scaleX: Double = 1
        var scaleY: Double = 1
    }

    /// 档位徽章的果冻：压扁 → 拉长 → 回正，带 ±8° 的轻微旋转。
    ///
    /// 用 `keyframeAnimator` 而不是 `phaseAnimator`：前者在 trigger 变化时**播一遍就停**，
    /// 后者按 phase 循环播放，图标会一直抖。440ms 是四段之和；
    /// 「灵动」全靠 1.18 那一帧的过冲，别把峰值削平。
    private struct GradeJelly: ViewModifier {
        var tick: Int

        func body(content: Content) -> some View {
            content.keyframeAnimator(initialValue: GradeMotionState(), trigger: tick) { view, motion in
                view
                    .scaleEffect(x: CGFloat(motion.scaleX), y: CGFloat(motion.scaleY))
                    .rotationEffect(.degrees(motion.rotation))
            } keyframes: { _ in
                KeyframeTrack(\GradeMotionState.scaleX) {
                    CubicKeyframe(0.80, duration: 0.09)
                    CubicKeyframe(1.18, duration: 0.13)
                    CubicKeyframe(0.95, duration: 0.11)
                    CubicKeyframe(1.00, duration: 0.11)
                }
                KeyframeTrack(\GradeMotionState.scaleY) {
                    CubicKeyframe(0.90, duration: 0.09)
                    CubicKeyframe(1.08, duration: 0.13)
                    CubicKeyframe(1.02, duration: 0.11)
                    CubicKeyframe(1.00, duration: 0.11)
                }
                KeyframeTrack(\GradeMotionState.rotation) {
                    CubicKeyframe(-8, duration: 0.09)
                    CubicKeyframe(5, duration: 0.13)
                    CubicKeyframe(-2, duration: 0.11)
                    CubicKeyframe(0, duration: 0.11)
                }
            }
        }
    }

    /// 档位文字的果冻：同一条节奏，幅度收到徽章的一半以下（文字大幅缩放会读不清）。
    /// 锚点固定在 **leading**——中文左对齐，从中心缩放会让第一个字往左爬出图标。
    private struct GradeTextJelly: ViewModifier {
        var tick: Int

        func body(content: Content) -> some View {
            content.keyframeAnimator(initialValue: GradeTextMotionState(), trigger: tick) { view, motion in
                view.scaleEffect(x: CGFloat(motion.scaleX), y: CGFloat(motion.scaleY), anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack(\GradeTextMotionState.scaleX) {
                    CubicKeyframe(0.84, duration: 0.118)
                    CubicKeyframe(1.035, duration: 0.078)
                    CubicKeyframe(0.99, duration: 0.084)
                    CubicKeyframe(1.00, duration: 0.084)
                }
                KeyframeTrack(\GradeTextMotionState.scaleY) {
                    CubicKeyframe(1.08, duration: 0.118)
                    CubicKeyframe(0.985, duration: 0.078)
                    CubicKeyframe(1.012, duration: 0.084)
                    CubicKeyframe(1.00, duration: 0.084)
                }
            }
        }
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
                noteFocused = false
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
                            .fill(Palette.accentFill(accentStyle))
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
