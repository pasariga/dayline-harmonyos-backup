from pathlib import Path
import tempfile,time,json,subprocess,sys,atexit
BASE=Path(tempfile.gettempdir());ROOT=Path.cwd();OUT=ROOT/'validation/conflict-recovery-2026-10-03'
exec((BASE/'dayline_ui.py').read_text(encoding='utf-8').split('cmd=sys.argv[1]')[0])
mode=sys.argv[1]; log=[]
def record(text): log.append(text);print(text,flush=True)
atexit.register(lambda:(OUT/('ui-'+mode+'.log')).write_text('\n'.join(log),encoding='utf-8'))
def tap(q,scroll=True):
 for i in range(10):
  m=[a for a in nodes() if q in (a.get('text','') or a.get('originalText','')) and a.get('visible')=='true' and a.get('type')!='AlertDialog']
  if m:
   x,y=center(m[0]['bounds'])
   if 130<int(y)<2740:
    run('shell','uitest','uiInput','click',x,y);time.sleep(.8);record('tap '+q);return
  if scroll:run('shell','uitest','uiInput','swipe','650','2350','650','650','700')
  time.sleep(.4)
 raise RuntimeError('No visible target '+q)
def keyback():run('shell','uitest','uiInput','keyEvent','Back');time.sleep(.8);record('Back')
def restart():run('shell','aa force-stop com.gary.ddl');run('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(2)
def capture(name):
 subprocess.run([sys.executable,str(OUT/'device-check.py'),'capture',name],check=True,capture_output=True)
 texts=[a.get('text','') for a in nodes() if a.get('visible')=='true' and a.get('text')];record(name+'\n'+'\n'.join(texts));return texts
def select(i):
 a=[a for a in nodes() if a.get('type')=='Select' and a.get('visible')=='true'][i];x,y=center(a['bounds']);run('shell','uitest','uiInput','click',x,y);time.sleep(.4)
def sql(s):
 p=subprocess.run([sys.executable,str(OUT/'device-check.py'),'sql',s],capture_output=True,text=True,encoding='utf-8');assert p.returncode==0,p.stderr;return p.stdout.strip()
if mode=='hours':
 restart();tap('修改需要查看');tap('剩余工作量确认测试');capture('zh-light-hours-before');tap('约 6 小时');tap('保存选择');capture('zh-light-hours-success');tap('返回');capture('zh-light-list-after-hours');keyback();tap('剩余工作量确认测试');capture('zh-light-hours-detail');restart()
 value=sql("SELECT estimated_hours,remaining_hours,remaining_state,remaining_updated_at FROM deadlines WHERE id='recovery-hours';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-hours';SELECT count(*) FROM ddl_sync_events WHERE deadline_id='recovery-hours';SELECT count(*) FROM ddl_sync_archive WHERE deadline_id='recovery-hours';")
 assert value.startswith('10.0|6.0|confirmed|') and value.splitlines()[1:]==['0','4','4'],value
 record('hours persistence '+value)
if mode=='de':
 restart();tap('设置');tap('外观与语言');select(0);tap('深色',False);select(1);tap('Deutsch',False);time.sleep(1);restart();capture('de-dark-home');tap('Änderungen prüfen');capture('de-dark-review-list');tap('任务确认测试');capture('de-dark-task-options');tap('Gespeicherte Variante 2');capture('de-dark-task-selected');tap('Auswahl speichern');capture('de-dark-task-success');tap('Zurück');capture('de-dark-list-after-task');keyback();capture('de-dark-home-after-task')
 value=sql("SELECT progress,estimated_hours,remaining_hours,remaining_state FROM deadlines WHERE id='recovery-task';SELECT title,completed FROM deadline_subtasks WHERE id='recovery-task-t';SELECT id,detail FROM ddl_sync_issues WHERE id LIKE 'recovery-%' ORDER BY id;")
 record(value);assert 'recovery-task|' not in value
if mode=='tree':
 restart();tap('Änderungen prüfen');tap('任务结构确认测试');capture('de-dark-tree-options');tap('Gespeicherte Variante 2');tap('Auswahl speichern');capture('de-dark-tree-success');tap('Zurück');capture('de-dark-list-after-tree')
 value=sql("SELECT id,parent_id FROM deadline_subtasks WHERE deadline_id='recovery-tree' ORDER BY id;SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-tree';")
 record(value);assert value.splitlines()[-1]=='0'
if mode=='en':
 restart();tap('Einstellungen');tap('Darstellung');select(0);tap('Hell',False);select(1);tap('English',False);time.sleep(1);restart();capture('en-light-home');tap('Changes to review');tap('Deadline 删除测试');capture('en-light-deleted-deadline');tap('Decide later');capture('en-light-list-after-cancel');tap('Deadline 删除测试');tap('Understood');capture('en-light-delete-ack-success');tap('Back');tap('任务删除测试');capture('en-light-task-deletion');tap('Understood');capture('en-light-task-delete-ack-success');tap('Back');capture('en-light-list-after-ack');restart();capture('en-light-home-after-ack')
 value=sql("SELECT count(*) FROM deadlines WHERE id='recovery-deadline-delete';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='recovery-deadline-delete';SELECT count(*) FROM deadline_subtasks WHERE id='recovery-task-delete-t';SELECT count(*) FROM ddl_sync_issues WHERE id IN ('ack:recovery-task-delete','ack:recovery-deadline-delete');SELECT id,detail FROM ddl_sync_issues WHERE id LIKE 'recovery-%';")
 assert value=='0\n0\n0\n2',value;record('deletion persistence '+value)
if mode=='unaffected':
 restart();tap('正常使用测试');capture('en-light-unaffected-before');tap('Complete task');capture('en-light-unaffected-after');restart();value=sql("SELECT progress FROM deadlines WHERE id='recovery-unaffected';SELECT completed FROM deadline_subtasks WHERE id='recovery-unaffected-t';");assert value=='100\n1',value;record('unaffected project saved '+value)
if mode=='restore':
 restart();tap('Settings');tap('Appearance');select(0);tap('Use device setting',False);select(1);tap('Follow system',False);restart();capture('final-zh-light-home')

if mode=='multi':
 restart();tap('修改需要查看');tap('名称确认测试');capture('zh-final-multi-name');tap('Checkpoint A');tap('下一项');capture('zh-final-multi-hours');tap('约 9 小时');tap('上一项');capture('zh-final-multi-previous');tap('下一项');tap('稍后处理');capture('zh-final-multi-cancel');restart()
 value=sql("SELECT name,remaining_hours,note FROM deadlines WHERE id='recovery-name';SELECT detail FROM ddl_sync_issues WHERE id='recovery-name';");assert value.startswith('名称确认测试|10.0|'),value;record('pending persistence '+value)
 tap('修改需要查看');tap('名称确认测试');tap('Checkpoint A');tap('下一项');tap('约 9 小时');tap('保存选择');capture('zh-final-multi-success');tap('返回');capture('zh-final-multi-list');keyback();restart();tap('Checkpoint A');capture('zh-final-multi-detail')
 value=sql("SELECT name,estimated_hours,remaining_hours,remaining_state,note FROM deadlines WHERE id='recovery-name';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-name';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='recovery-name';");assert value=='Checkpoint A|10.0|9.0|confirmed|保留独立备注\n0\n2',value;record('multi saved '+value)

if mode=='zh':
 restart();tap('Settings');tap('Appearance');select(1);tap('简体中文',False);restart();capture('zh-final-home-before-multi')

if mode=='waiting':
 restart();tap('修改需要查看');tap('剩余工作量确认测试');texts=capture('zh-final-waiting');assert any('尚不完整' in t for t in texts),texts;assert not any('保存选择' in t for t in texts);tap('稍后处理');capture('zh-final-waiting-back')
if mode=='current-hours':
 restart();tap('修改需要查看');tap('剩余工作量确认测试');capture('zh-final-hours-choices');tap('本机原有内容')
if mode=='final-name':
 restart();tap('修改需要查看');tap('Checkpoint A');capture('zh-final-title-options');tap('本机原有内容');tap('保存选择');time.sleep(1)
 texts=capture('zh-final-stable-success');assert any('已保存' in t for t in texts),texts
 tap('返回');capture('zh-final-list-after-title');keyback();restart();tap('Checkpoint A');capture('zh-final-title-detail')
if mode=='restore-zh':
 restart();tap('设置');tap('外观与语言');select(0);tap('跟随系统',False);select(1);tap('跟随系统',False);restart();capture('final-empty-system-home')
if mode=='final-de-en':
 restart();tap('设置');tap('外观与语言');select(0);tap('深色',False);select(1);tap('Deutsch',False);restart();capture('final-package-de-dark-home');tap('Änderungen prüfen');tap('UI audit Course project');capture('final-package-de-dark-deletion');tap('Später entscheiden');keyback()
 tap('Einstellungen');tap('Darstellung');select(0);tap('Hell',False);select(1);tap('English',False);restart();tap('Changes to review');tap('UI audit Course project');capture('final-package-en-light-deletion');tap('Decide later');keyback()
 tap('Settings');tap('Appearance');select(1);tap('简体中文',False);restart()
if mode=='ack-history':
 restart();tap('修改需要查看');count=0
 while True:
  texts=[a.get('text','') for a in nodes() if a.get('visible')=='true' and a.get('text')]
  names=[t for t in texts if t.startswith(('UI audit ','V6 ','Remote B','Remote reminder','Tree B'))]
  if not names:break
  tap(names[0]);texts=capture('history-notice-'+str(count));assert any('删除' in t for t in texts),texts
  tap('知道了');time.sleep(.3);tap('返回');count+=1
  if count>20:raise RuntimeError('Unexpected historical notice count')
 record('Acknowledged known historical test notices '+str(count));capture('history-list-after-ack');keyback()
if mode=='final-copy':
 restart();tap('设置');tap('外观与语言');select(0);tap('深色',False);select(1);tap('Deutsch',False);restart();tap('Änderungen prüfen');tap('剩余工作量确认测试');capture('signed-final-de-dark-options');tap('Auf diesem Gerät gespeichert');tap('Auswahl speichern');time.sleep(1);texts=capture('signed-final-de-dark-success');assert any('gespeichert' in t for t in texts),texts;tap('Zurück');keyback()
 tap('Einstellungen');tap('Darstellung');select(0);tap('Hell',False);select(1);tap('English',False);restart();capture('signed-final-en-home');tap('剩余工作量确认测试');capture('signed-final-en-detail');keyback();tap('Settings');tap('Appearance');select(1);tap('简体中文',False);restart();capture('signed-final-zh-home')
 value=sql("SELECT name,estimated_hours,remaining_hours,remaining_state FROM deadlines WHERE id='recovery-hours';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-hours';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='recovery-hours';");assert value=='剩余工作量确认测试|10.0|6.0|confirmed\n0\n2|2',value;record('final signed package save/restart '+value)
if mode=='finish-copy':
 restart();tap('Settings');tap('Appearance');select(1);tap('简体中文',False);restart();capture('signed-final-zh-home')
 value=sql("SELECT name,estimated_hours,remaining_hours,remaining_state FROM deadlines WHERE id='recovery-hours';SELECT count(*) FROM ddl_sync_issues WHERE id='recovery-hours';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='recovery-hours';");assert value=='剩余工作量确认测试|10.0|6.0|confirmed\n0\n2|2',value;record('final signed package save/restart '+value)
