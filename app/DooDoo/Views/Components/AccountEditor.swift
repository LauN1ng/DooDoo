import SwiftUI
import SwiftData

/// 新建 / 编辑账户。
///
/// M2a 用系统 `Form`：字段先对齐 PRD 第八节，样式留到 M4。
/// 余额不直接写 `currentBalance`，保存时走 `LedgerService.adjustAccountBalance`。
struct AccountEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = 新建。
    let account: Account?
    let defaultKind: AccountKind

    @State private var name = ""
    @State private var kind: AccountKind = .savings
    @State private var brandId = "cash"
    @State private var shortName = ""
    @State private var last4 = ""
    @State private var limitText = ""
    @State private var balanceText = "0"
    @State private var dueDay = 0
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    private var isNew: Bool { account == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AccountKind.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    TextField("短名（流水里显示，如「招行8857」）", text: $shortName)
                }

                Section("卡面") {
                    Picker("品牌", selection: $brandId) {
                        ForEach(BrandPalette.sortedIds, id: \.self) { id in
                            Text(BrandPalette.style(id).name).tag(id)
                        }
                    }
                    TextField("卡号后四位", text: $last4)
                        .keyboardType(.numberPad)
                }

                Section("金额") {
                    HStack {
                        // 负债账户的界面口径是「欠款正数」，落库才取负（真机反馈 #8）。
                        Text(kind.isLiability ? "欠款" : "余额")
                        Spacer()
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if kind == .credit || kind == .loan {
                        HStack {
                            Text("额度")
                            Spacer()
                            TextField("无", text: $limitText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Text(kind.isLiability
                         ? "欠款填正数（欠 600 就填 600）。余额是派生值：保存后会按流水重算，当前输入作为校准目标。"
                         : "余额是派生值：保存后会按流水重算，当前输入作为校准目标。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if kind == .credit {
                    Section("账单") {
                        Stepper(value: $dueDay, in: 0...31) {
                            Text(dueDay == 0 ? "还款日：未设" : "还款日：每月 \(dueDay) 日")
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Text("删除账户")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.expense)
                    }
                }
            }
            .navigationTitle(isNew ? "新建账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(
                "删除后这个账户的流水会保留但失去归属，且无法撤销。",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除账户", role: .destructive, action: deleteAccount)
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        kind = account?.kind ?? defaultKind
        brandId = account?.brandId ?? BrandPalette.defaultId(for: defaultKind)
        guard let account else {
            balanceText = "0"
            return
        }
        name = account.name
        shortName = account.shortName
        last4 = account.last4
        limitText = account.creditLimit.map { MoneyMath.money($0) } ?? ""
        // 编辑负债账户时也显示「欠款正数」，与保存口径一致；否则来回编辑会把符号翻两次。
        let balance = account.currentBalance
        let shown = account.kind.isLiability && balance < 0 ? -balance : balance
        balanceText = MoneyMath.money(shown)
        dueDay = account.dueDay ?? 0
    }

    private func save() {
        let parsed = Decimal(string: balanceText.replacingOccurrences(of: ",", with: ""),
                             locale: Locale(identifier: "en_US_POSIX")) ?? 0
        // 2026-11-09 真机反馈 #8：用户按「欠 600」填 600，首版直接存成 +600，
        // 导致还款页 maxDebt = 0、金额带出 0.00、主按钮禁用。
        // Account.currentBalance 的语义是「信用/借款欠款为负」，这里统一取负。
        // 填 -600 也按 600 处理，避免符号来回翻。
        let magnitude = parsed < 0 ? -parsed : parsed
        let target = kind.isLiability ? -magnitude : parsed
        let limit = limitText.isEmpty
            ? nil
            : Decimal(string: limitText.replacingOccurrences(of: ",", with: ""),
                      locale: Locale(identifier: "en_US_POSIX"))

        do {
            let targetAccount: Account
            if let account {
                targetAccount = account
                account.name = name.trimmingCharacters(in: .whitespaces)
                account.shortName = shortName.trimmingCharacters(in: .whitespaces)
                account.kind = kind
                account.brandId = brandId
                account.last4 = last4
                account.networkLabel = BrandPalette.style(brandId).network
                account.creditLimit = limit
                account.dueDay = dueDay == 0 ? nil : dueDay
            } else {
                let created = Account(
                    name: name.trimmingCharacters(in: .whitespaces),
                    kind: kind,
                    initialBalance: 0,
                    brandId: brandId,
                    last4: last4,
                    networkLabel: BrandPalette.style(brandId).network,
                    shortName: shortName.trimmingCharacters(in: .whitespaces),
                    creditLimit: limit,
                    dueDay: dueDay == 0 ? nil : dueDay,
                    sortOrder: 999
                )
                context.insert(created)
                targetAccount = created
            }
            try context.save()
            try LedgerService.adjustAccountBalance(targetAccount, to: target, in: context)
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteAccount() {
        guard let account else { return }
        do {
            context.delete(account)
            try context.save()
            try LedgerService.recalculateAll(in: context)
            dismiss()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
