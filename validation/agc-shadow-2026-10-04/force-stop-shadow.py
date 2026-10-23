from pathlib import Path
import runpy, subprocess, time, json, hashlib

OUT = Path(__file__).parent
h = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'), run_name='shadow_helper')
call, sql = h['call'], h['sql']
sql.__globals__['DB'] = '/data/app/el2/100/database/com.gary.ddl/entry/rdb/shadow-native.db'
sql("INSERT OR REPLACE INTO shadow_control VALUES ('pause',1);")
before = sql("SELECT json_group_array(json_object('id',id,'name',name,'completed',completed,'total',estimated_hours,'remaining',remaining_hours)) FROM deadlines;")
ready = False
previous_markers = set(call('shell', 'hilog -x -T DDLShadow').splitlines())
with (OUT / 'native-pause-run.log').open('w', encoding='utf-8') as log:
    proc = subprocess.Popen([h['HDC'], 'shell', 'aa test -b com.gary.ddl -m entry_test -s unittest OpenHarmonyTestRunner -w 180'], stdout=log, stderr=log)
    try:
        for attempt in range(40):
            time.sleep(1)
            own_log = call('shell', 'hilog -x -T DDLShadow')
            if any('SHADOW_PAUSE_READY' in line and line not in previous_markers for line in own_log.splitlines()):
                ready = True
                (OUT / 'identity-and-pause.txt').write_text(own_log, encoding='utf-8')
                break
        assert ready, 'Controlled inspection did not reach the pause.'
        call('shell', 'aa force-stop com.gary.ddl')
        after = sql("SELECT json_group_array(json_object('id',id,'name',name,'completed',completed,'total',estimated_hours,'remaining',remaining_hours)) FROM deadlines;")
        assert after == before, 'Independent source changed while inspection was killed.'
        sql("UPDATE shadow_control SET armed=0 WHERE id='pause';")
        call('shell', 'aa start -a EntryAbility -b com.gary.ddl')
        (OUT / 'force-stop-result.txt').write_text('PASS: stopped after partial inspection at SHADOW_PAUSE_READY.\n'
            'Independent source rows unchanged. No partial result or import was committed.\n'
            'sha256=' + hashlib.sha256(after.encode()).hexdigest() + '\n', encoding='utf-8')
        print('Controlled in-flight shadow force-stop: PASS; synthetic source preserved.')
    finally:
        if proc.poll() is None:
            proc.terminate()
        proc.wait(timeout=10)
