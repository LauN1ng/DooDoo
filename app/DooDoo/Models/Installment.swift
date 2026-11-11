import Foundation
import SwiftData

/// 分期计划（M3-1，PRD 9.5）。
///
/// **这不是一笔账，是一张还款时间表。** 它本身不动余额——真正动钱的是挂在它下面的
/// `repayment` 流水（`Transaction.installmentKey` 指回这里）。
///
/// 三条口径（PRD 9.5 总原则）：
/// 1. **历史照账单填，未来由 App 算**——已还的期数只存 `paidPeriods` 这个汇总值，
///    不逐期建记录；未来的期数由 `InstallmentMath.futurePeriods` 现算，也不落库。
/// 2. **只填能看到的**——剩余期数、每期金额、下一期还款日三个必填；首期/末期金额、
///    剩余本金、总利息都是选填。
/// 3. **金额优先，利率是结果**——没有「年化利率」输入栏。它是 `InstallmentMath.impliedAnnualRate`
///    反算出来的展示值，标注「估算」，不参与任何账务计算（AGENTS 7.1）。
///
/// 为什么不用 `InstallmentPeriod` 子表：已还部分是汇总的、未来部分是现算的，
/// 落库一张逐期表只会两边都不对齐；等「每期挂哪条流水」真需要时再加（见 PROGRESS M3）。
@Model
final class Installment {
    /// 稳定标识。`Transaction.installmentKey` 用它回指，不用 SwiftData 关系——
    /// 理由同 `Transaction.groupID`：老库迁移只依赖「可选字段」这一条自动迁移规则。
    var key: String

    /// 计划名，如「花呗分期 · AirPods」。存量 58 笔要靠它区分。
    var name: String

    /// 挂在哪张卡上。分期必然属于某个信用账户。
    /// 新模型加关系没有迁移风险（风险只在给**已有**模型加字段时）。
    var account: Account?

    /// 总期数（含已还）。如 12 期。
    var totalPeriods: Int

    /// 已还期数。未来期数 = `totalPeriods - paidPeriods`。
    /// 存量录入时这是用户照账单填的关键数——它和 `nextDueDate` 一起把「剩下什么」定死。
    var paidPeriods: Int

    /// 单位：元。等额情况下的每期金额，如 120.03（含利息）。
    var perPeriodAmount: Decimal

    /// 单位：元。首期金额，与每期不同时才有值（如招行账单「首期 120.06」）。
    /// 这里指**剩余期里的第一期**，不是历史第一期。
    var firstPeriodAmount: Decimal?

    /// 单位：元。末期金额，与每期不同时才有值（余数落末期、贴息减免落末期）。
    var lastPeriodAmount: Decimal?

    /// 单位：元。剩余本金，账单上有的话填，用于更准地反算年化。
    var remainingPrincipal: Decimal?

    /// 单位：元。总利息（账单上的「含利息」，如 110.56）。
    /// 反算年化时用：现值 = 每期金额 × 期数 − 总利息。
    var totalInterest: Decimal?

    /// 单位：元。已享减免合计（国家贴息等，如「已享利息减免 0.57」）。
    ///
    /// PRD 9.5.6 要求分期模型能拆出**本金 / 利息 / 减免**三层，不能只有一个「每期金额」——
    /// 账单上「每期 120.03（含利息 9.22）」和「贴息减免 0.53」是两件事，
    /// 混成一个数就再也拆不回去了，而减免是真金白银的优惠，用户要看得到。
    var totalRebate: Decimal?

    /// 下一期的还款日。**不是历史首期**——存量录入时用户只填「还剩几期、下期什么时候还」。
    var nextDueDate: Date

    /// Fluent3D 图标资源名（bundle 里的 PNG，不带扩展名）。空串 = 用账户默认图标。
    var iconName: String = ""

    var createdAt: Date

    init(
        key: String,
        name: String,
        account: Account? = nil,
        totalPeriods: Int,
        paidPeriods: Int = 0,
        perPeriodAmount: Decimal,
        firstPeriodAmount: Decimal? = nil,
        lastPeriodAmount: Decimal? = nil,
        remainingPrincipal: Decimal? = nil,
        totalInterest: Decimal? = nil,
        totalRebate: Decimal? = nil,
        nextDueDate: Date,
        iconName: String = "",
        createdAt: Date = .now
    ) {
        self.key = key
        self.name = name
        self.account = account
        self.totalPeriods = totalPeriods
        self.paidPeriods = paidPeriods
        self.perPeriodAmount = perPeriodAmount
        self.firstPeriodAmount = firstPeriodAmount
        self.lastPeriodAmount = lastPeriodAmount
        self.remainingPrincipal = remainingPrincipal
        self.totalInterest = totalInterest
        self.totalRebate = totalRebate
        self.nextDueDate = nextDueDate
        self.iconName = iconName
        self.createdAt = createdAt
    }
}

extension Installment {
    /// 还剩几期。已还满为 0。
    var remainingPeriods: Int { max(0, totalPeriods - paidPeriods) }

    /// 是否已还清。还清的计划不再进「本月要还」，但仍留在账户详情里做历史。
    var isSettled: Bool { remainingPeriods == 0 }

    /// 剩余总额：未来各期之和。口径在 `InstallmentMath.remainingTotal`，这里只做取值转发，
    /// 不重复实现一份（两处算钱迟早会分叉）。
    var remainingTotal: Decimal {
        InstallmentMath.remainingTotal(
            count: remainingPeriods,
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount
        )
    }

    /// 未来每一期（含日期与金额）。现算不落库，见 `InstallmentMath.futurePeriods`。
    func futurePeriods(calendar: Calendar = .current) -> [InstallmentMath.Period] {
        InstallmentMath.futurePeriods(
            count: remainingPeriods,
            nextDueDate: nextDueDate,
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount,
            calendar: calendar
        )
    }

    /// 反算年化（估算，展示用，不参与账务）。**返回百分数**：`16.43` 表示 16.43%，
    /// 展示时直接拼「%」，不要再乘 100。
    ///
    /// 两条路径，期数口径必须配平：
    /// - 有「剩余本金」→ 配**剩余期数**。账单直接给了现在的欠款，这是最准的一条，
    ///   也不会把整笔的利息错摊到剩余期上。
    /// - 只有「总利息」→ 配**总期数**，按 PRD 9.5.3 的「每期 × 期数 − 总利息」倒推现值。
    /// - 两者都没有 → `nil`。宁可显示「—」也不猜一个假利率。
    var estimatedAnnualRate: Decimal? {
        if let principal = remainingPrincipal, principal > 0, remainingPeriods > 1 {
            return InstallmentMath.impliedAnnualRate(
                periods: remainingPeriods,
                perPeriodAmount: perPeriodAmount,
                presentValue: principal
            )
        }
        if let totalInterest {
            return InstallmentMath.impliedAnnualRate(
                periods: totalPeriods,
                perPeriodAmount: perPeriodAmount,
                totalInterest: totalInterest
            )
        }
        return nil
    }
}
