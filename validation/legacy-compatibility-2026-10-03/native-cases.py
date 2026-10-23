from pathlib import Path
import json,sys,time,copy,uuid,datetime,subprocess
exec(Path('validation/legacy-compatibility-2026-10-03/device-check.py').read_text(encoding='utf-8-sig').split('\ncmd=sys.argv[1]')[0])
NOW=int(call('shell','date +%s'))*1000
ACCOUNT='compat-local-test'
def old(did,name=None,tasks=False):
 due=NOW+9*86400000;dt=datetime.datetime.fromtimestamp(due/1000)
 row=dict(id=did,name=name or did,type='考试',deadline_date=dt.strftime('%Y-%m-%d'),deadline_time=dt.strftime('%H:%M'),deadline_at=due,created_at=NOW,completed=0,estimated_hours=10,progress=0,progress_mode='automatic',reminder_offset_minutes=60)
 ts=[]
 if tasks:
  ts=[dict(id=did+'-p',deadline_id=did,title='Exam preparation',completed=0,created_at=NOW,parent_id='',sort_order=0),dict(id=did+'-s',deadline_id=did,title='Read notes (small)',completed=1,created_at=NOW+1,parent_id=did+'-p',sort_order=0),dict(id=did+'-l',deadline_id=did,title='Practice exam (large)',completed=0,created_at=NOW+2,parent_id=did+'-p',sort_order=1)]
 return dict(deadlines=[row],tasks=ts,manifests=[dict(deadlineId=did,taskIds=[t['id'] for t in ts])])
def event(data,eid=None):
 r=data['deadlines'][0];did=r['id']
 d=dict(id=did,name=r['name'],type=r['type'],deadlineDate=r['deadline_date'],deadlineTime=r['deadline_time'],note='',createdAt=r['created_at'],deadlineAt=r['deadline_at'],completed=bool(r['completed']),estimatedHours=r['estimated_hours'],remainingHours=6,remainingState='confirmed',remainingUpdatedAt=NOW,progress=50 if data['tasks'] else 0,progressMode=r['progress_mode'],taskCount=0,reminderOffsetMinutes=r['reminder_offset_minutes'])
 ts=[dict(id=t['id'],deadlineId=did,title=t['title'],completed=bool(t['completed']),createdAt=t['created_at'],parentId=t.get('parent_id',''),sortOrder=t.get('sort_order',0)) for t in data['tasks']]
 return dict(version=2,id=eid or str(uuid.uuid4()),deadlineId=did,parents=[],snapshot=dict(deadline=d,tasks=ts),removedTasks=[],deleted=False,legacy=False)
def stage(bid,data,account=ACCOUNT,complete=1,stopped=1,journal=1):
 payload=data if isinstance(data,str) else json.dumps(data,ensure_ascii=False,separators=(',',':'))
 sql('INSERT OR REPLACE INTO ddl_legacy_imports (id,kind,account_id,source_id,payload,complete,writers_stopped,journal_complete,status,detail,event_id) VALUES('+','.join(quote(x) for x in [bid,'batch',account,'frozen-local-'+bid,payload,complete,stopped,journal,'staged','',''])+');')
def check(name,query,expected):
 value=sql(query);assert value==expected,(name,value,expected);record(name,value+'\nPASS')
def summary(did):return sql("SELECT name,estimated_hours,remaining_hours,remaining_state,progress FROM deadlines WHERE id="+quote(did)+";SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id="+quote(did)+";SELECT detail FROM ddl_sync_issues WHERE id="+quote(did)+";SELECT kind,status,detail FROM ddl_legacy_imports WHERE id IN ("+quote('batch-'+did)+','+quote('item:'+did)+');')
mode=sys.argv[1]
PROJECTS=['compat-fresh','compat-local','compat-choice','compat-deleted','compat-pruned','compat-bad-good','compat-bad-tree','compat-duplicate','compat-versions','compat-wait','compat-history-wait','compat-account-b','compat-rollback','compat-kill','compat-upgrade','compat-carrier','compat-good-history','compat-bad-history']
if mode=='history-guard':
 call('shell','aa force-stop com.gary.ddl')
 good=event(old('compat-good-history','Certified original history'));good['version']=1
 bad=dict(version=1,id=str(uuid.uuid4()),deadlineId='compat-bad-history',parents=[],removedTasks=[],deleted=True,legacy=False,unknownFutureField=True)
 for e in [good,bad]:
  payload=json.dumps(e,ensure_ascii=False,separators=(',',':'))
  sql('INSERT INTO ddl_sync_archive VALUES('+','.join(quote(x) for x in [e['id'],e['deadlineId'],payload])+');')
 restart()
 check('native-history-canonical-guard',"SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-good-history';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-bad-history';SELECT name FROM deadlines WHERE id='compat-good-history';",'1\n0\nCertified original history')
 record('native-history-original-bytes',sql('SELECT payload FROM ddl_sync_archive WHERE id='+quote(bad['id'])+';')+'\nPASS: abnormal archive kept unchanged and not republished; independent canonical archive got its carrier')
