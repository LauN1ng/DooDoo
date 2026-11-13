import Foundation
import SwiftData

/// 分期计划（M3-1，PRD 9.5）。
///
/// **这不是一笔账，是一张还款时间表。** 它本身不动余额——真正动钱的是挂在它下面的
/// `repayment` 流水（`Transaction.installmentKey` 指回这里）。
///
/// 三条口径（PRD 9.5 总原则）：
/// 1. **历史照账单填，未来由 App 算**——已还的期数只存 `paidPeriods` 这个汇总值，
///    不逐期建记录；未来的期数由 `InstallmentMath.futurePeriods` 展开后**落库**到
///    `InstallmentPeriod`（M3-2 起，见那个文件的注释：任意一期都要能被账单改正）。
/// 2. **只填能看到的**——剩余期数、每期金额、下一期还款日三个必填；首期/末期金额、
///    剩余本金、总利息都是选填。
/// 3. **金额优先，利率是结果**——没有「年化利率」输入栏。它是 `InstallmentMath.impliedAnnualRate`
///    反算出来的展示值，标注「估算」，不参与任何账务计算（AGENTS 7.1）。
///
/// 为什么历史期不落库、未来期落库：过去那一期的真实金额（含利息、贴息、退款抵扣、
/// 余数分配）只有账单知道，App 算不出也不该猜；未来没有账单可抄，适合推算，
/// 而且推算值要允许用户逐期改。
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
    ///
    /// 录入界面不让用户填：`remainingDue` 摊平时会自己算首期（余数落首期，
    /// 见 `InstallmentMath.splitEvenly`）。这个字段只在**老数据**（没有
    /// `remainingDue`）里回放，以及将来分期详情页手工覆盖首期时用。
    var firstPeriodAmount: Decimal?

    /// 单位：元。末期金额，与每期不同时才有值。
    ///
    /// **余数不再落这里**——M3-3 的「余数落末期」是错的（用户 11-11 用两张
    /// 白条账单纠正：15.34 ÷ 3 是 5.12 / 5.11 / 5.11，零头在首期）。
    /// 现在只有老数据回放和手工覆盖会写这个字段。
    var lastPeriodAmount: Decimal?

    /// 单位：元。**剩余应还**——账单上「分期剩余应还(元)」那一栏，如 1830.15。
    ///
    /// 这是存量录入的权威金额（M3-3）：用户能一眼抄到、能拿 App 的数跟账单逐字核对。
    /// 剩余总额、逐期金额都由它摊出来（`InstallmentMath.splitEvenly`），
    /// 除不尽时余数落**首期**，用户不用管首期/其余差异。
    ///
    /// 老数据为 `nil`（那时表单里是「剩余本金」），此时退回按每期金额推算。
    var remainingDue: Decimal?

    /// 单位：元。~~剩余本金~~ —— **已弃用，不再读取**。
    ///
    /// 这个名字在账单上根本不存在（账单给的是含息的「剩余应还」），
    /// 用户只能把 `1830.15` 填进来，而 `203.35 × 9` 恰好也是 `1830.15`，
    /// 于是年化被判成「本金 = 总还款额 = 零息」输出 0.0%（用户 11-11 回传）。
    /// 保留字段只为老库自动迁移不做破坏性动作，新数据一律不写。
    var remainingPrincipal: Decimal?

    /// 单位：元。总利息（账单上的「含利息」，如 176.99）。
    /// 年化反算的唯一输入：现值 = 每期金额 × 总期数 − 总利息。
    var totalInterest: Decimal?

    /// 单位：元。**剩余期**的利息（账单拆两栏时才有值，如 e招贷 的 851.57）。
    ///
    /// 为什么不塞进 `totalInterest`：那个字段的口径是**整笔**（现值 = 每期 × 总期数 − 它），
    /// 拿剩余利息套整笔公式会把 16.43% 报成 8.2%——本金 6,670.93 却按 24 期去折，
    /// 分子分母对不上。账单把「本金 / 利息」拆开时，三个数（剩余应还 − 剩余利息 = 剩余本金、
    /// 剩余期数、每期金额）本身就构成一个自洽的年金，用**剩余口径**算才是对的，
    /// 而且新贷（一期没还）时剩余 = 整笔，两个口径给出同一个答案。
    ///
    /// 可选、默认 `nil`——老库靠这条自动迁移，不会崩（见 `Account` 顶部的迁移说明）。
    var remainingInterest: Decimal?

    /// 单位：元。已享减免合计（国家贴息等，如「已享利息减免 0.57」）。
    ///
    /// PRD 9.5.6 要求分期模型能拆出**本金 / 利息 / 减免**三层，不能只有一个「每期金额」——
    /// 账单上「每期 120.03（含利息 9.22）」和「贴息减免 0.53」是两件事，
    /// 混成一个数就再也拆不回去了，而减免是真金白银的优惠，用户要看得到。
    var totalRebate: Decimal?

    /// 下一期的还款日。**不是历史首期**——存量录入时用户只填「还剩几期、下期什么时候还」。
    var nextDueDate: Date

    /// 这张计划是不是**在「记一笔」里跟消费一起建的**（M3-10，PRD 9.5.6）。
    ///
    /// 两种计划在账上完全不同：
    /// - **存量录入**（`false`）：消费那笔没进本 App，账户余额里一分钱都没有，
    ///   所以「我欠」必须把它的未还期加上（`CardDebt` 的账期那一项）。
    /// - **记一笔新建**（`true`）：消费按**全额**记了一条 `expense`，欠款已经进了
    ///   `Account.currentBalance`。这时再把未还期加一遍就会**翻倍**
    ///   （1,440.39 的平板记成 2,880.78）。
    ///
    /// 所以 `CardDebt` 只对 `false` 的那些期做「余额之外再加」。
    /// 带默认值 → 老库自动迁移，存量计划保持原行为。
    var createdFromEntry: Bool = false

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
        remainingDue: Decimal? = nil,
        remainingPrincipal: Decimal? = nil,
        totalInterest: Decimal? = nil,
        remainingInterest: Decimal? = nil,
        totalRebate: Decimal? = nil,
        nextDueDate: Date,
        createdFromEntry: Bool = false,
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
        self.remainingDue = remainingDue
        self.remainingPrincipal = remainingPrincipal
        self.totalInterest = totalInterest
        self.remainingInterest = remainingInterest
        self.totalRebate = totalRebate
        self.nextDueDate = nextDueDate
        self.createdFromEntry = createdFromEntry
        self.iconName = iconName
        self.createdAt = createdAt
    }
}

