# Views · SwiftUI 视图

> 状态：**M2b**。首页、资产页、记一笔都可用。
> 首页：`FlowView` + `DeckView` / `DayCardView` / `TxRowView`；
> 资产页：`AssetsView` + `NetWorthCard` / `AccountGroupView` / `AccountDeck` / `CardFace` / `GroupOverlay` / `AccountEditor`；
> 记一笔：`Entry/EntryView` + `AccountCardStrip` / `CategoryPicker`。设置页仍是最简版本。

| 视图 | 里程碑 | 对应规格 |
|---|---|---|
| `FlowView` | M1 | `docs/design/spec/首页规格冻结-v1.0.md` |
| `AssetsView` | M2 | `docs/design/spec/资产页规格冻结-v1.0.md`（正文 v1.1） |
| `Entry/EntryView` | M1b / M2b | `docs/design/spec/记一笔规格冻结-v1.0.md`（四类型、卡面六层、二级分类） |
| `CardFace` | M2b | 同上第三节（六层，158×100 / 144×96 / 132×82 / 112×72 四档） |
| `SettingsView` | M0 起可用 | PRD 9.15 + M5 验收清单 |

## 约束

- 视图只做展示与回调：不写库、不算钱、不做全表统计（`body` 里禁止全表遍历）。
- 列表用 `LazyVStack` + 按天分组，性能红线见 `AGENTS.md` 7.5。
- 视觉数值一律来自 `docs/design/spec/`，不要把原型 HTML 的 CSS 直接抄成 SwiftUI。
