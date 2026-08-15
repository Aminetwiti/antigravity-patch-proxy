# protodump4.py — full field tree of step_payload for idx=3 (the "Greeting Via Terminal ConnectRPC" session)
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

def walk(b, indent=0, maxdepth=8):
    i = 0
    while i < len(b):
        key, i = rv(b, i)
        fnum, wt = key >> 3, key & 7
        if wt == 0:
            v, i = rv(b, i)
            print("  " * indent + f"#{fnum} varint={v}")
        elif wt == 2:
            ln, i = rv(b, i)
            data = b[i : i + ln]
            i += ln
            printable = all(32 <= x < 127 or x in (10, 13, 9) for x in data[:200])
            if printable and len(data) > 2:
                print("  " * indent + f"#{fnum} str({ln})={data[:80]!r}")
            elif len(data) <= 8:
                print("  " * indent + f"#{fnum} bytes({ln})={data.hex()}")
            else:
                print("  " * indent + f"#{fnum} msg({ln})")
                if indent < maxdepth:
                    walk(data, indent + 2, maxdepth)
        else:
            print("  " * indent + f"#{fnum} wt={wt} (unsupported)")
            break

row = c.execute("SELECT idx, step_type, metadata, step_payload FROM steps ORDER BY rowid DESC LIMIT 1").fetchone()
print(f"idx={row[0]} step_type={row[1]}")
print("=== step_payload full tree ===")
walk(row[3], maxdepth=10)
