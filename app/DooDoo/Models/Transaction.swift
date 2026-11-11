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

    /// 付款方 / 转出方 / 还款的扣款账户。
    var account: Account?

    /// 收款方 / 转入方 / 被还的信用卡（M2b 新增）。
    /// 只有 `.repayment` / `.transfer` 有值；其余类型为 nil。
    var toAccount: Account?

    /// 单位：元。转账的**实际到账金额**（M2b 新增）。
    /// `nil` 表示没有到账差额（转账且无手续费时等于 `amount`）。
    var receivedAmount: Decimal?

    /// 单位：元。手续费，`amount − receivedAmount` 的结果（M2b 新增）。
    /// 冗余存一份是为了统计时能直接求和，不必逐笔相减；写入一律由 `LedgerService` 计算。
    var fee: Decimal?

    /// 转账与它自动生成的手续费流水共享的分组标识（M2b 补充）。
    ///
    /// 两个用途：
    /// 1. **级联软删除**——删掉转账时必须把手续费那条一起删，否则留下一条
    ///    永远回滚不掉的孤儿流水，账户余额会永久少掉一份手续费。
    /// 2. **M3 双边关联**——升级成「转出/转入各一条」时，两条靠它配对。
    ///
    /// 用纯 `String` 而不是 `Transaction` 关系，是为了让老库迁移只依赖
    /// 「可选字段」这一条 SwiftData 自动迁移就能吃下的规则（见 `Account` 顶部注释）。
    var groupID: String?

    /// 消费评分（M1b 新增，PRD 9.13）。存 raw 值，`nil` = 未评分。
    /// 只有 `kind == .expense` 允许非 nil。
    var gradeRaw: String?

    /// 这笔流水属于哪个分期计划（M3 新增）。指向 `Installment.key`，`nil` = 非分期。
    ///
    /// 用纯 `String` 而不是 `Installment` 关系，理由同下面的 `groupID`：
    /// 给**已有**模型加字段时，老库迁移只认「可选」或「带默认值」，
    /// 加一条可选关系同样过得了，但 String 更轻、也更容易在删除分期时留下审计痕迹
    /// （分期删了、流水还在，只是 `installmentKey` 变成悬空引用，不影响余额统计）。
    ///
    /// 只有 `.repayment` 会带它——分期的本金早在消费那天就扣过了，
    /// 每期还的是同一个账户的欠款，不是新的消费。
    var installmentKey: String?

    var category: Category?

    /// 这一笔自己的 Fluent3D 图标（bundle 资源名，如 `"HotBeverage"`）。
    /// 流水行的图标是按「这一笔是什么」选的，不是按分类——同一类里咖啡和正餐不该是同一张图。
    /// 为空时退回分类的默认图标。
    var iconName: String?

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// 消费评分。`nil` = 未评分（不是 `.npc`）。
    var grade: SpendGrade? {
        get { gradeRaw.flatMap { SpendGrade(rawValue: $0) } }
        set { gradeRaw = newValue?.rawValue }
    }

    /// 是否允许评分：只有支出（PRD 9.13 规则 2）。
    var canBeGraded: Bool { kind == .expense }

    /// 是否已被软删除。
    var isDeleted: Bool { deletedAt != nil }

    init(
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        receivedAmount: Decimal? = nil,
        fee: Decimal? = nil,
        category: Category? = nil,
        iconName: String? = nil,
        grade: SpendGrade? = nil,
        installmentKey: String? = nil,
        groupID: String? = nil,
        createdAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.account = account
        self.toAccount = toAccount
        self.receivedAmount = receivedAmount
        self.fee = fee
        self.category = category
        self.iconName = iconName
        self.gradeRaw = grade?.rawValue
        self.installmentKey = installmentKey
        self.groupID = groupID
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
