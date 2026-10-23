"""Preserve all baseline history; restore only this run's transient preferences."""
from pathlib import Path
import runpy,json,hashlib,xml.etree.ElementTree as ET
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT/'harness.py'));u=h['u']
owned={r['id'] for r in json.loads((OUT/'owned-fixtures-all.json').read_text(encoding='utf-8'))}
u['run']('shell','aa force-stop com.gary.ddl')
state=h['h']['snapshot']();before=json.loads((OUT/'before-tables.json').read_text())
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
for table,rows in state.items():
 original=[r for r in rows if r.get('deadline_id') not in owned]
 assert len(original)==before[table]['count'] and digest(original)==before[table]['sha256'],table
assert not state['deadlines'] and not state['deadline_subtasks'] and not state['deadline_reminder_states']
assert h['sql']('PRAGMA integrity_check;')=='ok' and h['sql']('PRAGMA user_version;')=='8'
assert h['sql']("SELECT count(*) FROM sqlite_master WHERE type='trigger';")=='0'
def values(p):return {e.attrib['key']:(e.tag,e.attrib.get('value',e.text or '')) for e in ET.parse(p).getroot()}
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
for name in ['dayline_app_settings','ddl_notification_settings','dayline_overdue_choices']:
 prior=OUT/(name+'.before.xml');after=OUT/(name+'.after.xml')
 u['run']('file','recv',base+name,str(after));current,original=values(after),values(prior)
 if name=='dayline_app_settings':
  assert current==original,'Restore App preferences through Settings first';continue
 if name=='ddl_notification_settings':
  transient={'last_activity_at','last_activity_deadline_id','last_plan_date','last_plan_task_ids','risk_marks','last_risk_at'}
  assert {k:v for k,v in current.items() if k not in transient}=={k:v for k,v in original.items() if k not in transient}
  assert current.get('last_activity_deadline_id',('string',''))[1] in owned|{''}
  marks=json.loads(current.get('risk_marks',('string','[]'))[1]);assert not marks or all(r.get('deadlineId') in owned for r in marks)
 else:
  choices=json.loads(current.get('choices',('string','[]'))[1]);assert not choices or all(r.get('id') in owned for r in choices)
 u['run']('file','send',str(prior),base+name)
 u['run']('file','recv',base+name,str(after));assert values(after)==original
result={'original_eight_table_digests_preserved':True,'counts_after':{t:len(rows) for t,rows in state.items()},
 'database_version':8,'integrity_check':'ok','triggers':0,'active_acceptance_data':0,
 'immutable_operation_and_deletion_history_retained':True,'original_preferences_restored':True}
(OUT/'cleanup.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
