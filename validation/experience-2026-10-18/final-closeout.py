from pathlib import Path
import runpy,json,time,sys
OUT=Path(__file__).parent
o=runpy.run_path(str(OUT/'ops.py'));u=o['u'];tap=o['tap'];shot=o['snapshot']
def values(locale):
 return {r['name']:r['value'] for kind in ['string','product','messages'] for r in json.loads((Path('entry/src/main/resources')/locale/'element'/(kind+'.json')).read_text(encoding='utf-8'))['string']}
def select(index,label):
 controls=[n for n in u['nodes']() if n.get('type')=='Select']
 assert len(controls)>index
 u['run']('shell','uitest uiInput click %d %d'%u['center'](controls[index]['bounds']))
 o['system_tap'](label)
def wait(label):
 for attempt in range(20):
  if label in u['texts']():return
  time.sleep(.4)
 raise RuntimeError('Expected UI state did not appear: '+label)
if sys.argv[1]=='regression':
 wait('开始这一步');shot('last-today')
 tap('完成任务');shot('last-task-completed',('撤销',))
 tap('撤销');tap('开始这一步')
 shot('last-task-undo',('0 / 8',))
 tap('工作量与计划');shot('last-plan',('约 20 小时',))
 u['back']();tap('Deadlines');tap('UX18-Quick')
 shot('last-persisted-manual',('25%',))
 tap('工作量与计划');shot('last-persisted-unknown',('剩余工作量待确认',))
 u['back']();tap('今天')
 # Final package remains the installed main HAP; restart verifies persisted data.
 u['restart']();wait('开始这一步');shot('last-cold-start')
 (OUT/'last-regression.json').write_text(json.dumps({'home_complete_undo':True,'nested_tree_preserved':True,
  'confirmed_estimate_twenty':True,'manual_twenty_five':True,'unknown_state_preserved':True,'cold_start':True},indent=2))
elif sys.argv[1]=='german':
 z=values('zh_CN');v=values('de_DE')
 tap(z['settings_title']);tap(z['settings_appearance_language'])
 select(0,z['settings_theme_dark']);select(1,'Deutsch');wait(v['settings_title'])
 tap('+');tap(v['experience_add_details'],True);tap(v['experience_task_options'],True)
 tap(v['core_automatic_progress'],True)
 # Move mode controls fully into view; the old screenshot was at the screen edge.
 u['run']('shell','uitest uiInput swipe 650 2250 650 1300 700');time.sleep(1)
 shot('last-german-two-line-modes',(v['core_automatic_progress'],v['core_manual_progress']))
elif sys.argv[1]=='restore':
 v=values('de_DE')
 u['back']();o['system_tap'](v['editor_discard_action'])
 tap(v['settings_title']);tap(v['settings_appearance_language'])
 select(0,v['settings_theme_system']);select(1,v['settings_language_system'])
 u['restart']();wait(values('zh_CN')['settings_title']);shot('last-restored-settings')
else:raise RuntimeError('Unknown phase')
print('PASS: '+sys.argv[1],flush=True)
