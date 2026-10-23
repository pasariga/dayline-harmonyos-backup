from pathlib import Path
import hashlib, json, runpy, re

OUT = Path(__file__).parent
h = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'))
def digest(rows):
    return hashlib.sha256(json.dumps(rows, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
state = h['snapshot']()
assert not state['deadlines'] and not state['deadline_subtasks'], 'Protect existing data before UI acceptance'
(OUT / 'before-tables.json').write_text(json.dumps({k:{'count':len(v),'sha256':digest(v)} for k,v in state.items()},indent=2),encoding='utf-8')
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
for name in ['ddl_notification_settings','dayline_app_settings','dayline_overdue_choices']:
    h['call']('file','recv',base+name,str(OUT/(name+'.before.xml')))
protected = ['AppScope/app.json5','build-profile.json5','entry/build-profile.json5',
 'entry/src/main/module.json5','entry/src/main/resources/base/profile/backup_config.json']
protected += [str(p) for p in Path('entry/src/main/ets/services').glob('*.ets')]
(OUT/'source-before.json').write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in protected},indent=2),encoding='utf-8')
print('Baseline captured: eight table hashes and original settings; no active records.')
