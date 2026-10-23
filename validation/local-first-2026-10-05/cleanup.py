"""Only restore acceptance-owned preferences; never delete database history."""
from pathlib import Path
import runpy, json, hashlib, xml.etree.ElementTree as ET

OUT = Path(__file__).parent
h = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'))
base = '/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
fixtures = json.loads((OUT / 'fixtures.json').read_text())
owned = {row['id'] for row in fixtures}
assert len(owned) == 2 and {row['name'] for row in fixtures} == {'LF-V1-Core', 'LF-V1-Final'}
h['call']('shell', 'aa force-stop com.gary.ddl')
state = h['snapshot']()
assert not state['deadlines'] and not state['deadline_subtasks'] and not state['deadline_reminder_states'], 'Delete the fixture through the App first'

def digest(rows):
    return hashlib.sha256(json.dumps(rows, sort_keys=True, ensure_ascii=False).encode()).hexdigest()

before = json.loads((OUT / 'before-tables.json').read_text())
counts = {}
for table, rows in state.items():
    original = [row for row in rows if row.get('deadline_id') not in owned]
    assert len(original) == before[table]['count'] and digest(original) == before[table]['sha256'], 'Original data changed: ' + table
    counts[table] = len(rows)
assert h['sql']('PRAGMA integrity_check;') == 'ok'
assert h['sql']('PRAGMA user_version;') == '8'
assert h['sql']("SELECT count(*) FROM sqlite_master WHERE type='trigger';") == '0'

def values(path):
    return {e.attrib['key']: (e.tag, e.attrib.get('value', e.text or '')) for e in ET.parse(path).getroot()}

for name in ['dayline_app_settings', 'dayline_overdue_choices', 'ddl_notification_settings']:
    after = OUT / (name + '.after.xml')
    prior = OUT / (name + '.before.xml')
    h['call']('file', 'recv', base + name, str(after))
    current, original = values(after), values(prior)
    if name == 'dayline_app_settings':
        assert current == original, 'Restore language/theme through the App before cleanup'
        continue
    if name == 'dayline_overdue_choices':
        entries = json.loads(current.get('choices', ('string', '[]'))[1])
        # Deletion normally removes this choice already.
        assert not entries or all(row.get('deadlineId') in owned for row in entries), 'Unrelated overdue choice found'
    else:
        activity = {'last_activity_at', 'last_activity_deadline_id', 'last_plan_date', 'last_plan_task_ids', 'risk_marks', 'last_risk_at'}
        assert {k:v for k,v in current.items() if k not in activity} == {k:v for k,v in original.items() if k not in activity}, 'Unrelated notification preference changed'
        assert current.get('last_activity_deadline_id', ('string', ''))[1] in owned | {''}, 'Unrelated activity found'
        marks = json.loads(current.get('risk_marks', ('string', '[]'))[1])
        assert not marks or all(row.get('deadlineId') in owned for row in marks), 'Unrelated risk mark found'
    h['call']('file', 'send', str(prior), base + name)
    h['call']('file', 'recv', base + name, str(after))
    assert values(after) == original

result = {'original_eight_table_digests_preserved': True, 'counts_after': counts,
          'immutable_acceptance_events_retained': True, 'active_fixtures': 0,
          'database_version': 8, 'integrity_check': 'ok', 'test_triggers': 0,
          'language_theme_and_notification_preferences_restored': True}
(OUT / 'cleanup.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
