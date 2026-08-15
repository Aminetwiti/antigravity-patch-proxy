import json, os, re
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
# All USER_INPUT entries
for i, l in enumerate(lines):
    d = json.loads(l)
    if d.get('type') == 'USER_INPUT':
        c = d.get('content', '')
        m = re.search(r'<USER_REQUEST>(.*?)</USER_REQUEST>', c, re.S)
        inner = m.group(1).strip()[:100] if m else c[:100]
        print(f'line {i}: step={d.get("step_index")} src={d.get("source")} content_len={len(c)} inner={inner.encode("ascii","replace").decode("ascii")}')
