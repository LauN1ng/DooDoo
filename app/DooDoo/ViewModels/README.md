# ViewModels · 状态与输入校验

> 状态：**M3-2**——`EntryViewModel.swift`（记一笔四类型）+ `InstallmentEntryViewModel.swift`（存量分期快速连录）。
> **不是空目录。** 本文件此前写「M0 空目录」，那是 2026-11-08 的快照，已过期（2026-11-10 核准）。

## 入口

| 文件 | 职责 |
|---|---|
| `EntryViewModel.swift` | `@Observable final class`。记一笔的全部草稿状态与校验，四类型共用一份：`.expense` / `.income` / `.repayment` / `.transfer` |
| `InstallmentEntryViewModel.swift` | 存量分期连录的状态与校验。存完**只清这笔独有的字段**，账户与还款日留到下一笔；「还差 N 笔」数库不另存计数器（目标笔数在 `UserDefaults`） |

它实际管这些：

| 分组 | 成员 | 说明 |
|---|---|---|
| 金额缓冲 | `amountText` / `receivedText` / `feeText` | 存字符串不存 Decimal——键盘输入中途态（`12.`）不能丢 |
| 三金额联动 | `syncReceivedFromFee()` / `syncFeeFromReceived()` | 填到账反算出账、填手续费反算到账，对应 PRD 9.8 的两路输入 |
| 类型切换 | `setType(_:)` + `resetForType()` | 换类型要清掉不适用的字段，不留脏状态 |
| 分类 | `topKey` / `subKey` / `showingSub` | 两级：一级必选、二级可选；统计只按一级 |
| 账户 | `payer` / `target` + `payerCandidates` / `targetCandidates` | 候选集随类型变（还款只列信用/借款，转账排除自身） |
| 余额预览 | `payerBalanceAfter` / `targetBalanceAfter` | 保存前先给结果，不用回列表看 |
| 评分 | `grade` + `rememberGrade()` | 保存后把档位写回分类，下次自动带出（PRD 9.13） |
| 校验 | `validationMessage` / `canSave` | 单一出口，视图只读这两个 |

## 职责边界

- 管状态与校验：金额 > 0、账户必选、还款/转账必须有目标账户。
- **不碰 SwiftData 写入**——`save(in:)` 自己只做四类型分支，每一支都调 `Services/LedgerService.insert(...)`；余额重算归 Service（AGENTS 7.2）。
- 不做金额运算——手续费、分账、舍入全在 `Math/` 的纯函数里。本文件只保留「文本 → `Decimal`」的输入解析（`Self.decimal(_:)`），那是格式解析，不是算术。
- 不直接改 `Account.currentBalance`。视图里的余额预览是算出来的，不是写进去的。

## 数据流向

```
View（输入 / 展示）
  → EntryViewModel（状态缓冲 + 校验 + 四类型分支）
    → LedgerService.insert(...)（写库 + 重算受影响账户余额）
      → Models（Transaction / Account）
```

## 新增 ViewModel 的前提

只有出现**新的状态机**才加文件。M3 的分期展开、账单期、逾期横幅若需要独立输入态，才在本目录新增；纯展示用的计算做成 `Math/` 里的纯函数，不要为「对称」硬塞一个 ViewModel。
