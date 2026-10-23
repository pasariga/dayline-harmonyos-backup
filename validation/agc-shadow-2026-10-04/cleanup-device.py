"""Remove only this task's known synthetic receiver files, never the main ddl.db."""
from pathlib import Path
import runpy, re

out = Path(__file__).parent
h = runpy.run_path(str(out.parent / 'legacy-reader-2026-10-04/device-check.py'), run_name='shadow_helper')
call = h['call']
root = '/data/app/el2/100/database/com.gary.ddl/entry/rdb'
call('shell', 'aa force-stop com.gary.ddl')
files = call('shell', 'find ' + root + '/agc-inspection -maxdepth 2 -type f').splitlines()
pattern = re.escape(root) + r'/agc-inspection/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/ddl\.db(?:-(?:wal|shm|dwr|compare))?'
assert all(re.fullmatch(pattern, p) for p in files), 'Unexpected inspection path; preserve it.'
directories = sorted({p.rsplit('/', 1)[0] for p in files})
for p in files:
    call('shell', 'rm ' + p)
for p in directories:
    call('shell', 'rmdir ' + p)
call('shell', 'rmdir ' + root + '/agc-inspection')
synthetic = call('shell', 'find ' + root + ' -maxdepth 1 -type f -name "shadow-native.db*"').splitlines()
assert all(re.fullmatch(re.escape(root) + r'/shadow-native\.db(?:-(?:wal|shm|dwr|compare))?', p) for p in synthetic)
for p in synthetic:
    call('shell', 'rm ' + p)
call('shell', 'aa start -a EntryAbility -b com.gary.ddl')
result = f'PASS: removed {len(files)} empty encrypted receiver files in {len(directories)} validated directories and {len(synthetic)} synthetic-source files. Main ddl.db never targeted.\n'
(out / 'cleanup-result.txt').write_text(result, encoding='utf-8')
print(result)
