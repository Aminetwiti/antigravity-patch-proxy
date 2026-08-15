import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
for i in [140, 199]:
    d = json.loads(lines[i])
    c = d.get('content', '')
    print(f'=== line {i} (step {d.get("step_index")}) content raw ===')
    print(c[:600].encode('ascii', 'replace').decode('ascii'))
    print()
