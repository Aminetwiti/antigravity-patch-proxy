import sqlite3, os, re
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
db_path = os.path.expanduser(f'~/.gemini/antigravity/conversations/{cid}.db')
conn = sqlite3.connect(db_path)

# Map step types to what they contain: find readable strings per step_type
step_types = conn.execute('SELECT step_type, COUNT(*) FROM steps GROUP BY step_type ORDER BY COUNT(*) DESC').fetchall()
print('Step types distribution:')
for st, cnt in step_types:
    print(f'  type {st}: {cnt}')

# Decode a few payloads for each step type
print('\n=== String samples per step_type ===')
for st, cnt in step_types[:10]:
    rows = conn.execute(f'SELECT idx, step_payload FROM steps WHERE step_type={st} ORDER BY idx LIMIT 2').fetchall()
    for idx, payload in rows:
        strs = [s.decode('utf-8', errors='ignore') for s in re.findall(rb'[\x20-\x7e]{8,}', payload)]
        print(f'--- step {idx} (type {st}) :')
        for s in strs[:6]:
            print('    ', s[:130])
