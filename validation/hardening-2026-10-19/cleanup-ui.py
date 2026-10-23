"""Delete only positively recorded synthetic projects via existing App controls."""
from pathlib import Path
import runpy,json,time
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];v=h['values']('zh_CN')
known={}
for p in [OUT/'fixtures.json',*OUT.glob('fixtures-*.json')]:
 for r in json.loads(p.read_text(encoding='utf-8')):
  assert r['name'].startswith('UX19-');known[r['id']]=r
rows=json.loads(h['sql']("SELECT json_group_array(json_object('id',id,'name',name)) FROM deadlines;"))
owned=[r for r in rows if r['id'] in known]
assert len(owned)==len(rows),'Unexpected user projects: preserve them and review cleanup'
(OUT/'owned-fixtures-all.json').write_text(json.dumps(list(known.values()),ensure_ascii=False,indent=2),encoding='utf-8')
u['restart']();h['wait'](v['settings_title'])
for r in owned:
 h['home']('zh_CN');h['tap'](v['experience_deadlines']);h['tap'](r['name'],True)
 h['wait'](v['common_edit']);h['delete_current'](v)
 assert h['sql']("SELECT count(*) FROM deadlines WHERE id='"+r['id']+"';")=='0'
 print('Deleted owned project',r['id'],flush=True)
assert h['sql']('SELECT count(*) FROM deadlines;')=='0'
print('PASS: all owned active data removed through the App.',flush=True)
