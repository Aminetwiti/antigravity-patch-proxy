# protodump5.py — decode the #19 msg(93) inside #30 of step_payload with full bytes
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

def dump(b, indent=0, maxdepth=6):
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
                print("  " * indent + f"#{f} str({ln})={data[:80]!r}")
            elif len(data) <= 8:
                print("  " * indent + f"#{f} bytes({ln})={data.hex()}")
            else:
                print("  " * indent + f"#{f} msg({ln})")
                if indent < maxdepth:
                    dump(data, indent + 2, maxdepth)
        else:
            print("  " * indent + f"#{f} wt={wt} raw={b[i:i+40].hex()}")
            i += 1  # skip one byte and continue best-effort
            # For wt=4 (groups) there is an end-group tag; just stop
            break

row = c.execute("SELECT step_payload FROM steps WHERE idx=3").fetchone()
payload = row[0]
# find #30 msg
r = find_field(payload, 30)
print("field 30:", r[0], len(r[1]) if r[0] == "bytes" else r[1])
inner = r[1]
# find #19 in inner
r19 = find_field(inner, 19)
print("field 30.19:", r19[0], len(r19[1]) if r19[0] == "bytes" else r19[1])
if r19[0] == "bytes":
    print("=== 30.19 msg(93) tree ===")
    dump(r19[1], maxdepth=8)
    print("=== raw hex ===")
    print(r19[1].hex())
