from pathlib import Path
import runpy,json,hashlib,tempfile
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
run,sql=h['call'],h['sql']
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
if __name__=='__main__':
    state=h['snapshot']()
    assert not state['deadlines'] and not state['deadline_subtasks'] and not state['deadline_reminder_states']
    summary={t:{'count':len(rows),'sha256':digest(rows)} for t,rows in state.items()}
    (OUT/'before-tables.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    old=json.loads((OUT.parent/'overdue-2026-10-04/protected-before.json').read_text())
    allowed=['DeadlineReminderService.ets','NotificationSettingsService.ets']
    paths=[p for p in old if not any(p.endswith(n) for n in allowed)]
    paths += ['entry/src/main/ets/services/'+n+'.ets' for n in ['DeadlineInsightService','DeadlineScheduleService','TodayActionService','DeadlineProgressService','DeadlineOverdueService']]
    (OUT/'protected-before.json').write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths},indent=2),encoding='utf-8')
    base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
    names=run('shell','ls '+base).split()
    saved=[]
    for name in ['ddl_notification_settings','dayline_app_settings']:
        if name in names:
            run('file','recv',base+name,str(OUT/(name+'.before.xml')));saved.append(name)
    (OUT/'before-preferences.json').write_text(json.dumps(saved),encoding='utf-8')
    print(json.dumps(summary)); print(sql('PRAGMA user_version;PRAGMA integrity_check;'))
