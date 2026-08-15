import os, json, glob

cid = 'a700c4a7-97fb-4ab7-be4a-0d55f0f9fff8'
base = os.path.expanduser(f'~/.gemini/antigravity/brain/{cid}/.system_generated/logs/')
tf = os.path.join(base, 'transcript_full.jsonl')
if os.path.exists(tf):
    with open(tf, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        print(f"Total lines for {cid}: {len(lines)}")
        for l in lines[-10:]:
            d = json.loads(l)
            c = d.get('content', '')
            th = d.get('thinking', '')
            print(f"step={d.get('step_index')} type={d.get('type')} src={d.get('source')} content={repr(c[:60])} th={repr(th[:60])}")
else:
    print(f"Transcript for {cid} not found at {tf}")
