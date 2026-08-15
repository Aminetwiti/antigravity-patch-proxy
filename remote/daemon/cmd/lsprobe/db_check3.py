# db_check3.py — read-only: rows + clean column dump
import sqlite3

db = r"C:\Users\amine\.gemini\antigravity\conversations\0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f.db"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
print("steps:", c.execute("SELECT COUNT(*) FROM steps").fetchone()[0])
cols = [r[1] for r in c.execute("PRAGMA table_info(steps)")]
print("columns:", cols)
print("--- newest rows (per-column length) ---")
for r in c.execute("SELECT * FROM steps ORDER BY rowid DESC LIMIT 3"):
    print([f"{len(v)}" if isinstance(v, bytes) else v for v in r])
print("--- newest row decoded strings ---")
r = c.execute("SELECT * FROM steps ORDER BY rowid DESC LIMIT 1").fetchone()
for name, v in zip(cols, r):
    if isinstance(v, bytes):
        try:
            print(f"{name}: {v[:400]!r}")
        except Exception as e:
            print(f"{name}: <{len(v)} bytes, undecodable>")
    else:
        print(f"{name}: {v!r}")
