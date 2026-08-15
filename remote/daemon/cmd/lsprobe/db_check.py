# db check
import sqlite3, sys

db = r"C:\Users\amine\.gemini\antigravity\conversations\0e6dbe7a-cb29-4efe-9631-2ed23d3f0d3f.db"
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
print("steps:", c.execute("SELECT COUNT(*) FROM steps").fetchone()[0])
for r in c.execute("SELECT idx, step_type, created_at FROM steps ORDER BY idx DESC LIMIT 5"):
    print(r)

