from pathlib import Path
import json,subprocess,sys,time,uuid,copy,datetime,hashlib,tempfile
HDC=r'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
DB='/data/app/el2/100/database/com.gary.ddl/entry/rdb/ddl.db'
OUT=Path('validation/conflict-recovery-2026-10-03')
def call(*args):
 p=subprocess.run([HDC,'-t','127.0.0.1:5555',*args],capture_output=True,text=True,encoding='utf-8',errors='replace')
 if p.returncode or '[Fail]' in p.stdout: raise RuntimeError(p.stdout+p.stderr)
 return p.stdout.strip()
def sql(s):
 value=call('shell','sqlite3 '+DB+' "'+s.replace('"','\\"')+'"')
 if 'Error:' in value or 'Parse error' in value or 'Runtime error' in value:raise RuntimeError(value)
 return value

def restart():
 call('shell','aa force-stop com.gary.ddl');call('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(2)
def record(name,value):
 (OUT/(name+'.txt')).write_text(value,encoding='utf-8');print(name+'\n'+value)
def insert(events):
 lines=[]
 for e in events:
  payload=json.dumps(e,ensure_ascii=False,separators=(',',':')).replace("'","''")
  lines.append(f"INSERT OR IGNORE INTO ddl_sync_events VALUES('{e['id']}','{e['deadlineId']}','{payload}');")
 return sql('BEGIN;'+''.join(lines)+'COMMIT;')
def update(eid,root,snapshot,removed=None,parents=None,base=None):
 e=dict(version=1,id=eid,deadlineId=root['deadlineId'],parents=parents or [root['id']],base=base or root['snapshot'],removedTasks=removed or [],deleted=snapshot is None,legacy=False)
 if snapshot is not None:e['snapshot']=snapshot
 return e
cmd=sys.argv[1]
FIX=OUT/'fixture.json'
if cmd=='seed':
 call('shell','aa force-stop com.gary.ddl')
 assert sql('SELECT count(*) FROM deadlines;SELECT count(*) FROM deadline_subtasks;')=='0\n0'
 baseline=Path(tempfile.gettempdir())/'dayline-conflict-before';baseline.mkdir(exist_ok=True)
 for suffix in ['', '-wal','-shm']:
  try:call('file','recv',DB+suffix,str(baseline/('ddl.db'+suffix)))
  except RuntimeError:
   if suffix=='':raise
 record('before-state',sql('PRAGMA user_version;PRAGMA integrity_check;SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT count(*) FROM ddl_sync_issues;SELECT * FROM ddl_sync_owner;'))
 now=int(call('shell','date +%s'))*1000;fixture={};roots=[]
 names={'name':'名称确认测试','date':'截止时间确认测试','hours':'剩余工作量确认测试','task':'任务确认测试','task-delete':'任务删除测试','deadline-delete':'Deadline 删除测试','tree':'任务结构确认测试','unaffected':'正常使用测试'}
 for i,(key,name) in enumerate(names.items()):
  did='recovery-'+key;due=now+(i+8)*86400000;dt=datetime.datetime.fromtimestamp(due/1000)
  d=dict(id=did,name=name,type='exam',deadlineDate=dt.strftime('%Y-%m-%d'),deadlineTime=dt.strftime('%H:%M'),note='',createdAt=now,deadlineAt=due,completed=False,estimatedHours=10,remainingHours=10,remainingState='initial',remainingUpdatedAt=now,progress=0,progressMode='automatic',taskCount=0,reminderOffsetMinutes=0)
  tasks=[dict(id=did+'-p',deadlineId=did,title='准备资料',completed=False,createdAt=now,parentId='',sortOrder=0),dict(id=did+'-t',deadlineId=did,title='完成复习',completed=False,createdAt=now+1,parentId='' if key=='tree' else did+'-p',sortOrder=1)]
  root=dict(version=1,id=str(uuid.uuid4()),deadlineId=did,parents=[],snapshot=dict(deadline=d,tasks=tasks),removedTasks=[],deleted=False,legacy=False)
  fixture[key]={'root':root};roots.append(root)
 insert(roots);restart()
 assert sql("SELECT count(*) FROM deadlines WHERE id LIKE 'recovery-%';")=='8'
 for key,item in fixture.items():
  if key=='unaffected':continue
  r=item['root'];a=copy.deepcopy(r['snapshot']);b=copy.deepcopy(r['snapshot']);removed=[]
  if key=='name':a['deadline']['name']='高数期末复习';b['deadline']['name']='数学期末考试';a['deadline']['note']='保留独立备注';b['tasks'][1]['completed']=True
  if key=='date':
   for n,s in enumerate([a,b],1):
    s['deadline']['deadlineAt']+=n*86400000;dd=datetime.datetime.fromtimestamp(s['deadline']['deadlineAt']/1000);s['deadline']['deadlineDate']=dd.strftime('%Y-%m-%d')
  if key=='hours':
   for n,s in enumerate([a,b]):s['deadline'].update(remainingHours=[6,9][n],remainingState='confirmed',remainingUpdatedAt=now+(n+1)*1000)
  if key=='task':a['tasks'][1]['title']='完成课程设计';b['tasks'][1]['completed']=True
  if key=='task-delete':a['tasks']=a['tasks'][:1];removed=[r['deadlineId']+'-t'];b['tasks'][1]['title']='另一端修改的复习任务'
  if key=='deadline-delete':a=None;b['deadline']['name']='另一端修改的 Deadline'
  if key=='tree':a['tasks'][0]['parentId']=r['deadlineId']+'-t';b['tasks'][1]['parentId']=r['deadlineId']+'-p'
  item['a']=update(str(uuid.uuid4()),r,a,removed);item['b']=update(str(uuid.uuid4()),r,b)
 insert([item[k] for key,item in fixture.items() if key!='unaffected' for k in ['a','b']]);FIX.write_text(json.dumps(fixture,ensure_ascii=False,indent=2),encoding='utf-8');restart()
 record('conflicts-initial',sql("SELECT id,name,progress,estimated_hours,remaining_hours,remaining_state FROM deadlines WHERE id LIKE 'recovery-%' ORDER BY id;SELECT id,detail FROM ddl_sync_issues ORDER BY id;SELECT deadline_id,count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id LIKE 'recovery-%' GROUP BY deadline_id;"))
elif cmd=='capture':
 name=sys.argv[2];call('shell','snapshot_display -f /data/local/tmp/dayline-recovery.jpeg');call('file','recv','/data/local/tmp/dayline-recovery.jpeg',str(OUT/(name+'.jpeg')))
 call('shell','uitest dumpLayout -b com.gary.ddl -p /data/local/tmp/dayline-recovery.json');call('file','recv','/data/local/tmp/dayline-recovery.json',str(OUT/(name+'.json')))
 print(name)
elif cmd=='sql':print(sql(sys.argv[2]))
elif cmd=='restart':restart();print('restarted')
elif cmd=='replay':
 f=json.loads(FIX.read_text(encoding='utf-8'));before=sql("SELECT id,name,progress,remaining_hours FROM deadlines WHERE id LIKE 'recovery-%' ORDER BY id;");insert([item[k] for key,item in f.items() if key!='unaffected' for k in ['a','b']]);restart();after=sql("SELECT id,name,progress,remaining_hours FROM deadlines WHERE id LIKE 'recovery-%' ORDER BY id;");assert before==after
 record('replay-state',after+'\n'+sql("SELECT id,detail FROM ddl_sync_issues ORDER BY id;"))
elif cmd=='arrival':
 f=json.loads(FIX.read_text(encoding='utf-8'));r=f['date']['root'];new=copy.deepcopy(r['snapshot']);new['deadline']['note']='页面打开后到达的新备注';e=update(str(uuid.uuid4()),r,new);insert([e]);f['date']['late']=e;FIX.write_text(json.dumps(f,ensure_ascii=False,indent=2),encoding='utf-8');print('new unarchived event injected while review open')
elif cmd=='fail':
 sql("CREATE TRIGGER recovery_test_abort BEFORE INSERT ON ddl_sync_archive WHEN NEW.deadline_id='recovery-hours' BEGIN SELECT RAISE(ABORT,'recovery test'); END;");record('before-failure',sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-hours' ORDER BY id;SELECT * FROM deadlines WHERE id='recovery-hours';SELECT * FROM ddl_sync_issues WHERE id='recovery-hours';"))
elif cmd=='unfail':sql('DROP TRIGGER IF EXISTS recovery_test_abort;');print('failure trigger removed')
elif cmd=='slow':
 sql("CREATE TRIGGER recovery_test_slow BEFORE INSERT ON ddl_sync_archive WHEN NEW.deadline_id='recovery-hours' BEGIN SELECT (WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x<200000000) SELECT sum(x) FROM c); END;");print('slow transaction trigger installed')
elif cmd=='unslow':sql('DROP TRIGGER IF EXISTS recovery_test_slow;');print('slow trigger removed')
elif cmd=='compare-failure':
 value=sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-hours' ORDER BY id;SELECT * FROM deadlines WHERE id='recovery-hours';SELECT * FROM ddl_sync_issues WHERE id='recovery-hours';")
 assert value==(OUT/'before-failure.txt').read_text(encoding='utf-8');record('after-failure',value)
elif cmd=='multi':
 history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-name';").splitlines()]
 r=next(e for e in history if len(e['parents'])>0 and 'base' not in e and 'snapshot' in e)
 now=int(call('shell','date +%s'))*1000
 a=copy.deepcopy(r['snapshot']);b=copy.deepcopy(r['snapshot'])
 a['deadline'].update(name='Checkpoint A',remainingHours=6,remainingState='confirmed',remainingUpdatedAt=now)
 b['deadline'].update(name='Checkpoint B',remainingHours=9,remainingState='confirmed',remainingUpdatedAt=now+1000)
 aa=update(str(uuid.uuid4()),r,a);bb=update(str(uuid.uuid4()),r,b);insert([aa,bb]);restart()
 record('multi-before',sql("SELECT name,note,remaining_hours FROM deadlines WHERE id='recovery-name';SELECT detail FROM ddl_sync_issues WHERE id='recovery-name';"))
elif cmd=='pending':
 history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-hours';").splitlines()]
 r=next(e for e in history if len(e['parents'])>0 and 'base' not in e and 'snapshot' in e)
 parent=update(str(uuid.uuid4()),r,copy.deepcopy(r['snapshot']))
 after=copy.deepcopy(parent['snapshot']);after['deadline']['note']='完整收到后保留的备注'
 child=update(str(uuid.uuid4()),r,after,parents=[parent['id']],base=parent['snapshot'])
 (OUT/'pending-fixture.json').write_text(json.dumps({'parent':parent,'child':child},ensure_ascii=False),encoding='utf-8')
 insert([child]);restart();record('pending-held',sql("SELECT name,estimated_hours,remaining_hours,remaining_state,note FROM deadlines WHERE id='recovery-hours';SELECT detail FROM ddl_sync_issues WHERE id='recovery-hours';"))
elif cmd=='resume':
 insert([json.loads((OUT/'pending-fixture.json').read_text(encoding='utf-8'))['parent']]);restart()
 record('pending-resumed',sql("SELECT name,estimated_hours,remaining_hours,remaining_state,note FROM deadlines WHERE id='recovery-hours';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-hours';"))
elif cmd=='repeat-hours':
 r=json.loads((OUT/'pending-fixture.json').read_text(encoding='utf-8'))['child'];now=int(call('shell','date +%s'))*1000
 a=copy.deepcopy(r['snapshot']);b=copy.deepcopy(r['snapshot'])
 a['deadline'].update(remainingHours=7,remainingState='confirmed',remainingUpdatedAt=now)
 b['deadline'].update(remainingHours=9,remainingState='confirmed',remainingUpdatedAt=now+1000)
 insert([update(str(uuid.uuid4()),r,a),update(str(uuid.uuid4()),r,b)]);restart()
 record('final-hours-conflict',sql("SELECT name,remaining_hours FROM deadlines WHERE id='recovery-hours';SELECT detail FROM ddl_sync_issues WHERE id='recovery-hours';"))
elif cmd=='final-name':
 history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-name';").splitlines()]
 r=next(e for e in history if len(e['parents'])>0 and 'base' not in e and e.get('snapshot',{}).get('deadline',{}).get('name')=='Checkpoint A')
 a=copy.deepcopy(r['snapshot']);b=copy.deepcopy(r['snapshot'])
 a['deadline']['name']='Final choice A';b['deadline']['name']='Final choice B'
 aa=update(str(uuid.uuid4()),r,a);bb=update(str(uuid.uuid4()),r,b)
 (OUT/'final-name-fixture.json').write_text(json.dumps({'root':r,'a':aa,'b':bb},ensure_ascii=False),encoding='utf-8')
 insert([aa,bb]);restart();record('final-name-before',sql("SELECT name,remaining_hours FROM deadlines WHERE id='recovery-name';SELECT detail FROM ddl_sync_issues WHERE id='recovery-name';"))
elif cmd=='final-note':
 f=json.loads((OUT/'final-name-fixture.json').read_text(encoding='utf-8'));a=f['a'];b=f['b']
 saved=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-name';").splitlines()]
 resolution=next(e for e in saved if set(e['parents'])=={a['id'],b['id']})
 assert resolution['resolvedFields']==['name'],resolution
 after=copy.deepcopy(a['snapshot']);after['deadline']['note']='Independent note preserved after review'
 e=update(str(uuid.uuid4()),a,after,parents=[a['id'],b['id']],base=a['snapshot'])
 insert([e]);restart();insert([a,b]);restart()
 value=sql("SELECT name,estimated_hours,remaining_hours,note FROM deadlines WHERE id='recovery-name';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-name';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='recovery-name';")
 assert value=='Checkpoint A|10.0|9.0|Independent note preserved after review\n0\n2|2',value
 record('final-review-and-independent-note',value+'\nresolvedFields='+json.dumps(resolution['resolvedFields']))
elif cmd=='final-copy':
 history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='recovery-hours';").splitlines()]
 parents={p for e in history for p in e['parents']};heads=[e for e in history if e['id'] not in parents];assert len(heads)==1
 r=heads[0];a=copy.deepcopy(r['snapshot']);b=copy.deepcopy(r['snapshot'])
 a['deadline']['name']='Package review A';b['deadline']['name']='Package review B'
 insert([update(str(uuid.uuid4()),r,a),update(str(uuid.uuid4()),r,b)]);restart()
 record('final-package-conflict',sql("SELECT name,remaining_hours FROM deadlines WHERE id='recovery-hours';SELECT detail FROM ddl_sync_issues WHERE id='recovery-hours';"))
elif cmd=='cleanup':
 f=json.loads(FIX.read_text(encoding='utf-8'));events=[]
 for key,item in f.items():
  r=item['root'];history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='"+r['deadlineId']+"';").splitlines()];parents={parent for e in history for parent in e['parents']};heads=[e['id'] for e in history if e['id'] not in parents];events.append(update(str(uuid.uuid4()),r,None,parents=heads))
 insert(events);restart();sql("DROP TRIGGER IF EXISTS recovery_test_abort;DROP TRIGGER IF EXISTS recovery_test_slow;")
 record('cleanup',sql("PRAGMA user_version;PRAGMA integrity_check;SELECT count(*) FROM deadlines;SELECT count(*) FROM deadline_subtasks;SELECT count(*) FROM deadline_reminder_states;SELECT count(*) FROM ddl_sync_issues WHERE id NOT LIKE 'ack:%';SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT name FROM sqlite_master WHERE name LIKE 'recovery_test_%';"))
