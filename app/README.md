# app/ · DooDoo iOS 工程

> 状态：**M0 已跑通**（2026-11-08）。CI 在 Xcode 26.6 / iOS 26.5 SDK 上构建通过、3 条单测绿、未签名 `.app` 已产出。
> 本机是 Windows + PowerShell，没有 Xcode——**以后每次改代码仍要靠 CI 或 Mac 验证**，本地只能说"写完了"。

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
| CI | `.github/workflows/ios.yml`：出未签名 `.app` + 跑单测 |

## 二、目录（实际，不是设想）

```
app/
├── project.yml                    # XcodeGen 定义
├── DooDoo/
│   ├── App/                       # 入口、根视图、tab 定义
│   │   ├── DooDooApp.swift        # @main，建 ModelContainer
│   │   ├── RootView.swift         # 页头 + 三段 tab + 内容
│   │   └── RootTab.swift          # flow / assets / settings
│   ├── Models/                    # @Model；M0 只有 AppSettings
│   ├── Services/                  # M1 起：LedgerService（唯一余额写入口）
│   ├── Math/                      # M2 起：纯函数 + 单测
│   ├── ViewModels/                # M1 起：状态与校验
│   ├── Views/                     # FlowView / AssetsView / SettingsView
│   └── Resources/Assets.xcassets  # AppIcon（空）/ AccentColor（墨色）
├── DooDooTests/SmokeTests.swift   # 3 条冒烟：tab 定义、默认值、内存容器读写
└── README.md
```

每个模块目录都有自己的 `README.md`（职责 / 入口文件 / 数据流向）。

## 三、怎么跑

Mac 上：

```bash
brew install xcodegen
cd app
xcodegen generate
open DooDoo.xcodeproj      # 选一台 iPhone 模拟器，⌘R
```

纯命令行（和 CI 一致）：

```bash
cd app
xcodegen generate
xcodebuild -project DooDoo.xcodeproj -scheme DooDoo \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

## 四、M0 门禁与验证方法

| 门禁 | 怎么验 | 现状 |
|---|---|---|
| 单测能过 | 3 条冒烟测试（tab 定义 / 默认值 / 内存容器读写） | ✅ CI 通过 |
| CI 能出未签名产物 | `DooDoo-unsigned-app`，5.8 MB，sha256 `a082958c…` | ✅ run `42423907280` |
| 模拟器能启动 | 单测已把 app 装进模拟器跑通；但**没人看过界面** | 🟡 CI 侧通过，观感待人工 |
| 数据能落盘 | 设置页拨「逾期横幅」→ 杀进程 → 重开，开关保持 | ⬜ 待人工 |

**前两条是硬门禁，已过；后两条是人工确认，进 M1 前顺手做一遍。**

## 五、不要做的事

- 不在 M3 之前做视觉打磨（门禁：M3 完成前不谈视觉）。
- 不把原型 HTML 的 CSS 数值直接硬编码进 SwiftUI，先对照 `docs/design/spec/`。
- 不引入 SwiftUI 之外的 UI 框架、图表库、格式化库。
- 不在这里写业务逻辑：记账走 Service，算钱走 Math。
- 不提前写 M1/M2 的模型——schema 一次只加本里程碑要用的。
