import SwiftUI

/// 一张实体银行卡的卡面。颜色全部来自 `BrandPalette`，**不贴位图**。
///
/// 六层（记一笔规格冻结 v1.0 第三节）：
/// 1. 基色渐变 142°
/// 2. 左上径向高光（模拟灯光）
/// 3. 斜向光带（模拟卡面反光）
/// 4. 金属芯片（19×14，金色三色渐变 + 内嵌十字线）
/// 5. 0.5pt 白色内描边
/// 6. 深色投影
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
        let chipWidth: CGFloat
        let chipHeight: CGFloat
    }

    private var metrics: Metrics {
        switch size {
        case .deck:
            .init(width: 132, height: 82, radius: 13, padding: 12,
                  titleSize: 12.5, subSize: 9, numberSize: 9, networkSize: 7,
                  chipWidth: 19, chipHeight: 14)
        case .detail:
            .init(width: 144, height: 96, radius: 15, padding: 13,
                  titleSize: 13.5, subSize: 9.5, numberSize: 9.5, networkSize: 7,
                  chipWidth: 19, chipHeight: 14)
        case .entry:
            .init(width: 158, height: 100, radius: 16, padding: 12,
                  titleSize: 12.5, subSize: 9, numberSize: 9.5, networkSize: 7,
                  chipWidth: 19, chipHeight: 14)
        case .entryCompact:
            .init(width: 112, height: 72, radius: 13, padding: 10,
                  titleSize: 10.5, subSize: 8, numberSize: 8, networkSize: 6.5,
                  chipWidth: 15, chipHeight: 11)
        }
    }

    var body: some View {
        let m = metrics
        let inkColor = Color(hex: style.ink)

        ZStack(alignment: .topLeading) {
            gradient
            highlight(width: m.width)
            lightBands

            VStack(alignment: .leading, spacing: m.titleSize > 12 ? 4 : 3) {
                Text(account.cardTitle)
                    .font(.system(size: m.titleSize, weight: .semibold))
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                Text(account.typeLabel)
                    .font(.system(size: m.subSize))
                    .foregroundStyle(inkColor.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.top, m.padding - 1)
            .padding(.leading, m.padding)

            HStack(alignment: .bottom, spacing: 6) {
                Text(account.maskedNumber)
                    .font(.system(size: m.numberSize))
                    .tracking(0.5)
                    .foregroundStyle(inkColor.opacity(0.82))
                    .lineLimit(1)

                Spacer(minLength: 2)

                chip(width: m.chipWidth, height: m.chipHeight)

                Text(displayNetwork)
                    .font(.system(size: m.networkSize, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(inkColor.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, m.padding)
            .padding(.bottom, m.padding - 4)
        }
        .frame(width: m.width, height: m.height)
        .clipShape(RoundedRectangle(cornerRadius: m.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.17), radius: 3.5, x: 0, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.cardTitle)，\(account.typeLabel)，\(account.maskedNumber)")
    }

    /// 第 1 层：基色渐变。
    private var gradient: some View {
        LinearGradient(
            colors: [Color(hex: style.c1), Color(hex: style.c2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 第 2 层：左上径向高光。半径跟卡宽走，大卡小卡观感一致。
    private func highlight(width: CGFloat) -> some View {
        RadialGradient(
            colors: [.white.opacity(0.30), .white.opacity(0)],
            center: .topLeading,
            startRadius: 2,
            endRadius: width * 1.05
        )
    }

    /// 第 3 层：斜向光带，两三道半透明白。
    private var lightBands: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.12), location: 0.00),
                .init(color: .white.opacity(0.00), location: 0.16),
                .init(color: .white.opacity(0.00), location: 0.60),
                .init(color: .white.opacity(0.08), location: 0.84),
                .init(color: .white.opacity(0.00), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.05, y: 0),
            endPoint: UnitPoint(x: 0.95, y: 1)
        )
    }

    /// 第 4 层：金属芯片。
    private func chip(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.25, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xF0E3B4), Color(hex: 0xC9A94E), Color(hex: 0xEFE2B2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.25, style: .continuous)
                    .strokeBorder(.black.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                // 内嵌十字线：一横一竖，比例照实体芯片
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.15))
                        .frame(height: 0.5)
                    Rectangle()
                        .fill(.black.opacity(0.15))
                        .frame(width: 0.5)
                }
                .padding(.vertical, height * 0.22)
                .padding(.horizontal, width * 0.3)
            )
    }

    /// 网络标优先用账户自己的，其次品牌默认，`NONE` 不显示。
    private var displayNetwork: String {
        let value = account.networkLabel.isEmpty ? style.network : account.networkLabel
        return value == "NONE" ? "" : value
    }
}
