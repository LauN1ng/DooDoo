import SwiftUI

/// 一张实体银行卡的卡面。
///
/// **底图是资源，文字是实时画的**（2026-11-09 换资源后的结构）：
/// - 底图 `CardXxxVn`：品牌色渐变 + 左上高光 + 斜向光带 + 金属芯片 + 白色单色行徽，
///   由 `assets/_build/gen-card-faces.js` 生成，21 品牌 × 3 variant 固化在 Asset Catalog 里。
/// - 纹理 `TexMatte` / `TexMetal` / `TexGrain`：灰度图按 tile 平铺，overlay 混合。
///   这是「扁平色块 → 真实卡片」最缺的一层，纯代码画不出来。
/// - 文字层：品牌名 / 类型 / 卡组织 / 尾号全部按账户数据实时渲染，
///   所以改账户名、改尾号会立刻反映到卡面上。
///
/// 版式照 `assets/brands/cards/*.svg`（设计稿）：左下品牌名 + 类型，右下卡组织 + 尾号，
/// 左上留给芯片或放大的行徽。
///
/// 四档尺寸：
/// - `.deck` 132×82（资产页卡堆）
/// - `.detail` 144×96（资产页浮层明细行）
/// - `.entry` 158×100（记一笔的账户横滑）
/// - `.entryCompact` 112×72（记一笔还款的扣款卡）
struct CardFace: View {
    enum Size {
        case deck
        case detail
        case entry
        case entryCompact
    }

    let account: Account
    let size: Size

    /// 兼容旧调用：`large: true` 等于 `.detail`，否则 `.deck`。
    init(account: Account, size: Size = .deck) {
        self.account = account
        self.size = size
    }

    init(account: Account, large: Bool) {
        self.init(account: account, size: large ? .detail : .deck)
    }

    private var style: BrandStyle { BrandPalette.style(account.brandId) }

    /// 各档尺寸与字号。集中放这里，改规格只动一处。
    private struct Metrics {
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let padding: CGFloat
        let titleSize: CGFloat
        let subSize: CGFloat
        let numberSize: CGFloat
        let networkSize: CGFloat
        /// 小卡放不下卡组织名（`UNIONPAY` 9 个字符 ≈ 35pt），直接不显示。
        let showsNetwork: Bool
    }

    private var metrics: Metrics {
        switch size {
        case .deck:
            .init(width: 132, height: 82, radius: 13, padding: 11,
                  titleSize: 12.5, subSize: 9, numberSize: 8.5, networkSize: 6.5,
                  showsNetwork: true)
        case .detail:
            .init(width: 144, height: 96, radius: 15, padding: 12,
                  titleSize: 13.5, subSize: 9.5, numberSize: 9, networkSize: 7,
                  showsNetwork: true)
        case .entry:
            .init(width: 158, height: 100, radius: 16, padding: 12,
                  titleSize: 13, subSize: 9, numberSize: 9, networkSize: 7,
                  showsNetwork: true)
        case .entryCompact:
            .init(width: 112, height: 72, radius: 13, padding: 9,
                  titleSize: 10.5, subSize: 8, numberSize: 7.5, networkSize: 6,
                  showsNetwork: false)
        }
    }

    var body: some View {
        let m = metrics
        let inkColor = Color(hex: style.ink)

        HStack(alignment: .bottom, spacing: 4) {
            VStack(alignment: .leading, spacing: m.titleSize > 12 ? 2.5 : 2) {
                Text(account.cardTitle)
                    .font(.system(size: m.titleSize, weight: .semibold))
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(account.typeLabel)
                    .font(.system(size: m.subSize))
                    .foregroundStyle(inkColor.opacity(0.76))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: m.titleSize > 12 ? 2.5 : 2) {
                if m.showsNetwork, !displayNetwork.isEmpty {
                    Text(displayNetwork)
                        .font(.system(size: m.networkSize, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(inkColor.opacity(0.5))
                        .lineLimit(1)
                }
                Text(account.maskedNumber)
                    .font(.system(size: m.numberSize))
                    .tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(inkColor.opacity(0.85))
                    .lineLimit(1)
            }
            // 尾号比品牌名重要：空间不够时先截品牌名（「中国邮政储蓄银行」这类长名）
            .layoutPriority(1)
        }
        .padding(.horizontal, m.padding)
        .padding(.bottom, m.padding - 2)
        // 尺寸只在这一处定，alignment: .bottom 把文字行压到卡底（芯片在左上，顶部要留白）
        .frame(width: m.width, height: m.height, alignment: .bottom)
        .background { cardArt(width: m.width, height: m.height) }
        .clipShape(RoundedRectangle(cornerRadius: m.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.17), radius: 3.5, x: 0, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.cardTitle)，\(account.typeLabel)，\(account.maskedNumber)")
    }

    /// 底图 + 纹理。底图按比例填满再裁，卡面比例（1.586）和卡片本身（1.5–1.61）不严格相等，
    /// 直接拉伸会把芯片拉成椭圆。
    ///
    /// 尺寸从 `metrics` 传进来而不是用 `GeometryReader`：卡面尺寸本来就是固定四档，
    /// 而且 tile 模式的 Image 若没有明确 frame，会按图片自身尺寸（512×512）铺，
    /// 平铺区域和卡片对不上。
    private func cardArt(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image(style.cardAsset(variant: account.variant))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()

            Image(textureAsset)
                .resizable(resizingMode: .tile)
                .frame(width: width, height: height)
                .opacity(style.texture == "metal" ? 0.46 : 0.40)
                .blendMode(.overlay)

            Image("TexGrain")
                .resizable(resizingMode: .tile)
                .frame(width: width, height: height)
                .opacity(0.06)
                .blendMode(.overlay)
        }
        // 不加这层，overlay 会跟卡外的背景元素混合，纹理直接发灰
        .compositingGroup()
    }

    private var textureAsset: String {
        style.texture == "metal" ? "TexMetal" : "TexMatte"
    }

    /// 网络标优先用账户自己的，其次品牌默认，`NONE` 不显示。
    private var displayNetwork: String {
        let value = account.networkLabel.isEmpty ? style.network : account.networkLabel
        return value == "NONE" ? "" : value
    }
}
