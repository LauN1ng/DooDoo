import SwiftUI

/// 一条流水。尺寸取自 `home-v1.0.html`：42×42 图标、14pt 标题、11.5pt 副标题。
struct TxRowView: View {
    let transaction: Transaction

    private var title: String {
        if let note = transaction.note, !note.isEmpty { return note }
        return transaction.category?.name ?? transaction.kind.title
    }

    private var subtitle: String {
        let category = transaction.category?.name
        let account = transaction.account?.name
        switch (category, account) {
        case let (c?, a?): return "\(c) · \(a)"
        case let (c?, nil): return c
        case let (nil, a?): return a
        default: return transaction.kind.title
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income: Palette.income
        case .repayment, .transfer, .adjustment: Palette.sub
        case .expense: Palette.ink
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(transaction.category?.emoji ?? "•")
                .font(.system(size: 20))
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
