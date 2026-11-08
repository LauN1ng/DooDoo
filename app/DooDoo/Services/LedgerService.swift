import Foundation
import SwiftData

/// 账本写入的唯一入口（AGENTS 7.2）。
///
/// M1 只有「插一笔」和「软删除」；余额重算（`recalculateAll`）与还款、转账属于 M2/M3，
/// **故意留空**——写一个半对的余额算法比没有更危险。
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
        in context: ModelContext
    ) throws -> Transaction {
        let tx = Transaction(
            amount: amount,
            kind: kind,
            date: date,
            note: note,
            account: account,
            category: category
        )
        context.insert(tx)
        try context.save()
        return tx
    }

    /// 软删除：只打时间戳，不物理删除（余额可回溯）。
    static func softDelete(_ transaction: Transaction, in context: ModelContext, at date: Date = .now) throws {
        transaction.deletedAt = date
        try context.save()
    }
}
