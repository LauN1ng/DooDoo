import Foundation
import SwiftData

/// 流水类型（PRD 8 节）。
enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case expense      // 支出
    case income       // 收入
    case repayment    // 信用卡还款：不计入消费统计
    case transfer     // 转账：可带手续费，手续费单独计入支出
    case adjustment   // 余额调整：对不上账时生成

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .repayment: "还款"
        case .transfer: "转账"
        case .adjustment: "调整"
        }
    }

    /// 是否计入消费统计。还款与转账不进（PRD 9.1）。
    var countsAsExpense: Bool { self == .expense }

    /// 列表里金额前的符号。
    var sign: String {
        switch self {
        case .income: "+"
        case .expense, .repayment, .transfer, .adjustment: "−"
        }
    }
}

/// 一笔流水。
///
/// **金额永远为正**，方向由 `kind` 决定：支出是 `expense` + 正数，不是负数金额。
@Model
final class Transaction {
    // 不自己声明 `id`：SwiftData 的 @Model 已通过 `persistentModelID` 提供 Identifiable，
    // 再写一个 `id: UUID` 会和它抢同一个名字，运行时 schema 容易出问题。
    /// 单位：元。恒为正数。
    var amount: Decimal

    var kindRaw: String

    /// 发生日（用户可改，用于补记），不是记录时间。
    var date: Date

    /// 备注 / 商户名。列表主标题优先用它，没有则显示分类名。
    /// PRD 里就叫 `note`，M1 不新造 `payee` 字段。
    var note: String?

    var createdAt: Date

    /// 软删除时间。非空即视为已删，**任何查询都要排除**（AGENTS 7.2）。
    var deletedAt: Date?

    /// 付款方 / 转出方。
    var account: Account?

    // 还款目标 `toAccount` 属于 M2（还款/转账），M1 不声明，
    // 免得 SwiftData 自动推断出错误的反向关系。

    var category: Category?

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// 是否已被软删除。
    var isDeleted: Bool { deletedAt != nil }

    init(
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String? = nil,
        account: Account? = nil,
        category: Category? = nil,
        createdAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.account = account
        self.category = category
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
