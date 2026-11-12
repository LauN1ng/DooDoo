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

    @State private var amountText: String = ""
    @State private var didLoad = false

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

                Toggle("已还清", isOn: paidBinding)
            } footer: {
                Text("改这一期不会影响其它期。已还清的那期不再计入「本月要还」。")
            }
        }
        .navigationTitle("第 \(period.index) 期")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            amountText = MoneyMath.plain(period.amount)
            didLoad = true
        }
    }

    private func parsed(_ text: String) -> Decimal? {
        let value = MoneyMath.decimal(text.trimmingCharacters(in: .whitespaces))
        return value > 0 ? value : nil
    }

    private var paidBinding: Binding<Bool> {
        Binding(
            get: { period.paidAt != nil },
            set: { paid in
                period.paidAt = paid ? .now : nil
                syncRemainingDue()
            }
        )
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
