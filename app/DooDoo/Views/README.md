# Views · SwiftUI 视图

> 状态：**M3-10**。首页、资产页、记一笔（含内联分期 + 账期归属）、存量分期录入、卡片详情都可用。
> 首页：`FlowView` + `DeckView` / `DayCardView` / `TxRowView`；
> 资产页：`AssetsView` + `NetWorthCard` / `AccountGroupView` / `AccountDeck` / `CardFace` / `GroupOverlay` / `AccountEditor`；
> 记一笔：`Entry/EntryView` + `AccountCardStrip` / `CategoryPicker`；
> 详情：`Detail/AccountDetailSheet` / `BillEntrySheet` / `PeriodEditorSheet` / `DebtTrendChart`。设置页仍是最简版本。

| 视图 | 里程碑 | 对应规格 |
|---|---|---|
| `FlowView` | M1 | `docs/design/spec/首页规格冻结-v1.0.md` |
| `AssetsView` | M2 | `docs/design/spec/资产页规格冻结-v1.0.md`（正文 v1.1） |
| `Entry/EntryView` | M1b / M2b / M3-10 | `docs/design/spec/记一笔规格冻结-v1.0.md`（四类型、二级分类、内联分期、账期归属） |
| `CardFace` | M2b → 11-09 换资源 | 规格第三节四档尺寸；**底图走 `Assets.xcassets/Card` 资源 + `Texture` 纹理，文字层实时画**（原「六层代码画」已废弃） |
| `SettingsView` | M0 起可用；M3-2 加分期入口 | PRD 9.15 + M5 验收清单 |
| `Components/TxRowView` | M1；**11-11 改成「转账 + 手续费」一行** | 金额不带符号、手续费小标签、转账借 `CurrencyExchange` 图标 |

## 约束

- 视图只做展示与回调：不写库、不算钱、不做全表统计（`body` 里禁止全表遍历）。
- 列表用 `LazyVStack` + 按天分组，性能红线见 `AGENTS.md` 7.5。
- 视觉数值一律来自 `docs/design/spec/`，不要把原型 HTML 的 CSS 直接抄成 SwiftUI。
