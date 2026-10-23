from pathlib import Path
import runpy,json
OUT=Path(__file__).parent; h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
run,sql=h['call'],h['sql']
run('shell','aa force-stop com.gary.ddl')
directory='/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/'
names=run('shell','ls '+directory).split()
if 'ddl.db' in names:
    attach="ATTACH DATABASE '"+directory+"ddl.db' AS fixture; "
    for table in ['deadlines','deadline_subtasks','ddl_sync_events','ddl_sync_archive']:
        key='id' if table=='deadlines' else 'deadline_id'
        assert sql(attach+"SELECT count(*) FROM fixture."+table+" WHERE "+key+" NOT LIKE 'notification-%';")=='0', 'Unexpected non-test record; preserve store.'
    for table in ['ddl_sync_owner','ddl_legacy_imports','ddl_sync_issues']:
        assert sql(attach+'SELECT count(*) FROM fixture.'+table+';')=='0'
    for name in ['ddl.db','ddl.db-wal','ddl.db-shm']:
        if name in names:run('shell','rm '+directory+name)
prefs='/data/app/el2/100/base/com.gary.ddl/haps/entry_test/preferences/'
names=run('shell','ls '+prefs).split()
for name in ['ddl_notification_settings','ddl_notification_settings.bak']:
    if name in names:run('shell','rm '+prefs+name)
print('Cleared only the verified notification-test module store; main database retained.')
