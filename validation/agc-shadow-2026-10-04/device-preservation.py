"""Local verification only. Export aggregate counts/hashes, never row contents."""
from pathlib import Path
import runpy, json, hashlib, sys, time

OUT = Path(__file__).parent
helper = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'), run_name='shadow_helper')
call, sql, snapshot = helper['call'], helper['sql'], helper['snapshot']

def digest():
    state = snapshot()  # retained only in process memory
    return {table: {'count': len(rows), 'sha256': hashlib.sha256(
        json.dumps(sorted(rows, key=lambda r: r['id']), sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
        for table, rows in state.items()}

if __name__ == '__main__':
    step = sys.argv[1]
    call('shell', 'aa force-stop com.gary.ddl')
    current = digest()
    if step == 'before':
        (OUT / 'main-before.json').write_text(json.dumps(current, indent=2), encoding='utf-8')
    else:
        before = json.loads((OUT / 'main-before.json').read_text(encoding='utf-8'))
        assert current == before, 'Main database differs; inspect privately before continuing.'
        (OUT / ('main-' + step + '.json')).write_text(json.dumps(current, indent=2), encoding='utf-8')
    print('Main database aggregate verification:', step, 'PASS')
    print({table: detail['count'] for table, detail in current.items()})
    print('Version / integrity:', sql('PRAGMA user_version; PRAGMA integrity_check;'))
    call('shell', 'aa start -a EntryAbility -b com.gary.ddl')