extension Installment {
    /// 还剩几期。已还满为 0。
    var remainingPeriods: Int { max(0, totalPeriods - paidPeriods) }

    /// 是否已还清。还清的计划不再进「本月要还」，但仍留在账户详情里做历史。
    var isSettled: Bool { remainingPeriods == 0 }

    /// 剩余总额：未来各期之和。
    ///
    /// 有 `remainingDue`（账单上的剩余应还）就**原样用它**——用户拿这个数逐字核对账单，
    /// 差一分钱都会变成疑点。口径在 `InstallmentMath.remainingTotal`，这里只做转发。
    var remainingTotal: Decimal {
        InstallmentMath.remainingTotal(
            count: remainingPeriods,
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount,
            remainingDue: remainingDue
        )
    }

    /// 未来每一期（含日期与金额）。口径在 `InstallmentMath.futurePeriods`；
    /// 建计划时由 `InstallmentService.generateFuturePeriods` 落成 `InstallmentPeriod`。
    func futurePeriods(calendar: Calendar = .current) -> [InstallmentMath.Period] {
        InstallmentMath.futurePeriods(
            count: remainingPeriods,
            nextDueDate: nextDueDate,
            perPeriodAmount: perPeriodAmount,
            firstPeriodAmount: firstPeriodAmount,
            lastPeriodAmount: lastPeriodAmount,
            remainingDue: remainingDue,
            calendar: calendar
        )
    }

