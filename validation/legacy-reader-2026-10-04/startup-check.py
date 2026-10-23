from pathlib import Path
import runpy, json, copy, time, sys
h=runpy.run_path(str(Path(__file__).with_name('device-check.py')),run_name='helper')
call,sql,snapshot,restart,capture,quote=[h[k] for k in ['call','sql','snapshot','restart','capture','quote']]
OUT=Path(__file__).parent
ACCOUNT='fixture-startup-reader'
IDS=['startup-reader-deleted','startup-reader-pending','startup-reader-good']
IDS.append('startup-reader-copy')
def event(eid,did,parents,a):
    e=dict(version=2,id=eid,deadlineId=did,parents=parents,removedTasks=[],deleted=a is None,legacy=False)
    if a is not None:e['snapshot']=a
    return e
def put(e):
    return 'INSERT OR IGNORE INTO ddl_sync_events(id,deadline_id,payload) VALUES('+','.join(quote(v) for v in [e['id'],e['deadlineId'],json.dumps(e,ensure_ascii=False,separators=(',',':'))])+');'
def old(did,name):
    return dict(id=did,name=name,deadline_date='2026-11-01',deadline_time='18:00',deadline_at=1793527200000,
        created_at=1791000000000,completed=0,estimated_hours=10,progress_mode='automatic',reminder_offset_minutes=0)
cmd=sys.argv[1]
if cmd=='copy-seed':
    call('shell','aa force-stop com.gary.ddl')
    assert sql('SELECT count(*) FROM deadlines;SELECT count(*) FROM ddl_sync_owner;SELECT count(*) FROM ddl_legacy_imports;')=='0\n0\n0'
    did='startup-reader-copy'
    tasks=[dict(id=did+'-p',deadline_id=did,title='准备复习',completed=0,created_at=1,parent_id='',sort_order=0),
        dict(id=did+'-t1',deadline_id=did,title='整理提纲',completed=1,created_at=2,parent_id=did+'-p',sort_order=0),
        dict(id=did+'-t2',deadline_id=did,title='完成练习',completed=0,created_at=3,parent_id=did+'-p',sort_order=1)]
    bad=old(did+'-bad','坏格式隔离');bad['created_at']=-1
    data=dict(deadlines=[old(did,'分页恢复验收'),bad],tasks=tasks,
        manifests=[dict(deadlineId=did,taskIds=[t['id'] for t in tasks]),dict(deadlineId=bad['id'],taskIds=[])])
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':'))
    sql('BEGIN;INSERT INTO ddl_sync_owner VALUES(\'owner\','+quote(ACCOUNT)+');'+
        'INSERT INTO ddl_legacy_imports(id,kind,account_id,source_id,payload,complete,writers_stopped,journal_complete,status) VALUES('+','.join(quote(v) for v in ['startup-reader-copy-batch','batch',ACCOUNT,'startup-reader-copy-frozen',payload])+",1,1,1,'staged');COMMIT;")
    restart();assert sql('SELECT id,estimated_hours,remaining_state FROM deadlines;')==did+'|10.0|unknown'
