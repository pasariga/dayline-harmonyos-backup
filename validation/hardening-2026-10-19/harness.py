from pathlib import Path
import runpy,json,time,re,os,shlex
OUT=Path(__file__).parent
o=runpy.run_path(str(OUT/'ops.py'));u=o['u'];tap=o['tap'];shot=o['snapshot']
W=int(os.environ.get('DAYLINE_TEST_WIDTH','1320'));H=int(os.environ.get('DAYLINE_TEST_HEIGHT','2856'))
DEVICE=os.environ.get('DAYLINE_TEST_DEVICE','pura')
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
h['sql'].__globals__['call']=lambda *args:u['run'](*args).strip()
sql=h['sql']
def values(locale):
 return {r['name']:r['value'] for kind in ['string','product','messages'] for r in json.loads((Path('entry/src/main/resources')/locale/'element'/(kind+'.json')).read_text(encoding='utf-8'))['string']}
def bounds(n):return tuple(map(int,re.findall(r'\d+',n['bounds'])))
def click(n):u['run']('shell','uitest uiInput click %d %d'%u['center'](n['bounds']));time.sleep(.35)
def scroll(down=True,observed=None):
 ns=observed if observed is not None else u['nodes']()
 sc=[n for n in ns if n.get('type')=='Scroll']
 left,top,right,bottom=bounds(sc[0]) if sc else (0,0,W,H)
 x=left+4;y1=max(top+70,int(H*.78));y2=max(top+30,int(H*.25))
 if not down:y1,y2=y2,y1
 u['run']('shell','uitest uiInput swipe %d %d %d %d 800'%(x,y1,x,y2));time.sleep(.2)
def wait(label,timeout=12):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  if label in u['texts']():return
  time.sleep(.25)
 raise RuntimeError('Expected UI did not appear: '+label)
def ensure(id,down=True):
 for i in range(14):
  ns=u['nodes']();items=[n for n in ns if n.get('id')==id and bounds(n)[3] < H*.95 and bounds(n)[3]-bounds(n)[1]>35]
  if items:return items[0]
  scroll(down,ns)
 raise RuntimeError('Input unavailable: '+id)
def fill(id,value):
 ensure(id)
 try:o['fill'](value,id)
 except AssertionError as error:
  if str(error)!='Input value not visible after typing':raise
  # Closing the real keyboard may retain a lower Scroll offset on a short
  # display. Reobserve the same input rather than infer that text was lost.
  n=ensure(id,False)
  assert n.get('text')==value,'Typed input differs after returning to the field'
def fill_area(value):
 n=ensure('deadlineNote');click(n)
 u['run']('shell','uitest uiInput keyEvent 2072 2017');u['run']('shell','uitest uiInput keyEvent 2055')
 u['run']('shell','uitest uiInput text '+shlex.quote(value));u['run']('shell','uitest uiInput keyEvent 2070');time.sleep(.3)
def top_until(label):
 for i in range(12):
  if label in u['texts']():return
  scroll(False)
 raise RuntimeError('Cannot return to page top: '+label)
def home(locale):
 v=values(locale);ensure('homeAddDeadline',False);wait(v['settings_title'])
 tap(v['experience_today'])
def select(index,label):
 cs=[n for n in u['nodes']() if n.get('type')=='Select']
 assert len(cs)>index,'Select is not visible'
 click(cs[index]);o['system_tap'](label)
def appearance(current,target,theme):
 v=values(current);home(current);tap(v['settings_title']);tap(v['settings_appearance_language'])
 select(0,v['settings_theme_dark'] if theme=='dark' else v['settings_theme_light'])
 if current!=target:
  names={'zh_CN':'简体中文','en_US':'English','de_DE':'Deutsch','fr_FR':'Français','es_ES':'Español'}
  select(1,names[target]);wait(values(target)['settings_title'])
 else:u['back']();u['back']()
 home(target)
def system_font(index,tag):
 u['run']('shell','aa start -a com.huawei.hmos.settings.MainAbility -b com.huawei.hmos.settings');time.sleep(1)
 def globaltap(text):
  xs=[n for n in u['nodes'](True) if n.get('text')==text]
  assert xs,'System display setting is not visible: '+text
  click(xs[-1])
 for i in range(12):
  ns=u['nodes'](True);texts=[n.get('text') for n in ns]
  if '字体大小' in texts and any(n.get('type')=='Slider' for n in ns):break
  if '字体大小和界面缩放' in texts and '显示和亮度' not in texts:
   u['run']('shell','uitest uiInput swipe 4 %d 4 %d 800'%(int(H*.82),int(H*.25)))
  elif '字体大小和界面缩放' in texts:globaltap('字体大小和界面缩放')
  elif '显示和亮度' in texts:
   entries=[n for n in ns if n.get('id')=='display_settings']
   if entries:click(entries[0])
   else:u['run']('shell','uitest uiInput swipe 4 %d 4 %d 800'%(int(H*.82),int(H*.25)))
  else:u['back']()
 else:raise RuntimeError('System font page unavailable')
 for i in range(10):
  ns=u['nodes'](True)
  if any(n.get('text')=='设置更大字体' for n in ns):globaltap('取消');continue
  labels=[n for n in ns if n.get('text')=='字体大小']
  assert labels
  labelbottom=bounds(labels[0])[3]
  sliders=[n for n in ns if n.get('type')=='Slider' and bounds(n)[1]>=labelbottom]
  if not sliders:
   # System font controls can lie below the preview on a short screen.
   u['run']('shell','uitest uiInput swipe %d %d %d %d 800'%(W//2,int(H*.8),W//2,int(H*.3)));continue
  slider=sliders[0];actual=round(float(slider['text']))
  if actual==index:break
  x1,y1,x2,y2=bounds(slider)
  u['run']('shell','uitest uiInput click %d %d'%((x2-2 if actual<index else x1+2),(y1+y2)//2));time.sleep(.3)
 else:raise RuntimeError('Could not confirm the system font setting')
 ns=u['nodes'](True)
 (OUT/(tag+'-system-font.json')).write_text(json.dumps({'device':DEVICE,'index':index,
  'sliders':[{'value':n.get('text'),'bounds':n.get('bounds')} for n in ns if n.get('type')=='Slider']},indent=2))
 u['restart']()
def remember(expected_name=None):
 rows=json.loads(sql("SELECT json_group_array(json_object('id',id,'name',name)) FROM deadlines WHERE name LIKE 'UX19-%';"))
 p=OUT/('fixtures-'+DEVICE+'.json');known={r['id']:r for r in json.loads(p.read_text())} if p.exists() else {}
 for r in rows:
  if r['id'] in known or r['name']==expected_name:known[r['id']]=r
 p.write_text(json.dumps(list(known.values()),ensure_ascii=False,indent=2),encoding='utf-8')
 return rows
def record(name):
 rows=remember(name);matches=[r for r in rows if r['name']==name];assert len(matches)==1,(name,len(matches))
 return matches[0]['id']
def state(id):
 return json.loads(sql("SELECT json_object('total',estimated_hours,'remaining',remaining_hours,'state',remaining_state,'progress',progress,'due',deadline_at,'complete',completed) FROM deadlines WHERE id='"+id+"';"))
def delete_current(v):
 tap(v['common_delete'],True)
 assert any(n.get('type')=='AlertDialog' for n in u['nodes']())
 o['system_tap'](v['common_delete']);wait(v['settings_title'])
