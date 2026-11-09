import SwiftUI
import UIKit

/// 一条流水。尺寸取自 `home-v1.0.html`：42×42 图标、14pt 标题、11.5pt 副标题。
/// 图标是 Fluent3D PNG（`assets/emoji/picked`），不是系统 emoji。
struct TxRowView: View {
    let transaction: Transaction

    private var title: String {
        if let note = transaction.note, !note.isEmpty { return note }
        return transaction.category?.name ?? transaction.kind.title
    }

    private var subtitle: String {
        var parts: [String] = []
        if let category = transaction.category?.name { parts.append(category) }
        if let account = transaction.account?.displayShortName { parts.append(account) }
        // 转账行金额是「转出本金」，本金不计消费；手续费才是支出。
        // 不在副标题写出来，用户无从判断那 0.10 到底进没进合计（真机反馈）。
        if transaction.kind == .transfer, let fee = transaction.fee, fee > 0 {
            parts.append("手续费 ¥" + MoneyMath.money(fee))
        }
        return parts.isEmpty ? transaction.kind.title : parts.joined(separator: " · ")
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income: Palette.income
        case .repayment, .transfer, .adjustment: Palette.sub
        case .expense: Palette.ink
        }
    }

    /// 这一笔自己的图标优先，没有就用分类默认图标；图片缺失才退回 emoji 字符。
    private var icon: UIImage? {
        if let own = transaction.iconName, let image = UIImage(named: own) { return image }
        if let category = transaction.category?.iconName, let image = UIImage(named: category) { return image }
        return nil
    }

    /// Fluent3D 图标 27×27（原型尺寸），落在 42×42 的分类色槽里。
    ///
    /// **必须走 `UIImage`**：`Image("Croissant")` 只查 asset catalog，
    /// 对 bundle 根目录的 PNG 会画成空白（槽里既没图也没 emoji 兜底，就是这个原因）。
    @ViewBuilder
    private var slot: some View {
        if let icon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
        } else {
            Text(transaction.category?.emoji ?? "•")
                .font(.system(size: 20))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            slot
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(hexString: transaction.category?.tintHex ?? "#F2F1ED"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(MoneyMath.signed(transaction.amount, kind: transaction.kind))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(subtitle)，\(MoneyMath.signed(transaction.amount, kind: transaction.kind))")
    }
}
