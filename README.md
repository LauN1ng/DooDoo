# DooDoo 记账 · 工作区

> 一个只给自己用的 iOS 记账 App：随手记一笔，随时知道我有多少钱，清楚看到每个月要还多少。
> 当前状态：**代码已到 M2b**（2026-11-10）。M0 工程搭建、M1 记一笔+流水、M2a 账户+资产页均已闭合；M2b 还款/转账的代码已过 CI，**待真机复判**；M3 分期未动工。进度只看 `PROGRESS.md`。

---

## 一、先读这三个文件

| 顺序 | 文件 | 作用 |
|---|---|---|
| 1 | `README.md`（本文件） | 这里是哪、每个目录是什么、从哪进入 |
| 2 | `AGENTS.md` | **规则唯一事实源**：什么说了算、能改什么、怎么写代码、怎么算做完 |
| 3 | `PROGRESS.md` | **进度唯一事实源**：做到哪了、什么没定、下一步做什么 |

任何 AI 编码工具（CodeBuddy / Claude Code / Cursor / Codex / Copilot）读完这三个文件即可接手，不需要读历史对话。

---

## 二、目录地图

| 目录 / 文件 | 是什么 | 从哪进 | 能不能改 |
|---|---|---|---|
| `docs/product/` | 产品事实：`PRD-v2.3.md`（已冻结） | `PRD-v2.3.md` 第四节起是数据模型与关键规则 | 决策已闭合，改需确认 |
| `docs/design/spec/` | **唯一实现依据**：资产页 / 首页 / 记一笔 三份规格，各 v1.0 | 同上 | 1.x 只改各文件标注「未锁定」的章节 |
| `docs/design/pending/` | 未定案：分类图标映射、首页底部 tab 材质等 8 份 | — | 可改，但不得据此写代码 |
| `docs/design/history/` | 推演与否决记录（卡片堆叠 8 轮、结构选题、资产页旧决定） | 改设计前读 | 只追加 |
| `docs/art/` | 卡面美术资源清单、交付记录 | `assets/index.html` 是验收页 | 可改 |
| `docs/reference/` | 原始信用卡账单文本、PDF/CSV 提取脚本、样本 | `bills/` 是单测数据源 | 只读证据 |
| `docs/archive/` | 已废止输入：开工前决策清单 xlsx + 生成脚本 | — | 只读 |
| `design/current/` | **当前可交互原型**（40 个 html + 截图） | `design/current/index.html` 是总入口 | 可迭代；`account-stack-v1.1.html`、`home-v1.0.html`、`entry-types-v1.0.html` 只读 |
| `design/archive/` | 11-03~11-05 早期原型、demo、ledger 原型、上一项目原型 | — | 只读 |
| `research/` | 竞品与灵感：mobbin 截图、小红书 UI、参考图、调研结论 | `research/README.md` | 只追加 |
| `assets/` | 美术资源：Fluent 3D Emoji（精选 492 + 全量 1545）、16 品牌色、3 纹理 | `assets/index.html` | 可改，改动写交付记录 |
| `tools/screenshot/` | 原型截图脚本（tabbit CLI 驱动） | `tools/README.md` | 可改 |
| `app/` | **iOS 工程**（M2b，55 条单测，编译只能靠 CI） | `app/README.md` | 代码区；`project.yml` 入库，`.xcodeproj` 不入库 |
| `.codebuddy/` `.workbuddy/` `.agents/` `skills-lock.json` | 工具私有（技能库、日志、缓存） | — | **不要删**，不进协作流程 |

---

## 三、三条常用路径

**我想看设计长什么样**
双击 `design/current/index.html`（浏览器直接开，无需服务器）。首页定稿是 `home-final.html`，资产页是 `account-stack.html`，记一笔 A 版是 `entry-a-optimize.html`。

**我要开始写代码**
读 `docs/product/PRD-v2.3.md` → 按 `PROGRESS.md` 的「下一步」→ 遵守 `AGENTS.md` 第七、八节。M3 完成前不谈视觉。

**我换了 AI 工具**
让它读 `README.md` + `AGENTS.md` + `PROGRESS.md`，然后按 `AGENTS.md` 第十一节做交接自检（4 个问题答得出才算接手成功）。

---

## 四、关于工具私有目录

`.workbuddy/memory/` 里有 2026-11-03 ~ 11-07 的逐日决策日志，是项目最贵的过程资产，但**格式与路径属于旧工具**：里面的 `doodoo-prototype/xxx.html` 现在应为 `design/current/xxx.html`。
结论已蒸馏进 `PROGRESS.md` 的变更时间线；日志仅作原文存档，**不要把它当作规则依据**。

---

## 五、当前环境事实

- 系统：Windows + PowerShell 5.1（无 bash / grep / sed）。
- **没有 macOS，没有 Xcode，手上只有一台 iPhone**。所以 iOS 代码只能由 GitHub Actions 编译，界面只能装到 iPhone 上看（CI 出未签名 IPA → Windows 用 Sideloadly 自签）。本机不存在 `xcodebuild` 与模拟器。
- Git 已接通（装在 `D:\Work\Tool\Git`，白名单只提交 `app/` 与 `.github/`）；原型与文档留在工作区，不做版本控制。
- 原型与资产全部本地文件，双击即开；不依赖任何服务器或构建步骤。
