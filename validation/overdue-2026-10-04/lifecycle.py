"""Real elapsed-time acceptance on synthetic fixtures; never changes system time."""
from pathlib import Path
import runpy, json, time

OUT = Path(__file__).parent
u = runpy.run_path(str(OUT / 'ui.py'))
h = runpy.run_path(str(OUT.parent / 'legacy-reader-2026-10-04/device-check.py'))
sql, run, tap, capture = h['sql'], u['run'], u['tap'], u['capture']
ids = ['overdue-acceptance-boundary3-' + str(i) for i in range(3)]
names = ['临界详情检查', '临界首页检查', '临界后台检查']
proof = []

def epoch():
    return int(run('shell', 'date +%s').strip()) * 1000

def note(phase, **values):
    item = {'phase': phase, 'device_time': epoch(), **values}
    proof.append(item)
    (OUT / 'lifecycle-timeline.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(item, ensure_ascii=False), flush=True)

def wait_cross(due):
    note('waiting without app interaction', due=due)
    while True:
        remaining = (due - epoch()) / 1000
        if remaining < -2:
            return
        time.sleep(min(20, max(1, remaining + 3)))

def ready():
    for _ in range(15):
        values = u['texts']()
        if '今天最优先' in values or '下一步' in values:
            return
        time.sleep(1)
    raise RuntimeError('Application did not reach a ready state.')

def adopt():
    # Only application-generated synthetic aggregates from the isolated runner.
    # The copy is a fixture setup transaction, never a product import path.
    run('shell', 'aa force-stop com.gary.ddl')
    assert sql("SELECT count(*) FROM deadlines WHERE id LIKE 'overdue-acceptance-boundary3-%';") == '0'
    q = "ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture; BEGIN IMMEDIATE; "
    for table in ['deadlines', 'deadline_subtasks', 'ddl_sync_events', 'ddl_sync_archive']:
        col = 'id' if table == 'deadlines' else 'deadline_id'
        q += f"INSERT INTO {table} SELECT * FROM fixture.{table} WHERE {col} IN (" + ','.join("'"+i+"'" for i in ids) + '); '
    sql(q + 'COMMIT; DETACH DATABASE fixture;')
    due = [int(sql("SELECT deadline_at FROM deadlines WHERE id='"+i+"';")) for i in ids]
    assert due[0] > epoch() + 90000, 'Fixtures already too close; no elapsed-time pass can be claimed.'
    note('fixtures adopted', due=due, integrity=sql('PRAGMA integrity_check;'))
    run('shell', 'aa start -a EntryAbility -b com.gary.ddl')
    ready()
    return due

if __name__ == '__main__':
    due = adopt()
    tap(names[0], True)
    ready()
    before = capture('lifecycle-detail-before')
    assert '需要处理' not in before and '已过期' not in before
    tap('查看计划与详情', True)
    capture('lifecycle-detail-plan-before')
    run('shell', 'uitest uiInput swipe 650 650 650 2350 700')
    note('detail remains foreground', due=due[0])
    wait_cross(due[0])
    after = capture('lifecycle-detail-after')
    assert '需要处理' in after and '已过期' in after
    run('shell', 'uitest uiInput swipe 650 2350 650 650 500')
    plan = capture('lifecycle-detail-plan-after')
    if '原截止时间已过' not in plan:
        run('shell', 'uitest uiInput swipe 650 2350 650 650 500')
        plan = capture('lifecycle-detail-plan-after-lower')
    assert '原截止时间已过' in plan
    assert '执行日日均' not in plan and '仍需工作量' not in plan
    note('detail automatic transition passed')

    u['back']()
    ready()
    before = capture('lifecycle-home-before')
    assert names[1] in before and before.index(names[1]) < before.index('全部 Deadline')
    note('home remains foreground', due=due[1])
    wait_cross(due[1])
    after = capture('lifecycle-home-after')
    assert names[2] in after and after.index(names[2]) < after.index('全部 Deadline')
    assert names[1] not in after.split('全部 Deadline')[0] or '处理已逾期的「'+names[1]+'」' in after
    note('home and today action automatic transition passed')

    tap(names[2])
    ready()
    tap('更新剩余估计')
    fields = [n for n in u['nodes']() if n.get('type') == 'TextInput' and n.get('text') == '6']
    assert len(fields) == 1
    run('shell', 'uitest uiInput inputText %d %d 9' % u['center'](fields[0]['bounds']))
    u['back']()  # keyboard only; keep the estimate draft open
    before = capture('lifecycle-background-before')
    assert '9' in before and '已过期' not in before
    pid = run('shell', 'pidof com.gary.ddl').strip()
    run('shell', 'uitest uiInput keyEvent Home')
    note('app background with preserved draft', due=due[2], pid=pid)
    wait_cross(due[2])
    run('shell', 'aa start -a EntryAbility -b com.gary.ddl')
    time.sleep(2)
    after = capture('lifecycle-background-after')
    assert run('shell', 'pidof com.gary.ddl').strip() == pid, 'Process restarted; this is not foreground resumption.'
    assert '需要处理' in after and '已过期' in after and '9' in after
    note('foreground resumption passed; draft preserved; same process')
    tap('沿用上次', True)
    u['back']()
    ready()
    capture('lifecycle-return-home')
    note('all three lifecycle cases passed')
