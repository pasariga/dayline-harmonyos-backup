from pathlib import Path
import runpy,json,sys
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];tap=h['tap'];v=h['values']('de_DE')
h['appearance'](sys.argv[1] if len(sys.argv)>1 else 'es_ES','de_DE','dark');tap(v['settings_title']);h['shot']('fixed-small-de-settings')
for key,tag in [('settings_appearance_language','appearance'),('settings_tasks_plans','planning'),('core_notification_policy','notification')]:
 tap(v[key],True);h['shot']('fixed-small-de-'+tag);u['back']()
u['back']();h['home']('de_DE');tap(v['experience_deadlines']);tap('UX19-Edge-H1',True);tap(v['experience_plan'])
for i in range(12):
 texts=u['texts']()
 if v['core_remaining_work'] in texts and v['core_risk_level'] in texts:break
 h['scroll']()
else:raise RuntimeError('Remaining and risk labels not reachable together')
h['shot']('fixed-small-de-plan-labels')
tap(v['experience_action'])
for i in range(12):
 ns=u['nodes']()
 if any(n.get('text')==v['experience_calibrate'] and h['bounds'](n)[3]<h['H']*.9 for n in ns):break
 h['scroll']()
else:raise RuntimeError('Action calibration is not reachable')
h['shot']('fixed-small-de-action-status')
u['back']();h['home']('de_DE')
print('PASS: affected headings and plan controls reachable; screenshots require visual review.',flush=True)
