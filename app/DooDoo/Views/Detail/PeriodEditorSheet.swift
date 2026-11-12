import SwiftUI
import SwiftData

/// 分期逐期改金额（PROGRESS 下一步 2 的「逐期改」，规格第六节说展示在本页、
/// 改动在「分期详情页」——这里就是那个详情页的最小形态）。
///
/// 为什么需要它：`InstallmentPeriod` 落库的意义就是「任意一期都能被账单改正」
/// （`isManualOverride` 字段从 M3 起就为这件事留着）。等额均摊只是按「零头进首期」
/// 推出来的草稿；提前还款、平台调整、账单末期抵扣都只有账单知道。
struct PeriodEditorSheet: View {
    let installment: Installment

    @Environment(\.dismiss) private var dismiss
    @Query private var allPeriods: [InstallmentPeriod]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(periods) { period in
                        NavigationLink {
                            PeriodEditView(period: period)
                        } label: {
                            row(period)
                        }
                    }
                } footer: {
                    Text("点某一期可以改金额和还款日。改过的那期会被标记，重新生成期表时不会被覆盖。")
                }
            }
            .navigationTitle(installment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var periods: [InstallmentPeriod] {
        allPeriods
            .filter { $0.installmentKey == installment.key }
            .sorted { $0.index < $1.index }
    }

    private func row(_ period: InstallmentPeriod) -> some View {
        HStack(spacing: 10) {
            Text("第 \(period.index) 期")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, alignment: .leading)

            Text(MonthDay.text(period.dueDate))
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)

            Spacer(minLength: 8)

            Text(MoneyMath.money(period.amount))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(period.paidAt != nil ? Palette.sub : Palette.ink)

            if period.isManualOverride {
                Text("改过")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.pillOn))
            }
        }
        .padding(.vertical, 2)
    }
}

/// 单期编辑。金额与日期都是**实时写回**：SwiftData 的 `@Model` 是引用类型，
/// 改完自动持久化，不需要「保存」按钮，也就不会出现「改了没生效」。
private struct PeriodEditView: View {
    @Bindable var period: InstallmentPeriod

    @Environment(\.modelContext) private var context
    @Query private var allInstallments: [Installment]
    @Query private var allPeriods: [InstallmentPeriod]
    @Query private var allAccounts: [Account]

    @State private var amountText: String = ""
    @State private var didLoad = false
    @State private var showingPayerPicker = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("金额") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .onChange(of: amountText) { _, newValue in
                            guard didLoad, let value = parsed(newValue) else { return }
                            period.amount = value
                            period.isManualOverride = true
                            syncRemainingDue()
                        }
                }

                DatePicker("还款日", selection: $period.dueDate, displayedComponents: .date)
                    .onChange(of: period.dueDate) {
                        period.isManualOverride = true
                    }

                if period.paidAt == nil {
                    Button("标记本期已还") { showingPayerPicker = true }
                } else {
                    LabeledContent("已还", value: MoneyMath.money(period.amount))
                    Button("撤销还款", role: .destructive) { undoPayment() }
                }
            } footer: {
                Text(period.paidAt == nil
                     ? "标记已还时会同时记一笔还款流水：从扣款卡扣钱、冲减信用账户欠款，两处一起动。"
                     : "撤销会把那笔还款流水一并软删除，欠款和余额都退回去。")
            }
        }
        .navigationTitle("第 \(period.index) 期")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            amountText = MoneyMath.plain(period.amount)
            didLoad = true
        }
        .confirmationDialog("从哪里扣款？", isPresented: $showingPayerPicker, titleVisibility: .visible) {
            ForEach(payerAccounts) { account in
                Button(account.name) { pay(from: account) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("还款 \(MoneyMath.money(period.amount))：从选中的卡扣钱，同时冲减这张信用账户的欠款。")
        }
        .alert("记还款失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("知道了", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    /// 扣款来源只能是储蓄 / 现金——用信用卡还信用卡不是还款。
    private var payerAccounts: [Account] {
        allAccounts.filter { $0.kind == .savings || $0.kind == .cash }
    }

    private var plan: Installment? {
        allInstallments.first { $0.key == period.installmentKey }
    }

    /// 标记已还 = **两件事一起做**：写一条 `repayment` 流水（扣款卡 −x、信用账户 +x
    /// 即欠款减少）+ 标 `paidAt`。只标期表不写流水的话，欠款会减少但余额和流水列表
    /// 一动不动，两处慢慢分叉——用户 2026-11-12 问「还款要不要做进流水」就是这件事。
    private func pay(from payer: Account) {
        guard let plan, let card = plan.account else {
            errorText = "这条分期没有挂在任何账户上，无法记还款。"
            return
        }
        do {
            let tx = try LedgerService.insert(
                amount: period.amount,
                kind: .repayment,
                date: .now,
                note: "\(plan.name) 第 \(period.index) 期",
                account: payer,
                toAccount: card,
                in: context
            )
            // 把流水绑回分期计划，撤销时靠它找回来。
            tx.installmentKey = plan.key
            period.paidAt = .now
            syncRemainingDue()
            try context.save()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 撤销还款：软删那条流水（余额与欠款一起退回）+ 清 `paidAt`。
    private func undoPayment() {
        if let plan {
            // 还款流水的付款方是扣款卡（`account`），被还的信用卡只出现在 `toAccount` 上，
            // 所以要从 `incomingTransactions` 里找——查 `transactions` 永远是空的。
            let matches: [Transaction] = (plan.account?.incomingTransactions ?? []).filter { tx in
                tx.kind == .repayment
                    && tx.deletedAt == nil
                    && tx.installmentKey == plan.key
                    && tx.amount == period.amount
            }
            if let tx = matches.max(by: { $0.date < $1.date }) {
                try? LedgerService.softDelete(tx, in: context)
            }
        }
        period.paidAt = nil
        syncRemainingDue()
    }

    private func parsed(_ text: String) -> Decimal? {
        let value = MoneyMath.decimal(text.trimmingCharacters(in: .whitespaces))
        return value > 0 ? value : nil
    }

    /// 手工改过金额或标了已还之后，计划的「剩余应还」要跟着改——
    /// 否则详情页顶部的剩余总额还停在原始账单数上，和期表对不上。
    /// 写回 `remainingDue` 而不是留着让它按每期金额推算：这里期表才是真值。
    private func syncRemainingDue() {
        guard let plan = allInstallments.first(where: { $0.key == period.installmentKey }) else { return }
        let unpaid = allPeriods
            .filter { $0.installmentKey == plan.key && $0.paidAt == nil }
            .reduce(Decimal.zero) { $0 + $1.amount }
        plan.remainingDue = unpaid
        try? context.save()
    }
}

/// `11/22` 这种短日期。分散在三处视图里各写一遍容易不一致。
enum MonthDay {
    static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
}
