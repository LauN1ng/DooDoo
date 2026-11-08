import Foundation
import SwiftData

/// 账户类型（PRD 3.1）。四类固定，数量与名称完全由用户建。
enum AccountKind: String, Codable, CaseIterable, Sendable {
    case savings   // 储蓄：钱在我这，可随时转出
    case cash      // 现金：手里的纸币
    case credit    // 信用：我欠机构的
    case loan      // 借款：我欠个人的

    var title: String {
        switch self {
        case .savings: "储蓄"
        case .cash: "现金"
        case .credit: "信用"
        case .loan: "借款"
        }
    }

    /// 是否为负债类（余额为负）。
    var isLiability: Bool {
        self == .credit || self == .loan
    }
}

/// 账户：只是容器。
///
/// M1 只用到 `name`（流水行要显示「吃 · 花呗」）与 `kind`；
/// 额度、账单周期、还款日等字段属于 M2/M3，**不要提前加**。
@Model
final class Account {
    /// 稳定标识。
    var id: UUID

    /// 账户名，如「花呗」「建行5044」。
    var name: String

    /// 账户类型。
    var kindRaw: String

    /// 单位：元。储蓄/现金为正；信用/借款的欠款为负。
    /// **只能由 `LedgerService` 写入**（AGENTS 7.2），M1 尚不重算，M2 才落地。
    var currentBalance: Decimal

    var createdAt: Date

    /// 该账户名下的流水（反向关系）。
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .savings }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: AccountKind, currentBalance: Decimal = 0, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.currentBalance = currentBalance
        self.createdAt = createdAt
    }
}
