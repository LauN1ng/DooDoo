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
/// **所有后加字段都带默认值**——SwiftData 老库迁移只认「可选」或「有默认值」，
/// 否则 `ModelContainer` 直接抛错、App 一启动就闪退（`iconName` 上已经踩过一次）。
@Model
final class Account {
    // 标识由 SwiftData 的 `persistentModelID` 提供，不自己声明 `id`。

    /// 账户名，如「花呗」「建行5044」。
    var name: String

    var kindRaw: String

    /// 单位：元。**建账那一刻的余额**，是重算的起点。
    /// 改余额不直接改 `currentBalance`，而是反推这个值（见 `LedgerService.adjustAccountBalance`）。
    var initialBalance: Decimal = 0

    /// 单位：元。储蓄/现金为正；信用/借款的欠款为负。
    /// **派生值，只能由 `LedgerService` 写**（AGENTS 7.2）。
    var currentBalance: Decimal = 0

    /// 单位：元。信用额度，仅信用账户有。
    var creditLimit: Decimal?

    /// 单位：元。被降额之前的额度，仅作历史展示。
    var originalLimit: Decimal?

    /// 账单周期起（日），如 15。
    var billCycleStart: Int?

    /// 账单周期止（日），如 14。
    var billCycleEnd: Int?

    /// 还款日（日），如 25。
    var dueDay: Int?

    /// 所属平台，如「招商银行」「支付宝」。
    var platform: String?

    /// 短名，流水副标题用（「行 · 招行8857」）。为空时退回 `name`。
    /// 卡面上不用它——卡面写品牌全名 + 类型。
    var shortName: String = ""

    /// 品牌 id，对应 `BrandPalette`，卡面取色的唯一来源。
    var brandId: String = "cash"

    /// 同一品牌下的第几张卡（影响卡面色阶）。
    var variant: Int = 0

    /// 卡号后四位，没有则为空串。
    var last4: String = ""

    /// 卡面右下角的网络标，如 `UNIONPAY` / `CREDIT` / `WALLET`。
    var networkLabel: String = ""

    /// 组内手工顺序，小的在前（规格第八节未锁定项）。
    var sortOrder: Int = 0

    var createdAt: Date = .now

    /// 该账户名下的流水（反向关系）。
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .savings }
        set { kindRaw = newValue.rawValue }
    }

    init(
        name: String,
        kind: AccountKind,
        initialBalance: Decimal = 0,
        brandId: String = "cash",
        variant: Int = 0,
        last4: String = "",
        networkLabel: String = "",
        platform: String? = nil,
        shortName: String = "",
        creditLimit: Decimal? = nil,
        originalLimit: Decimal? = nil,
        billCycleStart: Int? = nil,
        billCycleEnd: Int? = nil,
        dueDay: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.initialBalance = initialBalance
        self.currentBalance = initialBalance
        self.brandId = brandId
        self.variant = variant
        self.last4 = last4
        self.networkLabel = networkLabel
        self.platform = platform
        self.shortName = shortName
        self.creditLimit = creditLimit
        self.originalLimit = originalLimit
        self.billCycleStart = billCycleStart
        self.billCycleEnd = billCycleEnd
        self.dueDay = dueDay
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension Account {
    /// 卡面上的类型说明，如「信用卡」「循环 + 分期」。规格 4.3 要求最多 1 行。
    var typeLabel: String {
        switch kind {
        case .savings: "储蓄卡"
        case .cash: "现金"
        case .credit: "信用卡"
        case .loan: "借款"
        }
    }

    /// 卡号显示位，没有卡号就不显示。
    var maskedNumber: String {
        last4.isEmpty ? "" : "•••• \(last4)"
    }

    /// 流水副标题与列表用的名字：短名优先。
    var displayShortName: String {
        shortName.isEmpty ? name : shortName
    }

    /// 卡面第一行：品牌全名（「招商银行」），没有品牌就用账户名。
    var cardTitle: String {
        let brand = BrandPalette.style(brandId)
        return brand.id == "cash" ? name : brand.name
    }
}
