from pathlib import Path
import runpy,json,time,sys
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];tap=h['tap'];v=h['values']('zh_CN')
NAME='UX19-Mathematik-Pruefung-Abschlussprojekt-langer-Titel'
def open_main():
 u['restart']();h['wait'](v['experience_now'])
results=json.loads((OUT/'keyboard-results.json').read_text()) if (OUT/'keyboard-results.json').exists() else []
for kind,id in [('Remaining','remainingEstimate'),('Task','detailTaskName'),('Name','deadlineName'),('Note','deadlineNote')]:
 if len(sys.argv)>1 and kind.lower()!=sys.argv[1].lower():continue
 open_main();record=h['record'](NAME)
 if kind=='Task':
  assert h['sql']("SELECT count(*) FROM deadline_subtasks WHERE deadline_id='"+record+"' AND title='UX19-Keyboard-Task-Resize';")=='0'
 result=u['run']('shell','aa test -b com.gary.ddl -m entry_test -s unittest OpenHarmonyTestRunner -s class hardeningKeyboard'+kind+' -s timeout 90000 -w 180')
 (OUT/('keyboard-'+kind.lower()+'-final.log')).write_text(result,encoding='utf-8')
 assert 'Tests run: 1, Failure: 0, Error: 0, Pass: 1' in result,kind+' native keyboard test did not pass'
 for suffix in ['', '-back','-submitted']:
  filename='hardening-keyboard-'+id+suffix+'.png'
  u['run']('file','recv','/data/app/el2/100/base/com.gary.ddl/cache/'+filename,str(OUT/filename))
 state=h['state'](record);assert state['total']==10 and state['complete']==0
 if kind=='Remaining':assert state['remaining']==6 and state['state']=='confirmed'
 if kind=='Task':assert h['sql']("SELECT count(*) FROM deadline_subtasks WHERE deadline_id='"+record+"' AND title='UX19-Keyboard-Task-Resize';")=='1'
 if kind=='Name':assert h['sql']("SELECT name FROM deadlines WHERE id='"+record+"';")==NAME
 if kind=='Note':
  path=OUT/'keyboard-note-value.json';u['run']('file','recv','/data/app/el2/100/base/com.gary.ddl/cache/hardening-keyboard-deadlineNote-value.json',str(path))
  value=json.loads(path.read_text(encoding='utf-8'))['value'];assert len(value)>=280
  assert h['sql']("SELECT hex(note) FROM deadlines WHERE id='"+record+"';")==value.encode('utf-8').hex().upper()
 results=[r for r in results if r['field']!=id]
 results.append({'field':id,'native_pass':True,'back_retains_input':True,'submit_reachable':True,'database_checked':True})
 (OUT/'keyboard-results.json').write_text(json.dumps(results,indent=2))
 print('PASS: keyboard '+kind,flush=True)
print('PASS: four prepared fields; actual keyboard visibility must also be inspected in captured PNGs.',flush=True)
