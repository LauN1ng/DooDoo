# Services · 领域服务

> 状态：**M1 已有两个**——`LedgerService`（插入 / 软删除）与 `SeedService`（首次启动铺演示数据）。
> `LedgerService.recalculateAll()` 故意留到 M2：余额算法比没有更危险，不写半成品。

| 服务 | 里程碑 | 职责 |
|---|---|---|
| `LedgerService` | M1 | **唯一允许写 `Account.currentBalance` 的地方**。流水增删改后重算受影响账户；提供 `recalculateAll()` 供数据修复与单测 |
| `DebtPlanService` | M3 | 由「剩余期数 + 每期金额 + 首期还款日」生成期数序列，处理首/末期不同与余数 |

## 约束

- 只在这里碰 `ModelContext` 的写操作；View 与 ViewModel 只调用，不自己 `save()`。
- 流水**软删除**（`Transaction.deletedAt`），不做物理删除。
- 任何金额计算先落到 `Math/` 的纯函数，Service 只做编排与持久化。
