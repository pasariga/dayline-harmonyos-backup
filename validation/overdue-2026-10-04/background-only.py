"""Elapsed-time background case, including an unsaved estimate draft."""
from pathlib import Path
import runpy,json,time,tempfile,uuid
OUT=Path(__file__).parent
l=runpy.run_path(str(OUT/'lifecycle.py')); u=l['u']; sql=l['sql']; run=l['run']; capture=l['capture']
l['proof'].extend(json.loads((OUT/'lifecycle-timeline.json').read_text(encoding='utf-8')))
id='overdue-acceptance-background2'
run('shell','aa force-stop com.gary.ddl')
assert sql("SELECT count(*) FROM deadlines WHERE id='"+id+"';")=='0'
q="ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture; BEGIN IMMEDIATE; "
for table in ['deadlines','deadline_subtasks','ddl_sync_events','ddl_sync_archive']:
 col='id' if table=='deadlines' else 'deadline_id'
 q+=f"INSERT INTO {table} SELECT * FROM fixture.{table} WHERE {col}='{id}'; "
sql(q+'COMMIT; DETACH DATABASE fixture;')
due=int(sql("SELECT deadline_at FROM deadlines WHERE id='"+id+"';"))
assert due>l['epoch']()+90000
l['note']('fresh background fixture adopted',due=due)
run('shell','aa start -a EntryAbility -b com.gary.ddl'); l['ready']()
u['tap']('独立后台临界检查'); l['ready'](); u['tap']('更新剩余估计')
fields=[n for n in u['nodes']() if n.get('type')=='TextInput' and n.get('text')=='6']; assert len(fields)==1
run('shell','uitest uiInput inputText %d %d 9'%u['center'](fields[0]['bounds']))
time.sleep(2)
# InputText appends to 6 on this image. Keep the resulting 69 as an unsaved
# synthetic draft; no estimate is committed and no input-method consent is given.
remote='/data/local/tmp/dayline-overdue-ime-'+uuid.uuid4().hex+'.json'
with tempfile.TemporaryDirectory() as folder:
 path=Path(folder)/'layout.json'
 run('shell','uitest dumpLayout -p '+remote); run('file','recv',remote,str(path)); tree=json.loads(path.read_text(encoding='utf-8')); run('shell','rm '+remote)
 nodes=[]
 def walk(n):
  a=n.get('attributes',{})
  if a.get('visible')=='true':nodes.append(a)
  for c in n.get('children',[]):walk(c)
 walk(tree)
 if any(n.get('text')=='小艺输入法' for n in nodes):
  cancel=[n for n in nodes if n.get('text')=='取消']; assert cancel
  run('shell','uitest uiInput click %d %d'%u['center'](cancel[-1]['bounds']))
  time.sleep(1)
before=capture('background-only-before')
assert '69' in before and '已过期' not in before and l['epoch']()<due
pid=run('shell','pidof com.gary.ddl').strip()
run('shell','uitest uiInput keyEvent Home')
l['note']('app background before due with preserved draft',due=due,pid=pid)
l['wait_cross'](due)
run('shell','aa start -a EntryAbility -b com.gary.ddl'); time.sleep(2)
after=capture('background-only-after')
assert run('shell','pidof com.gary.ddl').strip()==pid
assert '69' in after
u['back']()  # dismiss keyboard; a draft back guard, if shown, is cancelled
if '放弃修改' in u['texts'](): u['tap']('取消')
run('shell','uitest uiInput swipe 650 650 650 1650 700')
run('shell','uitest uiInput swipe 650 650 650 1650 700')
status=capture('background-only-after-status')
assert '需要处理' in status and '已过期' in status
l['note']('background resumption passed; unsaved draft preserved; same process')
u['tap']('沿用上次',True); u['back'](); l['ready'](); capture('background-only-return-home')
l['note']('all three lifecycle cases passed')
