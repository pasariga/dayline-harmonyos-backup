from pathlib import Path
import runpy,re,json
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];removed=[]
root='/data/app/el2/100/base/com.gary.ddl'
paths=[root+'/cache/'+name for name in u['run']('shell','ls '+root+'/cache').splitlines() if name.startswith('hardening-')]
for path in paths:
 assert path.startswith(root+'/') and '/cache/' in path and re.fullmatch(r'hardening-[A-Za-z0-9_.-]+\.(?:png|json)',path.rsplit('/',1)[-1]),path
 u['run']('shell','rm '+path);removed.append(path)
for name in u['run']('shell','ls /data/local/tmp').splitlines():
 if re.fullmatch(r'dayline-overdue-ui-[0-9a-f]+\.json',name):
  u['run']('shell','rm /data/local/tmp/'+name);removed.append('/data/local/tmp/'+name)
(OUT/'cache-cleanup.json').write_text(json.dumps({'owned_artifact_count_removed':len(removed),'only_guarded_test_cache_and_layout_files':True},indent=2))
print('Removed owned temporary artifacts:',len(removed),flush=True)
