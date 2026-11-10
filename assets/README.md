# DooDoo 美术资源

> 一句话：**卡面不靠照片，靠数据 + 白色单色行徽。** 这里没有一张银行卡照片，只有官网实测品牌色、15 枚白色矢量行徽、三张灰度纹理和一套 3D Emoji。
> 打开 `index.html` 可以逐项看效果。

---

## 一、目录

```
assets/
├── index.html              验收页（双击打开，无需服务器）
├── emoji/
│   ├── fluent3d/           1545 个 PNG · 全量素材库（49 MB，不进包）
│   ├── picked/             492 个 PNG · 精选集（已分类，进包）
│   ├── catalog.json        全量索引（名称 / 尺寸 / 字节 / 指纹）
│   ├── categories.json     分类映射（8 大类 + 收入 + 评分 / 操作 / 账户）
│   ├── icon-picker.html    分类图标对照表 · 全量库（71 槽位 × 1545 张，双击打开）
│   └── icon-map.html       旧版候选式对照表（已被上面取代，留作语义参考）
├── textures/               3 张灰度纹理（122 KB）
├── brands/
│   ├── brands.json         21 个品牌 + 13 个账户 + 5 张样卡（色值 / chip / logo）
│   ├── logos/              15 枚白色单色行徽 SVG（纯 path，卡面内联）
│   │   └── _source/        官网 logo 与 Simple Icons 原始素材（不进包）
│   ├── cards/              18 张卡面**设计稿** SVG + index.html 总览（含文字，不进包）
│   └── faces/              63 张卡面**底图** SVG（无文字，进包）
├── app-icon/               App 图标 light / dark 1024 + 证验页（规格见该目录 README）
└── _build/                 生成脚本，可重跑
```

---

## 二、Emoji（Fluent 3D）

