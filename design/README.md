# design/ 原型区

> 所有原型都是**单文件 HTML**，双击即开，不依赖服务器与构建。
> 这里只做设计验证；**实现依据永远是 `docs/design/spec/`，不是原型代码**。

---

## 一、当前原型 `current/`

### 入口

| 文件 | 是什么 | 状态 |
|---|---|---|
| `index.html` | **总入口**：流水卡片组 / 资产（Copilot 式）/ 记一笔三类型 | 可交互 |
| `home-v3.html` | **首页 v3**：B 记账行（已定入口）+ 卡堆按天数 1/2/4/7 + 首次使用空账本 + 顶部 T1 tab | **最新** |
| `home-v2.html` | 首页 v2：T1 tab + 记一笔第一轮四版（已否） | 被 v3 取代 |
| `tab-top.html` | **顶部 tab 三版材质**：T1 灰槽白块 / T2 墨槽亮块 / T3 裸图标墨点 + 尺寸标注 | **T1 已定案** |
| `slot-and-stack.html` | **小图对比**：7 张时的 4 种叠法 + 记账行槽 4 版（390 实际尺寸取样） | 待选定 |
| entry-bcd.html | **记一笔第二轮**：B 记账行 / C 页脚墨线栏 / D 卡沿纸签 + 共用的半屏记账面板 | 待定案（推荐 B） |
| `fab-options.html` | 记一笔第一轮四版（悬浮方案） | 已否决：与纸的风格不符 |
| `home-final.html` | 首页定稿（旧）：四层卡堆 + 底部墨键导航 + 便签 + 渐隐 | 已被 v2 取代 |
| `account-stack.html` | **资产页 v1.3 工作副本**：卡牌堆 + 全屏朦胧浮层 + 账户详情页 v0.3 + **顶部图标分段 tab** | 可迭代 |
| `entry-a-optimize.html` | **记一笔 A 版（已选定）** 降密度优化前后对照 | 已选定 |
| `account-stack-v1.0.html` | **资产页 v1.0 冻结快照** | 🔒 只读，SHA256 前 16 位 `a970c4f8cd77af92` |
| `home-v1.0.html` | **首页 v1.0 冻结快照**（顶部 tab + 记账行 B2 + 卡堆规则） | 🔒 只读，SHA256 前 16 位 `4526633e70570c11` |

### 方案对比页（含结论，改设计前先看）

| 文件 | 议题 | 结论 |
|---|---|---|
| `nav-mat.html` / `nav-mat-compare.html` | 首页底部 tab 材质五版 A~E | **已废止**：tab 移到顶部，见 `tab-top.html` |
| `entry-options.html` / `entry-compare.html` | 记一笔四版 A/B/C/D | **A 版选定**（纸卡续写） |
| `day-overflow.html` / `day-overflow-compare.html` | 单日多笔三版 | **B 渐隐采纳，不加计数行** |
| `deck-fix.html` / `deck-fix-compare.html` | 卡堆修正四版 | S2 被否，**保持现状**（要纸叠质感，不要求数得清） |
| `nav-final.html` / `nav-final-compare.html` | tab 位置 A/B/C | 已被材质五版取代 |
| `nav-deck.html` / `nav-deck-compare.html` | tab 与卡堆层级 D0/D1/D2 | **D2 只压前卡**（遮内容不遮结构） |
| `nav-layer.html` / `nav-layer2.html` | 层级手法校准 | 墨色实心是唯一一眼可读；白浮白必糊 |
| `account-deck.html` | 账户卡形态对比（平铺 / 卡堆 / 满宽叠层） | 已收敛到卡牌堆 |
| `stack-variants.html` | 首页卡堆四个变体 | `v-scatter` 即现状 |
| `home-bottom.html` | 底部导航五方案（已推翻） | 仅存档 |

### 截图

`*.png` 与原型同名；`_` 前缀为临时对比图（`_e-*` 记一笔四版、`_ov-*` 单日多笔）。
`shots/` 为空目录，预留给后续批量截图。

---

## 二、归档 `archive/`

| 路径 | 内容 | 为什么归档 |
|---|---|---|
| `site-2026-11-03/` | 11-03~11-05 的 16 个原型（prototype v1~v4、directions、structure-options、assembler、prd-wireframes、home-options 等） | 已被 `current/` 取代 |
| `demo/index.html` | 最早的演示页 | 已被取代 |
| `ledger-prototype/index.html` | 单页账本雏形 | 已被取代 |
| `other-projects/iown-home-prototype/index.html` | **上一个项目（iOwn）**的首页原型 | 与本项目无关 |

归档区只读：不再修改，只在需要追溯「当初为什么不这么做」时查看。

---

## 三、纪律

1. 改原型前先看对应的对比页与 `docs/design/history/`，确认不是重走已否决的路。
2. 冻结快照永不覆盖，要改出新版本 `主题-vX.Y.html`。
3. 原型改完要用 `tools/screenshot/` 的脚本截图核对几何（`getBoundingClientRect`），不能只靠肉眼。
4. 原型里的 CSS 数值是设计证据，但**实现时以 spec 文档为准**——两者不一致时，先改文档再改代码。
