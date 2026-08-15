import json, os
tp = os.path.expanduser('~/.gemini/antigravity/brain/e7e59f3a-342c-480e-8587-104674f56d4f/.system_generated/logs/transcript.jsonl')
with open(tp, 'r', encoding='utf-8') as f:
    lines = f.readlines()
d = json.loads(lines[2])
print('=== PLANNER_RESPONSE keys:', list(d.keys()))
print('content present:', 'content' in d, '| len:', len(d.get('content','')))
print('thinking len:', len(d.get('thinking','')))
tc = d.get('tool_calls', [])
print('tool_calls count:', len(tc))
if tc: print('first tool_call keys:', list(tc[0].keys()))
print()
for i, l in enumerate(lines[:40]):
    try: dd = json.loads(l)
    except: continue
    c = dd.get('content', '')
    if dd.get('source') == 'MODEL' and len(c) > 50:
        src = dd.get('source')
        typ = dd.get('type')
        print(f'ligne {i}: source={src} type={typ} content_len={len(c)}')
        print('   head:', c[:100].replace(chr(10), ' '))
