# ViewModels · 状态与输入校验

> 状态：M0 空目录。M1 起随「记一笔」落地。

## 职责边界

- 管状态：草稿金额、选中分类、选中账户、评分档位、键盘输入缓冲。
- 管校验：金额 > 0、账户必选、分期期数 ≥ 1。
- **不碰 SwiftData 写入**——保存交给 `Services/LedgerService`。
- 不做金额运算——算术交给 `Math/` 的纯函数。

## 数据流向

```
View（输入/展示） → ViewModel（状态 + 校验） → LedgerService（写库 + 重算余额） → Models
```
