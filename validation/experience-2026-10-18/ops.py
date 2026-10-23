from pathlib import Path
import runpy,time,shlex,sys,json
OUT=Path(__file__).parent
u=runpy.run_path(str(OUT/'ui.py'))
def fill(value, index=0):
    inputs=[n for n in u['nodes']() if n.get('type')=='TextInput']
    if isinstance(index,str):
        inputs=[n for n in inputs if n.get('id')==index]
        index=0
    assert len(inputs)>index, 'Observe the desired input first'
    u['run']('shell','uitest uiInput click %d %d'%u['center'](inputs[index]['bounds']))
    u['run']('shell','uitest uiInput keyEvent 2072 2017')
    u['run']('shell','uitest uiInput keyEvent 2055')
    u['run']('shell','uitest uiInput text '+shlex.quote(value))
    time.sleep(.8)
    # Escape dismisses the input method without risking a page-level Back or
    # clicking a form control underneath a hidden keyboard.
    u['run']('shell','uitest uiInput keyEvent 2070')
    time.sleep(.4)
    assert any(n.get('text')==value for n in u['nodes']()), 'Input value not visible after typing'
def tap(label,scroll=False):u['tap'](label,scroll)
def system_tap(label):
    nodes=[n for n in u['nodes'](True) if n.get('text')==label]
    assert nodes, 'System control unavailable: '+label
    u['run']('shell','uitest uiInput click %d %d'%u['center'](nodes[-1]['bounds']));time.sleep(.7)
def snapshot(name,required=()):
    value=u['capture'](name)
    for item in required:assert item in value,(name,item)
    return value
def remember_fixtures():
    h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
    rows=json.loads(h['sql']("SELECT json_group_array(json_object('id',id,'name',name)) FROM deadlines WHERE name LIKE 'UX18-%';"))
    before=json.loads((OUT/'fixtures.json').read_text()) if (OUT/'fixtures.json').exists() else []
    known={r['id']:r for r in before}
    for row in rows:known[row['id']]=row
    (OUT/'fixtures.json').write_text(json.dumps(list(known.values()),ensure_ascii=False,indent=2),encoding='utf-8')
    print('Recorded owned fixtures:',len(known),flush=True)
if __name__=='__main__':
    if sys.argv[1]=='fill':fill(sys.argv[2],(int(sys.argv[3]) if sys.argv[3].isdigit() else sys.argv[3]) if len(sys.argv)>3 else 0)
    elif sys.argv[1]=='remember':remember_fixtures()
