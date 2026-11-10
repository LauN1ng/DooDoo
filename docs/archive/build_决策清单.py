# -*- coding: utf-8 -*-
"""记账 App 开工前决策清单"""

try:
    import openpyxl
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "openpyxl>=3.1.0"])
    import openpyxl

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter


def xl_color(css_hex: str) -> str:
    value = css_hex.removeprefix("#").upper()
    if len(value) != 6:
        raise ValueError(f"Expected #RRGGBB, got: {css_hex}")
    return "FF" + value


XL_HEAD_BG = xl_color("#F2F2F2")
XL_INPUT_BG = xl_color("#FFFDF5")
XL_REF_BG = xl_color("#FAFAFA")
XL_BORDER = xl_color("#D9D9D9")
XL_DARK = xl_color("#1A1A1A")
XL_MUTED = xl_color("#8C8C8C")
XL_ACCENT = xl_color("#E0E0E0")

FONT = "微软雅黑"

thin = Side(style="thin", color=XL_BORDER)
BORDER_ALL = Border(left=thin, right=thin, top=thin, bottom=thin)


def head_row(ws, row, headers, widths=None):
    for i, h in enumerate(headers, start=1):
        c = ws.cell(row=row, column=i, value=h)
        c.font = Font(name=FONT, size=10, bold=True, color=XL_DARK)
        c.fill = PatternFill("solid", fgColor=XL_HEAD_BG)
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = BORDER_ALL
    ws.row_dimensions[row].height = 30
    if widths:
        for i, w in enumerate(widths, start=1):
            ws.column_dimensions[get_column_letter(i)].width = w


def fill_cell(ws, row, col, value, wrap=True, align="left", bg=None, bold=False, color=None):
    c = ws.cell(row=row, column=col, value=value)
    c.font = Font(name=FONT, size=10, bold=bold, color=color or XL_DARK)
    c.alignment = Alignment(horizontal=align, vertical="top", wrap_text=wrap)
    c.border = BORDER_ALL
    if bg:
        c.fill = PatternFill("solid", fgColor=bg)
    return c


def title_block(ws, text, sub, ncols):
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
    c = ws.cell(row=1, column=1, value=text)
    c.font = Font(name=FONT, size=14, bold=True, color=XL_DARK)
    c.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 34

    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=ncols)
    c = ws.cell(row=2, column=1, value=sub)
    c.font = Font(name=FONT, size=9, color=XL_MUTED)
    c.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
    ws.row_dimensions[2].height = 20


wb = Workbook()

# ============ 01 填写说明 ============
ws = wb.active
ws.title = "01 填写说明"
ws.sheet_properties.tabColor = XL_ACCENT
ws.column_dimensions["A"].width = 4
ws.column_dimensions["B"].width = 22
ws.column_dimensions["C"].width = 96

ws.merge_cells("B1:C1")
c = ws["B1"]
c.value = "记账 App · 开工前决策清单"
c.font = Font(name=FONT, size=16, bold=True, color=XL_DARK)
c.alignment = Alignment(vertical="center")
ws.row_dimensions[1].height = 40

ws.merge_cells("B2:C2")
c = ws["B2"]
c.value = "这份表填完，产品需求就可以冻结，直接进入开发。填之前先看下面三条。"
c.font = Font(name=FONT, size=10, color=XL_MUTED)
ws.row_dimensions[2].height = 22

