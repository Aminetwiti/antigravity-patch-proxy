# db_check2.py — read-only step count + schema peek
import sqlite3

db = r"C:\Users\amine\.gemini\antigravity\conversations\0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f.db"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
print("steps:", c.execute("SELECT COUNT(*) FROM steps").fetchone()[0])
cols = [r[1] for r in c.execute("PRAGMA table_info(steps)")]
print("columns:", cols)
print("rows:")
for r in c.execute("SELECT * FROM steps ORDER BY rowid DESC LIMIT 3"):
    print("  ", r)
