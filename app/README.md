# app/ · DooDoo iOS 工程

> 状态：**M2b 收口中**（2026-11-10 核准）。M0 工程搭建、M1 记一笔+流水、M2a 账户+资产页均已闭合；M2b 还款/转账的 11-09 真机缺陷已修完，CI run `42648536927` 全绿（`DooDooTests/` 55 条单测）。
> **M2a / M2b 都还差一步：真机复判。没在 iPhone 上复看前不得算完成**。M3 分期尚未动工。
> 进度一律以仓库根的 `PROGRESS.md` 为准，本文件只记工程事实，不记进度。
> 开发机是 **Windows + PowerShell，没有 Mac、没有 Xcode，只有一台 iPhone**——每次改代码只能靠 CI 编译、靠 iPhone 真机验收，本地只能说"写完了"。

## 一、工程事实

| 项 | 值 |
|---|---|
| 工程名 | `DooDoo` |
| 工程生成 | **XcodeGen**（`project.yml` 入库，`DooDoo.xcodeproj` 不入库） |
| Bundle id | `com.doodoo.app`。**bundle id 不需要域名**，它只是设备内唯一标识；只有上架或有开发者证书要匹配时才需要注意 |
| 部署目标 | iOS **26.0**（本机没有 iOS 27 SDK，先用 26；iPhone 上仍能正常跑） |
| 设备 | 仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`），仅竖屏 |
| 依赖 | **零第三方依赖** |
| 数据 | SwiftData，纯本地，无 CloudKit、无账号 |
| 网络 | 零请求、零分析 SDK |
| 并发 | `SWIFT_VERSION = 6.0`，`SWIFT_STRICT_CONCURRENCY = complete` |
| CI | `.github/workflows/ios.yml` 两个 job，**串行**：`build`（XcodeGen → 模拟器 Debug 构建 → 55 条单测）→ `ipa`（真机 Release 构建 → 压 `Payload/` → 出未签名 IPA）。`build` 在 push 与 PR 都跑；`ipa` 只在 `push`（仅 main）或手动触发时跑。仓库 public，分钟不计费 |

## 二、目录（实际，不是设想）

```
app/
├── project.yml                    # XcodeGen 定义
├── DooDoo/
│   ├── App/                       # 入口、根视图、tab 定义
│   │   ├── DooDooApp.swift        # @main，建 ModelContainer
│   │   ├── RootView.swift         # 页头 + 三段 tab + 内容
│   │   └── RootTab.swift          # flow / assets / settings
│   ├── Models/                    # @Model：AppSettings / Account / Category / Transaction
│   │                              #   非模型附属：BrandPalette（卡面配色）、SpendGrade（评分四档）
│   ├── Services/                  # LedgerService（唯一余额写入口）/ SeedService（演示数据）
│   ├── Math/                      # 6 个纯函数文件：Day / Money / NetWorth / AccountDelta
│   │                              #   / NetWorthSeries / Transfer
│   ├── ViewModels/                # EntryViewModel（记一笔草稿与校验）
│   ├── Views/                     # FlowView / AssetsView / SettingsView（设置页仍是最简版）
│   │   ├── Entry/                 # 记一笔四类型面板 + 分类选择
│   │   └── Components/            # 日卡 / 卡面 / 层叠 / 净值卡 / 账户编辑器
│   ├── Resources/Assets.xcassets  # AppIcon / AccentColor
│   └── Resources/Emoji            # 3D 图标（bundle 根 PNG，必须用 Image(uiImage:) 加载）
├── DooDooTests/                   # 6 个文件 55 条 @Test（1002 行）
└── README.md
```

每个模块目录都有自己的 `README.md`（职责 / 入口文件 / 数据流向）。

## 三、怎么跑（本工作区**没有 Mac**）

**事实：开发机是 Windows，手上只有一台 iPhone。** Xcode、`xcodebuild`、`xcodegen`、iOS 模拟器在本机全部跑不了，**唯一**的编译路径是 GitHub Actions。别在本机找 Xcode，找不到是正常的。

| 想做的事 | 唯一做法 | 不存在 |
|---|---|---|
| 编译 / 跑单测 | push 到 `main`，看 Actions 的 `build` job | 本机编译 |
| 在 iPhone 上打开 | 每次 push 到 `main` 都出包 → 下载未签名 IPA → Sideloadly 自签 | 本机连真机调试 |
| 看界面长什么样 | 只有上面这一条 | iOS 模拟器（要 macOS） |

本地能做的只有三件：改 Swift、改 `project.yml`、读 CI 日志。写完就 push，让 CI 给结论——**不要写"本地编译通过"，那是假话**。

### 拿到能装进 iPhone 的 IPA（四步）

1. **push 到 `main`**（或在 Actions 页手动 **Run workflow**）→ 等两个 job 变绿：`build`（编译 + 单测）→ `ipa`（真机 Release 构建 + 打包）。仓库是 public，Actions 分钟不计费，**每次 push 都直接出包**。
2. 在该次 run 页面底部下载 artifact **`DooDoo-unsigned-ipa`**（7 天后过期），内含 `DooDoo-unsigned.ipa` 与 `.sha256`。
3. Windows 上用 **Sideloadly** 拿自己的 Apple ID 重签。Sideloadly 需要 iTunes 提供 Apple 驱动，**装官网版 iTunes，不要装 Microsoft Store 版**（商店版不带驱动）。
4. 装到 iPhone：首次要先在手机上打开开发者模式（见下表）并信任证书。

关键限制（**不是 bug，是 iOS 的规则**）：

| 限制 | 说明 |
|---|---|
| 不能直接装 | 产物**未签名**，iOS 拒绝安装未签名 App，必须由自签工具补签 |
| 开发者模式必须开 | iPhone「设置 → 隐私与安全性 → 开发者模式」打开并重启，否则自签 App 点开即闪退 |
| 7 天过期 | 免费 Apple ID 签的证书 7 天失效；同一账号 7 天内最多 3 个自签 App |
| 设备要信任 | 首次安装后到「设置 → 通用 → VPN与设备管理」信任对应开发者证书 |
| 不要用 archive 导出 | `xcodebuild archive` + `-exportArchive` 强制要求证书与描述文件，无证书必失败；CI 因此走 `build` + 手工压 `Payload/` |

> 想免掉手动续签：Windows 上装 **AltServer**，手机同一 Wi-Fi 下 AltStore 会自动续签；或上付费开发者账号（一年有效）。M1 之后每次改代码都要重装一次，续签成本远低于重新构建。

## 四、M0 门禁（历史记录，六条已闭合）

> 本节只记 M0 当时怎么验、验到哪。**当前状态一律看 `PROGRESS.md`**，别拿这张表判断进度。

| 门禁 | 怎么验 | 结果 |
|---|---|---|
| 单测能过 | 当时 3 条冒烟（tab 定义 / 默认值 / 内存容器读写） | ✅ 现已扩到 55 条 |
| CI 能出未签名产物 | `DooDoo-unsigned-app`，5.8 MB，sha256 `a082958c…` | ✅ run `42423907280` |
| CI 能出未签名 IPA | 手动 `Run workflow` → `ipa` job → artifact `DooDoo-unsigned-ipa` | ✅ 已多次出包，11-09 装上真机 |
| iPhone 能装上并打开 | Sideloadly 自签 → 首页出得来 | ✅ 11-09 已装 |
| 界面观感对 | 在 iPhone 上逐页看 | 🔁 **每轮改完都靠这个**，不过就改，无终态 |
| 数据能落盘 | 杀进程 → 重开，数据保持 | ✅ M1 已验流水持久化 |

**后三条永远只能靠 iPhone 人工确认——本工作区没有 macOS，模拟器这条路不存在。**
**「装得上」不是一次性门禁，是每次发版都要过一遍的门禁**，M2a 的「老库升级不崩」就挂在这一条上。

## 五、不要做的事

- 不在 M3 之前做视觉打磨（门禁：M3 完成前不谈视觉）。
- 不把原型 HTML 的 CSS 数值直接硬编码进 SwiftUI，先对照 `docs/design/spec/`。
- 不引入 SwiftUI 之外的 UI 框架、图表库、格式化库。
- 不在这里写业务逻辑：记账走 Service，算钱走 Math。
- 不提前写未来里程碑的模型——schema 一次只加本里程碑要用的。M3 的 `DebtPlan` / `Installment` / `BillStatement` 属 M3，M2 阶段不预埋：旧库迁移还没在真机验过，此时加新表会让崩溃无法归因。
