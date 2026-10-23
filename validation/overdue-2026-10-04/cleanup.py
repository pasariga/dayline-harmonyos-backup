"""Delete only recorded synthetic UI fixtures; preserve immutable sync history."""
from pathlib import Path
import runpy, json, re, time, hashlib, tempfile, xml.etree.ElementTree as ET

OUT = Path(__file__).parent
u = runpy.run_path(str(OUT/'ui.py'))
h = runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
sql, run = h['sql'], u['run']
FIXTURE = re.compile(r'overdue-acceptance-(?:[0-6]|clock|background[23]?|boundary(?:2|3)?-[0-2]|final-[0-1])')
MANIFEST = OUT/'cleanup-owned.json'

def rows():
    return json.loads(sql("SELECT json_group_array(json_object('id',id,'name',name,'completed',completed)) FROM deadlines;"))

def owned():
    saved = json.loads(MANIFEST.read_text(encoding='utf-8')) if MANIFEST.exists() else {}
    for row in rows():
        if FIXTURE.fullmatch(row['id']):
            saved[row['id']] = row['name']
    MANIFEST.write_text(json.dumps(saved,ensure_ascii=False,indent=2),encoding='utf-8')
    return saved

def ready_home():
    for _ in range(15):
        values = u['texts']()
        if 'Dayline' in values and '设置' in values and not any('正在加载' in x for x in values):
            return values
        time.sleep(.5)
    raise RuntimeError('Home not ready.')

def click_last(label):
    values=[n for n in u['nodes']() if n.get('text')==label and n.get('type')!='AlertDialog']
    assert values, 'Observed control missing: '+label
    run('shell','uitest uiInput click %d %d'%u['center'](values[-1]['bounds']))
    time.sleep(.7)

def clear_active():
    mapping=owned(); removed=[]
    u['restart']()
    while True:
        remaining=[r for r in rows() if r['id'] in mapping]
        if not remaining: break
        values=ready_home()
        if len(remaining)==1 and '今天没有待推荐的行动。保留的项目可在全部 Deadline 中查看。' in values:
            assert remaining[0]['completed']==0
            u['capture']('cleanup-stopped-is-not-completed')
        names={r['name'] for r in remaining}
        selected=None
        for _ in range(12):
            nodes=u['nodes']()
            found=[n for n in nodes if n.get('text') in names]
            if found:
                selected=found[0]['text']
                u['tap'](selected)
                break
            all_button=[n['text'] for n in nodes if n.get('text','').startswith('查看全部 ')]
            if all_button:
                u['tap'](all_button[0])
                run('shell','uitest uiInput swipe 650 650 650 2600 700')
            else:
                run('shell','uitest uiInput swipe 650 2350 650 650 500')
        assert selected is not None, 'No owned fixture visible; do not delete anything else.'
        detail=u['texts']()
        assert 'Deadline 详情' in detail and selected in detail
        if '重新处理' in detail: u['tap']('重新处理')
        u['tap']('删除', True)
        click_last('删除')  # confirmed dialog control, never the underlying footer
        for _ in range(10):
            after=[r for r in rows() if r['id'] in mapping]
            if len(after)==len(remaining)-1: break
            time.sleep(.4)
        assert len(after)==len(remaining)-1, 'Deletion was not durably applied.'
        removed.append(selected)
        print('Removed owned fixture; remaining:',len(after),flush=True)
    return removed

def clear_preferences(mapping):
    run('shell','aa force-stop com.gary.ddl')
    remote='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/dayline_overdue_choices'
    with tempfile.TemporaryDirectory(prefix='dayline-overdue-clean-') as folder:
        local=Path(folder)/'preferences'
        run('file','recv',remote,str(local))
        root=ET.parse(local).getroot()
        entries=[n for n in root if 'choices' in n.attrib.values()]
        assert len(entries)==1
        value=entries[0].text or entries[0].attrib.get('value')
        assert isinstance(value,str), 'Unknown preference format; preserve the file.'
        decisions=json.loads(value)
        assert all(r['id'] in mapping or r['id']=='overdue-native-intent' for r in decisions), 'Non-test intent found; preserve preferences.'
        run('shell','rm '+remote)
        run('shell','rm -f '+remote+'.lock')

def preservation(mapping, name):
    state=h['snapshot'](); original=json.loads((OUT/'main-before.json').read_text(encoding='utf-8'))
    report={}
    for table, values in state.items():
        kept=[r for r in values if r.get('deadline_id',r.get('id','')) not in mapping]
        detail={'count':len(kept),'sha256':hashlib.sha256(json.dumps(sorted(kept,key=lambda r:r['id']),sort_keys=True,separators=(',',':')).encode()).hexdigest()}
        assert detail==original[table], 'Original data changed: '+table
        report[table]={'total':len(values),'original':detail}
    assert sql('PRAGMA integrity_check;')=='ok'
    assert sql("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND (name LIKE 'test_%' OR name LIKE '%fault%' OR name LIKE '%abort%');")=='0'
    (OUT/(name+'.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report

if __name__=='__main__':
    mapping=owned()
    preservation(mapping,'cleanup-before')
    removed=clear_active()
    clear_preferences(mapping)
    report=preservation(mapping,'cleanup-after')
    u['restart'](); ready_home(); u['capture']('cleanup-empty-home')
    print('PASS: business fixtures and local intent cleared; original rows and normal deletion history preserved.',flush=True)
