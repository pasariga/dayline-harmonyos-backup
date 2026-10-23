from pathlib import Path
import runpy,json
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
rows=json.loads(h['sql']("SELECT json_group_array(json_object('id',id,'name',name)) FROM deadlines WHERE name='FinalNormalCheck';"))
assert len(rows)==1
file=OUT/'cleanup-owned.json'
mapping=json.loads(file.read_text(encoding='utf-8'))
mapping[rows[0]['id']]=rows[0]['name']
file.write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')
print('Ordinary UI-created fixture registered for scoped cleanup.')
