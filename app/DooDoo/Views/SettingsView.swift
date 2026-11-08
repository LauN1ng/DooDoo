import SwiftUI
import SwiftData

/// 设置。
///
/// M1 只放「数据仅存本机」提示与一个真实开关，用来验证 SwiftData 读写通了。
/// 完整设置页（导出 CSV、清除演示数据等）留到后续，PRD 未定义的部分不得自己加。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]

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
        .modelContainer(for: [Account.self, Category.self, Transaction.self, AppSettings.self], inMemory: true)
}
