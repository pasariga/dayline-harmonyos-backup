from pathlib import Path
import runpy,json,time
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
 for attempt in range(16):
  if label in u['texts']():return
  time.sleep(.4)
 raise RuntimeError('Expected translated home did not appear')
def change(current,target,theme):
 v=values(current)
 tap(v['settings_title']);tap(v['settings_appearance_language'])
 select(0,v['settings_theme_dark'] if theme=='dark' else v['settings_theme_light'])
 select(1,'English' if target=='en_US' else 'Deutsch')
 wait(values(target)['settings_title'])
def inspect(locale,tag):
 v=values(locale)
 shot(tag+'-today',(v['experience_today'],v['experience_start']))
 tap(v['experience_start'])
 shot(tag+'-action',('UX18-Design-Coursework-with-a-very-long-project-title',v['experience_plan']))
 tap(v['experience_plan']);shot(tag+'-plan')
 tap(v['experience_calibrate']);shot(tag+'-calibration')
 tap(v['common_cancel']);u['back']();tap('+')
 shot(tag+'-create',(v['experience_name'],v['experience_due']))
 tap(v['experience_add_details'],True);tap(v['experience_task_options'],True)
 tap(v['core_automatic_progress'],True)
 shot(tag+'-create-progress')
 # Selecting a progress mode is a real draft choice, even with an empty name.
 u['back']()
 if any(n.get('type')=='AlertDialog' for n in u['nodes']()):
  o['system_tap'](v['editor_discard_action'])
 assert not any(n.get('type')=='AlertDialog' for n in u['nodes']())
change('zh_CN','en_US','dark');inspect('en_US','english-dark')
change('en_US','de_DE','dark');inspect('de_DE','german-dark')
v=values('de_DE')
tap(v['settings_title']);tap(v['settings_appearance_language']);select(0,v['settings_theme_light'])
u['back']();u['back']();shot('german-light-today')
tap(v['experience_start']);shot('german-light-action')
u['back']();tap('+');o['fill']('UX18-Locale-Draft','deadlineName');u['back']()
shot('german-draft-back-dialog',(v['editor_discard_action'],))
o['system_tap'](v['common_cancel']);shot('german-draft-retained',('UX18-Locale-Draft',))
u['back']();o['system_tap'](v['editor_discard_action'])
# Restore the exact original theme/language choice through the real settings UI.
tap(v['settings_title']);tap(v['settings_appearance_language']);select(0,v['settings_theme_system'])
select(1,v['settings_language_system']);u['restart']();time.sleep(1)
wait(values('zh_CN')['settings_title'])
shot('final-system-theme-language')
(OUT/'runtime-locales.json').write_text(json.dumps({'english_dark':True,'german_dark':True,'german_light':True,
 'german_back_cancel_retains_draft':True,'original_system_theme_and_language_restored':True},indent=2))
print('PASS: locale/theme workflows, real dialogs, original settings restored.',flush=True)
