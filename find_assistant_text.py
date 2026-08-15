import sqlite3, os, re

cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
db_path = os.path.expanduser(f'~/.gemini/antigravity/conversations/{cid}.db')
conn = sqlite3.connect(db_path)

# Look for markdown-ish text in ALL steps payloads (long readable strings)
print('=== Searching for assistant markdown text in steps ===')
rows = conn.execute('SELECT idx, step_type, step_payload FROM steps ORDER BY idx').fetchall()
for idx, st, payload in rows:
    if not payload: continue
    strs = [s.decode('utf-8', errors='ignore') for s in re.findall(rb'[\x20-\x7e]{15,}', payload)]
    for s in strs:
        ls = s.strip()
        if ls.startswith('#') or ls.startswith('Voici') or ls.startswith("J'ai") or ls.startswith('Je vais') or ls.startswith('##') or ls.startswith('|') or '```' in ls:
            print(f'  step {idx} (type {st}): {ls[:150]}')
            break
