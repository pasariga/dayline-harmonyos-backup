from pathlib import Path
import runpy,json,hashlib
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u']
state=h['h']['snapshot']()
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
(OUT/('before-tables-'+h['DEVICE']+'.json')).write_text(json.dumps({t:{'count':len(r),'sha256':digest(r)} for t,r in state.items()},indent=2))
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
files=u['run']('shell','ls '+base).splitlines()
for name in ['dayline_app_settings','ddl_notification_settings','dayline_overdue_choices']:
 if name in files:u['run']('file','recv',base+name,str(OUT/(h['DEVICE']+'-'+name+'.before.xml')))
print('Captured baseline for',h['DEVICE'],{t:len(r) for t,r in state.items()},flush=True)
