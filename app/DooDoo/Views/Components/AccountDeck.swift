import SwiftUI

/// 一摞银行卡。几何照 `资产页规格冻结-v1.0.md` 2.3：
/// 容器宽 146，高 `84 + 16×(层数−1)`，层数 `min(账户数, 3)`，层厚 16。
struct AccountDeck: View {
    let accounts: [Account]
    var onTap: () -> Void

    private var layerCount: Int { min(max(accounts.count, 1), 3) }
    private var deckHeight: CGFloat { CGFloat(84 + 16 * (layerCount - 1)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array((0..<layerCount).reversed()), id: \.self) { index in
                layer(at: index)
            }
        }
        .frame(width: 146, height: deckHeight, alignment: .bottom)
        .overlay(alignment: .bottomTrailing) {
            if accounts.count > 1 {
                Text("\(accounts.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 23, minHeight: 23)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Palette.ink))
                    .padding(.trailing, 9)
                    .padding(.bottom, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func layer(at index: Int) -> some View {
        let bottom = CGFloat(16 * (layerCount - 1 - index))
        if index == 0, let front = accounts.first {
            CardFace(account: front)
                .padding(.bottom, bottom)
                .zIndex(10)
        } else if index < accounts.count {
            backSheet(for: accounts[index], depth: index)
                .padding(.bottom, bottom)
                .offset(x: index == 1 ? 4 : -4)
                .rotationEffect(.degrees(index == 1 ? 0.8 : -1.0), anchor: .bottom)
                .zIndex(Double(10 - index))
        }
    }

    /// 后层只有纸边：同一张卡面底图（无文字），靠亮度分档区分前后（规格 6.2）。
    ///
    /// 用底图而不是重新拼渐变，是为了和前层卡面同色同质感——
    /// 底图里叠了高光和光带，纯渐变拼出来的纸边会明显比前卡暗一档。
    private func backSheet(for account: Account, depth: Int) -> some View {
        let style = BrandPalette.style(account.brandId)
        return Image(style.cardAsset(variant: account.variant))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 132, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
            .brightness(backBrightness(style: style, depth: depth))
            .shadow(color: .black.opacity(0.13), radius: 3, x: 0, y: 2)
    }

    /// 深色卡（亮度 < .30）再压暗会和自己的投影糊成一条，改提亮。
    private func backBrightness(style: BrandStyle, depth: Int) -> Double {
        if style.luminance < 0.30 {
            return depth == 1 ? 0.10 : 0.16
        }
        return depth == 1 ? -0.10 : -0.20
    }

    private var accessibilityText: String {
        guard let front = accounts.first else { return "空账户堆" }
        return "\(front.cardTitle)，共 \(accounts.count) 个账户"
    }
}
