import os
import glob
import sqlite3
import re
import json

home = os.path.expanduser('~')
convos_dir = os.path.join(home, '.gemini', 'antigravity', 'conversations')
annotations_dir = os.path.join(home, '.gemini', 'antigravity', 'annotations')

print("=== RECENT CONVERSATION ANNOTATIONS ===")
for p in sorted(glob.glob(os.path.join(annotations_dir, '*.pbtxt')), key=os.path.getmtime, reverse=True):
    cid = os.path.splitext(os.path.basename(p))[0]
    with open(p, 'r') as f:
        content = f.read().strip()
    print(f"  {cid}: {content}")

print("\n=== ACTIVE CONVERSATION DBS ===")
for p in sorted(glob.glob(os.path.join(convos_dir, '*.db')), key=os.path.getmtime, reverse=True)[:15]:
    cid = os.path.splitext(os.path.basename(p))[0]
    conn = sqlite3.connect(p)
    # check tables
    tables = [t[0] for t in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    meta_blob = None
    if 'trajectory_metadata_blob' in tables:
        row = conn.execute("SELECT metadata_blob FROM trajectory_metadata_blob WHERE key='main'").fetchone()
        if row:
            meta_blob = row[0]
            
    strs = []
    if meta_blob:
        strs = [s.decode('utf-8', errors='ignore') for s in re.findall(rb'[\x20-\x7e]{3,}', meta_blob)]
    
    # check first step / user prompt
    first_prompt = ""
    transcript_p = os.path.join(home, '.gemini', 'antigravity', 'brain', cid, '.system_generated', 'logs', 'transcript.jsonl')
    if os.path.exists(transcript_p):
        with open(transcript_p, 'r', encoding='utf-8') as f:
            for l in f:
                d = json.loads(l)
                if d.get('type') == 'USER_INPUT':
                    first_prompt = d.get('content', '')[:60]
                    break
    
    print(f"CID: {cid} | Workspace/Strings: {strs[:2]} | Prompt: {first_prompt}")
