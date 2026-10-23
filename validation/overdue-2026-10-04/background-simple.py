"""Real background crossing, no keyboard/input-method interaction."""
from pathlib import Path
import runpy,json,time
OUT=Path(__file__).parent
l=runpy.run_path(str(OUT/'lifecycle.py')); u=l['u']; run=l['run']; sql=l['sql']
l['proof'].extend(json.loads((OUT/'lifecycle-timeline.json').read_text(encoding='utf-8')))
id='overdue-acceptance-background3'
run('shell','aa force-stop com.gary.ddl')
assert sql("SELECT count(*) FROM deadlines WHERE id='"+id+"';")=='0'
q="ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture; BEGIN IMMEDIATE; "
for table in ['deadlines','deadline_subtasks','ddl_sync_events','ddl_sync_archive']:
    col='id' if table=='deadlines' else 'deadline_id'
    q+=f"INSERT INTO {table} SELECT * FROM fixture.{table} WHERE {col}='{id}'; "
sql(q+'COMMIT; DETACH DATABASE fixture;')
due=int(sql("SELECT deadline_at FROM deadlines WHERE id='"+id+"';"))
assert due>l['epoch']()+90000
run('shell','aa start -a EntryAbility -b com.gary.ddl'); l['ready']()
u['tap']('独立后台临界检查'); l['ready']()
before=u['capture']('background-simple-before')
assert '需要处理' not in before and '已过期' not in before
pid=run('shell','pidof com.gary.ddl').strip()
run('shell','uitest uiInput keyEvent Home')
l['note']('background before deadline without edits',due=due,pid=pid)
l['wait_cross'](due)
run('shell','aa start -a EntryAbility -b com.gary.ddl'); time.sleep(2)
after=u['capture']('background-simple-after')
assert run('shell','pidof com.gary.ddl').strip()==pid
assert '需要处理' in after and '已过期' in after
l['note']('background resumption passed; same process; no edit or reopen')
u['tap']('查看计划与详情',True)
plan=u['capture']('background-simple-plan')
if '原截止时间已过' not in plan:
    run('shell','uitest uiInput swipe 650 2350 650 650 500')
    plan=u['capture']('background-simple-plan-lower')
assert '原截止时间已过' in plan and '执行日日均' not in plan
u['back'](); l['ready'](); u['capture']('background-simple-home')
l['note']('all three lifecycle cases passed')
