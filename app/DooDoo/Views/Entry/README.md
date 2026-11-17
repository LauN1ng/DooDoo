# Views/Entry · 记一笔

> 依据：`docs/design/spec/记一笔规格冻结-v2.7.md`（1.x 只改第九节未锁定项；v1.0 / v2.0 / v2.1 / v2.2 / v2.3 / v2.4 / v2.5 / v2.6 已废止）。
> 原型：`design/current/entry-types.html`（快照 `entry-types-v1.0.html`）。

## 职责

四类型录入面板：支出 / 收入 / 还款 / 转账。**只做展示与回调**，状态与校验在
`ViewModels/EntryViewModel.swift`，写库在 `Services/LedgerService.swift`。

## 文件

| 文件 | 职责 |
|---|---|
| `EntryView.swift` | 面板骨架：标题 → 类型分段 → 字段 → 底部主按钮；按 `vm.type` 分派四类型 |
| `AccountCardStrip.swift` | 账户横滑卡组。大卡 158×100（账户、被还卡、转账双卡）、小卡 112×72（还款扣款卡） |
| `CategoryPicker.swift` | 一级 52×52 色块横滑 + 二级浮层（5 列 × 2 行、圆底 42、覆盖不推挤） |
| `InstallmentEntryView.swift` | **存量分期快速连录**（M3-2 / M3-3 改表单）：主卡三行对应账单三次抄写——剩余应还、剩余期数、每期金额（只读，下面小字写清算式）。顶部「还差 N 笔」、存完不关面板只清这笔独有字段、账户与还款日留到下一笔。入口在设置页 |

## 数据流向

```
日卡记账行（DayCardView.addRow）
  → FlowView 打开 sheet，带上这一天的日期
  → EntryView.task 里 vm.load(context)
  → 用户输入 → vm 校验（validationMessage）
  → vm.save(in:) → LedgerService.insert(...)
  → 增量写 Account.currentBalance（只改受影响账户）
  → dismiss，FlowView 的 @Query 自动刷新日卡
```

## 四类型字段差异

| | 支出 | 收入 | 还款 | 转账 |
|---|---|---|---|---|
| 卡池 | 全部 | 仅储蓄/现金 | 还谁=信用/借款，扣款=储蓄/现金 | 双卡（Menu 选） |
| 分类 | 一级 8 + 二级 | 一级 2 + 二级 | 无 | 无 |
| 评分 | 有 | 无 | 无 | 无 |
| 金额 | 1 个 | 1 个 | 1 个（默认带出欠款） | 2 个（转出 / 到账） |
| 预览 | 单行 | 单行 | 双行（欠款 + 扣款卡） | 双行（两账户） |

## 存量分期为什么单独一个面板

它**不是一笔账**——分期计划不动余额，只记「还剩几期、每期多少、什么时候还」。
记一笔是「一天多次」，存量录入是「一次性几十次」，两者最优交互不同：
前者要快，后者要连贯（保留账户、进度可见、可中断）。详见
`Services/InstallmentService.swift` 与 `Math/InstallmentIntake.swift` 的注释。

## M3 已落地的位置（本节留作追溯，勿按它判断待办）

- **账单期关联**（M3-10 已落）：`Math/BillCycleMath` 按账户真实账单周期算账期名，归属行胶囊可切本期/下一期，`Transaction.billPeriod` 落库；`BillStatement` 由 M3-8 落地，还款流水也补了账期。
- **分期开关**（M3-10 已落）：支出 + 信用/借款账户时，金额下方出现「分期」块（期数 chip + 每期 + 首期日），提交写一条全额 `expense` + 一张 `createdFromEntry` 计划。
- **仍待办**：这两块的**视觉**密度偏高（四行堆在白卡里、账期胶囊文案过长），属 M4 视觉批，与分期录入面板一起收。

## 不要做的事

- 不要在视图里直接给 `currentBalance` 赋值（AGENTS 7.2）。
- 不要用 `Double` 处理金额（AGENTS 7.1）。
- 不要把四种类型写成四份视图：差异集中在 `EntryViewModel` 的派生属性里。
