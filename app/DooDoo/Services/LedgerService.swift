import Foundation
import SwiftData

/// 一笔流水对**两个**账户的净影响（M2b 起）。
///
/// 单位：元。两个值**分别对应 `Transaction` 的两个账户字段**，不按「付出/收入」命名：
/// - `from` = `transaction.account` 的余额变化（支出/还款/转账为负，收入为正）
/// - `to` = `transaction.toAccount` 的余额变化（还款/转账为正，其余为 0）
///
/// 收入没有 `toAccount`，钱进的是 `account`，所以记在 `from` 位上。
struct AccountFlow: Equatable, Sendable {
    var from: Decimal
    var to: Decimal

    static let zero = AccountFlow(from: 0, to: 0)

    var isEmpty: Bool { from == 0 && to == 0 }
}

/// 账本写入的唯一入口（AGENTS 7.2）。
///
/// M2b 起支持双账户流转：还款、转账同时影响两个账户。
///
/// **转账 + 手续费的正确模型**（2026-11-10 修正）：
/// 转账本身按**等额**记（转出 = 转入 = 到账额），手续费另生成一条 `expense`
/// 流水、分类「其他 › 手续费」。两者相加正好是用户填的转出总额。
///
/// 早期实现走的是「转账直接扣全额、手续费只藏在 `fee` 字段里不落流水」，
/// 结果是首页日卡里看不到那一行，用户无法核对「列表加总」与「支出合计」——
/// 合计含 4 元手续费，列表却只有 4 条 −1,000 的转账（真机反馈 #13）。
/// 之所以当初不敢生成独立流水，是担心「另记一笔会让转出账户多扣一次」；
/// 把转账改成等额之后这个担心就不成立了。
///
/// 写入走**增量重算**（只改受影响账户），`recalculateAll` 保留给数据修复、导入校验与单测。
@MainActor
enum LedgerService {
    /// 插入一笔流水。金额恒为正，方向由 `kind` 决定。
    ///
    /// - `toAccount`：还款的被还信用卡 / 转账的转入账户；
    /// - `receivedAmount`：转账的实际到账（`nil` 视为等于 `amount`，即无手续费）；
    /// - `grade`：消费评分，只有 `.expense` 会被记录（PRD 9.13）。
    @discardableResult
    static func insert(
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        receivedAmount: Decimal? = nil,
        category: Category? = nil,
        iconName: String? = nil,
        grade: SpendGrade? = nil,
        in context: ModelContext
    ) throws -> Transaction {
        let received: Decimal? = kind == .transfer ? (receivedAmount ?? amount) : nil
        let fee: Decimal? = kind == .transfer
            ? TransferMath.fee(amount: amount, received: received ?? amount)
            : nil

        // 有手续费才建分组：转账本体与手续费流水共用一个 ID，删除时一起回滚
        // （否则会留下一条永远对不回来的孤儿流水）。
        let group: String? = (fee ?? 0) > 0 ? UUID().uuidString : nil

        let tx = Transaction(
            amount: amount,
            kind: kind,
            date: date,
            note: note,
            account: account,
            toAccount: toAccount,
            receivedAmount: received,
            fee: fee,
            category: category,
            iconName: iconName,
            grade: kind == .expense ? grade : nil,
            groupID: group
        )
        context.insert(tx)
        apply(flow(of: tx), from: account, to: toAccount)

        // PRD 9.8 原文：手续费 > 0 时，自动生成一条 `expense`，分类「手续费」，计入本月消费。
        // 转账 `flow` 已改成等额（转出 = 到账），所以这条是**真实扣款**、不是装饰：
        // 转账扣 amount−fee，这条再扣 fee，两者相加正好等于 amount。
        if let group, let fee, fee > 0, let account {
            // 分类表最多几十条，直接过滤比 Predicate 宏更稳（本工作区无编译器可验）。
            let feeCategory = try context.fetch(FetchDescriptor<Category>())
                .first { $0.key == "misc.fee" }
            let feeTx = Transaction(
                amount: fee,
                kind: .expense,
                date: date,
                // 备注留空：列表标题会退回分类名「手续费」，不会显示成「支出」
                note: nil,
                account: account,
                category: feeCategory,
                iconName: feeCategory?.iconName,
                groupID: group
            )
            context.insert(feeTx)
            apply(flow(of: feeTx), from: account, to: nil)
        }

        try context.save()
        return tx
    }

