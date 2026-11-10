import sys, os
from pypdf import PdfReader

for src in sys.argv[1:]:
    name = os.path.basename(src)
    try:
        r = PdfReader(src)
        pages = []
        for p in r.pages:
            try:
                pages.append(p.extract_text() or "")
            except Exception as e:
                pages.append("")
        txt = "\n\n---PAGE---\n\n".join(pages)
        out = os.path.join(r"D:\Work\WorkBuddy_File\account\docs\reference\bills", name.replace(".pdf", ".txt"))
        with open(out, "w", encoding="utf-8") as f:
            f.write(txt)
        print("=====", name, "pages=", len(r.pages), "chars=", len(txt))
        head = "\n".join([l for l in txt.splitlines() if l.strip()][:45])
        print(head)
        print()
    except Exception as e:
        print("=====", name, "FAIL", e)