    /// 年化该用哪个「每期金额」。
    ///
    /// 没填末期金额时就是 `perPeriodAmount`（各期相等，二者无差别）。
    /// 填了末期金额时**不能**再用它——那时的 `perPeriodAmount` 是**中间各期**的真值
    /// （496.65 那笔是 83.19），末期只有 80.66。拿 83.19 当每期，年化会被报成
    /// **14.28%**；用整笔平均 `(已还 × 每期 + 剩余应还) ÷ 总期数 = 82.775` 才是 12.53%。
    /// 年化是整笔口径（PRD 9.5.3），要的就是这个平均数。
    var perPeriodForAnnualRate: Decimal {
        guard lastPeriodAmount != nil,
              totalPeriods > 0,
              let remainingDue, remainingDue > 0
        else { return perPeriodAmount }
        let paid = Decimal(max(0, paidPeriods))
        return (paid * perPeriodAmount + remainingDue) / Decimal(totalPeriods)
    }

    /// 反算年化（估算，展示用，不参与账务）。**返回百分数**：`16.43` 表示 16.43%，
    /// 展示时直接拼「%」，不要再乘 100。
    ///
    /// 只走**整笔口径**（PRD 9.5.3 原文）：
    ///
    ///     现值 = 每期金额 × 总期数 − 含利息
    ///     求月利率 r 使 现值 = 每期 × (1 − (1+r)^−n) / r，再 × 12
    ///
    /// 为什么不再用「剩余本金 + 剩余期数」那条路径：那个数账单上没有（见
    /// `remainingPrincipal` 的注释），用户填进来的必然是含息的「剩余应还」，
    /// 一填就撞上「现值 = 总还款额」被判成零息。**字段不可得，就别让它参与计算。**
    ///
    /// 整笔口径还有个好处：招行这种平息法（每期利息固定）的产品，
    /// 名义年利率 7.82% 而真实年化 14.13%，只有整笔口径能算出这个翻倍，
    /// 剩余口径会把它报成 18.4%，看着像利率随时间上涨。
    ///
    /// **唯一例外是「剩余本金」真的可得的时候**：账单把「本金 / 利息」拆两行录入
    /// （e招贷 那种），`剩余应还 − 剩余利息` 就是账单自己写的剩余本金，这时改走剩余口径
    /// 反而精确——见 `remainingInterest` 与下面第一个分支。
    ///
    /// 边界：`totalInterest` 没填 / ≤ 0 / `totalPeriods <= 1` → `nil`，
    /// 界面显示「—」并提示补「含利息」，不猜假利率。
    var estimatedAnnualRate: Decimal? {
        guard perPeriodAmount > 0 else { return nil }
        // 账单把「本金 / 利息」拆开录入时（e招贷），利息是**剩余期**的，走剩余口径：
        // 现值 = 剩余应还 − 剩余利息 = 剩余本金（6,670.93），配剩余期数 17，
        // 反算得 16.43%。若硬套整笔公式（总期数 24 + 剩余利息），本金只有 6,670.93
        // 却按 24 期折，会报成 8.2%——分子分母对不上。
        if let remainingInterest, remainingInterest > 0, remainingPeriods > 1 {
            return InstallmentMath.impliedAnnualRate(
                periods: remainingPeriods,
                perPeriodAmount: perPeriodAmount,
                totalInterest: remainingInterest
            )
        }
        guard let totalInterest, totalInterest > 0, totalPeriods > 1 else {
            return nil
        }
        return InstallmentMath.impliedAnnualRate(
            periods: totalPeriods,
            perPeriodAmount: perPeriodForAnnualRate,
            totalInterest: totalInterest
        )
    }
}
