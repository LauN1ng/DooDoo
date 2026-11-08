# Models · SwiftData 模型

> 状态：**M1 已落四个模型**——`AppSettings` / `Account` / `Category` / `Transaction`。分期与账单等 M3 再加。

| 模型 | 里程碑 | 说明 |
|---|---|---|
| `AppSettings` | M0 ✅ | 收支配色、逾期横幅开关 |
| `Account` | M2 | 账户容器：名字 / 类型 / 额度 / 账单周期 / 还款日 / 当前余额 |
| `Transaction` | M1 | 流水，软删除（`deletedAt`），金额一律 `Decimal` |
| `DebtPlan` | M3 | 分期计划：剩余期数 + 每期金额 + 首期还款日；利率是反算只读 |
| `Installment` / `BillStatement` | M3 | 期数与账单期，用于「本月要还」口径 |
| `Category` | M1 | 8 类支出 + 2 类收入，v1 不支持自定义 |

## 硬规则（`AGENTS.md` 7.1）

- **所有金额用 `Decimal`**，禁止 `Double`/`Float` 参与金额运算与存储。
- 字段注释必须写单位与正负约定，例：`var currentBalance: Decimal // 单位：元；储蓄为正，信用/借款欠款为负`。
- `Account.currentBalance` **只能由 `LedgerService` 写入**，任何视图不得直接赋值。
