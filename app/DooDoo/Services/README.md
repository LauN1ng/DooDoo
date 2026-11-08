# Services · 领域服务

> 状态：**M2a**——`LedgerService` 已有 `insert` / `softDelete` / `recalculateAll` / `adjustAccountBalance`；`SeedService` 按 `seedVersion` 重建演示数据。

| 入口 | 职责 |
|---|---|
| `LedgerService.recalculateAll(in:)` | 扫全部账户与流水，`currentBalance = initialBalance + Σ effect`。数据修复、导入校验、单测都走它 |
| `LedgerService.adjustAccountBalance(_:to:in:)` | 改余额的唯一入口：反推 `initialBalance` 再重算，视图层不许直接赋 `currentBalance` |
| `LedgerService.effect(of:)` | 单笔流水对付款账户的影响。**还款/转账当前返回 0**，M2b 才实现 |
| `SeedService.prepare(context:)` | `seedVersion` 迁移 → 补图标 → 重算。首页与资产页启动时都调 |

| 服务 | 里程碑 | 职责 |
|---|---|---|
| `LedgerService` | M1 | **唯一允许写 `Account.currentBalance` 的地方**。流水增删改后重算受影响账户；提供 `recalculateAll()` 供数据修复与单测 |
| `DebtPlanService` | M3 | 由「剩余期数 + 每期金额 + 首期还款日」生成期数序列，处理首/末期不同与余数 |

## 约束

- 只在这里碰 `ModelContext` 的写操作；View 与 ViewModel 只调用，不自己 `save()`。
- 流水**软删除**（`Transaction.deletedAt`），不做物理删除。
- 任何金额计算先落到 `Math/` 的纯函数，Service 只做编排与持久化。
