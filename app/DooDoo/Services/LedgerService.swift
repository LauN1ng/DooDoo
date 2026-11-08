import Foundation
import SwiftData

/// 一笔流水对**两个**账户的净影响（M2b 起）。
///
/// 单位：元。`from` 是付款方 / 转出方 / 扣款账户的变化（通常是负数），
/// `to` 是收款方 / 转入方 / 被还信用卡的变化（正数：储蓄增加，信用欠款减少）。
struct AccountFlow: Equatable, Sendable {
    var from: Decimal
    var to: Decimal

    static let zero = AccountFlow(from: 0, to: 0)

    var isEmpty: Bool { from == 0 && to == 0 }
}

/// 账本写入的唯一入口（AGENTS 7.2）。
///
/// M2b 起支持双账户流转：还款、转账同时影响两个账户，差额即手续费，**不额外生成扣款流水**
/// （PRD 9.8：另记一笔会让转出账户多扣一次，余额必然对不上）。
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
            grade: kind == .expense ? grade : nil
        )
        context.insert(tx)
        apply(flow(of: tx), from: account, to: toAccount)
        try context.save()
        return tx
    }

    /// 软删除：只打时间戳，不物理删除（余额可回溯）。
    static func softDelete(_ transaction: Transaction, in context: ModelContext, at date: Date = .now) throws {
        // 先把影响取出来，再打时间戳——`flow` 对已删除的流水返回 zero。
        let flow = flow(of: transaction)
        let from = transaction.account
        let to = transaction.toAccount
        transaction.deletedAt = date
        apply(AccountFlow(from: -flow.from, to: -flow.to), from: from, to: to)
        try context.save()
    }

    /// 单笔流水对两个账户的影响。软删除的返回 zero。
    ///
    /// - `.expense`：付款账户 −amount
    /// - `.income`：收款账户 +amount
    /// - `.repayment`：扣款账户 −amount，被还信用卡 +amount（欠款变少）
    /// - `.transfer`：转出账户 −amount，转入账户 +receivedAmount，差额即手续费
    /// - `.adjustment`：余额校准不靠流水实现（见 `adjustAccountBalance`），返回 zero
    static func flow(of transaction: Transaction) -> AccountFlow {
        guard transaction.deletedAt == nil else { return .zero }
        switch transaction.kind {
        case .expense:
            return AccountFlow(from: -transaction.amount, to: 0)
        case .income:
            return AccountFlow(from: 0, to: transaction.amount)
        case .repayment:
            return AccountFlow(from: -transaction.amount, to: transaction.amount)
        case .transfer:
            let received = transaction.receivedAmount ?? transaction.amount
            return AccountFlow(from: -transaction.amount, to: received)
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
