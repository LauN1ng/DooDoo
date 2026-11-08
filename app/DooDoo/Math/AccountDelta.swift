import Foundation

/// 颜色的语义类，视图层只认这三个值。
enum DeltaClass: String, Sendable {
    case up      // 涨：红
    case down    // 跌：绿
    case flat    // 无变化或无基准：灰
}

/// 「较上月」的口径。
///
/// **分母用上期值，不是当前值**：3,120 → 4,360，变化 +1,240。
/// 正确是 `+1,240 ÷ 3,120 = +39.7%`；用当前值做分母会得到 28.4%，把变化说小了。
///
/// 上期为 0 时无意义，返回 nil，视图显示 `—`（不显示 0%，那是在假装有数据）。
enum AccountDelta {
    /// 返回带一位小数的百分比；`previous == 0` 时返回 nil。
    static func percent(current: Decimal, previous: Decimal) -> Decimal? {
        guard previous != 0 else { return nil }
        var raw = (current - previous) / previous * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 1, .plain)
        return rounded
    }

    /// `↗ 4.1%` / `↘ 28.4%` / `—`。箭头由符号决定，颜色由 `classify` 决定。
    static func text(_ percent: Decimal?) -> String {
        guard let value = percent, value != 0 else { return "—" }
        let arrow = value > 0 ? "↗" : "↘"
        return "\(arrow) \(percentNumber(abs(value)))%"
    }

    static func classify(_ percent: Decimal?) -> DeltaClass {
        guard let value = percent, value != 0 else { return .flat }
        return value > 0 ? .up : .down
    }

    /// 一位小数的纯数字文本，例 `28.4`。
    static func percentNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.0"
    }
}
