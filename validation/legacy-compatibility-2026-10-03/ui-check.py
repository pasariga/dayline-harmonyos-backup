from pathlib import Path
import tempfile,json,subprocess,sys,time,atexit
exec((Path(tempfile.gettempdir())/'dayline_ui.py').read_text(encoding='utf-8').split('cmd=sys.argv[1]')[0])
REMOTE='/data/local/tmp/dayline-compat-layout-'+str(os.getpid())+'.json'
LOCAL=str(Path(tempfile.gettempdir())/('dayline-compat-layout-'+str(os.getpid())+'.json'))
def run(*args):
 p=subprocess.run([HDC,'-t','127.0.0.1:5555',*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=20)
 if p.returncode or '[Fail]' in p.stdout:raise RuntimeError(p.stdout+p.stderr)
 return p.stdout
OUT=Path('validation/legacy-compatibility-2026-10-03');mode=sys.argv[1];log=[]
def record(s):log.append(s);print(s,flush=True)
atexit.register(lambda:(OUT/('ui-'+mode+'.log')).write_text('\n'.join(log),encoding='utf-8'))
def restart():
 run('shell','aa force-stop com.gary.ddl');run('shell','aa start -a EntryAbility -b com.gary.ddl')
 for i in range(20):
  time.sleep(.5)
  if any(a.get('text')=='Dayline' and a.get('visible')=='true' for a in nodes()):return
 raise RuntimeError('Home did not become ready; do not scroll a loading page')
def tap(q,scroll=True):
 for i in range(10):
  targets=[a for a in nodes() if q.casefold() in (a.get('text','') or a.get('originalText','')).casefold() and a.get('visible')=='true' and a.get('type')!='AlertDialog']
  if targets:
   x,y=center(targets[0]['bounds'])
   if 130<int(y)<2740:run('shell','uitest','uiInput','click',x,y);time.sleep(.8);record('tap '+q);return
  if scroll:run('shell','uitest','uiInput','swipe','650','2350','650','650','600');time.sleep(.4)
 raise RuntimeError('No visible target '+q)
def back():run('shell','uitest','uiInput','keyEvent','Back');time.sleep(.7)
def capture(name):
 subprocess.run([sys.executable,str(OUT/'device-check.py'),'capture',name],check=True,capture_output=True)
 t=[a.get('text','') for a in nodes() if a.get('visible')=='true' and a.get('text')];record(name+'\n'+'\n'.join(t));return t
def select(i):
 a=[a for a in nodes() if a.get('type')=='Select' and a.get('visible')=='true'][i];run('shell','uitest','uiInput','click',*center(a['bounds']));time.sleep(.4)
def sql(s):
 p=subprocess.run([sys.executable,str(OUT/'device-check.py'),'sql',s],capture_output=True,text=True,encoding='utf-8');assert p.returncode==0,p.stderr;return p.stdout.strip()
if mode=='zh':
 restart();capture('zh-home-held');tap('修改需要查看');tap('Current exam');t=capture('zh-choice-name');assert '名称' in t
 tap('本机原有内容');tap('下一项');capture('zh-choice-date');tap('本机原有内容');tap('下一项');capture('zh-choice-tree');tap('本机原有内容');tap('稍后处理');restart()
 assert sql("SELECT name,remaining_hours FROM deadlines WHERE id='compat-choice';SELECT count(*) FROM deadline_subtasks WHERE deadline_id='compat-choice';")=='Current exam|6.0\n3'
 tap('修改需要查看');tap('Current exam');tap('本机原有内容');tap('下一项');tap('本机原有内容');tap('下一项');tap('本机原有内容');tap('保存选择');t=capture('zh-choice-success');assert any('已保存' in s for s in t)
 restart();assert sql("SELECT name,remaining_hours FROM deadlines WHERE id='compat-choice';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-choice';SELECT count(*),count(distinct id) FROM deadline_subtasks WHERE deadline_id='compat-choice';")=='Current exam|6.0\n0\n3|3'
 tap('修改需要查看');tap('Older client update');t=capture('zh-older-upgrade');assert any('更新 Dayline' in s for s in t);assert '保存选择' not in t;tap('稍后处理');restart();tap('Old exam restored');capture('zh-restored-detail');restart();tap('设置');tap('华为账号与云同步');capture('zh-account-held')
if mode=='zh-tail':
 restart();tap('设置');tap('华为账号与云同步');capture('zh-account-held')
if mode=='de-en':
 restart();tap('设置');tap('外观与语言');select(0);tap('深色',False);select(1);tap('Deutsch',False);restart();capture('de-dark-home');tap('Änderungen prüfen');tap('Older client update');t=capture('de-dark-upgrade');assert any('aktualisier' in s.lower() for s in t);tap('Später entscheiden');restart();tap('Einstellungen');tap('Huawei');capture('de-dark-held');restart();tap('Einstellungen');tap('Darstellung');select(0);tap('Hell',False);select(1);tap('English',False);restart();capture('en-light-home');tap('Changes to review');tap('Older client update');t=capture('en-light-upgrade');assert any('Update Dayline' in s for s in t);tap('Decide later');restart();tap('Settings');tap('Huawei');capture('en-light-held');restart();tap('Old exam restored');capture('en-light-restored-detail')
if mode=='pending-zh':
 restart();tap('设置');tap('华为账号与云同步');t=capture('zh-old-data-pending');assert any('旧资料' in s for s in t)
if mode=='finish':
 restart();t=capture('final-empty-system-home');assert '创建第一个 Deadline' in t,t
 tap('设置');tap('外观与语言');t=capture('final-system-preferences');assert sum('跟随系统' in s for s in t)>=2,t
 restart()
if mode=='restore':
 restart();tap('Settings');tap('Appearance');select(0);tap('Use device setting',False);select(1);tap('Follow system',False);restart();capture('restored-system-home')
if mode=='de-resume':
 restart();tap('Einstellungen');tap('Huawei');capture('de-dark-held');restart();tap('Einstellungen');tap('Darstellung');select(0);tap('Hell',False);select(1);tap('English',False);restart();capture('en-light-home');tap('Changes to review');tap('Older client update');t=capture('en-light-upgrade');assert any('Update Dayline' in s for s in t);tap('Decide later');restart();tap('Settings');tap('Huawei');capture('en-light-held');restart();tap('Old exam restored');capture('en-light-restored-detail')
if mode=='en-tail':
 restart();tap('Settings');tap('Huawei');capture('en-light-held');restart();tap('Old exam restored');capture('en-light-restored-detail')
if mode=='final':
 restart();capture('final-signed-home');tap('修改需要查看');tap('Older client update');capture('final-signed-upgrade');tap('稍后处理');restart();tap('Current exam');capture('final-signed-choice-detail');assert sql("SELECT name,remaining_hours FROM deadlines WHERE id='compat-choice';SELECT count(*) FROM ddl_sync_issues WHERE id='compat-choice';")=='Current exam|6.0\n0';restart();tap('Old exam restored');capture('final-signed-unknown-detail')
