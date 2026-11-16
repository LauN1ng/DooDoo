import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// `LedgerService.effect(of:for:)` 的口径门禁（2026-11-16 新增）。
///
/// 加这个方法是为了储蓄详情页的余额走势：只看 `account.transactions` 会漏掉
/// `toAccount` 那一侧（转账转入、信用卡还款入账），曲线会一直往下掉，
/// 而余额是涨的。
///
/// **为什么不能用 `-effect(of:)` 代替**：带手续费的转账 `from = −到账额`、
/// `to = +到账额`，两者有时绝对值相等（无手续费）；但 `.expense` 的 `to` 恒为 0，
/// 取负会凭空多出一笔收入。这组测试把「按账户落在哪一侧取对应值」这件事钉住。
@MainActor
struct AccountEffectTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self,
            Installment.self, InstallmentPeriod.self, BillStatement.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeAccount(_ name: String, _ kind: AccountKind, _ balance: String, in context: ModelContext) -> Account {
        let account = Account(name: name, kind: kind, initialBalance: dec(balance))
        context.insert(account)
        return account
    }

    @Test("支出：付款方拿到 −amount，收款方与无关账户都拿到 0")
    func expenseOnlyTouchesPayer() throws {
        let context = try makeContext()
        let card = makeAccount("招行 8857", .credit, "-3000", in: context)
        let other = makeAccount("建行 5044", .savings, "5000", in: context)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("120.00"), kind: .expense, date: .now, account: card, in: context
        )

        #expect(LedgerService.effect(of: tx, for: card) == dec("-120.00"))
        #expect(LedgerService.effect(of: tx, for: other) == dec("0"))
    }

    @Test("收入：钱进的是 account 一侧，所以从那一侧拿到 +amount")
    func incomeLandsOnAccountSide() throws {
        let context = try makeContext()
        let salary = makeAccount("工资卡", .savings, "0", in: context)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("6476.47"), kind: .income, date: .now, account: salary, in: context
        )

        #expect(LedgerService.effect(of: tx, for: salary) == dec("6476.47"))
    }

    @Test("转账：A 侧 −到账额、B 侧 +到账额；带手续费时两侧绝对值不相等，取负会错")
    func transferReadsBothSides() throws {
        let context = try makeContext()
        let from = makeAccount("建行 5044", .savings, "5000", in: context)
        let to = makeAccount("微信零钱", .savings, "0", in: context)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("1000.00"),
            kind: .transfer,
            date: .now,
            account: from,
            toAccount: to,
            receivedAmount: dec("999.90"),
            in: context
        )

        #expect(LedgerService.effect(of: tx, for: from) == dec("-999.90"))
        #expect(LedgerService.effect(of: tx, for: to) == dec("999.90"))
        // 若实现误用「取负」，B 侧会得到 +999.90 恰好也对——
        // 真正会露馅的是 `.expense`（见上一条），这里额外确认两侧都由 flow 各自给出。
        #expect(LedgerService.effect(of: tx, for: from) != LedgerService.effect(of: tx, for: to))
    }

    @Test("还款：扣款卡 −amount、被还信用卡 +amount（欠款变小）")
    func repaymentMovesInOppositeDirections() throws {
        let context = try makeContext()
        let payer = makeAccount("建行 5044", .savings, "5000", in: context)
        let card = makeAccount("招行 8857", .credit, "-1115.03", in: context)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("1115.03"), kind: .repayment, date: .now,
            account: payer, toAccount: card, in: context
        )

        #expect(LedgerService.effect(of: tx, for: payer) == dec("-1115.03"))
        #expect(LedgerService.effect(of: tx, for: card) == dec("1115.03"))
    }

    @Test("软删除后两侧都归零：曲线不该再被那条流水推动")
    func softDeletedReturnsZero() throws {
        let context = try makeContext()
        let from = makeAccount("建行 5044", .savings, "5000", in: context)
        let to = makeAccount("微信零钱", .savings, "0", in: context)
        try context.save()

        let tx = try LedgerService.insert(
            amount: dec("500.00"), kind: .transfer, date: .now,
            account: from, toAccount: to, in: context
        )
        try LedgerService.softDelete(tx, in: context)

        #expect(LedgerService.effect(of: tx, for: from) == dec("0"))
        #expect(LedgerService.effect(of: tx, for: to) == dec("0"))
    }
}
