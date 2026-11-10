import Foundation
import SwiftData
import Testing

@testable import DooDoo

/// 转账回执与「被转账户收入」提示（真机反馈 #12）。
///
/// 背景：转账一笔同时动两个账户，但流水里只留**一条**转出记录。
/// 用户看到钱从 A 出去了，却没有任何地方说 B 收到了，于是报「被转账户没收入」。
/// 账本身是对的（`LedgerService.apply` 给收款方 `+= received`），
/// 缺的是可见性——这组测试锁住那句话确实说得对、且该说的时候才说。
@MainActor
struct TransferReceiptTests {
    private func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self, Category.self, Transaction.self, AppSettings.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// 建好两个账户并把 ViewModel 停在指定类型上。
    /// 顺序要紧：`load` 末尾会 `resetForType`，先 load 再指定账户才不会被清掉。
    private func makeVM(
        type: TransactionKind,
        targetKind: AccountKind = .savings,
        in context: ModelContext
    ) throws -> EntryViewModel {
        let payer = Account(name: "建行 5044", kind: .savings, initialBalance: dec("5000"))
        let target = Account(
            name: targetKind == .credit ? "花呗" : "招行 8857",
            kind: targetKind,
            initialBalance: targetKind == .credit ? dec("-3217.42") : dec("800")
        )
        context.insert(payer)
        context.insert(target)
        try context.save()

        let vm = EntryViewModel()
        vm.setType(type)
        vm.load(context: context)
        vm.payer = payer
        vm.target = target
        return vm
    }

    @Test("转账有手续费：回执写清转出、到账与手续费三个数")
    func receiptWithFee() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .transfer, in: context)
        vm.setAmountText("1000")
        vm.setFeeText("0.10")

        let text = try #require(vm.receiptText)
        #expect(text.contains("建行 5044"))
        #expect(text.contains("转出 ¥1,000.00"))
        #expect(text.contains("招行 8857"))
        #expect(text.contains("到账 ¥999.90"))
        #expect(text.contains("手续费 ¥0.10"))
    }

    @Test("转账无手续费：回执明说「无手续费」，不写 0.00")
    func receiptWithoutFee() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .transfer, in: context)
        vm.setAmountText("500")

        let text = try #require(vm.receiptText)
        #expect(text.contains("到账 ¥500.00"))
        #expect(text.contains("无手续费"))
    }

    @Test("非转账类型不给回执")
    func noReceiptForNonTransfer() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .expense, in: context)
        vm.setAmountText("32")

        #expect(vm.receiptText == nil)
    }

    @Test("转进信用账户说「还款」，不是「到账」")
    func receiptIntoCredit() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .transfer, targetKind: .credit, in: context)
        vm.setAmountText("600")

        let text = try #require(vm.receiptText)
        #expect(text.contains("还款 ¥600.00"))
        #expect(!text.contains("到账"))
    }

    @Test("同一账户转账不给回执（校验未过就不该有回执）")
    func noReceiptWhenSameAccount() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .transfer, in: context)
        vm.target = vm.payer
        vm.setAmountText("100")

        #expect(vm.receiptText == nil)
    }

    @Test("收款方余额确实增加了到账金额——回执不是空口白话")
    func targetBalanceActuallyGrows() throws {
        let context = try makeContext()
        let vm = try makeVM(type: .transfer, in: context)
        vm.setAmountText("1000")
        vm.setFeeText("0.10")

        // 顺序要紧：预览值必须在填完金额之后取，否则拿到的是 800（还没算到账）。
        let preview = try #require(vm.targetBalanceAfter)
        let targetBefore = vm.target?.currentBalance ?? 0

        vm.save(in: context)

        #expect(vm.errorMessage == nil)
        let after = vm.target?.currentBalance ?? 0
        #expect(after - targetBefore == dec("999.90"))
        // 保存前的预览值必须等于落库后的真实余额，否则面板说了假话。
        #expect(after == preview)
    }
}
