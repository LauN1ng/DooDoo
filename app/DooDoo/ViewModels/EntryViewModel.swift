import Foundation
import Observation
import SwiftData

/// 记一笔的状态与校验。**不碰 SwiftData 写入**——保存交给 `LedgerService`（AGENTS 7.4）。
///
/// 四类型共用一套字段，差异靠 `type` 分派：
/// - 支出 / 收入：`payer` = 付款/收款账户，需要分类与（支出的）评分
/// - 还款：`target` = 被还信用卡，`payer` = 扣款账户，无分类无评分
/// - 转账：`payer` = 转出，`target` = 转入，双金额，无分类无评分
@MainActor
@Observable
final class EntryViewModel {
    /// `nonisolated` 是为了让视图能在 `@State` 的属性初始化器里直接 `EntryViewModel()`
    /// （属性初始化器不在 MainActor 上下文里）。所有属性都有默认值，构造过程不碰隔离状态。
    nonisolated init() {}

    // MARK: - 输入

    /// 当前类型。**改它要走 `setType(_:)`**：`@Observable` 不支持 `didSet`，
    /// 默认值重算必须显式调用。
    private(set) var type: TransactionKind = .expense

    /// 金额文本（界面原样，两位小数上限由键盘输入约束）。
    var amountText: String = ""
    /// 转账的到账金额文本。为空时视为等于金额（无手续费）。
    var receivedText: String = ""
    /// 转账的手续费文本。PRD 9.8 明确允许「…或直接填『手续费 0.1』」，
    /// 首版只做了「填到账」那一半（2026-11-09 真机反馈 #9）。
    /// 与 `receivedText` 双向联动，改任何一个另一个自动反算。
    var feeText: String = ""
    /// 改「转出」时按哪一边重算：true = 手续费固定、到账跟动。
    private(set) var feeDriven = false
    var note: String = ""
    var date: Date = .now

    /// 消费评分（只有支出有效）。
    var grade: SpendGrade?

    /// 一级分类 key（如 `food`）。
    var topKey: String = ""
    /// 二级分类 key（如 `food.coffee`），可为空 = 只记一级。
    var subKey: String?
    /// 二级浮层是否展开。
    var showingSub = false

    /// 付款方 / 转出方 / 还款的扣款账户。
    var payer: Account?
    /// 收款方 / 转入方 / 被还的信用卡。
    var target: Account?

    /// 保存失败时的提示，由视图展示。
    var errorMessage: String?

    // MARK: - 数据

    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []

    // MARK: - 派生

    /// 合法的数字输入（POSIX 小数，避免系统区域把 `5.5` 解析成 `55`）。
    /// 实现已收到 `MoneyMath.decimal(_:)`——两处各写一份迟早不一致。
    static func decimal(_ text: String) -> Decimal {
        MoneyMath.decimal(text)
    }

    var amount: Decimal { Self.decimal(amountText) }

    var received: Decimal {
        guard type == .transfer else { return amount }
        return receivedText.isEmpty ? amount : Self.decimal(receivedText)
    }

    var fee: Decimal {
        type == .transfer ? TransferMath.fee(amount: amount, received: received) : 0
    }

    // MARK: - 转账三字段联动

    /// 三个输入框都走**自定义 Binding 的 setter**，不用 `.onChange`：
    /// 联动写另一个字段是直接赋值，不会再触发它的 setter，从根上避免两个
    /// onChange 互相触发成死循环。
    ///
    /// `feeDriven` 只在用户真的编辑了手续费时为 true，改「转出」时据此决定
    /// 保持手续费固定（到账跟动）还是保持到账固定（手续费跟动）。
    func setAmountText(_ new: String) {
        amountText = new
        guard type == .transfer else { return }
        if feeDriven { syncReceivedFromFee() } else { syncFeeFromReceived() }
    }

    func setFeeText(_ new: String) {
        feeText = new
        guard type == .transfer else { return }
        feeDriven = !new.isEmpty
        syncReceivedFromFee()
    }

    func setReceivedText(_ new: String) {
        receivedText = new
        guard type == .transfer else { return }
        feeDriven = false
        syncFeeFromReceived()
    }

    /// 填手续费 → 到账 = 转出 − 手续费（PRD 9.8 第二路）。
    /// 边界：手续费大于转出时到账下限取 0，由校验提示。
    private func syncReceivedFromFee() {
        let value = amount - Self.decimal(feeText)
        let normalized = value > 0 ? value : 0
        receivedText = Self.plainAmount(normalized)
    }