elif cmd=='seed':
    call('shell','aa force-stop com.gary.ddl')
    assert sql('SELECT count(*) FROM deadlines;SELECT count(*) FROM ddl_sync_owner;SELECT count(*) FROM ddl_legacy_imports;')=='0\n0\n0'
    native=json.loads((OUT/'native-test-isolated-state.json').read_text(encoding='utf-8'))
    root=next(json.loads(r['payload']) for r in native['ddl_sync_archive'] if r['id'].endswith('-root'))
    template=root['snapshot']
    def aggregate(did,name):
        a=copy.deepcopy(template);a['deadline']['id']=did;a['deadline']['name']=name;a['deadline']['progress']=0;a['tasks']=[]
        return a
    dead=aggregate(IDS[0],'已删除的旧项目')
    child=aggregate(IDS[1],'尚缺完整历史的项目')
    events=[event('startup-reader-root',IDS[0],[],dead),event('startup-reader-tomb',IDS[0],['startup-reader-root'],None),
        event('startup-reader-child',IDS[1],['startup-reader-parent'],child)]
    tasks=[dict(id='startup-reader-p',deadline_id=IDS[2],title='准备复习',completed=0,created_at=1,parent_id='',sort_order=0),
        dict(id='startup-reader-t1',deadline_id=IDS[2],title='整理提纲',completed=1,created_at=2,parent_id='startup-reader-p',sort_order=0),
        dict(id='startup-reader-t2',deadline_id=IDS[2],title='完成练习',completed=0,created_at=3,parent_id='startup-reader-p',sort_order=1)]
    data=dict(deadlines=[old(IDS[0],'旧云仍在'),old(IDS[1],'旧云名称'),old(IDS[2],'分页恢复验收')],tasks=tasks,
        manifests=[dict(deadlineId=did,taskIds=[t['id'] for t in tasks if t['deadline_id']==did]) for did in IDS])
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':'))
    statement='BEGIN;INSERT INTO ddl_sync_owner VALUES(\'owner\','+quote(ACCOUNT)+');'+''.join(put(e) for e in events)
    statement+='INSERT INTO ddl_legacy_imports(id,kind,account_id,source_id,payload,complete,writers_stopped,journal_complete,status) VALUES('+','.join(quote(v) for v in ['startup-reader-batch','batch',ACCOUNT,'startup-reader-frozen',payload])+",1,1,1,'staged');COMMIT;"
    sql(statement);(OUT/'startup-fixture.json').write_text(json.dumps(dict(data=data,events=events),ensure_ascii=False,indent=2),encoding='utf-8')
    restart();state=snapshot();(OUT/'startup-held-state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
    assert [d['id'] for d in state['deadlines']]==[IDS[2]],state['deadlines']
    assert state['deadlines'][0]['progress']==50 and state['deadlines'][0]['estimated_hours']==10 and state['deadlines'][0]['remaining_state']=='unknown'
    assert len(state['deadline_subtasks'])==3
    assert not any(e['id']=='legacy-v2:'+did for e in state['ddl_sync_events'] for did in IDS[:2])
    assert any(i['id']==IDS[1] and i['detail']=='["pending"]' for i in state['ddl_sync_issues'])
    assert any(r['kind']=='batch' and r['status']=='quarantined' for r in state['ddl_legacy_imports'])
    assert any(r['kind']=='item' and r['id']=='item:'+IDS[0] and r['status']=='deleted' for r in state['ddl_legacy_imports'])
    (OUT/'startup-order.txt').write_text('PASS: deleted root suppressed without a legacy baseline; missing history quarantined before import; independent tree imported as 1/2 leaf tasks, total10, remaining unknown.\n',encoding='utf-8')
    capture('startup-good-home');restart();assert snapshot()==state,'Restart added or changed rows'
elif cmd=='complete':
    call('shell','aa force-stop com.gary.ddl')
    fixture=json.loads((OUT/'startup-fixture.json').read_text(encoding='utf-8'))
    parent=event('startup-reader-parent',IDS[1],[],fixture['events'][2]['snapshot'])
    sql(put(parent));restart();state=snapshot()
    assert any(d['id']==IDS[1] and d['name']=='尚缺完整历史的项目' for d in state['deadlines'])
    assert not any(i['id']==IDS[1] for i in state['ddl_sync_issues'])
    assert not any(e['id']=='legacy-v2:'+IDS[1] for e in state['ddl_sync_events'])
    (OUT/'startup-complete-state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'startup-history-retry.txt').write_text('PASS: late missing parent restored the full current project; old quarantined business input did not overwrite it or add a baseline.\n',encoding='utf-8')
    capture('startup-recovered-home')
elif cmd=='cleanup':
    call('shell','aa force-stop com.gary.ddl');state=snapshot();lines=[]
    for did in IDS:
        history=[json.loads(r['payload']) for r in state['ddl_sync_archive'] if r['deadline_id']==did]
        if not history or any(e['deleted'] for e in history):continue
        parents={p for e in history for p in e['parents']};heads=sorted(e['id'] for e in history if e['id'] not in parents)
        lines.append(put(event('startup-reader-cleanup-'+did,did,heads,None)))
    sql('BEGIN;'+''.join(lines)+'COMMIT;');restart()
    assert not snapshot()['deadlines']
    sql('BEGIN;DELETE FROM ddl_legacy_imports WHERE account_id='+quote(ACCOUNT)+';DELETE FROM ddl_sync_owner WHERE account_id='+quote(ACCOUNT)+';COMMIT;')
    restart()
