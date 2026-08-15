# protodump8.py — dump the FULL cascade_config (#5) of real IDE steps
import sqlite3, glob, os

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

def walk(b, indent=0, maxdepth=10):
    i = 0
    while i < len(b):
        key, i = rv(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = rv(b, i)
            print("  " * indent + f"#{f} varint={v}")
        elif wt == 2:
            ln, i = rv(b, i)
            data = b[i : i + ln]
            i += ln
            printable = all(32 <= x < 127 or x in (10, 13, 9) for x in data[:200])
            if printable and len(data) > 2:
                print("  " * indent + f"#{f} str({ln})={data[:60]!r}")
            elif len(data) <= 8:
                print("  " * indent + f"#{f} bytes({ln})={data.hex()}")
            else:
                print("  " * indent + f"#{f} msg({ln})")
                if indent < maxdepth:
                    walk(data, indent + 2, maxdepth)
        else:
            print("  " * indent + f"#{f} wt={wt}")
            break

def find_field(b, fnum):
    i = 0
    while i < len(b):
        key, i = rv(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = rv(b, i)
            if f == fnum:
                return ("varint", v)
        elif wt == 2:
            ln, i = rv(b, i)
            data = b[i : i + ln]
            i += ln
            if f == fnum:
                return ("bytes", data)
        else:
            return None
    return None

for db in glob.glob(r"C:\Users\amine\.gemini\antigravity\conversations\*.db")[:6]:
    name = os.path.basename(db)
    if name.startswith(("0e6dbe7a", "2947da31")):
        continue
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        row = c.execute("SELECT idx, step_type, step_payload FROM steps ORDER BY idx DESC LIMIT 1").fetchone()
        r = find_field(row[2], 5)
        if r and r[0] == "bytes":
            print(f"### {name} type={row[1]} cascade_config ({len(r[1])}B) ===")
            walk(r[1], maxdepth=10)
            print()
        c.close()
    except Exception as e:
        print(f"### {name}: {e}")