    /// 填到账（或改转出）→ 手续费 = 转出 − 到账，负数按 0。
    private func syncFeeFromReceived() {
        let value = TransferMath.fee(amount: amount, received: received)
        feeText = value > 0 ? Self.plainAmount(value) : ""
    }

    /// 一级分类（支出 8 类 / 收入 2 类）。
    var topCategories: [Category] {
        let income = type == .income
        return categories
            .filter { $0.isTopLevel && $0.isIncome == income }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 当前一级下的二级分类。
    var subCategories: [Category] {
        categories
            .filter { $0.parentKey == topKey }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 最终落库的分类：选了二级用二级，否则用一级。
    var selectedCategory: Category? {
        if let subKey, let sub = categories.first(where: { $0.key == subKey }) { return sub }
        return categories.first { $0.key == topKey }
    }

    /// 需要选账户的卡池：支出全部、收入只储蓄、还款只信用/借款、转账两边都是全部。
    var payerCandidates: [Account] {
        switch type {
        case .income:
            return accounts.filter { $0.kind == .savings || $0.kind == .cash }
        case .repayment:
            return accounts.filter { $0.kind == .savings || $0.kind == .cash }
        default:
            return accounts
        }
    }

    /// 还款的目标卡（信用 / 借款）；转账的转入卡（全部）。
    var targetCandidates: [Account] {
        switch type {
        case .repayment:
            return accounts.filter { $0.kind.isLiability }
        case .transfer:
            return accounts
        default:
            return []
        }
    }

    /// 保存后账户余额会发生什么（只做展示，不写库）。
    var payerBalanceAfter: Decimal? {
        guard let payer else { return nil }
        switch type {
        case .expense, .repayment, .transfer: return payer.currentBalance - amount
        case .income: return payer.currentBalance + amount
        case .adjustment: return payer.currentBalance
        }
    }

    var targetBalanceAfter: Decimal? {
        guard let target else { return nil }
        switch type {
        case .repayment: return target.currentBalance + amount
        case .transfer: return target.currentBalance + received
        default: return nil
        }
    }

    // MARK: - 校验

    /// 能不能存。`nil` 表示可以存。
    var validationMessage: String? {
        if amount <= 0 { return "金额要大于 0" }
        if type == .transfer {
            if let message = TransferMath.validationMessage(amount: amount, received: received) {
                return message
            }
            if feeDriven, Self.decimal(feeText) > amount {
                return "手续费不能大于转出金额"
            }
        }
        if payer == nil && type != .adjustment { return "选一个账户" }
        if (type == .repayment || type == .transfer) && target == nil { return "选一个目标账户" }
        if type == .repayment, let payer, let target,
           payer.persistentModelID == target.persistentModelID {
            return "扣款账户和被还的卡不能是同一个"
        }
        if type == .transfer, let payer, let target,
           payer.persistentModelID == target.persistentModelID {
            return "转出和转入不能是同一个账户"
        }
        if type == .expense || type == .income, selectedCategory == nil {
            return "选一个分类"
        }
        return nil
    }

    var canSave: Bool { validationMessage == nil }

    /// 保存成功后给用户看的一句回执。
    ///
    /// 只有转账需要：它一笔同时动两个账户，而流水里只留一条「转出」记录。
    /// 真机反馈 #12——用户看到钱从 A 出去了，却没有任何地方说 B 收到了，
    /// 于是以为「被转账户没收入」。账其实是对的（`LedgerService` 给了对方
    /// `+= received`），缺的就是这句。
    var receiptText: String? {
        guard type == .transfer, canSave, let payer, let target else { return nil }
        let inWord = target.kind.isLiability ? "还款" : "到账"
        let head = "已从 \(payer.displayShortName) 转出 ¥" + MoneyMath.money(amount)
        let tail = "\(target.displayShortName) \(inWord) ¥" + MoneyMath.money(received)
        let feePart = fee > 0 ? "，手续费 ¥" + MoneyMath.money(fee) : "，无手续费"
        return head + "，" + tail + feePart
    }

    /// 主按钮文案。
    var primaryTitle: String {
        switch type {
        case .expense, .income: "记下这笔"
        case .repayment: "确认还款"
        case .transfer: "确认转账"
        case .adjustment: "确认调整"
        }
    }

    // MARK: - 载入与默认值

    /// 切换类型：改值 + 重算默认值（账户池、金额、分类都跟着变）。
    func setType(_ newType: TransactionKind) {
        guard newType != type else { return }
        type = newType
        resetForType()
    }

    func load(context: ModelContext) {
        do {
            accounts = try context.fetch(
                FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.sortOrder)])
            )
            categories = try context.fetch(FetchDescriptor<Category>())
        } catch {
            errorMessage = "读取账户失败：\(error.localizedDescription)"
        }
        resetForType()
    }

    /// 切换类型或首次载入时，把默认值摆好（PRD 9.7：账户与分类都带上次的）。
    private func resetForType() {
        showingSub = false
        subKey = nil
        grade = nil
        errorMessage = nil
        receivedText = ""
        feeText = ""
        feeDriven = false

        switch type {
        case .expense:
            payer = payerCandidates.first
            target = nil
            if topKey.isEmpty || !topCategories.contains(where: { $0.key == topKey }) {
                topKey = topCategories.first?.key ?? ""
            }
        case .income:
            payer = payerCandidates.first
            target = nil
            topKey = topCategories.first?.key ?? ""
            amountText = ""
        case .repayment:
            target = targetCandidates.first
            payer = payerCandidates.first(where: { $0.kind == .savings }) ?? payerCandidates.first
            if let target {
                // 默认带出欠款总额，用户可改。
                amountText = Self.plainAmount(-target.currentBalance)
            }
            topKey = ""
        case .transfer:
            payer = payerCandidates.first
            target = targetCandidates.first { $0.persistentModelID != payer?.persistentModelID }
            amountText = ""
            topKey = ""
        case .adjustment:
            payer = payerCandidates.first
            target = nil
            topKey = ""
        }
    }

    /// 选择一级分类：同类再点一次收起，异类直接打开二级。
    func selectTop(_ category: Category) {
        if topKey == category.key {
            showingSub.toggle()
        } else {
            topKey = category.key
            subKey = nil
            showingSub = true
        }
        grade = category.defaultGrade
    }

    /// 选择二级分类：收起浮层，记住默认档位。
    func selectSub(_ category: Category) {
        subKey = category.key
        showingSub = false
        if let inherited = category.defaultGrade {
            grade = inherited
        }
    }

    /// 评分改一次就记到分类上（PRD 9.13 规则 3），下次自动带出。
    func rememberGrade() {
        guard type == .expense, let category = selectedCategory else { return }
        category.defaultGrade = grade
    }

    // MARK: - 保存

    /// 写入账本。抛错时把信息落到 `errorMessage`，由视图提示。
    func save(in context: ModelContext) {
        errorMessage = nil
        guard canSave, let payer else {
            errorMessage = validationMessage
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmedNote.isEmpty ? nil : trimmedNote

        do {
            switch type {
            case .expense:
                try LedgerService.insert(
                    amount: amount,
                    kind: .expense,
                    date: date,
                    note: noteValue,
                    account: payer,
                    category: selectedCategory,
                    iconName: selectedCategory?.iconName,
                    grade: grade,
                    in: context
                )
                rememberGrade()
            case .income:
                try LedgerService.insert(
                    amount: amount,
                    kind: .income,
                    date: date,
                    note: noteValue,
                    account: payer,
                    category: selectedCategory,
                    iconName: selectedCategory?.iconName,
                    in: context
                )
            case .repayment:
                guard let target else { return }
                try LedgerService.insert(
                    amount: amount,
                    kind: .repayment,
                    date: date,
                    note: noteValue,
                    account: payer,
                    toAccount: target,
                    in: context
                )
            case .transfer:
                guard let target else { return }
                try LedgerService.insert(
                    amount: amount,
                    kind: .transfer,
                    date: date,
                    note: noteValue,
                    account: payer,
                    toAccount: target,
                    receivedAmount: received,
                    in: context
                )
            case .adjustment:
                break
            }
            try context.save()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    /// `Decimal` → 纯数字文本（不带千分位、不带货币符号）。
    /// 实现已收到 `MoneyMath.plain(_:)`，理由同上。
    static func plainAmount(_ value: Decimal) -> String {
        MoneyMath.plain(value)
    }
}
