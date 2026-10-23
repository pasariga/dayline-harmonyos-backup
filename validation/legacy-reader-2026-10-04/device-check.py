from pathlib import Path
import subprocess, json, tempfile, uuid, re, sys, time
HDC=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
DB='/data/app/el2/100/database/com.gary.ddl/entry/rdb/ddl.db'
OUT=Path(__file__).parent
def call(*args):
    p=subprocess.run([HDC,'-t','127.0.0.1:5555',*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30)
    if p.returncode or '[Fail]' in p.stdout: raise RuntimeError(p.stdout+p.stderr)
    return p.stdout.strip()
def sql(query):
    local=Path(tempfile.gettempdir())/('dayline-reader-'+str(uuid.uuid4())+'.sql')
    remote='/data/local/tmp/'+local.name
    local.write_text(query,encoding='utf-8')
    try:
        call('file','send',str(local),remote)
        value=call('shell','cat '+remote+' | sqlite3 '+DB)
        value='\n'.join(x for x in re.sub(r'cost: \d+ us','',value).splitlines() if x.strip())
        if any(x in value for x in ['Error:','Parse error','Runtime error']): raise RuntimeError(value)
        return value
    finally:
        call('shell','rm '+remote);local.unlink(missing_ok=True)
def quote(v): return "'"+str(v).replace("'","''")+"'"
def snapshot():
    state={}
    for t in ['deadlines','deadline_subtasks','deadline_reminder_states','ddl_sync_events','ddl_sync_archive','ddl_sync_issues','ddl_sync_owner','ddl_legacy_imports']:
        cols=[line.split('|')[1] for line in sql('PRAGMA table_info('+t+');').splitlines()]
        state[t]=json.loads(sql('SELECT json_group_array(json_object('+','.join(quote(c)+','+c for c in cols)+')) FROM '+t+';'))
    return state
def restart():
    call('shell','aa force-stop com.gary.ddl');call('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(3)
def capture(name):
    remote='/data/local/tmp/dayline-reader-'+name+'.jpeg'
    call('shell','snapshot_display -f '+remote);call('file','recv',remote,str(OUT/(name+'.jpeg')));call('shell','rm '+remote)
if __name__=='__main__':
    cmd=sys.argv[1]
    if cmd=='backup':
        call('shell','aa force-stop com.gary.ddl')
        (OUT/'before-native-state.json').write_text(json.dumps(snapshot(),ensure_ascii=False,indent=2),encoding='utf-8')
        call('file','recv',DB,str(OUT/'before-db8.db'))
        print(sql('PRAGMA user_version;PRAGMA integrity_check;SELECT count(*) FROM deadlines;SELECT count(*) FROM ddl_sync_events;SELECT count(*) FROM ddl_sync_archive;SELECT count(*) FROM ddl_sync_issues;SELECT count(*) FROM ddl_sync_owner;SELECT count(*) FROM ddl_legacy_imports;'))
    elif cmd=='sql':print(sql(sys.argv[2]))
    elif cmd=='capture':capture(sys.argv[2])
    elif cmd=='final':
        restart();after=snapshot();before=json.loads((OUT/'before-native-state.json').read_text(encoding='utf-8'))
        for t in ['ddl_sync_events','ddl_sync_archive','ddl_sync_issues']:
            new={r['id']:r for r in after[t]}
            assert all(new.get(r['id'])==r for r in before[t]),'Original data changed: '+t
        for t in ['deadlines','deadline_subtasks','deadline_reminder_states','ddl_sync_owner','ddl_legacy_imports']:
            assert after[t]==before[t],'Unexpected data remaining: '+t
        assert sql('PRAGMA integrity_check;')=='ok'
        (OUT/'after-native-state.json').write_text(json.dumps(after,ensure_ascii=False,indent=2),encoding='utf-8')
        counts={t:len(rows) for t,rows in after.items()};print(json.dumps(counts))
        (OUT/'native-preservation.txt').write_text('PASS: original rows/immutable payloads/ACKs preserved.\n'+json.dumps(counts)+'\n',encoding='utf-8')
        capture('final-empty-home')
