import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript_full.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
for i, l in enumerate(lines):
    d = json.loads(l)
    if d.get('source') == 'MODEL' and d.get('type') == 'PLANNER_RESPONSE':
        print(f'line {i}: content={len(d.get("content",""))} thinking={len(d.get("thinking",""))} tool_calls={len(d.get("tool_calls",[]))}')
