import os, json, glob

cands = glob.glob(os.path.expanduser('~/.gemini/antigravity/brain/*/.system_generated/logs/transcript*.jsonl')) + \
        glob.glob(os.path.expanduser('~/.gemini/antigravity-ide/brain/*/.system_generated/logs/transcript*.jsonl'))

print(f"Found {len(cands)} transcripts")
cands.sort(key=lambda x: os.path.getmtime(x), reverse=True)
for c in cands[:6]:
    print(f"\nFile: {c}")
    try:
        with open(c, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            print(f"  Total lines: {len(lines)}")
            for line in lines[-4:]:
                d = json.loads(line)
                print(f"    step={d.get('step_index')} type={d.get('type')} src={d.get('source')} content={repr(d.get('content',''))[:60]} thinking={repr(d.get('thinking',''))[:40]}")
    except Exception as e:
        print(f"  Error: {e}")
