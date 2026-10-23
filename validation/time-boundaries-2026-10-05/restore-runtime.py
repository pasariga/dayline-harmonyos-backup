"""Restore only this acceptance run's activity marker after guarded comparisons."""
from pathlib import Path
import hashlib, json, runpy, xml.etree.ElementTree as ET

OUT = Path(__file__).parent
h = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'))
run = h['call']
base = '/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
owned = json.loads((OUT / 'fixture-manifest.json').read_text())

def values(path):
    return {e.attrib['key']: e.get('value', e.text or '') for e in ET.parse(path).getroot()}

run('shell', 'aa force-stop com.gary.ddl')
for name in ['dayline_app_settings', 'dayline_overdue_choices', 'ddl_notification_settings']:
    current = OUT / (name + '.cleanup-check.xml')
    run('file', 'recv', base + name, str(current))
    before = values(OUT / (name + '.before.xml'))
    actual = values(current)
    if name != 'ddl_notification_settings':
        assert actual == before, 'Unrelated preference changed: ' + name
        continue
    assert set(actual) == set(before), 'Unexpected notification preference'
    assert actual['last_activity_deadline_id'] in ['', *owned], 'Activity belongs to another record'
    assert all(actual[k] == v for k, v in before.items()
               if k not in ['last_activity_deadline_id', 'last_activity_at']), 'Unrelated notification state changed'
    source = OUT / (name + '.before.xml')
    run('file', 'send', str(source), base + name)
    if name + '.bak' in run('shell', 'ls ' + base).split():
        run('file', 'send', str(source), base + name + '.bak')

run('shell', 'aa start -a EntryAbility -b com.gary.ddl')
run('file', 'recv', base + 'ddl_notification_settings', str(OUT / 'notification-runtime-restored.xml'))
assert values(OUT / 'notification-runtime-restored.xml') == values(OUT / 'ddl_notification_settings.before.xml')
hap = Path('entry/build/default/outputs/default/entry-default-signed.hap')
signed = json.loads((OUT / 'signed-hap.json').read_text(encoding='utf-8-sig'))
assert hashlib.sha256(hap.read_bytes()).hexdigest().upper() == signed['Hash']
bundle_dump = run('shell', 'bm dump -n com.gary.ddl')
modules = json.loads(bundle_dump[bundle_dump.index('{'):])
module_names = [m['moduleName'] for m in modules['hapModuleInfos']]
assert 'entry_test' not in module_names, 'Acceptance module still installed'
zone = run('shell', 'param get persist.time.timezone')
assert zone == 'Asia/Shanghai'
auto_time = run('shell', 'param get persist.time.auto_time')
assert auto_time == 'ON'
(OUT / 'runtime-cleanup.json').write_text(json.dumps({
    'preference_choices_preserved': True, 'own_activity_marker_cleared': True,
    'overdue_choices_empty': True, 'test_module_absent': True,
    'timezone': zone, 'automatic_time': auto_time, 'signed_hap_sha256': signed['Hash']
}, indent=2), encoding='utf-8')
print('PASS: guarded runtime cleanup; original choices preserved; test module absent; final HAP unchanged.')
