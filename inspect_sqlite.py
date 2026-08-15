import sqlite3, os

cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
db_path = os.path.expanduser(f'~/.gemini/antigravity/conversations/{cid}.db')
print('DB path exists:', os.path.exists(db_path))

if os.path.exists(db_path):
    conn = sqlite3.connect(db_path)
    tables = [t[0] for t in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    print('Tables:', tables)
    for t in tables:
        cols = [c[1] for c in conn.execute(f'PRAGMA table_info({t})').fetchall()]
        count = conn.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]
        print(f'\n=== {t} ({count} rows) ===')
        print('  cols:', cols)
        if count > 0:
            row = conn.execute(f'SELECT * FROM {t} LIMIT 1').fetchone()
            for c, v in zip(cols, row):
                s = str(v)
                print(f'  {c}: {s[:150]}')
