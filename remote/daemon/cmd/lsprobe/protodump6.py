# protodump6.py — dump idx 4 & 5 (the new steps created by the accepted prompt)
import sqlite3

db = r"C:\Users\amine\.gemini\antigravity\conversations\0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f.db"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)

def rv(b, i):
    v = 0
    s = 0
    while True:
        x = b[i]
        i += 1
        v |= (x & 0x7F) << s
        if not (x & 0x80):
            return v, i
        s += 7

def find_texts(b, out, depth=0, maxdepth=7):
    i = 0
    while i < len(b):
        key, i = rv(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            _, i = rv(b, i)
        elif wt == 2:
            ln, i = rv(b, i)
            data = b[i : i + ln]
            i += ln
            printable = all(32 <= x < 127 or x in (10, 13, 9) for x in data[:200])
            if printable and len(data) > 2:
                out.append((depth, f, data[:120]))
            elif not printable and len(data) > 8 and depth < maxdepth:
                find_texts(data, out, depth + 1, maxdepth)
        else:
            break

for idx in (4, 5):
    row = c.execute("SELECT idx, step_type, step_payload FROM steps WHERE idx=?", (idx,)).fetchone()
    print(f"=== idx={row[0]} step_type={row[1]} payload={len(row[2])}B ===")
    out = []
    find_texts(row[2], out)
    seen = set()
    for d, f, t in out:
        key = (d, t[:40])
        if key in seen:
            continue
        seen.add(key)
        print(f"  d{d} f{f}: {t!r}")
