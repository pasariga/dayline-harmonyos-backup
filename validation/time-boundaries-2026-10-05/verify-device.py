from pathlib import Path
import runpy,json,hashlib,sys
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
state=h['snapshot']()
owned=[r for r in state['deadlines'] if r['name'].startswith('Time-')]
manifest=OUT/'fixture-manifest.json'
prior=json.loads(manifest.read_text()) if manifest.exists() else {}
for row in owned:
    prior.setdefault(row['id'],{k:row[k] for k in ['deadline_at','deadline_date','deadline_time']})
manifest.write_text(json.dumps(prior,indent=2),encoding='utf-8')
before=json.loads((OUT/'before-tables.json').read_text())
results={}
for table,rows in state.items():
    original=[r for r in rows if r.get('deadline_id',r.get('id','')) not in prior]
    assert len(original)==before[table]['count'] and digest(original)==before[table]['sha256'], table+' originals changed'
    results[table]={'original_count':len(original),'current_count':len(rows),'original_sha256_preserved':True}
if len(sys.argv)>1 and sys.argv[1]=='final':
    assert not state['deadlines'] and not state['deadline_subtasks'] and not state['deadline_reminder_states']
    protected=json.loads((OUT/'protected-before.json').read_text())
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in protected.items())
    assert h['sql']('PRAGMA user_version;PRAGMA integrity_check;')=='8\nok'
    assert h['sql']("SELECT count(*) FROM sqlite_master WHERE type='trigger';")=='0'
    results.update({'protected_files':len(protected),'database_version':8,'integrity_check':'ok','triggers':0})
(OUT/('preservation-final.json' if len(sys.argv)>1 else 'device-progress.json')).write_text(json.dumps(results,indent=2),encoding='utf-8')
print(json.dumps([{k:r[k] for k in ['id','name','deadline_at','deadline_date','deadline_time']} for r in owned]))
print(json.dumps(results))
