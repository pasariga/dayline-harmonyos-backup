from pathlib import Path
import json,re,hashlib
ROOT=Path('entry/src/main/resources');OUT=Path('validation/legacy-compatibility-2026-10-03')
keys=['review_upgrade','cloud_legacy_pending','cloud_protocol_pending']
english=json.loads((ROOT/'en_US/element/messages.json').read_text(encoding='utf-8'))
translations={s['name']:s['value'] for s in english['string']}
base=ROOT/'base/element/messages.json';data=json.loads(base.read_text(encoding='utf-8'))
for s in data['string']:
 if s['name'] in keys:s['value']=translations[s['name']]
base.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
reference=None;results={}
for path in ROOT.glob('*/element/messages.json'):
 rows=json.loads(path.read_text(encoding='utf-8'))['string'];names=[s['name'] for s in rows]
 assert len(names)==len(set(names)),path
 if reference is None:reference=set(names)
 assert reference==set(names),path
 values={s['name']:s['value'] for s in rows}
 for key in keys:
  assert '?' not in values[key] and '\ufffd' not in values[key],(path,key)
  assert re.findall(r'%[sd]',values[key])==re.findall(r'%[sd]',translations[key]),(path,key)
 results[path.parent.parent.name]={'keys':len(names),'messages':{k:values[k] for k in keys}}
assert len(results)==9
(OUT/'resource-check.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: nine resource sets, '+str(len(reference))+' keys, no duplicates, matching new placeholders')
before=json.loads((OUT/'before-hashes.json').read_text(encoding='utf-8-sig'));changed=[]
for row in before:
 if hashlib.sha256(Path(row['Path']).read_bytes()).hexdigest().upper()!=row['Hash']:changed.append(str(Path(row['Path']).relative_to(Path.cwd())))
(OUT/'changed-existing-services-configs.json').write_text(json.dumps(changed,ensure_ascii=False,indent=2),encoding='utf-8')
print('Changed existing services/configs: '+', '.join(changed))