elif mode=='final':
 call('shell','aa force-stop com.gary.ddl');sql("UPDATE ddl_legacy_imports SET status='staged' WHERE id='batch-compat-fresh';");restart()
 check('final-package-idempotency-and-choice',"SELECT name,remaining_state,progress FROM deadlines WHERE id='compat-fresh';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-fresh';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-fresh';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-fresh';SELECT name,remaining_hours FROM deadlines WHERE id='compat-choice';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-choice';",'Old exam restored|unknown|50\n1\n1\n3|3\nCurrent exam|6.0\n0')
 check('final-package-batch-committed',"SELECT status FROM ddl_legacy_imports WHERE id='batch-compat-fresh';",'done')
 before=json.loads((OUT/'before-native-state.json').read_text(encoding='utf-8'));after=snapshot()
 for t in ['ddl_sync_archive','ddl_sync_events']:
  index={r['id']:r for r in after[t]};assert all(index[r['id']]==r for r in before[t]),t
 record('final-package-original-history','PASS: all original events/archive rows remain identical, including original ACK records')
elif mode=='cleanup':
 call('shell','aa force-stop com.gary.ddl');state=snapshot();state['ddl_legacy_imports']=json.loads(rows('ddl_legacy_imports'));(OUT/'fixture-state-before-cleanup.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
 deletes=[]
 for did in PROJECTS:
  history=[json.loads(line) for line in sql('SELECT payload FROM ddl_sync_archive WHERE deadline_id='+quote(did)+';').splitlines()]
  if not history or any(e.get('deleted') for e in history):continue
  parents={p for e in history for p in e['parents']};heads=sorted(e['id'] for e in history if e['id'] not in parents)
  deletes.append(dict(version=2,id=str(uuid.uuid4()),deadlineId=did,parents=heads,removedTasks=[],deleted=True,legacy=False))
 insert(deletes);restart()
 check('cleanup-business','SELECT count(*) FROM deadlines;SELECT count(*) FROM deadline_subtasks;SELECT count(*) FROM deadline_reminder_states;SELECT count(*) FROM ddl_sync_issues WHERE id NOT LIKE \'ack:%\';','0\n0\n0\n0')
 call('shell','aa force-stop com.gary.ddl')
 receipts=['item:'+did for did in PROJECTS];batches=['batch-'+did for did in PROJECTS]+['batch-bad','batch-duplicate','batch-versions','batch-malformed','batch-wait','batch-history-wait','batch-account-b','batch-source-changed','batch-rollback','batch-kill']
 sql('BEGIN;DELETE FROM ddl_legacy_imports WHERE id IN ('+','.join(quote(x) for x in receipts+batches)+");DELETE FROM ddl_sync_owner WHERE id='owner' AND account_id="+quote(ACCOUNT)+";DROP TRIGGER IF EXISTS compat_import_abort;DROP TRIGGER IF EXISTS compat_import_slow;COMMIT;")
 restart();record('after-native-counts',sql("PRAGMA user_version;PRAGMA integrity_check;SELECT count(*) FROM deadlines;SELECT count(*) FROM deadline_subtasks;SELECT count(*) FROM deadline_reminder_states;SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT count(*) FROM ddl_sync_issues WHERE id NOT LIKE 'ack:%';SELECT count(*) FROM ddl_sync_issues WHERE id LIKE 'ack:%';SELECT count(*) FROM ddl_sync_owner;SELECT count(*) FROM ddl_legacy_imports;SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'compat_import_%';"))
 before=json.loads((OUT/'before-native-state.json').read_text(encoding='utf-8'));after=snapshot()
 for t in ['ddl_sync_archive','ddl_sync_events','ddl_sync_issues']:
  index={r['id']:r for r in after[t]};assert all(index[r['id']]==r for r in before[t]),t
 assert before['ddl_sync_owner']==after['ddl_sync_owner'];record('cleanup-original-preserved','PASS: original immutable events, archive, ACK and empty owner preserved; only test staging removed and legal fixture tombstones added')
 (OUT/'after-native-state.json').write_text(json.dumps(after,ensure_ascii=False,indent=2),encoding='utf-8')
elif mode=='delete-upgrade':
 call('shell','aa force-stop com.gary.ddl');history=[json.loads(line) for line in sql("SELECT payload FROM ddl_sync_archive WHERE deadline_id='compat-upgrade';").splitlines()];parents={p for e in history for p in e['parents']};heads=[e['id'] for e in history if e['id'] not in parents]
 insert([dict(version=2,id=str(uuid.uuid4()),deadlineId='compat-upgrade',parents=heads,removedTasks=[],deleted=True,legacy=False)]);restart()
 check('native-unsupported-cannot-resurrect',"SELECT count(*) FROM deadlines WHERE id='compat-upgrade';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-upgrade';",'0\n0')
elif mode=='core':
 call('shell','aa force-stop com.gary.ddl');assert sql('SELECT count(*) FROM ddl_sync_owner;')=='0'
 sql("INSERT INTO ddl_sync_owner VALUES('owner',"+quote(ACCOUNT)+');')
 fresh=old('compat-fresh','Old exam restored',True);matching=old('compat-local','Local confirmed exam',True);difference=old('compat-choice','Current exam',True);deleted=old('compat-deleted','Deleted old exam',True);pruned=old('compat-pruned','Deleted branch')
 bases=[event(x) for x in [matching,difference,deleted,pruned]]
 insert(bases);restart();call('shell','aa force-stop com.gary.ddl')
 de=dict(version=2,id=str(uuid.uuid4()),deadlineId='compat-deleted',parents=[bases[2]['id']],removedTasks=[],deleted=True,legacy=False)
 pe=copy.deepcopy(bases[3]);pe.update(id=str(uuid.uuid4()),parents=[bases[3]['id']],base=copy.deepcopy(bases[3]['snapshot']),removedTasks=['compat-pruned-p'])
 insert([de,pe]);restart();call('shell','aa force-stop com.gary.ddl')
 difference['deadlines'][0]['name']='Other old exam';difference['deadlines'][0]['deadline_at']+=86400000;difference['deadlines'][0]['deadline_date']=datetime.datetime.fromtimestamp(difference['deadlines'][0]['deadline_at']/1000).strftime('%Y-%m-%d')
 difference['tasks']=difference['tasks'][:2];difference['manifests'][0]['taskIds']=[t['id'] for t in difference['tasks']]
 pruned=old('compat-pruned','Deleted branch',True)
 for data in [fresh,matching,difference,deleted,pruned]:stage('batch-'+data['deadlines'][0]['id'],data)
 bad=old('compat-bad-good','Independent good row');wrong=old('compat-bad-tree','Missing parent',True);wrong['tasks'][1]['parent_id']='absent'
 bad['deadlines']+=wrong['deadlines']+[dict(id='',name='Bad')];bad['tasks']+=wrong['tasks'];bad['manifests']+=wrong['manifests'];stage('batch-bad',bad)
 duplicate=old('compat-duplicate','Identical task duplicates',True);duplicate['tasks'].append(copy.deepcopy(duplicate['tasks'][1]));stage('batch-duplicate',duplicate)
 versions=old('compat-versions','Different task versions',True);versions['tasks'].append(copy.deepcopy(versions['tasks'][1]));versions['tasks'][-1]['title']='Other task';stage('batch-versions',versions)
 stage('batch-malformed','{broken');stage('batch-wait',old('compat-wait'),stopped=0);stage('batch-history-wait',old('compat-history-wait'),journal=0);stage('batch-account-b',old('compat-account-b'),account='compat-other-account')
 restart()
 check('native-fresh-tree-unknown',"SELECT estimated_hours,remaining_hours,remaining_state,progress FROM deadlines WHERE id='compat-fresh';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-fresh';",'10.0|0.0|unknown|50\n3|3')
 check('native-local-confirmed-preserved',"SELECT estimated_hours,remaining_hours,remaining_state,progress FROM deadlines WHERE id='compat-local';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-local';",'10.0|6.0|confirmed|50\n0')
 check('native-deleted-not-restored',"SELECT count(*) FROM deadlines WHERE id='compat-deleted';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-deleted';SELECT count(*) FROM ddl_sync_events WHERE id='legacy-v2:compat-deleted';SELECT status FROM ddl_legacy_imports WHERE id='item:compat-deleted';",'0\n0\n0\ndeleted')
 check('native-deleted-parent-descendants',"SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-pruned';",'0')
 check('native-bad-rows-isolated',"SELECT count(*) FROM deadlines WHERE id='compat-bad-good';SELECT count(*) FROM deadlines WHERE id IN ('compat-bad-tree','compat-versions');SELECT status FROM ddl_legacy_imports WHERE id IN ('batch-bad','batch-malformed','batch-versions') ORDER BY id;",'1\n0\nquarantined\nquarantined\nquarantined')
 check('native-duplicate-collapse',"SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-duplicate';",'3|3')
 check('native-auth-writer-history-barriers',"SELECT count(*) FROM deadlines WHERE id IN ('compat-wait','compat-history-wait','compat-account-b');SELECT status FROM ddl_legacy_imports WHERE id IN ('batch-wait','batch-history-wait','batch-account-b') ORDER BY id;",'0\nwaiting\nwaiting\nwaiting')
 record('native-choice-held',summary('compat-choice'));assert sql("SELECT name FROM deadlines WHERE id='compat-choice';")=='Current exam'
 reasons=json.loads(sql("SELECT detail FROM ddl_sync_issues WHERE id='compat-choice';"));assert all(k in reasons for k in ['name','due','tree']),reasons
 original=sql("SELECT payload FROM ddl_sync_events WHERE id='legacy-v2:compat-fresh';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-fresh';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-fresh';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-fresh';")
 for i in range(9):
  call('shell','aa force-stop com.gary.ddl');sql("UPDATE ddl_legacy_imports SET status='staged' WHERE id='batch-compat-fresh';");restart()
 assert sql("SELECT payload FROM ddl_sync_events WHERE id='legacy-v2:compat-fresh';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-fresh';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-fresh';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-fresh';")==original
 record('native-ten-imports','PASS: one event, one archive baseline, one receipt, three unique tasks; identical canonical payload after ten native attempts')
 fresh['deadlines'][0]['name']='Old source changed after freezing';call('shell','aa force-stop com.gary.ddl');stage('batch-source-changed',fresh);restart()
 check('native-source-mutation-isolated',"SELECT name FROM deadlines WHERE id='compat-fresh';SELECT status FROM ddl_legacy_imports WHERE id='batch-source-changed';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-fresh';",'Old exam restored\nquarantined\n1')
 (OUT/'native-fixtures.json').write_text(json.dumps(dict(bases=bases,fresh=fresh),ensure_ascii=False,indent=2),encoding='utf-8')
elif mode=='rollback':
 call('shell','aa force-stop com.gary.ddl');data=old('compat-rollback','Native rollback test',True);stage('batch-rollback',data)
 sql("CREATE TRIGGER compat_import_abort BEFORE INSERT ON ddl_legacy_imports WHEN NEW.id='item:compat-rollback' BEGIN SELECT RAISE(ABORT,'compat fixture');END;")
 restart();check('native-import-rollback',"SELECT count(*) FROM deadlines WHERE id='compat-rollback';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-rollback';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-rollback';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-rollback';SELECT count(*) FROM ddl_legacy_imports WHERE id='item:compat-rollback';SELECT status FROM ddl_legacy_imports WHERE id='batch-rollback';",'0\n0\n0\n0\n0\nretry')
 call('shell','aa force-stop com.gary.ddl');sql('DROP TRIGGER compat_import_abort;');restart()
 check('native-import-rollback-retry',"SELECT count(*) FROM deadlines WHERE id='compat-rollback';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-rollback';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-rollback';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-rollback';SELECT status FROM ddl_legacy_imports WHERE id='batch-rollback';",'1\n3|3\n1\n1\ndone')
elif mode=='kill':
 call('shell','aa force-stop com.gary.ddl');stage('batch-kill',old('compat-kill','Interrupted import',True))
 sql("CREATE TRIGGER compat_import_slow BEFORE INSERT ON ddl_legacy_imports WHEN NEW.id='item:compat-kill' BEGIN SELECT sum(x) FROM (WITH RECURSIVE seq(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM seq WHERE x<200000000) SELECT x FROM seq);END;")
 call('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(1)
 locked=False
 for i in range(10):
  try:sql('PRAGMA busy_timeout=100;BEGIN IMMEDIATE;ROLLBACK;')
  except RuntimeError as e:
   if 'locked' in str(e).lower():locked=True;break
  time.sleep(.3)
 assert locked,'No active transaction observed; do not count interruption as passed'
 call('shell','aa force-stop com.gary.ddl');time.sleep(.5)
 check('native-force-stop-uncommitted',"SELECT count(*) FROM deadlines WHERE id='compat-kill';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-kill';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-kill';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-kill';SELECT count(*) FROM ddl_legacy_imports WHERE id='item:compat-kill';SELECT status FROM ddl_legacy_imports WHERE id='batch-kill';",'0\n0\n0\n0\n0\nstaged')
 sql('DROP TRIGGER compat_import_slow;');restart()
 check('native-force-stop-retry',"SELECT count(*) FROM deadlines WHERE id='compat-kill';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-kill';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-kill';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-kill';SELECT status FROM ddl_legacy_imports WHERE id='batch-kill';",'1\n3|3\n1\n1\ndone')
elif mode=='carrier-existing':
 call('shell','aa force-stop com.gary.ddl')
 child=json.loads(sql("SELECT payload FROM ddl_sync_events WHERE deadline_id='compat-carrier' LIMIT 1;"))
 root=dict(version=1,id=child['parents'][0],deadlineId=child['deadlineId'],parents=[],snapshot=child['base'],removedTasks=[],deleted=False,legacy=False)
 payload=json.dumps(root,ensure_ascii=False,separators=(',',':'));carrier=dict(version=2,id='history-v2:'+root['id'],deadlineId=root['deadlineId'],historicalPayload=payload)
 insert([carrier]);restart()
 check('native-carrier-out-of-order-recovery',"SELECT name,remaining_hours FROM deadlines WHERE id='compat-carrier';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-carrier';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-carrier';",'Recovered newer child|6.0\n2\n0')
 record('native-carrier-counts',sql("SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-carrier';SELECT payload FROM ddl_sync_archive WHERE id="+quote(root['id'])+';'))
 before=summary('compat-carrier');restart();assert summary('compat-carrier')==before
 record('native-carrier-restart','PASS: original event ID retained, carrier not copied into archive, two causal events persist')
elif mode=='mixed':
 call('shell','aa force-stop com.gary.ddl');base=event(old('compat-upgrade','Older client update'));insert([base]);restart();call('shell','aa force-stop com.gary.ddl')
 e=copy.deepcopy(base);e.update(version=1,id=str(uuid.uuid4()),parents=[base['id']],base=copy.deepcopy(base['snapshot']));e['snapshot']['deadline']['name']='Unsafe old client edit';insert([e]);restart()
 check('native-older-client-held',"SELECT name FROM deadlines WHERE id='compat-upgrade';SELECT detail FROM ddl_sync_issues WHERE id='compat-upgrade';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-upgrade';",'Older client update\n["upgrade"]\n1')
 call('shell','aa force-stop com.gary.ddl');root=event(old('compat-carrier','Transferred old history'));root['version']=1;root['snapshot']['tasks']=sorted(root['snapshot']['tasks'],key=lambda t:t['id'])
 payload=json.dumps(root,ensure_ascii=False,separators=(',',':'));carrier=dict(version=2,id='history-v2:'+root['id'],deadlineId=root['deadlineId'],historicalPayload=payload)
 child=copy.deepcopy(root);child.update(version=2,id=str(uuid.uuid4()),parents=[root['id']],base=copy.deepcopy(root['snapshot']));child['snapshot']['deadline']['name']='Recovered newer child';insert([child]);restart()
 assert sql("SELECT count(*) FROM deadlines WHERE id='compat-carrier';")=='0'
 call('shell','aa force-stop com.gary.ddl');insert([carrier]);restart()
 check('native-carrier-out-of-order-recovery',"SELECT name,remaining_hours FROM deadlines WHERE id='compat-carrier';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='compat-carrier';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-carrier';",'Recovered newer child|6.0\n2\n0')
 record('native-carrier-counts',sql("SELECT count(*) FROM ddl_sync_events WHERE deadline_id='compat-carrier';SELECT payload FROM ddl_sync_archive WHERE id="+quote(root['id'])+';'))
 before=summary('compat-carrier');restart();assert summary('compat-carrier')==before
 record('native-carrier-restart','PASS: original event ID retained, carrier not copied into archive, two causal events persist')
