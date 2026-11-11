import Foundation

/// 金额格式化。只负责显示，不参与任何账务运算。
enum MoneyMath {
    /// 两位小数 + 千分位，例：`12345.6` → `12,345.60`。
    ///
    /// 每次调用新建 `NumberFormatter`：M1 一屏最多 7 张卡、几十行，开销可忽略；
    /// 若 M4 之后列表变长再换成缓存实例（届时注意 Swift 6 的并发隔离）。
    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }

    /// 带符号与货币符号，列表右侧用。例：支出 → `−¥32.00`，收入 → `+¥6,476.00`。
    static func signed(_ value: Decimal, kind: TransactionKind) -> String {
        "\(kind.sign)¥\(money(value))"
    }

    /// 用户输入 → `Decimal`。空串、乱码一律 0。
    ///
    /// **必须用 POSIX 区域**：`Decimal(string:)` 不带 locale 时按系统区域解析，
    /// 而 `de_DE`、`fr_FR` 这类区域的**小数点是逗号**，`.5` 会被当成千分位——
    /// 用户输 `5.5` 可能变成 55。钱一律走这一条，不要在别处另写解析。
    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// `Decimal` → 纯数字文本（不带千分位、不带货币符号），回填输入框用。
    /// 例：`120.03` → `"120.03"`；`120` → `"120.00"`。
    static func plain(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }

    /// 百分数（`16.43` = 16.43%）→ 展示文本。`nil` → `"—"`，不猜。
    ///
    /// 年化由 `InstallmentMath.impliedAnnualRate` 反算，**返回的就是百分数**，
    /// 这里不要再 ×100。
    static func percent(_ value: Decimal?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let text = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
        return text + "%"
    }
}
