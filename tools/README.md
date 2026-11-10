# tools/ 脚本

> 只放**辅助脚本**，不放产品代码。产品代码在 `app/`（M0 才建）。

---

## 一、`screenshot/` 原型截图与几何测量

9 个脚本是 **tabbit CLI 的程序片段**（不是独立 Node 程序）：内部直接使用注入的 `page` 对象与顶层 `await`，必须由 tabbit 的 `nodejs` 入口执行。视口按页面需要设定（`520×1000` 或 `900×950`），截图落盘在 `design/current/`。

| 脚本 | 打开的原型 | 产出 |
|---|---|---|
| `hf2-shoot.js` | `design/current/home-final.html` | `hf2-home.png` + 几何回执（便签数、rows 溢出、FAB/tab 间隙） |
| `mt-shoot.js` | `nav-mat.html` | `mt-*.png`（tab 五版） |
| `mtcmp.js` | `nav-mat-compare.html` | `nav-mat-compare.png`（整页） |
| `nav-shoot.js` | `nav-final.html` | `nav-a/b/c.png` |
| `nav-cmp.js` | `nav-final-compare.html` | `nav-final-compare.png`（整页） |
| `ov-shoot.js` | `day-overflow.html` | `_ov-A/B/C.png` + 几何回执（溢出像素、行高） |
| `render-check.js` | 依次打开 index / home-final / account-stack-v1.0 | 每页标题、图片数、**破图清单**、设备框尺寸 + 截图；搬动目录或改资源路径后先跑这个 |
| `tab-shoot.js` | `tab-top.html` | `_tab-t1/t2/t3.png` + 几何（胶囊 112×34、右内距、字标间隙、层厚） |
| `fab-shoot.js` | `fab-options.html` | `_fab-a~d.png` + 几何（控件尺寸、距底、流水行间隙、卡内 padding） |
| `homev2-shoot.js` | `home-v2.html#fX`（改脚本第一行换方案） | `_homev2-fx.png` + 几何（顶部胶囊、控件与流水行间隙） |
| `verify-ui.js` | `tab-top.html` + `home-v2.html` | 交互自检（不截图）：三版/四版切换是否更新几何与文案、标注文案、顶部 tab 点击 toast、破图数 |
| `note-gap.js` | `home-v2.html` | 纯测量：胶囊底 ↔ 便签顶的间隔、卡堆顶、卡高、便签露出卡顶高度、rows 是否溢出 |

早期脚本统一 `520 × 1000`（容纳 390×844 的设备框 + 页面留白）；新增的三个采用 `900 × 950` 并把设备缩放置 1，保证截出来是 390×844 的原尺寸。

### 运行方式（Windows PowerShell）

```powershell
$cli = "<tabbit-cli 路径>"
Get-Content -Raw -Encoding UTF8 tools\screenshot\hf2-shoot.js | & $cli nodejs
```

`cmd /c` 与 `<` 重定向被安全策略禁用；必须用 `Get-Content -Raw -Encoding UTF8 | & $cli nodejs` 管道，否则中文字面量会变乱码。

### 实测坑（2026-11-07 新增三条）

1. **量几何要以 `.screen` 的 rect 为参照系**，不能用视口坐标（设备框在页面里有偏移）。
2. **隐藏变体的 `getBoundingClientRect()` 全是 0**，测哪一版就先切到那一版。
3. 截图偶发 `SCREENSHOT_CAPTURE_FAILED`，**文件通常仍会落盘**，重试即可；动画后等 `1500ms` 再截，否则会抓到半透明中间帧。
4. **一个请求只能截一张图**：同一 `nodejs` 请求里第二次 `page.screenshot` 会 30s 超时（`taking page screenshot` 卡住）。要 N 张就拆 N 个请求，每个换一个 `--request-id`。
5. **元素截图（`locator.screenshot`）在两处会卡死**：① 祖先有 `transform: scale()`；② 页面有持续动画。表现都是 `waiting for element to be stable` 直到超时。对策：先把 `.device` 的 `transform` 置 `none`、把 `.card` 的 `transition` 置 `none`，再用 `page.screenshot({ clip })`。
6. **`page.screenshot({ path })` 不一定写到指定路径**，产物常落在 tabbit 的 `Runtime/artifacts/task-*/` 下。用 `Get-ChildItem ... -Filter "_xxx-shot-*.png" | Sort LastWriteTime | Select -Last 1` 取回并复制。
7. **截图后尺寸会变**：`page.screenshot` 的 `clip` 用 CSS 像素，若设备被 `fit()` 缩放过，先置 `transform:none`，否则截出来的宽高是缩放后的（例如 375×812 而不是 390×844）。

---

## 二、历史脚本

`design/current/` 里那些 `_e-*.png`、`dk-*.png`、`nl-*.png` 等对比图由已删除的一次性脚本生成，脚本未保留（参数与结论已写进 `docs/design/history/`）。需要复现时按该文档的尺寸表重写即可。

---

## 三、未来会放在这里的东西

- M0 的工程生成与打包脚本（XcodeGen 调用、未签名 IPA 打包）→ 届时新建 `tools/build/`。
- 账单导入的解析器验证脚本（现在还是 `docs/reference/scripts/` 里的 Python 雏形）。
