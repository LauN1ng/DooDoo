import Foundation
import SwiftData

/// 账本写入的唯一入口（AGENTS 7.2）。
///
/// M2a 只支持「支出 / 收入」影响余额；还款与转账要同时动两个账户，
/// 属于 M2b，这里**故意返回 0 并留注释**——写一个半对的还款算法比没有更危险。
@MainActor
enum LedgerService {
    /// 插入一笔流水。金额恒为正，方向由 `kind` 决定。
    @discardableResult
    static func insert(
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String? = nil,
        account: Account? = nil,
        category: Category? = nil,
        iconName: String? = nil,
        in context: ModelContext
    ) throws -> Transaction {
        let tx = Transaction(
            amount: amount,
            kind: kind,
            date: date,
            note: note,
            account: account,
            category: category,
            iconName: iconName
        )
        context.insert(tx)
        try context.save()
        try recalculateAll(in: context)
        return tx
    }

    /// 软删除：只打时间戳，不物理删除（余额可回溯）。
    static func softDelete(_ transaction: Transaction, in context: ModelContext, at date: Date = .now) throws {
        transaction.deletedAt = date
        try context.save()
        try recalculateAll(in: context)
    }

    /// 单笔流水对「付款账户余额」的影响。软删除的返回 0。
    ///
    /// - `.expense`：−amount
    /// - `.income`：+amount
    /// - `.repayment` / `.transfer`：涉及两个账户，M2b 实现，**当前返回 0**
    /// - `.adjustment`：余额校准不靠流水实现（见 `adjustAccountBalance`），返回 0
    static func effect(of transaction: Transaction) -> Decimal {
        guard transaction.deletedAt == nil else { return 0 }
        switch transaction.kind {
        case .expense: return -transaction.amount
        case .income: return transaction.amount
        case .repayment, .transfer, .adjustment: return 0
        }
    }

    /// 重算全部账户余额：`currentBalance = initialBalance + Σ effect(未软删流水)`。
    ///
    /// 一次扫表 + 一次写回，O(账户 + 流水)。数据修复、导入校验、单测都走它。
    @discardableResult
    static func recalculateAll(in context: ModelContext) throws -> Int {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        var netByAccount: [PersistentIdentifier: Decimal] = [:]
        for tx in transactions {
            guard let account = tx.account else { continue }
            let delta = effect(of: tx)
            guard delta != 0 else { continue }
            netByAccount[account.persistentModelID, default: 0] += delta
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
    /// M2b 会改成「生成一条 `.adjustment` 流水」，那时才能逐笔回溯是谁在什么时候改的。
    static func adjustAccountBalance(
        _ account: Account,
        to target: Decimal,
        in context: ModelContext
    ) throws {
        let net = account.transactions.reduce(Decimal.zero) { $0 + effect(of: $1) }
        account.initialBalance = target - net
        try recalculateAll(in: context)
    }

    /// 某个账户当前流水造成的净影响（不含 initialBalance）。
    static func netEffect(for account: Account) -> Decimal {
        account.transactions.reduce(Decimal.zero) { $0 + effect(of: $1) }
    }
}
