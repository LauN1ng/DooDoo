import Foundation
import SwiftData

/// 分期计划里**未来**的一期（M3，PRD 9.5.4 / 9.5.5）。
///
/// 为什么逐期落库、而不是每次现算：
///
/// 1. **任意一期都能被手工改**（PRD 9.5.5）。均摊只是按「零头进首期」的账单规律
///    推出来的草稿（见 `InstallmentMath.splitEvenly`）。真实各期 = 本金均摊 +
///    该期利息，而利息不按期均分（例：496.65 分 6 期的利息是 3.38 / 3.36 × 4 /
///    0.83，末期金额 80.66 = 本金 79.83 + 利息 0.83）；提前还款、平台临时调整
///    也只有账单知道。`isManualOverride` 就是给「重新生成」用的：改过的那期不许被覆盖。
/// 2. **要能标记已还**（`paidAt`）。逾期判断靠的就是「这一期过了还款日还没还」。
///
/// 已发生的历史期**不落库**（PRD 9.5.4）：那部分只有汇总值 `Installment.paidPeriods`。
/// 历史每期的金额（含利息、贴息、退款抵扣、余数分配）App 算不出也不该猜；
/// 58 笔分期逐期补录的成本高到不可能坚持。历史明细也没丢——那笔消费本来就在流水里。
@Model
final class InstallmentPeriod {
    /// 所属分期计划，指向 `Installment.key`。
    /// 用 String 而非关系：理由同 `Transaction.groupID`，迁移只依赖可选字段规则。
    var installmentKey: String

    /// 期号，从 1 开始。1 = **剩余期里的第一期**，不是历史第一期。
    var index: Int

    /// 这一期的还款日。
    var dueDate: Date

    /// 单位：元。这一期应还总额（本金 + 利息 − 减免）。
    var amount: Decimal

    /// 单位：元。本金部分。`nil` = 用户没拆，只有总额。
    var principal: Decimal?

    /// 单位：元。利息部分。
    var interest: Decimal?

    /// 单位：元。这一期的减免（国家贴息，PRD 9.5.6）。
    var rebate: Decimal?

    /// 用户手工改过这一期。重新生成时**跳过**，不覆盖（PRD 9.5.5）。
    var isManualOverride: Bool = false

    /// 还清时间。`nil` = 未还。逾期判断：`dueDate < 今天 && paidAt == nil`。
    var paidAt: Date?

    /// 已还时那条 `repayment` 流水的分组标识，用于撤销/回滚时配对。
    /// 目前留空，等 M3 接还款流水时填。
    var transactionKey: String?

    var createdAt: Date

    init(
        installmentKey: String,
        index: Int,
        dueDate: Date,
        amount: Decimal,
        principal: Decimal? = nil,
        interest: Decimal? = nil,
        rebate: Decimal? = nil,
        isManualOverride: Bool = false,
        paidAt: Date? = nil,
        transactionKey: String? = nil,
        createdAt: Date = .now
    ) {
        self.installmentKey = installmentKey
        self.index = index
        self.dueDate = dueDate
        self.amount = amount
        self.principal = principal
        self.interest = interest
        self.rebate = rebate
        self.isManualOverride = isManualOverride
        self.paidAt = paidAt
        self.transactionKey = transactionKey
        self.createdAt = createdAt
    }
}

extension InstallmentPeriod {
    /// 是否已还。
    var isPaid: Bool { paidAt != nil }

    /// 是否逾期：过了还款日还没还。
    ///
    /// 按**自然日**比较，不看时分秒——还款日当天还算正常，
    /// 第二天开始才是逾期（PRD 9.7 的警示就是这个口径）。
    func isOverdue(on today: Date, calendar: Calendar = .current) -> Bool {
        guard !isPaid else { return false }
        let due = calendar.startOfDay(for: dueDate)
        let now = calendar.startOfDay(for: today)
        return due < now
    }

    /// 距还款日还有几天。负数 = 已逾期天数。
    func daysUntilDue(from today: Date, calendar: Calendar = .current) -> Int {
        let due = calendar.startOfDay(for: dueDate)
        let now = calendar.startOfDay(for: today)
        return calendar.dateComponents([.day], from: now, to: due).day ?? 0
    }
}