rows = [
    ("怎么填", "只有**浅黄色**的单元格需要你填。灰色底和白色底的是参考信息，不用动。\n"
               "带下拉箭头的格子点一下选一个；没有下拉的直接打字。不确定的写「不确定」或「你定」，不要空着。"),
    ("优先级", "先填 02 必答决策，这 8 条影响数据模型，定了就不好改。\n"
               "再填 03 到 06 的账户和负债，这部分用你真实的数据，不要编。\n"
               "07 产品偏好最后填，都是可以边做边改的。\n"
               "08 已定事项不用填，是给你核对用的，看有没有记错。"),
    ("为什么要这么细", "前面六版设计都没过，根因不是审美，是需求没具体到能推出设计。\n"
                      "举个例：「信用卡还款算不算支出」这一条不定，你的「本月花了多少」会永久虚高，\n"
                      "因为每笔刷卡记一次、还款又记一次。这类问题必须在写代码前有答案。"),
    ("金额怎么填", "欠款填正数，不用加负号，系统会按账户类型处理方向。\n"
                  "利率填百分比数字，比如 16.43% 就填 16.43。\n"
                  "日期填 YYYY-MM-DD，比如 2026-11-25。"),
    ("填完怎么办", "保存后直接把文件发回来。我会按你的答案更新 PRD，然后开始搭工程。\n"
                  "有拿不准的条目，在备注里写一句你的顾虑，比空着更有用。"),
]

r = 4
for label, text in rows:
    c = ws.cell(row=r, column=2, value=label)
    c.font = Font(name=FONT, size=11, bold=True, color=XL_DARK)
    c.alignment = Alignment(vertical="top")
    c2 = ws.cell(row=r, column=3, value=text)
    c2.font = Font(name=FONT, size=10, color=XL_DARK)
    c2.alignment = Alignment(vertical="top", wrap_text=True)
    ws.row_dimensions[r].height = 22 * (text.count("\n") + 2)
    r += 4 if label != "填完怎么办" else 3

# 图例
r += 1
ws.cell(row=r, column=2, value="颜色约定").font = Font(name=FONT, size=10, bold=True, color=XL_DARK)
r += 1
legend = [
    ("需要你填", XL_INPUT_BG, "浅黄底 = 待填写"),
    ("参考信息", XL_REF_BG, "灰底 = 只是信息，不用改"),
    ("已定事项", XL_HEAD_BG, "深灰底 = 已经确定的，核对即可"),
]
for name, bg, desc in legend:
    c = ws.cell(row=r, column=2, value=name)
    c.font = Font(name=FONT, size=10)
    c.fill = PatternFill("solid", fgColor=bg)
    c.border = BORDER_ALL
    c.alignment = Alignment(horizontal="center", vertical="center")
    c = ws.cell(row=r, column=3, value=desc)
    c.font = Font(name=FONT, size=10, color=XL_MUTED)
    r += 1

# ============ 02 必答决策 ============
ws = wb.create_sheet("02 必答决策")
ws.sheet_properties.tabColor = xl_color("#FFD966")
title_block(ws, "02 必答决策 · 8 条",
            "这 8 条决定数据结构。定错了，后面所有数据都是错的，改起来要洗数据。每条都给了我的建议，不同意的改掉即可。", 6)
head_row(ws, 4, ["#", "决策问题", "为什么必须现在定", "选项", "我的建议", "你的答案"], [5, 26, 52, 26, 26, 24])

decisions = [
    ("1", "信用卡还款怎么记？",
     "刷卡时记了一次支出，还款时如果又记一次，本月支出会永久虚高。这是最常见的翻车点。",
     "A 不计入支出\nB 计入支出", "A 不计入支出"),
    ("2", "聚餐 AA、我先付 300 收回 200，怎么记？",
     "决定「支出」到底记我承担的部分还是我垫付的全额，影响余额是否对得上。",
     "A 只记我承担的 100\nB 记 300 再记 200 收入", "A 只记我承担的 100"),
    ("3", "微信提现到银行卡，怎么记？",
     "如果不当成账户互转，会被算成支出，虚增当月花销。",
     "A 账户互转，不计收支\nB 当支出", "A 账户互转"),
    ("4", "退款怎么处理？",
     "花呗 11 月账单里有 172.74 退款。记成收入会让当月收入虚高，看不出真实消费。",
     "A 冲减原分类支出\nB 记一笔收入", "A 冲减原分类支出"),
    ("5", "统计「本月」用什么口径？",
     "自然月（1 号到月底）和发薪月（发薪日到下次发薪日）算出来的数字完全不同。",
     "A 自然月\nB 发薪日到发薪日", "A 自然月"),
    ("6", "花呗这类循环负债，怎么录？",
     "平台给的数字是准的，自己按利率推演一定对不上。",
     "A 每月手录本期应还\nB 填欠款+利率让 App 推演", "A 每月手录本期应还"),
    ("7", "分期计划怎么录？比如 e招贷剩 17 期",
     "决定录入界面要几个字段，也决定能不能算出总利息。",
     "A 只填剩余本金+剩余期数\nB 填原始金额+已还期数", "A 只填剩余本金+剩余期数"),
    ("8", "亲友借款怎么记？",
     "无息、无固定期限，套用利率模型会算出错误结果。",
     "A 只记总欠款+每月还多少\nB 也要设利率和期限", "A 只记总欠款+每月还多少"),
]

