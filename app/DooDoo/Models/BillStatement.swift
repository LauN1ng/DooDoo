import Foundation
import SwiftData

/// 账单状态（PRD 第八节 `BillStatus`）。
///
/// **`.overdue` 不落库**——它是「`pending` 且过了还款日」的派生状态，
/// 到底逾不逾期取决于「今天」是哪天，存下来第二天就过期了。
/// 录入与存储只写 `.pending` / `.paid`，逾期一律由 `isOverdue(on:)` 现算。
enum BillStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case paid
    case overdue

    var title: String {
        switch self {
        case .pending: "待还"
        case .paid: "已还"
        case .overdue: "逾期"
        }
    }
}

/// 循环类账户的一期账单（PRD 第八节 `BillStatement`、9.12）。
///
/// 花呗、白条、抖音月付、信用卡本体这类「每月出一期、这个月还上个月」的账户，
/// 每期账单录一次这里。它是「本月要还」在**有账单**时的唯一权威：
/// `DueMath.accountDue` 一旦拿到账单就只认账单金额，绝不与分期相加
/// （叠加会把分期算两遍：账单 2,742.00 + 分期 693.67 = 3,435.67）。
///
/// 与 `Installment` 的关系：**账单是账期视角，分期是计划视角**。
/// 同一笔分期既会出现在某期账单的 `dueAmount` 里，也会有自己的剩余期数——
/// 所以「我欠」的算法必须按账期去重（见 `CardDebt`），不能两边直接相加。
///
/// 字段与 PRD 一致；`paidAmount` / `totalAmount` / `refundAmount` 为选填，
/// 现阶段录入面板只问必填的三个（账期、本期应还、到期日）。
@Model
final class BillStatement {
    // 标识由 SwiftData 的 `persistentModelID` 提供，不自己声明 `id`——
    // `PersistentModel` 协议已经用 `id: PersistentIdentifier` 占了这个名字，
    // 再声明一个 `var id: UUID` 会与协议要求撞车（`Account` 顶部也记了这条）。

    /// 挂在哪张卡上。循环账单必然属于某个信用账户。
    /// 用可选关系、不加 inverse——理由同 `Installment.account`：
    /// 新模型加关系没有迁移风险（风险只在给**已有**模型加字段时）。
    var account: Account?

    /// 账期，形如 `2026-11`。**它是账单的名字，不是还款日所在月**——
    /// 花呗 10/15–11/14 这一期的名字是 `2026-11`，还款日是 11/25。
    var period: String = ""

    /// 本期还款日，如 2026-11-25。
    var dueDate: Date = Date.now

    /// 单位：元。**本期应还**——账单上那个数的原样，如 1,115.03。
    /// 「本月要还」在账单存在时直接读它，不由消费与分期反算（规格 8.2）。
    var dueAmount: Decimal = 0

    /// 单位：元。实还金额。为 `nil` 时按 `status` 判断是否已还。
    var paidAmount: Decimal?

    /// 单位：元。账单总计（退款前），如 1,806.82。选填，只做展示。
    var totalAmount: Decimal?

    /// 单位：元。本期退款（正数记账，展示时带减号），如 172.74。选填。
    var refundAmount: Decimal?

    /// `BillStatus` 的原始值。用 String 而非枚举字段：
    /// 与 `Account.kindRaw` 同风格，迁移只依赖「有默认值的字段」这一条规则。
    var statusRaw: String = BillStatus.pending.rawValue

    /// 还清时间。`nil` = 未还。与 `status` 冗余，但逾期天数与「哪天还的」都要它。
    var paidAt: Date?

    var createdAt: Date = Date.now

    init(
        account: Account? = nil,
        period: String,
        dueDate: Date,
        dueAmount: Decimal,
        paidAmount: Decimal? = nil,
        totalAmount: Decimal? = nil,
        refundAmount: Decimal? = nil,
        status: BillStatus = .pending,
        paidAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.account = account
        self.period = period
        self.dueDate = dueDate
        self.dueAmount = dueAmount
        self.paidAmount = paidAmount
        self.totalAmount = totalAmount
        self.refundAmount = refundAmount
        self.statusRaw = status.rawValue
        self.paidAt = paidAt
        self.createdAt = createdAt
    }
}

extension BillStatement {
    /// 存储里的状态，不含逾期判断。
    var status: BillStatus {
        get { BillStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// 是否已还清。实还金额填了且覆盖应还，也算还清——
    /// 允许「还了一部分」这种真实情况不把状态改掉。
    var isPaid: Bool {
        if status == .paid { return true }
        if let paidAmount, paidAmount >= dueAmount, dueAmount > 0 { return true }
        return false
    }

    /// 是否逾期：未还且过了还款日。按**自然日**比较，还款日当天不算逾期
    /// （与 `InstallmentPeriod.isOverdue` 同一口径）。
    func isOverdue(on today: Date, calendar: Calendar = .current) -> Bool {
        guard !isPaid else { return false }
        let due = calendar.startOfDay(for: dueDate)
        let now = calendar.startOfDay(for: today)
        return due < now
    }

    /// 逾期天数。未逾期返回 0。
    func overdueDays(on today: Date, calendar: Calendar = .current) -> Int {
        guard isOverdue(on: today, calendar: calendar) else { return 0 }
        let due = calendar.startOfDay(for: dueDate)
        let now = calendar.startOfDay(for: today)
        return calendar.dateComponents([.day], from: due, to: now).day ?? 0
    }

    /// 状态（含逾期判断），给列表标签用。
    func displayStatus(on today: Date, calendar: Calendar = .current) -> BillStatus {
        if isPaid { return .paid }
        return isOverdue(on: today, calendar: calendar) ? .overdue : .pending
    }

    /// 「10/22 已还」这种副标题里的一句。规格第五节要求行下方 9.5pt 小字。
    func dueDateCaption(on today: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: dueDate)
        let monthDay = "\(parts.month ?? 0)/\(parts.day ?? 0)"
        switch displayStatus(on: today, calendar: calendar) {
        case .paid: return "\(monthDay) 已还"
        case .overdue: return "\(monthDay) 逾期 \(overdueDays(on: today, calendar: calendar)) 天"
        case .pending: return "\(monthDay) 到期"
        }
    }
}
