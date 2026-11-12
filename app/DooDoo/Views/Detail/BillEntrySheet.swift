import SwiftUI
import SwiftData

/// 录一期循环账单（PRD 9.12「每月手录本期应还」）。
///
/// 只问三个必填：**账期、本期应还、到期日**。`totalAmount` / `refundAmount`
/// 这些账单明细 PRD 里有字段，但录入端不逼用户抄——他只需要 App 回答
/// 「这个月要还多少、几号还」，多一个框就多一次放弃。
///
/// 同一张卡同一个账期只保留一期：重复录入视为**修订**，不是新建。
struct BillEntrySheet: View {
    let account: Account

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allBills: [BillStatement]

    @State private var period: String = BillEntrySheet.periodText(for: .now)
    @State private var amountText: String = ""
    @State private var dueDate: Date = .now
    @State private var isPaid = false
    @State private var didLoadDefaults = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("账期") {
                        TextField("2026-11", text: $period)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    LabeledContent("本期应还") {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    DatePicker("还款日", selection: $dueDate, displayedComponents: .date)

                    Toggle("已还清", isOn: $isPaid)
                } footer: {
                    Text("账期是账单的名字，不是还款日所在月——花呗 10/15–11/14 这一期叫 2026-11，11/25 还。")
                }

                if let existing = existingBill {
                    Section {
                        Text("\(existing.period) 期已经录过（\(MoneyMath.money(existing.dueAmount))），保存会覆盖它。")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                }

                Section {
                    Text("账单里的分期部分已经包含在本期应还里，App 不会再把分期加一遍。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("录本期账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadDefaultsIfNeeded)
        }
    }

    // MARK: - 逻辑

    private var amount: Decimal? {
        let value = MoneyMath.decimal(amountText)
        return value > 0 ? value : nil
    }

    private var canSave: Bool {
        amount != nil && !period.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var billForAccount: [BillStatement] {
        allBills.filter { $0.account?.persistentModelID == account.persistentModelID }
    }

    /// 同账期已有账单 → 这次是修订。
    private var existingBill: BillStatement? {
        billForAccount.first { $0.period == period.trimmingCharacters(in: .whitespaces) }
    }

    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true

        if let latest = billForAccount.max(by: { $0.dueDate < $1.dueDate }) {
            // 有历史账单时默认落在「下一期」，比让用户改账期更快。
            period = BillEntrySheet.periodText(for: BillEntrySheet.advance(latest.dueDate, months: 1))
        }
        dueDate = BillEntrySheet.defaultDueDate(for: account, on: .now)
    }

    private func save() {
        guard let amount else { return }
        let trimmed = period.trimmingCharacters(in: .whitespaces)

        if let existing = existingBill {
            existing.dueAmount = amount
            existing.dueDate = dueDate
            existing.status = isPaid ? .paid : .pending
            existing.paidAt = isPaid ? (existing.paidAt ?? .now) : nil
        } else {
            let bill = BillStatement(
                account: account,
                period: trimmed,
                dueDate: dueDate,
                dueAmount: amount,
                status: isPaid ? .paid : .pending,
                paidAt: isPaid ? .now : nil
            )
            context.insert(bill)
        }

        try? context.save()
        dismiss()
    }

    // MARK: - 日期工具（纯计算，不碰 SwiftData）

    /// `2026-11`。
    static func periodText(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        return String(format: "%04d-%02d", parts.year ?? 2026, month)
    }

    static func advance(_ date: Date, months: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// 按账户的还款日（`dueDay`）给出本月那一期；没有 `dueDay` 就沿用今天。
    static func defaultDueDate(for account: Account, on today: Date, calendar: Calendar = .current) -> Date {
        guard let day = account.dueDay, day > 0 else { return today }
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? today
    }
}
