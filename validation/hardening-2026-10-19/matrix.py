from pathlib import Path
import runpy,json,time,sys,os
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT/'harness.py'));o=h['o'];u=h['u'];tap=h['tap'];shot=h['shot'];values=h['values']
def ratio(text):
 for i in range(12):
  if text in '\n'.join(u['texts']()):return
  h['scroll']()
 raise RuntimeError('Task count not reachable: '+text)
def case(locale,theme,font,tag,current):
 print('START',tag,flush=True)
 v=values(locale);h['appearance'](current,locale,theme)
 shot(tag+'-home')
 tap('+');h['fill']('deadlineName','UX19-'+tag);tap(v['experience_tomorrow'])
 if h['DEVICE'] in ['compact','wide']:shot(tag+'-create')
 tap(v['experience_add_details'],True);h['fill']('totalEstimate','10')
 tap(v['experience_task_options'],True);tap(v['core_automatic_progress'],True)
 tap(v['create_save'],True);h['wait'](v['settings_title'])
 id=h['record']('UX19-'+tag);initial=h['state'](id);assert initial['total']==10
 print('Created',tag,flush=True)
 h['home'](locale);tap(v['experience_deadlines']);tap('UX19-'+tag,True)
 task='Read-notes-'+tag
 h['fill']('detailTaskName',task);tap(v['common_add'],True)
 tap(v['experience_action'])
 tap(v['home_complete_task'],True)
 ratio('1 / 1')
 tap(v['common_undo']);tap(v['experience_action']);ratio('0 / 1')
 tap(v['experience_action']);tap(v['experience_calibrate'],True)
 h['fill']('remainingEstimate','6');tap(v['remaining_save_button'],True)
 tap(v['experience_plan'])
 expected=h['state'](id);assert expected['remaining']==6 and expected['state']=='confirmed'
 print('Task complete/undo and six hours confirmed',tag,flush=True)
 shot(tag+'-plan')
 tap(v['common_edit']);h['fill']('deadlineName','UX19-'+tag+'-edited')
 u['back']();o['system_tap'](v['common_cancel'])
 assert any(n.get('id')=='deadlineName' and n.get('text')=='UX19-'+tag+'-edited' for n in u['nodes']())
 tap(v['create_save_changes'],True);h['wait'](v['experience_plan'])
 print('Edit/back draft and save checked',tag,flush=True)
 assert h['state'](id)['due']==initial['due']
 tap(v['experience_calibrate'],True);h['fill']('remainingEstimate','7')
 before=u['run']('shell','pidof com.gary.ddl').strip()
 u['run']('shell','uitest uiInput keyEvent Home');time.sleep(.4)
 u['run']('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(1)
 assert before==u['run']('shell','pidof com.gary.ddl').strip()
 assert any(n.get('id')=='remainingEstimate' and n.get('text')=='7' for n in u['nodes']())
 h['top_until'](v['common_cancel']);tap(v['common_cancel']);u['restart']();h['wait'](v['settings_title'])
 print('Background draft and cold restart checked',tag,flush=True)
 tap(v['experience_deadlines']);tap('UX19-'+tag+'-edited',True)
 tap(v['experience_plan']);shot(tag+'-restart')
 actual=h['state'](id);assert actual['remaining']==6 and actual['total']==10 and actual['progress']==0
 assert h['sql']("SELECT count(*) FROM deadline_subtasks WHERE deadline_id='"+id+"';")=='1'
 if tag.endswith('-0'):
  tap(v['experience_action']);h['fill']('detailTaskName','Unsaved-next-step-'+tag)
 h['remember']();h['delete_current'](v)
 assert h['sql']("SELECT count(*) FROM deadlines WHERE id='"+id+"';")=='0'
 assert not any(n.get('type')=='AlertDialog' for n in u['nodes']())
 result={'device':h['DEVICE'],'locale':locale,'theme':theme,'font_setting':font,'tag':tag,
  'create_task_complete_undo_estimate_edit_return_background_restart':True,
  'saved_hours':actual['remaining'],'task_count_before_delete':1,'due_preserved_on_rename':True,
  'unsaved_seven_preserved_in_background':True,'confirmed_six_preserved_on_restart':True,
  'deleted_through_ui':True}
 if tag.endswith('-0'):result['committed_delete_with_unsaved_task_has_no_second_discard_dialog']=True
 p=OUT/('matrix-results-'+h['DEVICE']+'.json');results=json.loads(p.read_text()) if p.exists() else []
 results=[r for r in results if r['tag']!=tag]+[result];p.write_text(json.dumps(results,indent=2))
 print('PASS',tag,flush=True)
 return locale
if __name__=='__main__':
 current=sys.argv[1];font=int(sys.argv[2]);prefix=sys.argv[3]
 for i,(locale,theme) in enumerate([('zh_CN','light'),('zh_CN','dark'),('en_US','light'),('de_DE','dark')]):
  current=case(locale,theme,font,prefix+'-'+str(i),current)
 print('PASS: four complete locale/theme flows at font setting',font,flush=True)
