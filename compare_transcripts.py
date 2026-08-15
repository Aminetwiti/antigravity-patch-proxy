import json, os
cid = 'e7e59f3a-342c-480e-8587-104674f56d4f'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
with open(os.path.join(base, 'transcript.jsonl'), 'r', encoding='utf-8') as f:
    lines = f.readlines()
print('total lines transcript.jsonl:', len(lines))
# Compare a few lines with transcript_full
for i in [2, 137, 139, 178, 201, 206]:
    if i >= len(lines):
        continue
    d = json.loads(lines[i])
    print(f'line {i}: keys={list(d.keys())} content={len(d.get("content",""))} thinking={len(d.get("thinking",""))} truncated={d.get("is_truncated")}')
