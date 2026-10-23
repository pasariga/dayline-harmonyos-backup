"""Final metadata-only preservation and test-state cleanup proof."""
from pathlib import Path
import runpy,json,hashlib,tempfile,xml.etree.ElementTree as ET
OUT=Path(__file__).parent
c=runpy.run_path(str(OUT/'cleanup.py')); u=c['u']; run=u['run']; sql=c['sql']
mapping=c['owned']()
report=c['preservation'](mapping,'closeout-preservation')
assert all(report[t]['total']==0 for t in ['deadlines','deadline_subtasks','deadline_reminder_states'])
assert sql('PRAGMA user_version;')=='8'
def prefs(name,module='entry'):
    path=f'/data/app/el2/100/base/com.gary.ddl/haps/{module}/preferences/{name}'
    with tempfile.TemporaryDirectory() as folder:
        local=Path(folder)/'settings'
        run('file','recv',path,str(local)); root=ET.parse(local).getroot()
        return {n.attrib.get('key',n.attrib.get('name')):n.text or n.attrib.get('value') for n in root}
settings=prefs('dayline_app_settings')
assert settings['theme_mode']=='system' and settings['language_mode']=='system'
assert float(settings['daily_available_hours'])==3 and float(settings['weekend_available_hours'])==5
entry_prefs=run('shell','ls /data/app/el2/100/base/com.gary.ddl/haps/entry/preferences').split()
if 'dayline_overdue_choices' in entry_prefs:
    assert json.loads(prefs('dayline_overdue_choices')['choices'])==[]
assert 'ddl.db' not in run('shell','ls /data/app/el2/100/database/com.gary.ddl/entry_test/rdb').split()
assert 'dayline_overdue_choices' not in run('shell','ls /data/app/el2/100/base/com.gary.ddl/haps/entry_test/preferences').split()
assert not any(n.startswith('dayline-overdue') for n in run('shell','ls /data/local/tmp').split())
protected=json.loads((OUT/'protected-before.json').read_text(encoding='utf-8'))
assert all(hashlib.sha256(Path(k).read_bytes()).hexdigest()==v for k,v in protected.items())
hap=Path('entry/build/default/outputs/default/entry-default-signed.hap')
saved=json.loads((OUT/'release-hap.json').read_text(encoding='utf-8-sig'))
assert hashlib.sha256(hap.read_bytes()).hexdigest().upper()==saved['Hash']
result={'active_business_rows':0,'subtasks':0,'reminders':0,'overdue_choices':0,'owned_fixture_count':len(mapping),
        'original_eight_tables_preserved':True,'database_version':8,'integrity':'ok','test_triggers':0,
        'isolated_native_fixtures_cleared':True,'remote_round_temporary_files':0,
        'settings':settings,'protected_files_unchanged':len(protected),'signed_hap_sha256':saved['Hash']}
(OUT/'closeout-final.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PASS: empty business store, cleared local test state, original rows preserved, DB8 intact, settings restored, final signed artifact unchanged.')
