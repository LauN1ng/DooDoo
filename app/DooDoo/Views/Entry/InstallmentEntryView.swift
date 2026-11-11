import SwiftData
import SwiftUI

/// 存量分期快速连录（M3-2，PRD 9.5.2 / 9.5.4；M3-3 改为「抄 3 个数」）。
///
/// 为什么单独一个面板、而不塞进「记一笔」：
/// - 存量分期**不是一笔账**，它不动余额，只是把「还剩几期、每期多少、什么时候还」
///   记下来供「本月要还」和结清预测用（PRD 9.5 总原则）。
/// - 记一笔是「一天多次」的动作，要求快；存量录入是「一次性 58 次」的动作，
///   要求**连贯**。两者的最优界面不一样，混在一起会把记一笔拖慢。
///
/// 连贯体现在三处：
/// 1. 顶部常显「还差 N 笔」，看一眼就知道离收工多远；
/// 2. 存完**不关面板**，只清掉这笔独有的字段，账户与还款日留着（58 笔大多共用）；
/// 3. 随时可以「先停，回头再录」，进度存在 `UserDefaults` 里，下次接着录。
///
/// M3-3 的表单收敛：手填从 8 个框降到 3 个（剩余应还 / 总共几期 / 含利息），
/// 每期金额由「剩余应还 ÷ 期数」派生、余数自动落**首期**。当时删掉的「剩余本金」
/// 是**账单上不存在的数**，用户怎么填都填不对。
///
/// M3-5 把「末期金额」单独请了回来（选填）——它跟「剩余本金」性质不同，**账单上明写着**。
/// 末期跟其他期不一样，是因为**退款/贴息的减免抵在了最后一期**（496.65 分 6 期：
/// 中间 83.19，末期 80.66，差的 2.53 就是 60 元退款同步减掉的息）。减免抵哪一期账单不写推导，
/// 给定总额和期数根本推不出单期金额；抄一个末期就能反推（见 `InstallmentMath.splitEndingAt`）。
/// 不填就退回均摊，跟 M3-4 完全一致。
struct InstallmentEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [AppSettings]

    @State private var vm = InstallmentEntryViewModel()
    @FocusState private var focus: Field?
    /// 存完的短回执（「已录 · 还差 57 笔」）。非 nil 时挡住主按钮 1.1 秒，防连点记两笔。
    @State private var receipt: String?
    @State private var targetText = ""
    @State private var showingTargetEditor = false

    private enum Field: Hashable {
        case name, due, remaining, total, interest, last, rebate
    }

    private var accentStyle: AccentStyle { settingsList.first?.accent ?? .ink }
    private var accent: Color { Palette.accent(accentStyle) }

    /// 常见期数。58 笔存量是 3/6/12 期三种（PRD 附录 B），24 期给 e招贷那种。
    private let periodPresets = [3, 6, 12, 24]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    accountStrip
                    mainCard
                    extraCard
                    advancedCard
                    previewBox
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .overlay(alignment: .top) { receiptBanner }
        .task {
            vm.load(context: context)
            // 第一个该填的是「剩余应还」——账单上最大的那个数。
            focus = .due
        }
        .alert("目标几笔？", isPresented: $showingTargetEditor) {
            TextField("58", text: $targetText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {}
            Button("保存") {
                vm.setTarget(Int(targetText.prefix { $0.isNumber }) ?? 0)
            }
        } message: {
            Text("存量在读的分期一共多少笔。填 0 = 不显示进度。")
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("存量分期")
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

            progressBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// 进度条：目标、已录、还差。
    ///
    /// 用两段文字 + 细进度条，不用环形图——这里的信息是「还剩几笔要动手」，
    /// 不是好看的比例。
    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(vm.progressText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(vm.batchRemaining == 0 && vm.target > 0 ? Palette.income : Palette.ink)

                Text("· 已录 \(vm.doneCount)\(vm.target > 0 ? " / \(vm.target)" : "") 笔")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.sub)

                Spacer(minLength: 8)

                Button {
                    targetText = vm.target > 0 ? String(vm.target) : ""
                    showingTargetEditor = true
                } label: {
                    Text("改目标")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.tabBed))
                }
                .buttonStyle(.plain)
            }

            if vm.target > 0 {
                GeometryReader { geo in
                    let ratio = min(CGFloat(1), CGFloat(vm.doneCount) / CGFloat(max(1, vm.target)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.tabBed)
                        Capsule()
                            .fill(accent)
                            .frame(width: max(2, geo.size.width * ratio))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - 账户

    private var accountStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("挂在哪张卡")
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
                .padding(.leading, 2)

            if vm.accounts.isEmpty {
                Text("还没有信用或借款账户。分期只能挂在负债卡上，先去资产页建一张。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.overdraft)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.accounts) { account in
                            accountCard(account)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func accountCard(_ account: Account) -> some View {
        let selected = vm.account?.persistentModelID == account.persistentModelID
        return CardFace(account: account, size: .entryCompact)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Palette.ink : .clear, lineWidth: 2)
            )
            .opacity(selected ? 1 : 0.66)
            .scaleEffect(selected ? 1 : 0.95)
            .animation(.easeOut(duration: 0.15), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .onTapGesture { vm.selectAccount(account) }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel(account.displayShortName)
    }

    // MARK: - 主卡：剩余应还 / 剩余期数 / 每期金额 / 末期金额

    /// 一张卡装下账单上那几个数（剩余应还、第 4/12 期里的期数、末期金额），
    /// 每期金额自动出来。卡片顺序就是核对顺序——从上往下读一遍，正好对上账单。
    private var mainCard: some View {
        card {
            // 剩余应还 —— 账单上最大的那个字
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("剩余应还")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text("¥")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.faint)
                TextField("0.00", text: $vm.remainingDueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .due)
                    .frame(maxWidth: 190)
            }
            Text("账单上「分期剩余应还」那一栏")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Divider().overlay(Palette.line)

            // 剩余期数
            HStack(spacing: 6) {
                Text("剩余期数")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 6)
                TextField("9", text: $vm.remainingText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .remaining)
                    .frame(maxWidth: 70)
                Text("期")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }

            HStack(spacing: 6) {
                ForEach(periodPresets, id: \.self) { value in
                    presetChip(String(value), selected: vm.remainingText == String(value)) {
                        vm.remainingText = String(value)
                        focus = nil
                    }
                }
                presetChip("其他", selected: !periodPresets.map(String.init).contains(vm.remainingText) && !vm.remainingText.isEmpty) {
                    focus = .remaining
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Palette.line)

            // 平均每期 —— 只读派生
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(vm.isUsingLastPeriod ? "中间每期" : "平均每期")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text(vm.split == nil ? "—" : "¥\(MoneyMath.money(vm.perPeriodAmount))")
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(vm.split == nil ? Palette.faint : Palette.ink)
            }
            Text(perPeriodNote)
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Divider().overlay(Palette.line)

            // 末期金额 —— 选填。填了就用它反推中间各期，不再算术平均
            HStack(spacing: 6) {
                Text("末期金额")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Text("选填")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.tabBed)
                    )
                Spacer(minLength: 6)
                Text("¥")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                TextField("0.00", text: $vm.lastPeriodText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .last)
                    .frame(maxWidth: 120)
            }
            Text("账单最后一期的金额。各期金额不一样时才填——填了中间各期就按它反推，不用均价")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 每期金额的来历。写在数字下面一行小字，是为了让用户能**自己验算**。
    ///
    /// 措辞的三条约束，都是被账单打出来的：
    /// 1. 不说「每期」只说「平均每期」——平台给的是首期多、其余相同
    ///    （15.34 ÷ 3 → 5.12 / 5.11 / 5.11），各期并不相等。填了末期金额之后
    ///    中间各期是确定的，标签换成「中间每期」。
    /// 2. 不说「末期收零头」也不说「首期收零头」这种像账本条文的词，只说
    ///    「多出的 ¥x 并进首期」——**这是我们的摊法，不是账单的规则**。
    ///    真实单期 = 本金均摊 + 该期利息，而利息本身是按期均分的（平息）；
    ///    之所以有期数跟平均值不同，是因为**减免抵在了那一期**（496.65 分 6 期：
    ///    中间 83.19，末期 80.66 = 抵掉 60 元退款同步减去的 2.53 元息）。
    /// 3. 填了末期就露出算式「(总额 − 末期) ÷ (期数 − 1)」，用户能立刻用账单验算；
    ///    这正是 M3-5 敢把「减免落在哪一期」交给一个输入框而不是算法的原因。
    private var perPeriodNote: String {
        guard let split = vm.split else {
            return "填上面两个数，自动算出来"
        }
        let rounding = split.firstPeriod != split.perPeriod
            ? "，多出的 ¥\(MoneyMath.money(split.firstPeriod - split.perPeriod)) 并进首期"
            : ""
        if vm.isUsingLastPeriod, vm.periods.remaining > 1 {
            return "= (¥\(MoneyMath.money(vm.remainingDue)) − 末期 ¥\(MoneyMath.money(split.lastPeriod)))"
                + " ÷ \(vm.periods.remaining - 1) 期\(rounding)"
        }
        return "= ¥\(MoneyMath.money(vm.remainingDue)) ÷ \(vm.periods.remaining) 期均摊\(rounding)"
    }

    private func presetChip(_ title: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.card : Palette.ink2)
                .frame(minWidth: 38)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? accent : Palette.tabBed)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 次卡：名称 / 总共几期 / 含利息 / 还款日

    private var extraCard: some View {
        card {
            // 名称（选填，58 笔要靠它区分）
            TextField(vm.resolvedName, text: $vm.name)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .focused($focus, equals: .name)
            Text("留空就叫「\(vm.resolvedName)」")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Divider().overlay(Palette.line)

            // 总共几期
            HStack(spacing: 6) {
                Text("总共几期")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 6)
                TextField("12", text: $vm.totalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .total)
                    .frame(maxWidth: 80)
                Text("期")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
            }
            Text(periodBreakdown)
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Divider().overlay(Palette.line)

            // 含利息 —— 年化的唯一输入
            HStack(spacing: 6) {
                Text("含利息")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 6)
                Text("¥")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                TextField("176.99", text: $vm.interestText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .interest)
                    .frame(maxWidth: 120)
            }
            Text("账单上「含利息」那一栏，不是每期利息×期数")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Divider().overlay(Palette.line)

            // 下一期还款日
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一期还款日")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.sub)
                    Text("账户的还款日自动带出，可以改")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 8)
                DatePicker("", selection: $vm.dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
    }

    private var periodBreakdown: String {
        guard vm.totalPeriods != nil else {
            return "填了才能显示「第 4/12 期」，也是算年化需要的分母"
        }
        let p = vm.periods
        return "第 \(p.paid + 1)/\(p.total) 期起 · 未来 \(p.remaining) 期"
    }

    // MARK: - 高级

    private var advancedCard: some View {
        card {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { vm.showingAdvanced.toggle() }
            } label: {
                HStack {
                    Text("已享减免")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink2)
                    Spacer(minLength: 8)
                    Text("选填")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                    Image(systemName: vm.showingAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if vm.showingAdvanced {
                Divider().overlay(Palette.line)
                moneyRow("国家贴息等", placeholder: "如 12.22", text: $vm.rebateText, field: .rebate)
                Text("只是记下来，不从每期金额里扣——那是已经优惠掉的，不是还要还的钱。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private func moneyRow(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Spacer(minLength: 8)
            Text("¥")
                .font(.system(size: 12))
                .foregroundStyle(Palette.faint)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .focused($focus, equals: field)
                .frame(maxWidth: 150)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 预览

    /// 预览承担三件事：**核对**（剩余总额是否等于账单）、**全貌**（整笔一共多少）、
    /// **揭示**（真实年化）。
    ///
    /// 剩余总额那一行不用「与账单一致」这种自我肯定的话——数字就是用户抄进去的。
    /// 有价值的是左边「剩 9 期 × ¥203.35」：用户拿每期金额跟账单对一眼，
    /// 就知道「除出来」的结果对不对。
    ///
    /// 整笔那一行是给「已经还了几期」的老分期用的：58 笔存量里大半都不是新分期，
    /// 只给剩余额等于只回答了一半问题（用户 11-11：「能不能把全部金额算出来展示」）。
    private var previewBox: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(previewLeftText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(vm.periods.remaining > 0 ? "共 ¥\(MoneyMath.money(vm.previewRemainingTotal))" : "—")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }

            // 整笔总额。存量录入的一大半是「已经还了几期」的老分期，
            // 用户真正想知道的是「这笔当初一共多少 / 我一共要还多少」——
            // 只给剩余额等于只回答了一半。
            if let grand = vm.previewGrandTotal, let total = vm.totalPeriods {
                HStack(spacing: 6) {
                    Text(grandTotalLabel(total: total))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.sub)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("约 ¥\(MoneyMath.money(grand))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Text("真实年化（整笔）")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text(MoneyMath.percent(vm.previewAnnualRate))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(vm.previewAnnualRate == nil ? Palette.faint : Palette.owe)
            }

            if let hint = vm.annualRateHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.ink.opacity(0.045))
        )
    }

    /// 左侧说明。除不尽时不能写「× 平均每期」——那会跟右边的总额差几分钱，
    /// 用户一乘就发现对不上。改成点出首期多出来的那一点，两边就自洽了：
    /// 5.12 + 5.11 × 2 = 15.34，正好等于右边。
    private var previewLeftText: String {
        guard vm.periods.remaining > 0 else { return "填完上面就能核对总额" }
        // 填了末期就不能写「× 中间每期」——那会跟右边差额，用户一乘就发现对不上。
        if vm.isUsingLastPeriod, let split = vm.split, vm.periods.remaining > 1 {
            return "剩 \(vm.periods.remaining) 期 · 末期 ¥\(MoneyMath.money(split.lastPeriod))"
        }
        if let first = vm.firstPeriodAmount {
            return "剩 \(vm.periods.remaining) 期 · 首期 ¥\(MoneyMath.money(first))"
        }
        return "剩 \(vm.periods.remaining) 期 × ¥\(MoneyMath.money(vm.perPeriodAmount))"
    }

    /// 「整笔 12 期 · 已还 1 期」。没还过就不写「已还 0 期」，那是废话。
    private func grandTotalLabel(total: Int) -> String {
        let paid = vm.periods.paid
        return paid > 0 ? "整笔 \(total) 期 · 已还 \(paid) 期" : "整笔 \(total) 期"
    }

    // MARK: - 回执

    @ViewBuilder
    private var receiptBanner: some View {
        if let receipt {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                Text(receipt)
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.ink.opacity(0.92))
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .allowsHitTesting(false)
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
                focus = nil
                guard vm.save(in: context) else { return }
                let remaining = vm.batchRemaining
                let text = remaining > 0 ? "已录 · 还差 \(remaining) 笔" : "已录 · 目标已达成"
                withAnimation(.easeOut(duration: 0.18)) { receipt = text }
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(.easeOut(duration: 0.18)) { receipt = nil }
                    focus = .due
                }
            } label: {
                Text(vm.primaryTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent)
                    )
            }
            .buttonStyle(.plain)
            // 回执停留的 1.1 秒里挡住主按钮，否则手快会连点记成两笔（同记一笔的处理）。
            .disabled(!vm.canSave || receipt != nil)
            .opacity(vm.canSave && receipt == nil ? 1 : 0.45)

            Button {
                dismiss()
            } label: {
                Text("先停，回头再录")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Palette.page)
    }

    // MARK: - 卡片容器

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
    }
}

#Preview {
    InstallmentEntryView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, AppSettings.self], inMemory: true)
}
