# Math · 纯函数

> 状态：**9 个文件**（`InstallmentMath` / `InstallmentIntake` 于 M3 加入，`TxRollup` 于 11-11 加入）。`DayMath`（分组/7 天窗口/合计，合计只看 `.expense`——手续费已是独立流水）、`MoneyMath`（格式化）、`NetWorth`（我有/我欠/净资产）、`AccountDelta`（环比，分母用上期值）、`NetWorthSeries`（5 区间回推走势）、`TransferMath`（手续费与还款后余额）、`InstallmentMath`（逐期展开与年化反算）、`InstallmentIntake`（存量录入的期数换算、批量进度、按账单日推还款日）、`TxRollup`（转账 + 手续费合并成一行）。

| 文件 | 里程碑 | 输入 → 输出 |
|---|---|---|
| `MoneyMath.swift` | M2 | 金额加减、分账、舍入（`NSDecimalRound`，显式指定规则） |
| `TransferMath.swift` | M2b | 转出/到账 → 手续费（`max(0, 转出−到账)`）、双金额校验、还款后欠款与余额 |
| `InstallmentMath.swift` | M3 | 剩余期数 + 下一期还款日 + 每期金额 → 逐期日期与金额序列；剩余总额；每期金额 + 期数 + 本金或总利息 → **反算年化（估算值，只展示）** |
| `InstallmentIntake.swift` | M3-2 | 存量录入：剩余期数（+ 可选总期数）→ `totalPeriods`/`paidPeriods`；目标/已录 → 还差几笔；账户还款日 → 下一个还款日（31 号落 2 月取当月最后一天） |
| `TxRollup.swift` | 11-11 | 一批流水 → 显示行：同 `groupID` 的转账与手续费合并成一行；孤儿手续费原样保留（不吞真实扣款） |

> 原计划拆成 `DebtPlanMath` + `AnnualRateSolver` 两个文件，实际合并成一个 `InstallmentMath`：
> 展开和反算吃的是同一组输入（期数、每期金额、首末期金额、本金），拆开只会让两个文件互相 import，
> 而 AGENTS 7.3 要的是「钱相关逻辑不夹在视图里」，不是「一个概念必须一个文件」。

## 硬规则

- 纯函数：不依赖 SwiftData、不依赖 UI、不发网络请求，可单测。
- 每个函数的注释写清：输入、输出、边界（0 期、首末期不同、退款超过剩余、除不尽）。
- 除法必须显式舍入规则；默认余数落末期。
- 校准基准：e招贷 9,000 元 24 期反算年化 ≈16.4%，与招行公布 16.43% 相差 < 0.5%。
- 用例取自 PRD 附录真实账单（招行 8857 / 白条序列 / e招贷 / 中移金科），**不得自己编数字**。
