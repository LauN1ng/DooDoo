# Models · SwiftData 模型

> 状态：**M3**——六个模型 `AppSettings` / `Account` / `Category` / `Transaction` / `Installment` / `InstallmentPeriod`，外加两个非模型的类型文件：`BrandPalette`（卡面配色）、`SpendGrade`（评分四档枚举）。`BillStatement`（循环账单）M3 后半段再加。

## 三条踩过的坑

1. **不能自己声明 `id`**：`@Model` 已通过 `persistentModelID` 提供 `Identifiable`，再写 `var id: UUID` 会抢名字。
2. **后加字段必须带默认值**：SwiftData 只认「可选」或「有默认值」，否则迁移抛错、App 启动闪退。
3. **默认值必须完全限定**：`var createdAt: Date = Date.now`，写成 `.now` 会报
   `A default value requires a fully qualified domain named value (from macro 'Model')`。

| 模型 | 里程碑 | 说明 |
|---|---|---|
| `AppSettings` | M0 ✅ | 收支配色、逾期横幅开关 |
| `Account` | M2 | 账户容器：名字 / 类型 / 额度 / 账单周期 / 还款日 / 当前余额 |
| `Transaction` | M1 | 流水，软删除（`deletedAt`），金额一律 `Decimal`。M2b 加 `toAccount` / `receivedAmount` / `fee` / `groupID`——`groupID` 让转账与它自动生成的手续费流水绑定，删除时级联。M3 加 `installmentKey`，指向分期计划，只有 `.repayment` 会带 |
| `Installment` | M3 ✅ | 分期计划。三个必填：剩余期数、每期金额、下一期还款日；**没有年化输入栏**，那是反算出来的展示值。本金 / 利息 / 减免拆三层（PRD 9.5.6），`totalRebate` 单独存 |
| `InstallmentPeriod` | M3 ✅ | 未来每一期。历史期**不落库**，只存 `Installment.paidPeriods` 汇总（PRD 9.5.4）；逐期落库是为了支持手工改（`isManualOverride`，重新生成时跳过）与已还标记（`paidAt`，逾期判断靠它） |
| `BillStatement` | M3 待建 | 循环账单：每月手录本期应还 |
| `Category` | M1 | 一级 8 类支出 + 2 类收入，各带二级子类（共 51 个内置，每个一级/二级各配一枚 Fluent3D 图标）；`key`/`parentKey` 存层级，统计按一级 |

## 硬规则（`AGENTS.md` 7.1）

- **所有金额用 `Decimal`**，禁止 `Double`/`Float` 参与金额运算与存储。
- 字段注释必须写单位与正负约定，例：`var currentBalance: Decimal // 单位：元；储蓄为正，信用/借款欠款为负`。
- `Account.currentBalance` **只能由 `LedgerService` 写入**，任何视图不得直接赋值。