    /// 软删除：只打时间戳，不物理删除（余额可回溯）。
    ///
    /// 同一 `groupID` 的流水（转账 + 它的手续费）一并删除并各自回滚，
    /// 否则删掉转账后那条手续费还在账上，付款账户会永久少掉一份手续费。
    static func softDelete(_ transaction: Transaction, in context: ModelContext, at date: Date = .now) throws {
        var targets: [Transaction] = [transaction]

        if let gid = transaction.groupID {
            // 这里用内存过滤而不是 `#Predicate`：`groupID` 是可选 String，
            // 「可选属性 == 非可选常量」在 Predicate 宏里能不能展开，本工作区没有编译器可验，
            // 而软删除不是热路径，一次全表扫描的代价可以接受。
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let matched = all.filter { $0.groupID == gid }
            if !matched.isEmpty { targets = matched }
        }

        for tx in targets where tx.deletedAt == nil {
            // 先把影响取出来，再打时间戳——`flow` 对已删除的流水返回 zero。
            let flow = flow(of: tx)
            let from = tx.account
            let to = tx.toAccount
            tx.deletedAt = date
            apply(AccountFlow(from: -flow.from, to: -flow.to), from: from, to: to)
        }
        try context.save()
    }

    /// 单笔流水对两个账户的影响。软删除的返回 zero。
    ///
    /// - `.expense`：付款账户 −amount
    /// - `.income`：收款账户 +amount
    /// - `.repayment`：扣款账户 −amount，被还信用卡 +amount（欠款变少）
    /// - `.transfer`：转出 −到账额，转入 +到账额（**两边等额**）；手续费由独立流水记录
    /// - `.adjustment`：余额校准不靠流水实现（见 `adjustAccountBalance`），返回 zero
    static func flow(of transaction: Transaction) -> AccountFlow {
        guard transaction.deletedAt == nil else { return .zero }
        switch transaction.kind {
        case .expense:
            return AccountFlow(from: -transaction.amount, to: 0)
        case .income:
            // 收入的收款方就是 `account`（没有 `toAccount`），必须记在 from 位上，
            // 记到 to 会让钱加到一个 nil 账户上——余额凭空消失（已用单测抓住）。
            return AccountFlow(from: transaction.amount, to: 0)
        case .repayment:
            return AccountFlow(from: -transaction.amount, to: transaction.amount)
        case .transfer:
            // 转账两边必须等额（复式记账）：转出 = 转入 = 实际到账额。
            //
            // 手续费**不是**转账金额的一部分——真实世界里银行从你卡上扣 1,000、
            // 对方收到 999.9，差的 0.1 是银行收的手续费，另记一笔 `expense`（PRD 9.8）。
            // 所以这里按 `received` 等额走，那条手续费流水再扣一次，
            // 两者相加正好等于用户填的转出总额，`recalculateAll` 扫全表也能对上。
            let received = transaction.receivedAmount ?? transaction.amount
            return AccountFlow(from: -received, to: received)
        case .adjustment:
            return .zero
        }
    }

    /// 单笔流水对**付款账户**的影响。给「按账户查流水」「净值曲线」这类单边场景用。
    static func effect(of transaction: Transaction) -> Decimal {
        flow(of: transaction).from
    }

    /// 把一笔流水的影响写进两个账户（增量重算的核心）。
    private static func apply(_ flow: AccountFlow, from: Account?, to: Account?) {
        if flow.from != 0, let from {
            from.currentBalance += flow.from
        }
        if flow.to != 0, let to {
            to.currentBalance += flow.to
        }
    }

    /// 重算全部账户余额：`currentBalance = initialBalance + Σ flow`。
    ///
    /// 一次扫表 + 一次写回，O(账户 + 流水)。数据修复、导入校验、单测都走它。
    @discardableResult
    static func recalculateAll(in context: ModelContext) throws -> Int {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        var netByAccount: [PersistentIdentifier: Decimal] = [:]
        for tx in transactions {
            let flow = flow(of: tx)
            guard !flow.isEmpty else { continue }
            if flow.from != 0, let account = tx.account {
                netByAccount[account.persistentModelID, default: 0] += flow.from
            }
            if flow.to != 0, let account = tx.toAccount {
                netByAccount[account.persistentModelID, default: 0] += flow.to
            }
        }

        for account in accounts {
            account.currentBalance = account.initialBalance + (netByAccount[account.persistentModelID] ?? 0)
        }
        try context.save()
        return accounts.count
    }

    /// 把某个账户的余额校准到 `target`：反推 `initialBalance`，再整体重算。
    ///
    /// 视图层改余额必须走这里，不允许直接赋 `currentBalance`。
    static func adjustAccountBalance(
        _ account: Account,
        to target: Decimal,
        in context: ModelContext
    ) throws {
        let net = netEffect(for: account)
        account.initialBalance = target - net
        try recalculateAll(in: context)
    }

    /// 某个账户当前流水造成的净影响（不含 initialBalance）。
    ///
    /// 两边都要算：作为付款方的 `.from` + 作为收款方的 `.to`。
    static func netEffect(for account: Account) -> Decimal {
        var net = Decimal.zero
        for tx in account.transactions {
            net += flow(of: tx).from
        }
        for tx in account.incomingTransactions {
            net += flow(of: tx).to
        }
        return net
    }
}
