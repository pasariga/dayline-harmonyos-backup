from pathlib import Path
import json,subprocess,sys,time,uuid,copy,datetime,hashlib,tempfile,re
exec(Path('validation/conflict-recovery-2026-10-03/device-check.py').read_text(encoding='utf-8').split('cmd=sys.argv[1]')[0])
OUT=Path('validation/legacy-compatibility-2026-10-03')
def sql(s):
 local=Path(tempfile.gettempdir())/('dayline-compat-'+str(uuid.uuid4())+'.sql')
 remote='/data/local/tmp/'+local.name
 local.write_text(s,encoding='utf-8')
 try:
  call('file','send',str(local),remote)
  value=call('shell','cat '+remote+' | sqlite3 '+DB)
  value='\n'.join(line for line in re.sub(r'cost: \d+ us', '', value).splitlines() if line.strip())
  if any(t in value for t in ['Error:','Parse error','Runtime error']):raise RuntimeError(value)
  return value
 finally:
  call('shell','rm '+remote);local.unlink(missing_ok=True)
def quote(v):return "'"+str(v).replace("'","''")+"'"
def rows(table):
 cols=[line.split('|')[1] for line in sql('PRAGMA table_info('+table+');').splitlines()]
 return sql('SELECT json_group_array(json_object('+','.join(quote(c)+','+c for c in cols)+')) FROM '+table+';')
def snapshot():
 return {t:json.loads(rows(t)) for t in ['deadlines','deadline_subtasks','deadline_reminder_states','ddl_sync_events','ddl_sync_archive','ddl_sync_issues','ddl_sync_owner']}
def capture(name):
 remote='/data/local/tmp/dayline-compat-'+name+'.jpeg'
 call('shell','snapshot_display -f '+remote);call('file','recv',remote,str(OUT/(name+'.jpeg')))
cmd=sys.argv[1]
if cmd=='backup':
 call('shell','aa force-stop com.gary.ddl')
 record('before-native-counts',sql('PRAGMA user_version;PRAGMA integrity_check;SELECT count(*) FROM deadlines;SELECT count(*) FROM deadline_subtasks;SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT count(*) FROM ddl_sync_issues;SELECT count(*) FROM ddl_sync_owner;'))
 state=snapshot();(OUT/'before-native-state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
 for suffix in ['', '-wal','-shm']:
  try:call('file','recv',DB+suffix,str(OUT/('before-db7.db'+suffix)))
  except RuntimeError:
   if suffix=='':raise
 assert not state['ddl_sync_owner'],'Unexpected bound account; inspect without replacing it'
elif cmd=='migration':
 restart();before=json.loads((OUT/'before-native-state.json').read_text(encoding='utf-8'));after=snapshot()
 for t in ['deadlines','deadline_subtasks','deadline_reminder_states','ddl_sync_archive','ddl_sync_issues','ddl_sync_owner']:assert before[t]==after[t],t
 old={r['id']:r for r in before['ddl_sync_events']};new={r['id']:r for r in after['ddl_sync_events']}
 assert all(new[k]==v for k,v in old.items()),'Original immutable history changed'
 assert sql('PRAGMA user_version;')=='8'
 record('native-db7-to8',sql('PRAGMA integrity_check;SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT count(*) FROM ddl_legacy_imports;')+'\nOriginal business rows, archive, ACKs, account and event payloads preserved byte-for-byte. Added carriers='+str(len(new)-len(old)))
 for i in range(2):restart()
 assert snapshot()==after,'Repeat startup changed state'
 record('native-migration-repeat','PASS: two further restarts did not add carriers/history or change business data')
elif cmd=='capture':capture(sys.argv[2])
elif cmd=='sql':print(sql(sys.argv[2]))

