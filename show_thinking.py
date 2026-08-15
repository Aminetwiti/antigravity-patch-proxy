import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript_full.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
for i in [2, 11, 19, 33, 201]:
    d = json.loads(lines[i])
    t = d.get('thinking', '')[:500].encode('ascii', 'replace').decode('ascii')
    print(f'=== line {i}: status={d.get("status")} ===')
    print(t)
    print()
