from pathlib import Path
import runpy,json,time
OUT=Path(__file__).parent
o=runpy.run_path(str(OUT/'ops.py'));u=o['u'];tap=o['tap']
o['remember_fixtures']()
fixtures=json.loads((OUT/'fixtures.json').read_text(encoding='utf-8'))
assert len(fixtures)==3 and all(r['name'].startswith('UX18-') for r in fixtures)
for index,row in enumerate(fixtures):
 tap('Deadlines')
 choices=[n.get('text','') for n in u['nodes']() if n.get('type')=='Button' and n.get('text','').startswith('查看全部')]
 if choices:tap(choices[0])
 tap(row['name'],True)
 o['snapshot']('last-delete-%d-before'%index,(row['name'],))
 tap('删除',True)
 assert any(n.get('type')=='AlertDialog' for n in u['nodes']()),'Deletion must retain existing confirmation'
 o['snapshot']('last-delete-%d-confirm'%index)
 o['system_tap']('删除')
 time.sleep(.5)
 assert 'Deadlines' in u['texts'](),'Deletion should return to Home'
 print('Deleted acceptance fixture through existing confirmation:',row['name'],flush=True)
tap('今天');o['snapshot']('last-empty-after-deletion')
print('PASS: all three owned acceptance fixtures deleted through the App.',flush=True)
