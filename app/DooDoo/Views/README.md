# Views · SwiftUI 视图

> 状态：**M2a 首页与资产页都可用**。
> 首页：`FlowView` + `DeckView` / `DayCardView` / `TxRowView`；
> 资产页：`AssetsView` + `NetWorthCard` / `AccountGroupView` / `AccountDeck` / `CardFace` / `GroupOverlay` / `AccountEditor`。设置页仍是最简版本。

| 视图 | 里程碑 | 对应规格 |
|---|---|---|
| `FlowView` | M1 | `docs/design/spec/首页规格冻结-v1.0.md` |
| `AssetsView` | M2 | `docs/design/spec/资产页规格冻结-v1.0.md`（正文 v1.1） |
| `SettingsView` | M0 起可用 | PRD 9.15 + M5 验收清单 |
| 记一笔面板 | M1 | **未冻结**（A 版已选定），不得凭 `pending/` 直接写生产代码 |

## 约束

- 视图只做展示与回调：不写库、不算钱、不做全表统计（`body` 里禁止全表遍历）。
- 列表用 `LazyVStack` + 按天分组，性能红线见 `AGENTS.md` 7.5。
- 视觉数值一律来自 `docs/design/spec/`，不要把原型 HTML 的 CSS 直接抄成 SwiftUI。
