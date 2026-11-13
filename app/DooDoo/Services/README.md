# Services · 领域服务

> 状态：**M3-10**——`LedgerService` 已有 `insert` / `softDelete` / `recalculateAll` / `adjustAccountBalance`；`SeedService` 按 `seedVersion` 重建演示数据；`InstallmentService` 建分期计划并展开未来期（存量录入与记一笔内联分期共用，后者带 `createdFromEntry`）；`AssetSummaryService` 做资产页聚合。

| 入口 | 职责 |
|---|---|
| `LedgerService.recalculateAll(in:)` | 扫全部账户与流水，`currentBalance = initialBalance + Σ effect`。数据修复、导入校验、单测都走它 |
| `LedgerService.adjustAccountBalance(_:to:in:)` | 改余额的唯一入口：反推 `initialBalance` 再重算，视图层不许直接赋 `currentBalance` |
| `LedgerService.flow(of:)` | 单笔流水对**两个**账户的影响（`AccountFlow{from,to}`）。还款、转账同时动两边；**转账两边等额**（转出 = 转入 = 到账额），手续费由一条独立的 `expense` 流水承担 |
| `LedgerService.insert(...)` | 唯一写入入口。支持 `toAccount` / `receivedAmount` / `grade`；写完整额后走**增量重算**，不再全表扫描 |
| `LedgerService.effect(of:)` | 单边视图（= `flow.from`），给「按账户查流水」「净值曲线」用 |
| `SeedService.prepare(context:)` | `seedVersion` 迁移 → 补图标 → 重算。首页与资产页启动时都调 |
| `InstallmentService.insert(...)` | 建分期计划 + `generateFuturePeriods` 展开未来逐期。**不动余额**——分期是时间表，动钱的是还款流水。`createdFromEntry` 标记「记一笔里跟消费一起建的」，`CardDebt` 据此不再把它的未还期再加进「我欠」 |
| `InstallmentService.generateFuturePeriods(for:in:)` | 按剩余期数/每期金额/下一期还款日重建期表，`isManualOverride` 的那几期保留不动 |
| `InstallmentService.count(in:)` / `mostRecentAccount(in:)` | 连录用：已录笔数与「上一笔挂的卡」 |
| `InstallmentService.migrateLegacyRemainingPrincipal(in:)` | M3-3 修数据：老计划把「剩余应还」误存在 `remainingPrincipal` 里，搬到 `remainingDue` 并清掉历史首期，重建期表。幂等，`SeedService.prepare` 末尾调用 |

| 服务 | 里程碑 | 职责 |
|---|---|---|
| `LedgerService` | M1 | **唯一允许写 `Account.currentBalance` 的地方**。流水增删改后重算受影响账户；提供 `recalculateAll()` 供数据修复与单测 |
| `InstallmentService` | M3 | 建计划 + 生成期表。原计划的 `DebtPlanService` 名字没用上（它只做期表，实际还要建 `Installment`） |

## 约束

- 只在这里碰 `ModelContext` 的写操作；View 与 ViewModel 只调用，不自己 `save()`。
- 流水**软删除**（`Transaction.deletedAt`），不做物理删除。
- 任何金额计算先落到 `Math/` 的纯函数，Service 只做编排与持久化。
