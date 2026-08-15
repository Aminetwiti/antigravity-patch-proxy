import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript_full.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
for i in [137, 139, 178, 201, 206]:
    d = json.loads(lines[i])
    print(f'=== line {i}: source={d.get("source")} type={d.get("type")} ===')
    c = d.get('content', '')[:300].encode('ascii', 'replace').decode('ascii')
    print('content:', c)
    print('status:', d.get('status'))
    print()
