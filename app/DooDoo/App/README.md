# App · 应用入口

> 状态：M0 已建（空壳）。只负责启动、注入数据容器、切 tab。

| 项 | 内容 |
|---|---|
| 入口文件 | `DooDooApp.swift`（`@main`） |
| 根视图 | `RootView.swift` |
| tab 定义 | `RootTab.swift`（`flow / assets / settings`，**没有 repayment**） |
| 数据流向 | `DooDooApp` 建 `ModelContainer` → 通过 `.modelContainer` 注入 → 视图用 `@Query` / `@Environment(\.modelContext)` 读写 |

## 约束

- 这里**不放业务逻辑**。记账走 `Services/LedgerService`，算钱走 `Math/`。
- 顶部 tab 的材质与尺寸（112×34、三段 36×30、圆角 17、`#EBE7E0`）属视觉，M4 才落地；M0 只保证结构与点击。
- 加新模型时要同步更新 `ModelContainer(for:)` 的 schema 列表，否则新表不会建。
