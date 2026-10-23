from pathlib import Path
import runpy,re,json,hashlib,sys
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u']
tag=sys.argv[1]
dump=u['run']('shell','hidumper -s DisplayManagerService -a -a')
result={}
for key in ['Width','Height','VirtualWidth','VirtualHeight','Density']:
 matches=re.findall(r'^\s*'+key+r':\s*([\d.]+)',dump,re.M);assert matches,key
 result[key]=float(matches[-1])
assert result['Width']==h['W'] and result['Height']==h['H']
if '--empty' in sys.argv:
 assert h['sql']('SELECT count(*) FROM deadlines;')=='0'
 result['owned_active_test_data_cleared']=True
else:
 assert h['sql']("SELECT count(*) FROM deadlines WHERE id='9638609c-bbd9-4a7b-915a-95455548e808';")=='1'
 result['same_saved_work_object_present']=True
result['database_version']=int(h['sql']('PRAGMA user_version;'))
result['integrity']=h['sql']('PRAGMA integrity_check;')
assert result['database_version']==8 and result['integrity']=='ok'
(OUT/('runtime-screen-'+tag+'.json')).write_text(json.dumps(result,indent=2))
state=h['h']['snapshot']()
def digest(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
(OUT/('tables-'+tag+'.json')).write_text(json.dumps({t:{'count':len(r),'sha256':digest(r)} for t,r in state.items()},indent=2))
print(json.dumps(result,indent=2))
