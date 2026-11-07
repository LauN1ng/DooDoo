# app/ · DooDoo iOS 工程

> 状态：**M0 骨架已建**（2026-11-08）。**尚未在本机编译验证**——当前机器是 Windows + PowerShell，没有 Xcode。
> 第一个可信的编译结果是 CI 或你在 Mac 上跑出来的；在那之前，这里的代码只能算"写完了"，不算"跑通了"。

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
| 模拟器能启动 | ⌘R，看到页头 `DooDoo` + 三段 tab，三个页面都切得动 | ⬜ 未验证 |
| CI 能出未签名产物 | push 后 Actions 绿，`DooDoo-unsigned-app` artifact 可下载 | ⬜ 未验证 |
| 数据能落盘 | 设置页拨「逾期横幅」→ 杀进程 → 重开，开关保持 | ⬜ 未验证 |
| 单测能过 | 3 条冒烟测试全绿 | ⬜ 未验证 |

**这四条只要有一条没过，就不能进 M1。** 本机 Windows 无法自证，必须到 Mac 或 CI 上跑。

## 五、不要做的事

- 不在 M3 之前做视觉打磨（门禁：M3 完成前不谈视觉）。
- 不把原型 HTML 的 CSS 数值直接硬编码进 SwiftUI，先对照 `docs/design/spec/`。
- 不引入 SwiftUI 之外的 UI 框架、图表库、格式化库。
- 不在这里写业务逻辑：记账走 Service，算钱走 Math。
- 不提前写 M1/M2 的模型——schema 一次只加本里程碑要用的。
