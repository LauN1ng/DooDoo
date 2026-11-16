# Copilot 指令（指针）

本项目规则的唯一事实源是根目录 **`AGENTS.md`**，本文件不复制规则。

请依次阅读：

1. `README.md` —— 工作区地图
2. `AGENTS.md` —— 规则正文
3. `PROGRESS.md` —— 进度与下一步

写代码前补读 `docs/product/PRD-v2.3.md`，以及 `docs/design/spec/` 下四份冻结规格（资产页 / 首页 / 记一笔 / 账户详情页，均 v1.0）。

关键约束（详见 `AGENTS.md` 第三、六、七、九节）：冻结物只读；`docs/design/pending/` 与 `history/` 不作为实现依据；金额用 `Decimal`；余额只由 `LedgerService` 写；零第三方依赖；交付后同步更新 `PROGRESS.md`。
