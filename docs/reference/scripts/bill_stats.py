import sys, csv, io, re, collections

def load_alipay(path):
    with open(path, encoding="gbk", errors="ignore") as f:
        text = f.read()
    lines = text.splitlines()
    hi = None
    for i, L in enumerate(lines):
        if L.strip().startswith("交易时间") and "交易分类" in L:
            hi = i
            break
    if hi is None:
        return []
    body = "\n".join(lines[hi:])
    body = body[body.index("交易时间"):]
    rows = list(csv.reader(io.StringIO(body)))
    header = [h.strip() for h in rows[0]]
    out = []
    for r in rows[1:]:
        if not r or len(r) < 8:
            continue
        d = dict(zip(header, r))
        t = d.get("交易时间", "").strip()
        if not re.match(r"\d{4}-\d{2}-\d{2}", t):
            continue
        try:
            amt = float(d.get("金额", "0").strip() or 0)
        except ValueError:
            continue
        out.append({
            "time": t,
            "cat": d.get("交易分类", "").strip(),
            "merchant": d.get("交易对方", "").strip(),
            "desc": d.get("商品说明", "").strip(),
            "dir": d.get("收/支", "").strip(),
            "amt": amt,
            "pay": d.get("收/付款方式", "").strip(),
            "status": d.get("交易状态", "").strip(),
        })
    return out

def load_jd(path):
    with open(path, encoding="utf-8-sig", errors="ignore") as f:
        text = f.read()
    lines = text.splitlines()
    hi = None
    for i, L in enumerate(lines):
        if L.strip().startswith("交易时间") and "商户名称" in L:
            hi = i
            break
    if hi is None:
        return []
    body = "\n".join(lines[hi:])
    rows = list(csv.reader(io.StringIO(body)))
    header = [h.strip() for h in rows[0]]
    out = []
    for r in rows[1:]:
        if not r or len(r) < 7:
            continue
        d = dict(zip(header, r))
        t = d.get("交易时间", "").strip()
        if not re.match(r"\d{4}-\d{2}-\d{2}", t):
            continue
        try:
            amt = float(d.get("金额", "0").strip() or 0)
        except ValueError:
            continue
        out.append({
            "time": t,
            "merchant": d.get("商户名称", "").strip(),
            "desc": d.get("交易说明", "").strip(),
            "amt": amt,
            "pay": d.get("收/付款方式", "").strip(),
            "dir": d.get("收/支", "").strip(),
            "cat": d.get("交易分类", "").strip(),
            "status": d.get("交易状态", "").strip(),
        })
    return out

ali = load_alipay(sys.argv[1])
jd = load_jd(sys.argv[2])

print("### 支付宝 明细", len(ali), "条，合计", round(sum(x["amt"] for x in ali if x["dir"] == "支出"), 2))
m = collections.defaultdict(float)
for x in ali:
    if x["dir"] == "支出":
        m[x["time"][:7]] += x["amt"]
print("按月份:", {k: round(v, 2) for k, v in sorted(m.items())})

c = collections.Counter()
for x in ali:
    if x["dir"] == "支出":
        c[x["cat"]] += x["amt"]
print("按分类 TOP12:")
for k, v in c.most_common(12):
    print("  ", k, round(v, 2))

p = collections.Counter()
for x in ali:
    if x["dir"] == "支出":
        p[x["pay"]] += x["amt"]
print("按付款方式:")
for k, v in p.most_common(12):
    print("  ", k, round(v, 2))

fx = [x for x in ali if "分期" in x["pay"] or "分期" in x["desc"]]
print("含分期的记录:", len(fx))
for x in fx[:12]:
    print("  ", x["time"], x["merchant"], x["amt"], x["pay"], x["status"])

print()
print("### 京东 明细", len(jd), "条")
repay = [x for x in jd if "白条" in x["merchant"] and "还款" in x["desc"]]
print("白条还款记录:")
for x in sorted(repay, key=lambda y: y["time"]):
    print("  ", x["time"], x["amt"], x["desc"], x["pay"])

print("京东支出:")
for x in jd:
    if x["dir"] == "支出":
        print("  ", x["time"], x["merchant"], x["amt"], x["pay"], x["cat"])

print("京东付款方式分布:")
pj = collections.Counter()
for x in jd:
    pj[x["pay"]] += x["amt"]
for k, v in pj.most_common():
    print("  ", k, round(v, 2))
