import SwiftUI
import SwiftData

/// 设置。
///
/// M1 只放「数据仅存本机」提示与一个真实开关，用来验证 SwiftData 读写通了。
/// 完整设置页（导出 CSV、清除演示数据等）留到后续，PRD 未定义的部分不得自己加。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @Query private var installments: [Installment]

    /// 存量录入的目标笔数。与 `InstallmentIntake.Batch` 共用同一个 key。
    @AppStorage(InstallmentIntake.Batch.targetKey) private var batchTarget = InstallmentIntake.Batch.defaultTarget

    @State private var showingInstallmentEntry = false

    var body: some View {
        Form {
            Section("数据") {
                LabeledContent("存储位置", value: "仅本机")
                LabeledContent("币种", value: settings.first?.currencyCode ?? "CNY")
                LabeledContent("版本", value: appVersion)
                Text("数据只存在这台 iPhone 上，卸载即丢失，也没有云端备份。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // 存量分期录入（M3-2）。放在设置里是因为它是一次性的初始化动作，
            // 不是每天会点的功能；等资产页「本月要还」上线后，入口会挪到信用组里。
            Section("分期") {
                Button {
                    showingInstallmentEntry = true
                } label: {
                    HStack {
                        Text("存量分期录入")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if batchTarget > 0 {
                            Text("还差 \(InstallmentIntake.batchRemaining(target: batchTarget, done: installments.count)) 笔")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                LabeledContent("已录分期", value: "\(installments.count) 笔")

                Text("已发生的分期照账单抄三个数：剩余应还、剩余期数、含利息，还款日按卡的还款日带出。每期金额自动除出来（除不尽的零头进首期）；各期金额不一样的账单，再补抄一个「末期金额」，中间各期就按它反推，不用逐期录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("偏好") {
                Toggle("逾期横幅", isOn: toggle(\.overdueAlertEnabled))
                Text("只在 App 内用横幅提示，不发系统通知。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .onAppear(perform: ensureDefaultSettings)
        .sheet(isPresented: $showingInstallmentEntry) {
            InstallmentEntryView()
                .presentationDetents([.large])
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    /// 单条记录：第一次进设置页时建默认值。
    private func ensureDefaultSettings() {
        guard settings.isEmpty else { return }
        context.insert(AppSettings())
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.first?[keyPath: keyPath] ?? true },
            set: { newValue in
                guard let current = settings.first else { return }
                current[keyPath: keyPath] = newValue
                current.updatedAt = .now
            }
        )
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, AppSettings.self], inMemory: true)
}
