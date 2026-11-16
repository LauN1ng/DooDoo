import SwiftUI

/// 根视图：页头（顶部 tab）与三个页面容器。
///
/// **M4 2026-11-16 落地**：按用户定案去掉左侧「DooDoo」字样，页头只留居中 tab；
/// 槽体视觉仍是 34 高胶囊（规格第二节 112×34 / 段 36×30 / 圆角 17），
/// 但材质改走 `Palette.tabBed`、命中区扩到 40×44（36×30 低于 44pt 推荐触摸尺寸）。
struct RootView: View {
    @State private var tab: RootTab = .flow

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        // 页头与状态栏必须是页面底色。原来这里是系统默认白，
        // 和白色卡片连成一片，真机上看起来像"顶上多了一块白"。
        .background(Palette.page.ignoresSafeArea())
    }

    private var header: some View {
        // 2026-11-16 用户定案：去掉左侧「DooDoo」字样，页头只留 tab，居中。
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ForEach(RootTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: tab == item ? .medium : .regular))
                            .frame(width: 36, height: 30)
                            .foregroundStyle(tab == item ? Palette.ink : Palette.sub)
                            .background {
                                if tab == item {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Palette.card)
                                        .shadow(color: Palette.ink.opacity(0.09), radius: 2, x: 0, y: 1)
                                }
                            }
                            // 视觉尺寸仍是 36×30（规格第二节），命中区扩到 40×44：
                            // 36×30 低于 44pt 推荐触摸尺寸，是 PROGRESS 里挂着的未闭合项。
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                }
            }
            // 槽体视觉仍是 34 高的胶囊（规格第二节），120×34；
            // 上下多出的 5pt 是命中区，透明不着色。
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Palette.tabBed)
                    .frame(width: 120, height: 34)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        // 规格里页头底到卡堆顶是 30（卡顶 116 − 页头底 86）。原来 12 太挤，卡片像贴着 tab。
        .padding(.bottom, 22)
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
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self], inMemory: true)
}
