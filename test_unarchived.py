import os
import glob
import json

home = os.path.expanduser('~')
agy_dir = os.path.join(home, '.gemini', 'antigravity')
projects_dir = os.path.join(home, '.gemini', 'config', 'projects')
annotations_dir = os.path.join(agy_dir, 'annotations')

archived = set()
for p in glob.glob(os.path.join(annotations_dir, '*.pbtxt')):
    cid = os.path.splitext(os.path.basename(p))[0]
    with open(p, 'r') as f:
        txt = f.read()
        if 'archived: true' in txt or 'archived:true' in txt:
            archived.add(cid)

print(f"Archived conversations count: {len(archived)}")

# Parse projects
projects = []
for p in sorted(glob.glob(os.path.join(projects_dir, '*.json'))):
    if 'outside-of-project' in p: continue
    with open(p, 'r') as f:
        d = json.load(f)
        pname = d.get('name')
        folder_uri = d.get('projectResources', {}).get('resources', [{}])[0].get('gitFolder', {}).get('folderUri', '')
        # normalize
        path = folder_uri.replace('file:///', '').replace('%3A', ':').replace('%20', ' ').replace('\\', '/').lower()
        projects.append({'name': pname, 'path': path, 'sessions': []})

# Scan brain
for bp in glob.glob(os.path.join(agy_dir, 'brain', '*')):
    cid = os.path.basename(bp)
    if cid in archived:
        continue # SKIP ARCHIVED!
    
    tp = os.path.join(bp, '.system_generated', 'logs', 'transcript.jsonl')
    if not os.path.exists(tp):
        continue
    
    # Read title and workspace
    title = ""
    ws = ""
    try:
        with open(tp, 'r', encoding='utf-8') as f:
            for l in f:
                if not l.strip(): continue
                d = json.loads(l)
                if d.get('type') == 'USER_INPUT' and not title:
                    title = d.get('content', '').strip()
                if 'workspace' in str(d).lower() and not ws:
                    ws = str(d)
    except Exception:
        pass
    
    if not title: continue
    ltitle = title.lower()
    if ltitle.startswith(('you are', 'en tant qu', 'system:', 'tu es', '@[', 'analyse en profondeur')):
        continue
    
    # Match to project
    matched = False
    for proj in projects:
        if (proj['path'] and proj['path'] in ws.lower()) or (proj['name'].lower() in ws.lower()) or (proj['name'].lower() in bp.lower()):
            proj['sessions'].append((os.path.getmtime(tp), cid, title[:50]))
            matched = True
            break
    if not matched and 'antigravity-add-model-main' in bp.lower() or 'antigravity-add-model-main' in ws.lower():
        projects[0]['sessions'].append((os.path.getmtime(tp), cid, title[:50]))

print("\n=== FINAL VERIFICATION ACROSS ALL PROJECTS ===")
for proj in projects:
    proj['sessions'].sort(key=lambda x: x[0], reverse=True)
    count = len(proj['sessions'])
    print(f"\n[Project: {proj['name']}] ({count} active conversations):")
    if count == 0:
        print("   └── No conversations yet")
    else:
        for mtime, cid, t in proj['sessions'][:6]:
            print(f"   * [{cid[:8]}] {t.encode('ascii', 'replace').decode('ascii')}")
