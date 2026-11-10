# Models · SwiftData 模型

> 状态：**M2b**——四个模型 `AppSettings` / `Account` / `Category` / `Transaction`，外加两个非模型的类型文件：`BrandPalette`（卡面配色）、`SpendGrade`（评分四档枚举）。分期与账单等 M3 再加。

## 三条踩过的坑

1. **不能自己声明 `id`**：`@Model` 已通过 `persistentModelID` 提供 `Identifiable`，再写 `var id: UUID` 会抢名字。
2. **后加字段必须带默认值**：SwiftData 只认「可选」或「有默认值」，否则迁移抛错、App 启动闪退。
3. **默认值必须完全限定**：`var createdAt: Date = Date.now`，写成 `.now` 会报
   `A default value requires a fully qualified domain named value (from macro 'Model')`。

| 模型 | 里程碑 | 说明 |
|---|---|---|
| `AppSettings` | M0 ✅ | 收支配色、逾期横幅开关 |
| `Account` | M2 | 账户容器：名字 / 类型 / 额度 / 账单周期 / 还款日 / 当前余额 |
| `Transaction` | M1 | 流水，软删除（`deletedAt`），金额一律 `Decimal` |
| `DebtPlan` | M3 | 分期计划：剩余期数 + 每期金额 + 首期还款日；利率是反算只读 |
| `Installment` / `BillStatement` | M3 | 期数与账单期，用于「本月要还」口径 |
| `Category` | M1 | 一级 8 类支出 + 2 类收入，各带二级子类（共 39 个内置）；`key`/`parentKey` 存层级，统计按一级 |

## 硬规则（`AGENTS.md` 7.1）

- **所有金额用 `Decimal`**，禁止 `Double`/`Float` 参与金额运算与存储。
- 字段注释必须写单位与正负约定，例：`var currentBalance: Decimal // 单位：元；储蓄为正，信用/借款欠款为负`。
- `Account.currentBalance` **只能由 `LedgerService` 写入**，任何视图不得直接赋值。
