import SwiftUI

/// 一张实体银行卡的卡面。颜色全部来自 `BrandPalette`，不画图片、不贴 Logo。
///
/// 两种尺寸：卡堆里 132×82（圆角 13），浮层明细行里 144×96（圆角 15）——见规格 2.3 / 4.3。
struct CardFace: View {
    let account: Account
    var large: Bool = false

    private var style: BrandStyle { BrandPalette.style(account.brandId) }
    private var width: CGFloat { large ? 144 : 132 }
    private var height: CGFloat { large ? 96 : 82 }
    private var radius: CGFloat { large ? 15 : 13 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: style.c1), Color(hex: style.c2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: large ? 4 : 3) {
                Text(account.cardTitle)
                    .font(.system(size: large ? 13.5 : 12.5, weight: .semibold))
                    .foregroundStyle(Color(hex: style.ink))
                    .lineLimit(1)
                Text(account.typeLabel)
                    .font(.system(size: large ? 9.5 : 9))
                    .foregroundStyle(Color(hex: style.ink).opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.top, large ? 12 : 10)
            .padding(.leading, large ? 13 : 12)

            HStack(alignment: .bottom) {
                Text(account.maskedNumber)
                    .font(.system(size: 9))
                    .tracking(0.5)
                    .foregroundStyle(Color(hex: style.ink).opacity(0.82))
                Spacer(minLength: 4)
                Text(displayNetwork)
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: style.ink).opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, large ? 13 : 12)
            .padding(.bottom, large ? 8 : 7)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.17), radius: 3.5, x: 0, y: 2)
    }

    /// 网络标优先用账户自己的，其次品牌默认，`NONE` 不显示。
    private var displayNetwork: String {
        let value = account.networkLabel.isEmpty ? style.network : account.networkLabel
        return value == "NONE" ? "" : value
    }
}
