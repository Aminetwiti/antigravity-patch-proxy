import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
# Show first user-ish lines
for i, l in enumerate(lines[:30]):
    d = json.loads(l)
    src = d.get('source'); typ = d.get('type')
    if src == 'USER_EXPLICIT' or typ == 'USER_INPUT':
        c = d.get('content', '')[:80].encode('ascii', 'replace').decode('ascii')
        print(f'line {i}: src={src} type={typ} content={c}')
print('---')
# What (source, type) pairs exist
types = {}
for l in lines:
    d = json.loads(l)
    key = (d.get('source'), d.get('type'))
    types[key] = types.get(key, 0) + 1
for k, v in sorted(types.items(), key=lambda x: -x[1])[:15]:
    print(k, v)
