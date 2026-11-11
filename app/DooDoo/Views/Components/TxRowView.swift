import SwiftUI
import UIKit

/// 一条流水。尺寸取自 `home-v1.0.html`：42×42 图标、14pt 标题、11.5pt 副标题。
/// 图标是 Fluent3D PNG（`assets/emoji/picked`），不是系统 emoji。
///
/// 2026-11-11 起**一行可以代表两条流水**：转账本体 + 它的手续费。
/// 传入 `fees` 时手续费不再单独占一行，而是收成副标题下面的一枚红色小标签
/// （`手续费 0.10`），金额列显示**转出总额**且不带符号——即用户说的「图一」。
struct TxRowView: View {
    let transaction: Transaction

    /// 挂在这一行上的手续费流水（同 `groupID` 的 `.expense`）。
    ///
    /// 数据层仍是两条（余额要靠两条才扣得对），`TxRollup` 只负责把它们渲染成一行。
    var fees: [Transaction] = []

    /// 转账方向，如「微信 → 支付宝」。收款方不可见时只留付款方（真机反馈 #12）。
    private var direction: String? {
        guard transaction.kind == .transfer else { return nil }
        if let from = transaction.account?.displayShortName,
           let to = transaction.toAccount?.displayShortName {
            return "\(from) → \(to)"
        }
        return transaction.account?.displayShortName
    }

    private var title: String {
        if let note = transaction.note, !note.isEmpty { return note }
        // 转账没有分类，标题本来会退成「转账」；用户 11-11 要的是方向当标题。
        if transaction.kind == .transfer { return direction ?? transaction.kind.title }
        return transaction.category?.name ?? transaction.kind.title
    }

    private var subtitle: String {
        if transaction.kind == .transfer {
            // 方向已经在标题上，副标题让位给时间（图一）。
            // 用户写了备注时标题是备注，方向就挪到副标题，信息不丢。
            if let note = transaction.note, !note.isEmpty, let direction { return direction }
            return timeText
        }

        var parts: [String] = []
        if let category = transaction.category?.name { parts.append(category) }
        if let account = transaction.account?.displayShortName { parts.append(account) }
        return parts.isEmpty ? transaction.kind.title : parts.joined(separator: " · ")
    }

    /// 时分。每次新建 formatter 而不是 static let：Swift 6 严格并发下
    /// `DateFormatter` 不是 `Sendable`，静态实例过不了编译（`MoneyMath` 同处理）。
    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: transaction.date)
    }

    /// 手续费合计。一行只挂一条是常态，仍用求和兜住历史脏数据。
    private var feeTotal: Decimal {
        fees.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// 金额列：转账显示**转出总额**，且不带符号。
    ///
    /// 手续费不再单独占一行，所以这里必须回到全额（原来是「到账额」，
    /// 为了让列表加总不出偏差）。扣款方向由图标与「A → B」表达，
    /// 金额再压一个 `−¥` 反而像消费，用户 11-11 要求去掉。
    private var amountText: String {
        transaction.kind == .transfer
            ? MoneyMath.money(transaction.amount)
            : MoneyMath.signed(transaction.amount, kind: transaction.kind)
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income: Palette.income
        case .transfer: Palette.ink
        case .repayment, .adjustment: Palette.sub
        case .expense: Palette.ink
        }
    }

    /// 这一笔自己的图标优先，没有就用分类默认图标；图片缺失才退回 emoji 字符。
    ///
    /// 转账没有分类，原来这里退成一个「•」——2026-11-11 改借手续费的图标
    /// （`CurrencyExchange`，钱在两个账户之间搬家），无手续费时也用同一张，
    /// 让转账行永远不再出现那个点。
    private var icon: UIImage? {
        if transaction.kind == .transfer {
            if let feeIcon = fees.first?.iconName, let image = UIImage(named: feeIcon) { return image }
            return UIImage(named: "CurrencyExchange")
        }
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

    /// 手续费小标签：`手续费 0.10`，红字浅红底。
    ///
    /// 手续费金额也算进当日「支出」合计（PRD 9.8），摆在这一行上
    /// 用户才能拿头部数字逐行对出来（真机反馈 #13 的可核对性要求）。
    private var feeBadge: some View {
        HStack(spacing: 3) {
            Text("手续费")
            Text(MoneyMath.money(feeTotal))
                .monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Palette.expense)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Palette.expense.opacity(0.09))
        )
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
                if feeTotal > 0 {
                    feeBadge
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let feePart = feeTotal > 0 ? "，手续费 \(MoneyMath.money(feeTotal))" : ""
        return "\(title)，\(subtitle)，\(amountText)\(feePart)"
    }
}
