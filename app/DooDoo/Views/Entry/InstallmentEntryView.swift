import SwiftData
import SwiftUI

/// 存量分期快速连录（M3-2，PRD 9.5.2 / 9.5.4）。
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
        case name, remaining, total, perPeriod, first, last, principal, interest, rebate
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
                    nameCard
                    periodCard
                    amountCard
                    dueDateCard
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
            focus = .perPeriod
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

    // MARK: - 名称

    private var nameCard: some View {
        card {
            TextField(vm.resolvedName, text: $vm.name)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .focused($focus, equals: .name)
            Divider().overlay(Palette.line)
            Text("留空就叫「\(vm.resolvedName)」")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.faint)
        }
    }

    // MARK: - 期数

    private var periodCard: some View {
        card {
            HStack(spacing: 6) {
                Text("剩余期数")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 6)
                TextField("9", text: $vm.remainingText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .remaining)
                    .frame(maxWidth: 80)
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

            HStack(spacing: 6) {
                Text("总共几期")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                Text("选填")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 6)
                TextField("—", text: $vm.totalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink2)
                    .focused($focus, equals: .total)
                    .frame(maxWidth: 80)
            }

            Text(vm.totalPeriods == nil
                 ? "填了才能显示「第 6/12 期」；不填就只算未来期。"
                 : periodBreakdown)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.faint)
        }
    }

    private var periodBreakdown: String {
        let p = vm.periods
        return "第 \(p.paid + 1)/\(p.total) 期起 · 未来 \(p.remaining) 期"
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

    // MARK: - 每期金额

    private var amountCard: some View {
        card {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("每期金额")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text("¥")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.faint)
                TextField("0.00", text: $vm.perPeriodText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .perPeriod)
                    .frame(maxWidth: 190)
            }
        }
    }

    // MARK: - 还款日

    private var dueDateCard: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一期还款日")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.sub)
                    Text("不是历史第一期；照账单填「下次什么时候还」")
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

    // MARK: - 高级

    private var advancedCard: some View {
        card {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { vm.showingAdvanced.toggle() }
            } label: {
                HStack {
                    Text("首期/末期金额、剩余本金、总利息、减免")
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
                moneyRow("首期金额", placeholder: "与每期相同", text: $vm.firstText, field: .first)
                moneyRow("末期金额", placeholder: "与每期相同", text: $vm.lastText, field: .last)
                moneyRow("剩余本金", placeholder: "账单上的欠款", text: $vm.principalText, field: .principal)
                moneyRow("总利息", placeholder: "如 110.56", text: $vm.interestText, field: .interest)
                moneyRow("已享减免", placeholder: "如 0.57", text: $vm.rebateText, field: .rebate)
                Text("减免单独存一栏，不从每期金额里扣——那是已经优惠掉的，不是还要还的钱。")
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

    private var previewBox: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("剩 \(vm.periods.remaining) 期 × ¥\(MoneyMath.money(vm.perPeriodAmount))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("共 ¥\(MoneyMath.money(vm.previewRemainingTotal))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("真实年化（估算）")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.sub)
                Spacer(minLength: 8)
                Text(MoneyMath.percent(vm.previewAnnualRate))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(vm.previewAnnualRate == nil ? Palette.faint : Palette.owe)
            }

            if vm.previewAnnualRate == nil {
                Text("填「剩余本金」或「总利息」就能反算。这是所有平台都不显示、但最该看的数字。")
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
                    focus = .perPeriod
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
