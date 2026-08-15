import os
import glob
import json

home = os.path.expanduser('~')
agy_dir = os.path.join(home, '.gemini', 'antigravity')
projects_dir = os.path.join(home, '.gemini', 'config', 'projects')
annotations_dir = os.path.join(agy_dir, 'annotations')

# 1. Load official projects
projects = {}
for p in glob.glob(os.path.join(projects_dir, '*.json')):
    if 'outside-of-project' in p: continue
    with open(p, 'r') as f:
        d = json.load(f)
        pid = d.get('id')
        name = d.get('name')
        uri = d.get('projectResources', {}).get('resources', [{}])[0].get('gitFolder', {}).get('folderUri', '')
        projects[pid] = {'name': name, 'uri': uri, 'sessions': []}

# 2. Check all annotations
active_cids = set()
archived_cids = set()

for p in glob.glob(os.path.join(annotations_dir, '*.pbtxt')):
    cid = os.path.splitext(os.path.basename(p))[0]
    with open(p, 'r') as f:
        text = f.read()
    if 'archived: true' in text or 'archived:true' in text:
        archived_cids.add(cid)
    else:
        active_cids.add(cid)

print(f"Total annotations: {len(active_cids) + len(archived_cids)}")
print(f"Active conversations (not archived): {len(active_cids)}")
print(f"Archived conversations: {len(archived_cids)}")

print("\n=== ACTIVE CONVERSATIONS (EXACT ANTIGRAVITY 2.0 SIDEBAR) ===")
for cid in sorted(active_cids):
    # read transcript first line
    tp = os.path.join(agy_dir, 'brain', cid, '.system_generated', 'logs', 'transcript.jsonl')
    title = ""
    ws = ""
    if os.path.exists(tp):
        with open(tp, 'r', encoding='utf-8') as f:
            for line in f:
                d = json.loads(line)
                if d.get('type') == 'USER_INPUT' and not title:
                    title = d.get('content', '')[:60].replace('\n', ' ')
                if 'workspace' in d.get('content', '').lower() and not ws:
                    ws = d.get('content', '')[:80]
    print(f"Active CID: {cid} | Title: {title}")