| 项 | 值 |
|---|---|
| 来源 | npm `fluent-emoji@0.1.2`（内嵌微软 Fluent Emoji 的 3D PNG） |
| 上游 | [microsoft/fluentui-emoji](https://github.com/microsoft/fluentui-emoji) |
| 授权 | 微软 Fluent Emoji 为 MIT；打包库声明 Apache-2.0 |
| 规格 | 256×256 PNG，RGBA，平均 33 KB |
| 数量 | 1545 个（素材库） / 492 个（精选） |

**为什么是 PNG 不是 SVG**：微软官方的 3D 版只有位图，矢量只有 Flat / Color 两套。选了 3D 就只能是 PNG。

**为什么保留全量**：以后加分类、换图标不用重新下载。进 App 的只有 `picked/`。

### 分类对应关系

`categories.json` 把图标挂到 PRD 3.1.2 的 8 个分类上，每类再拆子类（共 44 个），例如：

```
吃 → 餐饮 28 个 / 外卖 4 个 / 买菜 37 个 / 咖啡饮品 15 个 / 甜点零食 18 个
```

**用法**：分类名由 PRD 固定（8 个），图标是从该类候选里选的。用户以后要换图标不用改数据模型，只改 `Category.emojiName`。

另有三组非分类用途，直接对应 PRD 的功能定义：

| 组 | 用途 | 对应 PRD |
|---|---|---|
| `grade` | 夯 / 飘 / 拉 / NPC 四档 | 9.13 消费评分 |
| `action` | 支出 / 收入 / 还款 / 转账 / 调整 | 五、决策 1、3；9.14 |
| `accountKind` | 储蓄 / 现金 / 信用 / 借款 | 3.1.1 |

> **评分徽章定稿（2026-11-09）**：`grade/final/` 是正式交付——J 版（官方 Fluent 3D 字块 1:1 反解），
> 每档 8 张 RGBA 透明底 PNG（1024 母版 / 256 / 58pt @2x·@3x = 116·174 / 40pt @2x·@3x = 80·120 / 87 / 60），
> 共 32 张，另附 `_contact-sheet.png` 总览。**只有 PNG，没有 SVG**（官方母版为位图，无矢量字模）。
> `grade/grade-*.svg`、`grade-*.png` 与所有 `_` 前缀目录均为历史 / 过程稿，不再作为实现依据。
> 生成：`python assets/_build/gen-grade-final.py`（源为 `grade/_replica/` 定稿主图，只重采样不再渲染）。

---

## 三、卡面纹理

三张都是**程序化生成**，固定随机种子，重跑结果完全一致。灰度 8bit，无色彩信息，靠 `overlay` / `soft-light` 混合叠在品牌色渐变上。

| 文件 | 尺寸 | 大小 | 用在哪 | 建议不透明度 |
|---|---|---|---|---|
| `tex-grain.png` | 256×256 | 49.9 KB | 全局叠加 | 3% |
| `tex-matte.png` | 512×512 | 53.7 KB | 银行卡、钱包 | 40–50% |
| `tex-metal.png` | 1024×512 | 18.5 KB | e招贷、放心借、小金库 | 35–45% |

**注意**：`tex-grain` 压不下去是物理原因——纯随机噪点熵太高，PNG 压缩率有下限。50 KB 换来的是真实的颗粒感，不是浪费。

**为什么不用真实银行卡照片**：17 个账户里只有 3–4 张有实体卡，混用照片必然风格割裂。全部走「品牌色渐变 + 纹理」才不会散。

---

## 四、品牌色与行徽（v1.2）

`brands.json` 定义 **21 个品牌、13 个账户、5 张品牌样卡**。每个品牌给两个色（渐变两端）+ 文字色 + 纹理 + 卡组织 + `chip` + `logo`。

**⚠️ 账户与卡分开维护（2026-11-08 定案）**：本文件的 `accounts` 只是**卡面展示清单**，不是产品数据。真实账户在 PRD / iOS 数据模型里按大类表达（循环 / 分期 / 储蓄 / 现金，`platform` 仅是标签），e招贷、白条分分卡这类细分产品从来不是独立账户实体。改卡面清单不等于改产品范围；v1.3 移除 6 张卡面只是「这几张卡不画了」，PRD 与 iOS 数据未动、也不需要动。

```json
{ "id": "ccb", "name": "中国建设银行", "short": "建行", "en": "CCB",
  "c1": "#0066B3", "c2": "#003563", "ink": "#FFFFFF",
  "texture": "matte", "network": "UNIONPAY", "group": "bank",
  "chip": true, "logo": "ccb" }
```

**色值来源（2026-11-08 浏览器实测）**：各行官网 CSS 高频色 + 官网 logo PNG 像素主色双向确认，不再是近似取色。工行 `#C7000A`、农行 `#319C8B`、中行 `#A71E32`、建行 `#0066B3`、交行 `#00377A`、邮储 `#18AE66`、招行 `#A30030`、上行 `#0F499E`、中移动 `#0085D0`、京东 `#E21C19`；支付宝 `#1677FF`、微信 `#07C160` 取 Simple Icons 官方色；余额宝 `#F7500E`、花呗 `#4781F0` 取用户提供的官方图标像素主色。`c2` 是 `c1` 同色系压暗，不是独立取色。

**`chip` 规则**：只有实体银行卡为 `true`（10 张：芯片左上 + 行徽右上）；网上钱包、虚拟信用、分期贷、现金一律 `false`，**去掉芯片但仍是卡片形态**，行徽放大到左上。账户可用同名 `chip` 字段覆盖（当前无账户使用）。

**`logo` 规则**：指向 `logos/logo-<id>.svg`，生成时内联进卡面，SVG 自包含。15 枚行徽全部压成白色单色纯矢量 path：10 枚从官网 logo 裁切、3 枚 Simple Icons 矢量、2 枚用户提供的官方图标（余额宝 / 花呗）。复用的品牌共享同一枚（京东系 / 抖音系 / e招贷）；现金与个人借款无 logo，降级为文字标。

**同品牌多账户靠 `variant` 区分**：0 原色 / 1 压暗 / 2 提亮。

### 卡面结构（`cards/*.svg` 就是按这个画的）

长宽比 1.586（ISO/IEC 7810 ID-1），圆角 14，品牌名左下，尾号右下，卡组织右下。

真实感来源排序：**排版 > 光影 > 纹理 > 颜色**。所以 SVG 里没有一张位图也能像卡。

---

## 五、重新生成

```bash
cd assets/_build
node fetch-fluent3d.js ..         # 下载 npm 包并提取 1545 个 3D PNG（已验证可重跑，结果一致）
node gen-textures.js ..           # 重生成 3 张纹理（固定种子，逐字节相同）
node build-emoji-catalog.js ..    # 校验分类表 → 复制精选 → 清理孤儿 → 生成 catalog / categories
python gen-logo-marks.py ..       # 从 _source/ 裁行徽 -> 15 枚白色单色 SVG
node gen-brand-cards.js ..        # 重画 18 张卡面设计稿 SVG（13 账户 + 5 样卡）
node gen-card-faces.js ..         # 重出 63 张无文字卡面底图（21 品牌 × 3 variant）
node sync-app-assets.js ..        # 底图 / 纹理 / 夯拉图标落进 Assets.xcassets
node build-gallery.js ..          # 重生成 index.html
node verify-assets.js ..          # 完整性校验（退出码非 0 表示有问题）
python gen-app-icon.py            # 重出 App 图标（light / dark 1024 + 证验页）
```

改了 `emoji-categories.source.json` 后必须跑 `build-emoji-catalog.js` + `build-gallery.js` + `verify-assets.js`。
改了品牌色 / chip / logo 后必须跑 `gen-logo-marks.py` + `gen-brand-cards.js` + `gen-card-faces.js` + `sync-app-assets.js` + `build-gallery.js` + `verify-assets.js`（顺序不能颠倒，卡面依赖行徽，底图依赖品牌色）。

校验会拦下四类错误：引用了不存在的图标名、页面引用了不存在的文件、精选目录出现孤儿文件、SVG 结构异常。2026-11-09 起另加三项：底图残留文字层或 clipPath、Asset Catalog 缺图 / imageset 数量不符、`BrandPalette.swift` 与 `brands.json` 色值漂移。当前状态：**2058 个资源引用 / 565 次分类引用 / 18 张设计稿 + 63 张底图 / 3 组 Asset / 0 缺失**。

---

## 五之二、仓库提交策略

本项目是 Windows 开发 + GitHub Action 构建，仓库里不该放可再生的二进制。`assets/.gitignore` 已按这个原则写好：

| 路径 | 大小 | 是否提交 | 理由 |
|---|---|---|---|
| `emoji/picked/` | 15 MB | ✅ 提交 | CI 构建唯一需要的 emoji 资源，不提交则每次 CI 都要下 50 MB 再筛 |
| `textures/` `brands/` | 175 KB | ✅ 提交 | 小，且是最终产物 |
| `emoji/fluent3d/` | 50 MB | ❌ 忽略 | `fetch-fluent3d.js` 可完整重建 |
| `emoji/catalog.json` | 300 KB | ❌ 忽略 | 随素材库重建 |
| `index.html` | 414 KB | ❌ 忽略 | `build-gallery.js` 可重建 |

净新增到仓库的约 **15.4 MB**。如果嫌大，把 `picked` 砍到 40 个常用图标（1.3 MB），其余按需加。

---

## 六、进 iOS 工程（2026-11-09 已落地，SVG 直接进包）

**结论：卡面 SVG 进包，但进的是「底图」不是「设计稿」。** 这是两套文件，别混：

| 文件 | 内容 | 进包 | 理由 |
|---|---|---|---|
| `brands/cards/*.svg` | 渐变 + 光影 + 芯片 + 行徽 **+ 品牌名 / 尾号 / 卡组织 / 类型标签** | ❌ | 文字写死在图里。账户名、尾号、卡组织都是可编辑的用户数据，贴上去改名不刷新，还会和 SwiftUI 的文字层重影 |
| `brands/faces/*.svg` | 渐变 + 光影 + 芯片 + 行徽，**零 `<text>`、零 `clipPath`** | ✅ | 纯装饰层，账户数据变化不影响它；圆角交给 SwiftUI 的 `clipShape` 统一裁，避免双重圆角 |

实际落地清单：

| 资源 | 落地方式 |
|---|---|
| `faces/*.svg`（63 张） | `Assets.xcassets/Card/Card<Brand>V<variant>.imageset`，Single Scale + `preserves-vector-representation`。命名规则在 `BrandStyle.cardAsset(variant:)` 里拼，两边必须一致 |
| `textures/*.png`（3 张） | `Assets.xcassets/Texture/TexMatte｜TexMetal｜TexGrain`，1x + 运行时 `resizable(resizingMode: .tile)` 平铺。**不要给 @2x/@3x**，否则不同倍率下 tile 边长不一致、接缝会粗 |
| `grade/final/*.png`（4 档） | `Assets.xcassets/Grade/GradeHang｜GradePiao｜GradeLa｜GradeNpc`，40pt 规格 @2x 80 / @3x 120 |
| `brands.json` | 转成 Swift 的 `BrandPalette` 静态字典，不进 Asset Catalog；`verify-assets.js` 会校验两边色值不漂移 |
| `logos/*.svg` | **不单独进包**，生成时已内联进 `faces/*.svg`，运行时不用再摆位 |
| `emoji/picked` | 仍在 `Resources/Emoji/` 平铺（未走 Asset Catalog），等 M4 视觉阶段一起收 |

**为什么底图要 21 × 3 = 63 张**：`variant` 是「同品牌第几张卡」，色阶（原色 / 压暗 / 提亮）是色相偏移，SwiftUI 的 `.brightness()` 做不出同色系压暗的手感，所以色阶必须固化成文件。这份清单由 `gen-card-faces.js` 与 `brands.json` 同步生成，加品牌只要改 json 再重跑两个脚本。

**底图比例与卡片比例不严格相等**（底图 1.586，卡片 1.5–1.61），运行时用 `aspectRatio(contentMode: .fill)` 填满再裁，不能直接拉伸——拉伸会把芯片压成椭圆。

`emoji/picked` 492 个图标 15.2 MB，Asset Catalog 会再压一轮，实际增量大概 8–10 MB。如果嫌大，第一批只放 8 个分类各 3–5 个图标（约 40 个），其余等真要换图标时再加。

---

## 七、待你决定

1. ~~品牌标要不要真 Logo~~ **已定案（2026-11-08）**：选 A 单色白色行徽，15 枚已落地。法律风险仍在——本地自用无碍，上架需换回「品牌色块 + 银行名简称」。
2. **精选集是否全量进包**。493 个图标 15.2 MB；只放常用 40 个约 1.3 MB。后者更省，但换图标时没得选。
3. **卡面比例**。现在是 148×93（1.586）。原型是 148×92（1.609），差 1.5%，肉眼无感，但要不要统一成严格的 1.586。

---

## 八、App 图标（2026-11-08）

`app-icon/` 只有两个成品 + 一张证验页，详细口径见 `app-icon/README.md`。

| 项 | 值 |
|---|---|
| 交付 | `app-icon-light-1024.png` / `app-icon-dark-1024.png` |
| 规格 | 1024×1024 · sRGB（ICC 内嵌）· 无 alpha · 不画圆角 |
| 内容占比 | 80% 宽 × 85% 高（字形 15 → 20.4pt @60pt） |
| 深浅关系 | 同一套 transform，猫 / 金币 / 猫爪同像素同坐标，只有字母明度与底色变 |

**没有设计草图的图层，别指望从成品里拆**：tinted 外观要 Icon Composer 的 `.icon` + 四层 alpha（背景 / 猫 / 字母 / 金币），flattened PNG 键不出干净 alpha（猫爪和白围兜本身近白，会一起被打穿）。要上 iOS 26 得回渲染侧出分层 pass。
