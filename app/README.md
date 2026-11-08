# app/ · DooDoo iOS 工程

> 状态：**M0 已跑通**（2026-11-08）。CI 在 Xcode 26.6 / iOS 26.5 SDK 上构建通过、3 条单测绿、未签名 `.app` 已产出；手动触发可另出**未签名真机 `.ipa`**，用于端侧安装查看。
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
| CI | `.github/workflows/ios.yml`：push/PR 跑构建 + 单测并出未签名模拟器 `.app`；手动 `Run workflow` 额外出未签名真机 `.ipa`（`ipa` job，需 `build` 绿） |

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

## 三、怎么跑（本工作区**没有 Mac**）

**事实：开发机是 Windows，手上只有一台 iPhone。** Xcode、`xcodebuild`、`xcodegen`、iOS 模拟器在本机全部跑不了，**唯一**的编译路径是 GitHub Actions。别在本机找 Xcode，找不到是正常的。

| 想做的事 | 唯一做法 | 不存在 |
|---|---|---|
| 编译 / 跑单测 | push 到 `main`，看 Actions 的 `build` job | 本机编译 |
| 在 iPhone 上打开 | 手动 `Run workflow` → 下载未签名 IPA → Sideloadly 自签 | 本机连真机调试 |
| 看界面长什么样 | 只有上面这一条 | iOS 模拟器（要 macOS） |

本地能做的只有三件：改 Swift、改 `project.yml`、读 CI 日志。写完就 push，让 CI 给结论——**不要写"本地编译通过"，那是假话**。

### 拿到能装进 iPhone 的 IPA（四步）

1. GitHub → Actions → **iOS** → 右上 **Run workflow**（分支 `main`）→ 运行。
2. 等 `build`（构建 + 单测）绿，再等 `ipa`（真机 Release 构建 + 打包）绿。
3. 在该次 run 页面底部下载 artifact **`DooDoo-unsigned-ipa`**（7 天后过期），内含 `DooDoo-unsigned.ipa` 与 `.sha256`。
4. Windows 上用 **Sideloadly** 拿自己的 Apple ID 重签后装到 iPhone。Sideloadly 需要 iTunes 提供 Apple 驱动，**装官网版 iTunes，不要装 Microsoft Store 版**（商店版不带驱动）。

关键限制（**不是 bug，是 iOS 的规则**）：

| 限制 | 说明 |
|---|---|
| 不能直接装 | 产物**未签名**，iOS 拒绝安装未签名 App，必须由自签工具补签 |
| 开发者模式必须开 | iPhone「设置 → 隐私与安全性 → 开发者模式」打开并重启，否则自签 App 点开即闪退 |
| 7 天过期 | 免费 Apple ID 签的证书 7 天失效；同一账号 7 天内最多 3 个自签 App |
| 设备要信任 | 首次安装后到「设置 → 通用 → VPN与设备管理」信任对应开发者证书 |
| 不要用 archive 导出 | `xcodebuild archive` + `-exportArchive` 强制要求证书与描述文件，无证书必失败；CI 因此走 `build` + 手工压 `Payload/` |

> 想免掉手动续签：Windows 上装 **AltServer**，手机同一 Wi-Fi 下 AltStore 会自动续签；或上付费开发者账号（一年有效）。M1 之后每次改代码都要重装一次，续签成本远低于重新构建。

## 四、M0 门禁与验证方法

| 门禁 | 怎么验 | 现状 |
|---|---|---|
| 单测能过 | 3 条冒烟测试（tab 定义 / 默认值 / 内存容器读写） | ✅ CI 通过 |
| CI 能出未签名产物 | `DooDoo-unsigned-app`，5.8 MB，sha256 `a082958c…` | ✅ run `42423907280` |
| CI 能出未签名 IPA | 手动 `Run workflow` → `ipa` job → artifact `DooDoo-unsigned-ipa` | ⬜ 待首次运行验证 |
| iPhone 能装上并打开 | 下载 IPA → Sideloadly 自签 → 首页出得来 | ⬜ 待人工 |
| 界面观感对 | 在 iPhone 上逐页看三个 tab 与设置页 | ⬜ 待人工（**本项目唯一的界面验收手段**） |
| 数据能落盘 | 设置页拨「逾期横幅」→ 杀进程 → 重开，开关保持 | ⬜ 待人工 |

**前三条是硬门禁（第 3 条待首次运行）；后三条只能靠 iPhone 人工确认——本工作区没有 macOS，模拟器这条路不存在。**

## 五、不要做的事

- 不在 M3 之前做视觉打磨（门禁：M3 完成前不谈视觉）。
- 不把原型 HTML 的 CSS 数值直接硬编码进 SwiftUI，先对照 `docs/design/spec/`。
- 不引入 SwiftUI 之外的 UI 框架、图表库、格式化库。
- 不在这里写业务逻辑：记账走 Service，算钱走 Math。
- 不提前写 M1/M2 的模型——schema 一次只加本里程碑要用的。
