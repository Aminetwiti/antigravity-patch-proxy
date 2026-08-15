# protodump7.py — decode the REAL IDE-created session's step_payload to extract the exact cascade_config layout
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

def walk(b, indent=0, maxdepth=6):
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

# real IDE sessions: pick a couple of recent conversation DBs
dbs = glob.glob(r"C:\Users\amine\.gemini\antigravity\conversations\*.db")
for db in dbs:
    name = os.path.basename(db)
    # skip daemon-test sessions we know about
    if name.startswith(("0e6dbe7a", "2947da31")):
        continue
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        n = c.execute("SELECT COUNT(*) FROM steps").fetchone()[0]
        if n == 0:
            continue
        row = c.execute("SELECT idx, step_type, step_payload FROM steps ORDER BY idx DESC LIMIT 1").fetchone()
        print(f"### {name} steps={n} newest idx={row[0]} type={row[1]} payload={len(row[2])}B")
        walk(row[2], maxdepth=4)
        print()
        c.close()
        if dbs.index(db) >= 3:
            break
    except Exception as e:
        print(f"### {name}: {e}")
