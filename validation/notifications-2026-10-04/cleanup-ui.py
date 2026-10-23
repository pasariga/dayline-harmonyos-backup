"""Delete only manifest-owned acceptance records through the application UI."""
from pathlib import Path
import json,runpy,time
OUT=Path(__file__).parent
u=runpy.run_path(str(OUT/'ui.py'))
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
owned=json.loads((OUT/'fixture-manifest.json').read_text(encoding='utf-8'))
records=h['snapshot']()['deadlines']
targets=[r for r in records if r['id'] in owned]
assert all(r['name']==owned[r['id']] for r in targets)
u['restart']();time.sleep(3)
u['capture']('persisted-ready-before-cleanup')
for record in targets:
    current=h['snapshot']()['deadlines']
    assert sum(r['name']==record['name'] for r in current)==1, 'Do not select an ambiguous name.'
    matches=[n for n in u['nodes']() if n.get('text')==record['name']]
    assert matches
    u['run']('shell','uitest uiInput click %d %d'%u['center'](matches[-1]['bounds']));time.sleep(1)
    for attempt in range(5):
        if any(n.get('text')=='删除' for n in u['nodes']()):break
        u['run']('shell','uitest uiInput swipe 650 2350 650 800 1600')
    u['tap']('删除')
    choices=[n for n in u['nodes']() if n.get('text')=='删除']
    assert len(choices)>=2, 'Expected the observed confirmation dialog.'
    u['run']('shell','uitest uiInput click %d %d'%u['center'](choices[-1]['bounds']));time.sleep(1)
    assert not any(r['id']==record['id'] for r in h['snapshot']()['deadlines'])
    print('Deleted owned acceptance record: '+record['id'],flush=True)
u['restart']();time.sleep(3)
u['capture']('empty-after-ui-cleanup')
