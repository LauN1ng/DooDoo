# Math · 纯函数

> 状态：**14 个文件**（`InstallmentMath` / `InstallmentIntake` 于 M3 加入，`TxRollup` 于 11-11，`DueMath` / `DetailMath` 于 11-12，`BillCycleMath` 于 M3-10，`CreditDebt` / `DebtSnapshot` 于 11-13 取代 `CardDebt`）。`DayMath`（分组/7 天窗口/合计，合计只看 `.expense`——手续费已是独立流水）、`MoneyMath`（格式化）、`NetWorth`（我有/我欠/净资产）、`AccountDelta`（环比，分母用上期值）、`NetWorthSeries`（5 区间回推走势）、`TransferMath`（手续费与还款后余额）、`InstallmentMath`（总额均摊、逐期展开与年化反算，年化只有整笔口径）、`InstallmentIntake`（存量录入的期数换算、批量进度、按账单日推还款日）、`TxRollup`（转账 + 手续费合并成一行）、`DueMath`（本月要还：每卡只出一个 `dueAmount`，账单优先、绝不相加）、`CreditDebt`（**我欠 = max(0, −余额)**，逐卡取正后求和；账单与分期不参与金额）、`DetailMath`（卡详情三列：本期消费 = 账单 − 本月分期，无账单时走 `periodSpend` 且**不含分期本金**；本月要还直接取账单）、`BillCycleMath`（发生日 + 账单周期 → 这一笔归到哪一期账单）、`DebtSnapshot`（`DebtBill` / `DebtPeriod` 两个纯数据快照，只喂 `DetailMath`，不参与欠款）。

| 文件 | 里程碑 | 输入 → 输出 |
|---|---|---|
| `MoneyMath.swift` | M2 | 金额加减、分账、舍入（`NSDecimalRound`，显式指定规则） |
| `TransferMath.swift` | M2b | 转出/到账 → 手续费（`max(0, 转出−到账)`）、双金额校验、还款后欠款与余额 |
| `InstallmentMath.swift` | M3 / M3-3 / M3-5 | 剩余应还 + 期数 → **均摊**（`splitEvenly`，余数落**首期**）；给了末期金额 → 反推中间各期（`splitEndingAt`）；剩余期数 + 下一期还款日 + 金额 → 逐期日期与金额序列；剩余总额（有剩余应还就原样返回）；每期金额 + 总期数 + 含利息 → **反算整笔年化（估算值，只展示）** |
| `InstallmentIntake.swift` | M3-2 | 存量录入：剩余期数（+ 可选总期数）→ `totalPeriods`/`paidPeriods`；目标/已录 → 还差几笔；账户还款日 → 下一个还款日（31 号落 2 月取当月最后一天） |
| `TxRollup.swift` | 11-11 | 一批流水 → 显示行：同 `groupID` 的转账与手续费合并成一行；孤儿手续费原样保留（不吞真实扣款） |
| `DueMath.swift` | 11-12 | 待还条目 + （可选）本期账单 → **每张卡一个** `AccountDue`（账单优先，无账单才取分期，**绝不相加**）；多卡 → `DueGroup`（Σ 各卡）；→ 资产页 2.4 那行文案。窗口 = `dueDate < 下月 1 号`（含逾期），逾期按自然日 |
| `CreditDebt.swift` | 11-13 | 余额 → 单卡欠款 = `max(0, −余额)`；多卡**逐卡取正再求和**（先求和再取正会让溢缴抵掉别卡的欠款）。三类账户同一口径：储蓄余额正 = 我的钱，信用/借款余额负 = 欠的钱 |
| `DebtSnapshot.swift` | 11-13 | `DebtBill` / `DebtPeriod` 两个不可变快照，从已删除的 `CardDebt.swift` 搬来。**只喂 `DetailMath`，不产生金额** |
| `DetailMath.swift` | M3-8 / 11-13 | 卡详情的三列：本期消费 = 本期账单 − 本月到期分期（规格 8.4 的 665.36）；本月要还**直接读账单**（8.2 禁止由消费与分期反推）；往期账单列表排除本期与未来期。11-13 新增 `periodSpend`——**没有账单时「本期消费」改成当前账期内、`installmentKey` 为空的消费流水**（分期本金排除，账期名缺失才退回自然月） |
| `BillCycleMath.swift` | M3-10 | 发生日 + 账户账单周期（起/止/还款日）→ 账期名（`2026-11`，取**周期止所在月**）、周期区间、还款日；账期前后平移；归属行文案「账单期 10/15–11/14 · 计入 11 月」 |

> 原计划拆成 `DebtPlanMath` + `AnnualRateSolver` 两个文件，实际合并成一个 `InstallmentMath`：
> 展开和反算吃的是同一组输入（期数、每期金额、首末期金额、本金），拆开只会让两个文件互相 import，
> 而 AGENTS 7.3 要的是「钱相关逻辑不夹在视图里」，不是「一个概念必须一个文件」。

## 硬规则

- 纯函数：不依赖 SwiftData、不依赖 UI、不发网络请求，可单测。
- 每个函数的注释写清：输入、输出、边界（0 期、首末期不同、退款超过剩余、除不尽）。
- 除法必须显式舍入规则；默认余数落**首期**（M3-4 用两张白条账单校准：15.34 ÷ 3 = 5.12 / 5.11 / 5.11）。
- 校准基准：e招贷 9,000 元 24 期反算年化 ≈16.4%，与招行公布 16.43% 相差 < 0.5%。
- **年化只有整笔口径**（M3-3）：`PV = 每期 × 总期数 − 含利息`。曾经有过「剩余本金 + 剩余期数」那条路径，但账单上没有「剩余本金」这个数，用户填进来的必然是含息的「剩余应还」，一填就撞成「零息 0.0%」（见 `Installment.remainingPrincipal` 注释）。**字段不可得，就别让它参与计算。**
- 用例取自 PRD 附录真实账单（招行 8857 / 白条序列 / e招贷 / 中移金科），**不得自己编数字**。
