import SwiftUI

/// 根视图：页头（字标 + 顶部 tab）与三个页面容器。
///
/// **M0 范围内只保证结构正确**：三段等宽、选中态可切换、内容随 tab 换。
/// 材质、精确尺寸（112×34 / 36×30 / 圆角 17 / `#EBE7E0`）留给 M4，
/// 依据 `docs/design/spec/首页规格冻结-v1.0.md` 第二节。
struct RootView: View {
    @State private var tab: RootTab = .flow

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("DooDoo")
                .font(.system(size: 19, weight: .semibold))
                .kerning(-0.4)

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                ForEach(RootTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: tab == item ? .semibold : .regular))
                            .frame(width: 36, height: 30)
                            .foregroundStyle(tab == item ? Color.primary : Color.secondary.opacity(0.6))
                            .background {
                                if tab == item {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(Color(.systemBackground))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                }
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color(.systemGray5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .flow: FlowView()
        case .assets: AssetsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, AppSettings.self], inMemory: true)
}
