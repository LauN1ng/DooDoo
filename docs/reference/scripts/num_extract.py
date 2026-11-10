import sys, zipfile, re


def snappy_decompress(data):
    i = 0
    shift = 0
    length = 0
    while True:
        b = data[i]
        i += 1
        length |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    out = bytearray()
    n = len(data)
    while i < n:
        tag = data[i]
        i += 1
        t = tag & 0x03
        if t == 0:
            ln = tag >> 2
            if ln < 60:
                ln += 1
            else:
                nb = ln - 59
                ln = int.from_bytes(data[i:i + nb], "little")
                i += nb
                ln += 1
            out += data[i:i + ln]
            i += ln
        else:
            if t == 1:
                ln = ((tag >> 2) & 0x07) + 4
                off = ((tag >> 5) << 8) | data[i]
                i += 1
            elif t == 2:
                ln = (tag >> 2) + 1
                off = int.from_bytes(data[i:i + 2], "little")
                i += 2
            else:
                ln = (tag >> 2) + 1
                off = int.from_bytes(data[i:i + 4], "little")
                i += 4
            start = len(out) - off
            for k in range(ln):
                out.append(out[start + k])
    return bytes(out)


UTF8_RUN = re.compile(
    rb"(?:[\x20-\x7E]|[\xC2-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF4][\x80-\xBF]{3}){2,}"
)

src = sys.argv[1]
dst = sys.argv[2]
z = zipfile.ZipFile(src)
lines = []
for name in z.namelist():
    if not name.endswith(".iwa"):
        continue
    raw = z.read(name)
    i = 0
    while i + 4 <= len(raw):
        typ = raw[i]
        ln = int.from_bytes(raw[i + 1:i + 4], "little")
        payload = raw[i + 4:i + 4 + ln]
        i += 4 + ln
        if typ != 0:
            continue
        try:
            dec = snappy_decompress(payload)
        except Exception:
            continue
        for m in UTF8_RUN.finditer(dec):
            try:
                s = m.group().decode("utf-8")
            except Exception:
                continue
            if len(s) >= 2:
                lines.append(s)

seen = set()
uniq = []
for s in lines:
    if s in seen:
        continue
    seen.add(s)
    uniq.append(s)

with open(dst, "w", encoding="utf-8") as f:
    f.write("\n".join(uniq))
print("strings=", len(uniq))
