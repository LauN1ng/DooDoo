# docs/reference/ 原始资料与提取脚本

> **只读证据区**：这里放的是「从真实平台导出的原始数据」和「解析它们的脚本」，不写结论、不写规则。
> 用途：单元测试的真实数据源（见 `docs/product/PRD-v2.1.md` 附录）、账单导入解析器的雏形。

---

## 一、目录

| 路径 | 内容 | 来源 |
|---|---|---|
| `bills/` | 4 份招行信用卡账单文本（2025-12 / 2026-04 / 2026-08 / 2026-09） | 用户导出的账单 PDF → `scripts/pdf_read.py` 提取 |
| `scripts/pdf_read.py` | 账单 PDF → 纯文本，输出到 `bills/`（`--PAGE--` 分页标记） | — |
| `scripts/num_extract.py` | 从截图中抽取数字（辅助核对金额） | — |
| `scripts/bill_stats.py` | 支付宝 CSV 统计：**按 GBK 解码**、定位表头、按分类汇总 | 用于 PRD 3.2 的消费规模数据 |
| `samples/num-text.txt` | 数字识别中间结果 | — |
| `samples/num-preview.jpg` | 截图核对预览 | — |

---

## 二、这些数据已经用在哪些结论上

| 数据 | 已产生的结论（见 PRD） |
|---|---|
| `bills/2026年08月信用卡账单.txt` | 逾期事实：违约金 16.05 + 循环利息 9.12，额度 9,000 → 4,600（PRD 二节、9.6） |
| `bills/` 四份合计 | 招行账单序列 0.00 / 547.28 / 665.36 / 525.72（PRD 附录 A） |
| `bill_stats.py` 跑支付宝导出 | 3 个月支出 22,566.44 元、331 笔；分类 TOP5；渠道分布（PRD 3.2 / 附录 E） |

**单测取值纪律**：金额相关的单测用例必须来自这里或 PRD 附录，**不得自造数字**。

---

## 三、脚本运行

```powershell
# 账单 PDF → txt（需要 pypdf，输出到 docs/reference/bills/）
python docs\reference\scripts\pdf_read.py "D:\path\to\账单.pdf"

# 支付宝 CSV 统计（脚本内以 GBK 解码，这是支付宝导出的真实编码）
python docs\reference\scripts\bill_stats.py "D:\path\to\alipay_record.csv"
```

注意：支付宝导出是 **GBK**，微信是 **UTF-8**（xlsx 或 csv 两种历史格式）；这条差异是 PRD 风险 #2/#3 的来源，写解析器时必须显式指定编码。

---

## 四、纪律

- 不改原始文本；需要更正就在新文件里做，并注明来源。
- 不把这里的数字写进文档当结论（结论属于 `docs/product/`）。
- 新增账号/平台的真实导出可以放进来，文件名沿用 `YYYY年MM月<平台>账单.txt`。
