import glob
import os
import re

leveldb_dir = r'C:\Users\amine\AppData\Roaming\Antigravity\Local Storage\leveldb'
files = glob.glob(os.path.join(leveldb_dir, '*.*'))

print(f"Scanning {len(files)} files in LevelDB...")
for fpath in files:
    try:
        with open(fpath, 'rb') as f:
            data = f.read()
            # find keys and JSON strings
            matches = re.findall(rb'(_https?://[^\x00]+|[\x20-\x7e]{10,})', data)
            print(f"\n--- File {os.path.basename(fpath)} (size: {len(data)}) ---")
            for m in matches:
                m_str = m.decode('utf-8', errors='ignore')
                if 'cascade' in m_str.lower() or 'conversation' in m_str.lower() or 'project' in m_str.lower() or 'antigravity' in m_str.lower():
                    print("  ", m_str[:150])
    except Exception as e:
        print(f"Error {fpath}: {e}")
