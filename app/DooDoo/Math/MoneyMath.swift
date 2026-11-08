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
}
