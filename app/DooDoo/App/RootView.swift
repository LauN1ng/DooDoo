import SwiftUI

/// 根视图：页头（顶部 tab）与三个页面容器。
///
/// **M4 2026-11-16 落地**：按用户定案去掉左侧「DooDoo」字样，页头只留 tab 并靠右；
/// 槽体视觉仍是 34 高胶囊（规格第二节 112×34 / 段 36×30 / 圆角 17），
/// 但材质改走 `Palette.tabBed`、命中区扩到 40×44（36×30 低于 44pt 推荐触摸尺寸）。
struct RootView: View {
    @State private var tab: RootTab = .flow

    /// 卡面 hero 的命名空间：资产页浮层里的明细行卡面与详情页顶部卡面共用，
    /// 点行时同一张卡从 144×96 长到 240×151。
    @Namespace private var cardSpace

    /// 账户详情全屏层（2026-11-16 用户定案：卡面放大，不再是 sheet）。
    ///
    /// **状态必须住在 RootView**：资产页在 `VStack { 页头; 内容 }` 的内容区里，
    /// 挂在它内部的层到不了页头与状态栏，卡面就飞不到屏幕顶部。
    @State private var detailAccount: Account?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                content
            }
            // 页头与状态栏必须是页面底色。原来这里是系统默认白，
            // 和白色卡片连成一片，真机上看起来像"顶上多了一块白"。
            .background(Palette.page.ignoresSafeArea())

            if let account = detailAccount {
                // 关闭由这里出：置空这个状态，明细行卡面在同一个事务里接手，
                // 卡面就沿原路飞回那一行——不是 dismiss 一个面板。
                AccountDetailView(account: account, cardSpace: cardSpace) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                        detailAccount = nil
                    }
                }
            }
        }
    }

    private var header: some View {
        // 2026-11-16 用户定案：去掉左侧「DooDoo」字样，tab 仍靠右。
        // 左侧留白是刻意的——原来那儿是字标，删掉字标后不留假占位，
        // 让页头只有 tab 一件东西，靠右与卡片右边距 20 对齐成一条竖线。
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
        case .assets: AssetsView(detailAccount: $detailAccount, cardSpace: cardSpace)
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self], inMemory: true)
}