r = 5
for num, q, why, opts, sug in decisions:
    fill_cell(ws, r, 1, num, align="center")
    fill_cell(ws, r, 2, q, bold=True)
    fill_cell(ws, r, 3, why, color=XL_MUTED)
    fill_cell(ws, r, 4, opts, bg=XL_REF_BG)
    fill_cell(ws, r, 5, sug, bg=XL_REF_BG)
    fill_cell(ws, r, 6, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 46
    r += 1

# 下拉
for i, (_, _, _, opts, _) in enumerate(decisions):
    items = ",".join([o.split(" ")[0] for o in opts.split("\n")])
    dv = DataValidation(type="list", formula1=f'"{items}"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"F{5 + i}")

ws.freeze_panes = "A5"

# ============ 03 账户清单 ============
ws = wb.create_sheet("03 账户清单")
ws.sheet_properties.tabColor = xl_color("#FFD966")
title_block(ws, "03 账户清单 · 你真实有哪些账户",
            "按截图里的平台填。储蓄卡、花呗、白条、e招贷、借父母的钱，各占一行。余额填当前实际数字即可，不用精确到分。", 8)
head_row(ws, 4, ["#", "账户名称", "类型", "所属平台", "当前余额/欠款（元）", "账单日", "还款日", "备注"],
         [5, 22, 12, 20, 20, 10, 10, 30])

samples = [
    ("1", "招行储蓄卡", "资产", "招商银行", 8000, "", "", "工资卡"),
    ("2", "招行信用卡", "负债", "招商银行", 12480, 14, 25, ""),
    ("3", "花呗", "负债", "支付宝", 1634.08, 14, 25, "账单周期 10/15-11/14"),
    ("4", "京东白条", "负债", "京东金融", 431.17, "", 25, ""),
]
for i, (n, name, kind, plat, amt, bd, dd, note) in enumerate(samples):
    r = 5 + i
    fill_cell(ws, r, 1, n, align="center", bg=XL_REF_BG)
    fill_cell(ws, r, 2, name, bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 3, kind, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 4, plat, bg=XL_REF_BG, color=XL_MUTED)
    c = fill_cell(ws, r, 5, amt, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 6, bd, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 7, dd, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 8, note, bg=XL_REF_BG, color=XL_MUTED)

# 空白填写行 9-22
FIRST_BLANK = 9
LAST_ROW = 22
for r in range(FIRST_BLANK, LAST_ROW + 1):
    fill_cell(ws, r, 1, r - 8, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 2, "", bg=XL_INPUT_BG)
    fill_cell(ws, r, 3, "", align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 4, "", bg=XL_INPUT_BG)
    c = fill_cell(ws, r, 5, None, align="right", bg=XL_INPUT_BG)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 6, None, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 7, None, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 8, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 20

dv = DataValidation(type="list", formula1='"资产,负债"', allow_blank=True)
ws.add_data_validation(dv)
dv.add(f"C5:C{LAST_ROW}")

# 底部提示（此表为填写表，不放公式，避免预览器读不到缓存值）
SUM_ROW = LAST_ROW + 2
ws.cell(row=SUM_ROW, column=2,
        value="填完后不用自己算合计，我会按你填的数字汇总。").font = \
    Font(name=FONT, size=10, color=XL_MUTED)
ws.cell(row=SUM_ROW + 2, column=2,
        value="提示：上面 4 行是示例，填之前请删掉。第 9 行开始是空的，直接填你自己的账户。").font = \
    Font(name=FONT, size=9, color=XL_MUTED)

ws.freeze_panes = "A5"

# ============ 04 负债-分期 ============
ws = wb.create_sheet("04 负债-分期")
ws.sheet_properties.tabColor = xl_color("#FFD966")
title_block(ws, "04 分期类负债 · 有明确期数和终点的",
            "e招贷、消费分期、白条订单分期都属于这类。一个分期计划填一行，不要合并。免息的利率填 0。", 9)
head_row(ws, 4, ["#", "名称", "所属平台", "总金额（元）", "总期数", "年化利率（%）", "已还期数", "每期金额（元）", "还款方式"],
         [5, 24, 18, 16, 10, 14, 12, 16, 18])

stage_samples = [
    ("1", "e招贷", "招商银行掌上生活", 9000, 24, 16.43, 7, "", "等额本息"),
    ("2", "消费分期-中移金科", "招商银行", 6699, 24, 0, 13, 279.13, "等额本金/免息平摊"),
]
for i, (n, name, plat, amt, periods, rate, paid, per, mode) in enumerate(stage_samples):
    r = 5 + i
    fill_cell(ws, r, 1, n, align="center", bg=XL_REF_BG)
    fill_cell(ws, r, 2, name, bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 3, plat, bg=XL_REF_BG, color=XL_MUTED)
    c = fill_cell(ws, r, 4, amt, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 5, periods, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 6, rate, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 7, paid, align="center", bg=XL_REF_BG, color=XL_MUTED)
    c = fill_cell(ws, r, 8, per if per else "", align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 9, mode, bg=XL_REF_BG, color=XL_MUTED)

for r in range(7, 17):
    fill_cell(ws, r, 1, r - 6, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 2, "", bg=XL_INPUT_BG)
    fill_cell(ws, r, 3, "", bg=XL_INPUT_BG)
    c = fill_cell(ws, r, 4, None, align="right", bg=XL_INPUT_BG)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 5, None, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 6, None, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 7, None, align="center", bg=XL_INPUT_BG)
    c = fill_cell(ws, r, 8, None, align="right", bg=XL_INPUT_BG)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 9, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 20

dv = DataValidation(type="list", formula1='"等额本息,等额本金/免息平摊,不确定"', allow_blank=True)
ws.add_data_validation(dv)
dv.add("I7:I16")

ws.freeze_panes = "A5"

# ============ 05 负债-循环 ============
ws = wb.create_sheet("05 负债-循环")
ws.sheet_properties.tabColor = xl_color("#FFD966")
title_block(ws, "05 循环类负债 · 每月出账单，没有固定终点",
            "花呗、信用卡、白条都算。填当前欠款和最近一期的应还金额。账单周期从哪号到哪号，按截图填。", 9)
head_row(ws, 4, ["#", "名称", "所属平台", "当前欠款（元）", "本期应还（元）", "账单周期起（日）", "账单周期止（日）", "还款日（日）", "额度（元）"],
         [5, 22, 18, 18, 18, 16, 16, 14, 16])

loop_samples = [
    ("1", "花呗", "支付宝", 1634.08, 1634.08, 15, 14, 25, 0),
    ("2", "招行信用卡", "招商银行", 12480, 442.50, 15, 14, 25, 20000),
]
for i, (n, name, plat, owed, cur, b1, b2, dd, limit) in enumerate(loop_samples):
    r = 5 + i
    fill_cell(ws, r, 1, n, align="center", bg=XL_REF_BG)
    fill_cell(ws, r, 2, name, bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 3, plat, bg=XL_REF_BG, color=XL_MUTED)
    c = fill_cell(ws, r, 4, owed, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    c = fill_cell(ws, r, 5, cur, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 6, b1, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 7, b2, align="center", bg=XL_REF_BG, color=XL_MUTED)
    fill_cell(ws, r, 8, dd, align="center", bg=XL_REF_BG, color=XL_MUTED)
    c = fill_cell(ws, r, 9, limit, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"

for r in range(7, 17):
    fill_cell(ws, r, 1, r - 6, align="center", bg=XL_INPUT_BG)
    for col in (2, 3):
        fill_cell(ws, r, col, "", bg=XL_INPUT_BG)
    for col in (4, 5, 9):
        c = fill_cell(ws, r, col, None, align="right", bg=XL_INPUT_BG)
        c.number_format = "#,##0.00"
    for col in (6, 7, 8):
        fill_cell(ws, r, col, None, align="center", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 20

ws.freeze_panes = "A5"

# ============ 06 负债-协商 ============
ws = wb.create_sheet("06 负债-协商")
ws.sheet_properties.tabColor = xl_color("#FFD966")
title_block(ws, "06 协商类负债 · 亲友借款等",
            "这类没有利率、没有固定期限。只记总欠多少、已经还了多少、每月打算还多少，不参与利息计算。", 7)
head_row(ws, 4, ["#", "对象", "总欠款（元）", "已还（元）", "剩余（元）", "每月计划还（元）", "备注"],
         [5, 20, 18, 16, 16, 20, 32])

nego_samples = [
    ("1", "父母", 20000, 0, 20000, 1000, "无息，没有约定还款日"),
]
for i, (n, who, total, paid, left, monthly, note) in enumerate(nego_samples):
    r = 5 + i
    fill_cell(ws, r, 1, n, align="center", bg=XL_REF_BG)
    fill_cell(ws, r, 2, who, bg=XL_REF_BG, color=XL_MUTED)
    for col, v in ((3, total), (4, paid)):
        c = fill_cell(ws, r, col, v, align="right", bg=XL_REF_BG, color=XL_MUTED)
        c.number_format = "#,##0.00"
    c = fill_cell(ws, r, 5, left, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    c = fill_cell(ws, r, 6, monthly, align="right", bg=XL_REF_BG, color=XL_MUTED)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 7, note, bg=XL_REF_BG, color=XL_MUTED)

for r in range(6, 16):
    fill_cell(ws, r, 1, r - 5, align="center", bg=XL_INPUT_BG)
    fill_cell(ws, r, 2, "", bg=XL_INPUT_BG)
    for col in (3, 4, 6):
        c = fill_cell(ws, r, col, None, align="right", bg=XL_INPUT_BG)
        c.number_format = "#,##0.00"
    c = fill_cell(ws, r, 5, None, align="right", bg=XL_INPUT_BG)
    c.number_format = "#,##0.00"
    fill_cell(ws, r, 7, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 20

ws.freeze_panes = "A5"

# ============ 07 产品偏好 ============
ws = wb.create_sheet("07 产品偏好")
ws.sheet_properties.tabColor = xl_color("#BFBFBF")
title_block(ws, "07 产品偏好 · 可以边做边改的",
            "这些不影响数据模型，先按我的建议做，用的时候觉得不对再改。有意见就改，没意见留空表示同意建议。", 5)
head_row(ws, 4, ["#", "问题", "选项", "我的建议", "你的答案"], [5, 32, 32, 30, 26])

prefs = [
    ("1", "App 叫什么名字？", "（自由填写）", "暂时叫「账」即可，上架前再定"),
    ("2", "现金要不要单独管？", "A 管，每次花现金都记\nB 不管，用其他账户偶尔校准", "B 不管"),
    ("3", "分类要不要支持自定义？", "A 固定 8 类\nB 可自己加", "A 固定 8 类"),
    ("4", "固定支出（房租等）要自动生成吗？", "A 每月自动生成一笔\nB 手动记", "A 自动生成"),
    ("5", "要不要还款日提醒？", "A 要\nB 不要", "B 不要，App 不该打扰"),
    ("6", "要不要显示信用卡额度使用率？", "A 要\nB 不要", "B 不要，v1 不做"),
    ("7", "首页要不要显示净资产？", "A 显示\nB 不显示，资产单独一页", "B 单独一页"),
    ("8", "要不要月度分类统计图？", "A 要一个饼图\nB 要条形图\nC 不要", "A 一个饼图"),
    ("9", "要不要深色模式？", "A 要\nB 暂时不要", "A 要，iOS 自动跟随系统"),
    ("10", "记一笔时要不要能选过去日期？", "A 能，默认今天\nB 不能，只能记今天", "A 能"),
]

r = 5
for num, q, opts, sug in prefs:
    fill_cell(ws, r, 1, num, align="center")
    fill_cell(ws, r, 2, q, bold=True)
    fill_cell(ws, r, 3, opts, bg=XL_REF_BG)
    fill_cell(ws, r, 4, sug, bg=XL_REF_BG)
    fill_cell(ws, r, 5, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 40
    r += 1

ws.freeze_panes = "A5"

# ============ 08 已定事项 ============
ws = wb.create_sheet("08 已定事项")
ws.sheet_properties.tabColor = xl_color("#BFBFBF")
title_block(ws, "08 已定事项 · 不用填，核对即可",
            "这些是前面聊定的，如果哪条记错了或者你想改，直接在备注里写。", 4)
head_row(ws, 4, ["#", "项目", "结论", "备注"], [5, 26, 72, 26])

settled = [
    ("1", "产品形态", "常规记账 App，不颠覆行业，只解决自己的痛点"),
    ("2", "首页第一眼", "今天的流水，不需要滑动或点击即可看到"),
    ("3", "可玩性", "v1 不做，后置为模块。好看优先于好玩"),
    ("4", "视觉语言", "Microsoft Fluent 3D Emoji 作为唯一彩色来源"),
    ("5", "导航", "不用底部 Tab Bar（待定替代形式）"),
    ("6", "负债结清口径", "按实际还款额推演，不做双口径"),
    ("7", "技术栈", "SwiftUI + SwiftData，新建工程不复用 iOwn"),
    ("8", "最低系统版本", "iOS 27，仅 iPhone，竖屏"),
    ("9", "数据存储", "纯本地，无云同步，无账号体系"),
    ("10", "记账粒度", "每天记流水，极简（金额 + 账户 + 分类）"),
    ("11", "账单导入", "v1.5 再做，v1 手动录入"),
    ("12", "余额对账", "v1 不做对账 UI，只留时间戳字段"),
    ("13", "分类", "固定 8 类 + 收入，不支持自定义"),
    ("14", "做不做的判断标准", "三个月后自己还在用它"),
    ("15", "设计流程", "M3 完成前不谈视觉，先让数据跑通"),
]

r = 5
for num, item, conclusion in settled:
    fill_cell(ws, r, 1, num, align="center", bg=XL_REF_BG)
    fill_cell(ws, r, 2, item, bold=True, bg=XL_REF_BG)
    fill_cell(ws, r, 3, conclusion, bg=XL_REF_BG)
    fill_cell(ws, r, 4, "", bg=XL_INPUT_BG)
    ws.row_dimensions[r].height = 22
    r += 1

ws.freeze_panes = "A5"

# 统一字体兜底
for sheet in wb.worksheets:
    sheet.sheet_view.showGridLines = False

wb.properties.title = "记账 App 开工前决策清单"
wb.save(r"D:/Work/WorkBuddy_File/account/docs/archive/记账_App_开工前决策清单.xlsx")
print("saved")
