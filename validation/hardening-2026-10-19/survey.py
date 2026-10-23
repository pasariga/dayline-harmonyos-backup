"""Read-only settings and transient form/dialog checks in a long locale."""
from pathlib import Path
import runpy,json,sys
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];tap=h['tap'];o=h['o']
current,locale,theme,tag=sys.argv[1:];v=h['values'](locale)
h['appearance'](current,locale,theme);h['shot'](tag+'-today')
tap(v['settings_title']);h['shot'](tag+'-settings')
tap(v['settings_tasks_plans'],True);h['shot'](tag+'-planning-top')
h['scroll']();h['shot'](tag+'-planning-bottom');u['back']()
tap(v['core_notification_policy'],True);h['shot'](tag+'-notification-top')
tap(v['notification_more_settings'],True);h['scroll']();h['shot'](tag+'-notification-advanced');u['back']()
tap(v['settings_privacy'],True);h['shot'](tag+'-data-dialog');o['system_tap'](v['review_understood'])
u['back']();h['home'](locale);tap('+');tap(v['create_save'],True)
assert v['validation_name_required'] in u['texts']()
h['shot'](tag+'-empty-error');h['click'](h['ensure']('deadlineDate',False))
h['shot'](tag+'-date-dialog');u['back']();u['back']()
h['home'](locale)
result={'device':h['DEVICE'],'locale':locale,'theme':theme,'settings_planning_notification_data_dialog':True,
 'empty_form_error_and_date_dialog_back':True,'business_data_written':False,'notification_and_plan_values_changed':False}
(OUT/(tag+'-survey.json')).write_text(json.dumps(result,indent=2));print('PASS',tag,flush=True)
