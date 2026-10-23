from pathlib import Path
import json,runpy,hashlib,xml.etree.ElementTree as ET
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
owned=json.loads((OUT/'fixture-manifest.json').read_text(encoding='utf-8'))
state=h['snapshot']();before=json.loads((OUT/'before-tables.json').read_text())
result={}
for table,rows in state.items():
 original=[r for r in rows if r.get('deadline_id',r.get('id','')) not in owned and
           not str(r.get('deadline_id',r.get('id',''))).startswith('notification-acceptance-')]
 assert len(original)==before[table]['count'] and digest(original)==before[table]['sha256'],table+' original rows changed'
 result[table]={'original_count':len(original),'current_count':len(rows),'original_sha256_preserved':True}
for table in ['deadlines','deadline_subtasks','deadline_reminder_states']:
 assert not state[table], 'Unexpected active data; do not erase it.'
protected=json.loads((OUT/'protected-before.json').read_text())
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in protected.items())
assert h['sql']('PRAGMA user_version;PRAGMA integrity_check;')=='8\nok'
assert h['sql']("SELECT count(*) FROM sqlite_master WHERE type='trigger';")=='0'
result['protected_files']=len(protected);result['database_version']=8;result['integrity_check']='ok';result['triggers']=0
(OUT/'preservation-final.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result),flush=True)
