from pathlib import Path
import runpy,json,hashlib
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
state=h['snapshot']()
assert not state['deadlines'] and not state['deadline_subtasks'] and not state['deadline_reminder_states'], 'Capture real data safely before proceeding'
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
(OUT/'before-tables.json').write_text(json.dumps({t:{'count':len(v),'sha256':digest(v)} for t,v in state.items()},indent=2),encoding='utf-8')
prior=json.loads((OUT.parent/'notifications-2026-10-04/protected-before.json').read_text())
allowed=['DeadlineInsightService.ets','DeadlineScheduleService.ets','TodayActionService.ets','DeadlineOverdueService.ets']
(OUT/'protected-before.json').write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in prior if not any(p.endswith(n) for n in allowed)},indent=2),encoding='utf-8')
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
for name in ['ddl_notification_settings','dayline_app_settings','dayline_overdue_choices']:
    h['call']('file','recv',base+name,str(OUT/(name+'.before.xml')))
print({t:len(v) for t,v in state.items()});print(h['sql']('PRAGMA user_version;PRAGMA integrity_check;'))
