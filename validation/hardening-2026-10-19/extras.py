from pathlib import Path
import runpy,json,time,sys,re
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];o=h['o'];tap=h['tap'];v=h['values']('zh_CN');shot=h['shot']
MAIN='UX19-Mathematik-Pruefung-Abschlussprojekt-langer-Titel'
def main():
 u['restart']();h['wait'](v['experience_now']);h['home']('zh_CN');tap(v['experience_deadlines']);tap(MAIN,True);h['wait'](v['experience_action'])
 return h['record'](MAIN)
def task_rows(id):return json.loads(h['sql']("SELECT json_group_array(json_object('id',id,'title',title,'parent',parent_id,'done',completed)) FROM deadline_subtasks WHERE deadline_id='"+id+"';"))
def select_day(day):
 for i in range(10):
  ns=u['nodes'](True);labels=[n.get('text','') for n in ns if n.get('type')=='Text' and re.fullmatch(r'\d+日',n.get('text',''))]
  if str(day)+'日' in labels:o['system_tap'](str(day)+'日');return
  numbers=sorted(int(x[:-1]) for x in labels);assert numbers
  o['system_tap'](str(min(numbers,key=lambda x:abs(x-day)))+'日')
 raise RuntimeError('Desired day is not reachable in native picker')
def more(title):
 for i in range(14):
  ns=u['nodes']();xs=[n for n in ns if n.get('type')=='Button' and n.get('text')=='⋯' and n.get('description')==title]
  if xs:h['click'](xs[0]);return
  h['scroll'](True,ns)
 raise RuntimeError('Task action context not found')
if sys.argv[1]=='tasks':
 id=main();rows=task_rows(id);initial={r['id'] for r in rows}
 for i in range(40):
  if len(rows)>=30:break
  title='UX19-Step-%02d-Check-coursework-and-notes'%i
  if any(r['title']==title for r in rows):continue
  h['fill']('detailTaskName',title);tap(v['common_add'],True)
  updated=task_rows(id);assert len(updated)==len(rows)+1,'Task addition was not committed exactly once'
  rows=updated
  print('Task count',len(rows),flush=True)
 tap(v['experience_action'])
 target=next(r for r in rows if r['title'].startswith('Literaturrecherche'))
 for i in range(14):
  ns=u['nodes']();labels=[n for n in ns if n.get('type')=='Text' and n.get('text')==target['title']]
  circles=[n for n in ns if n.get('type')=='Row' and abs((h['bounds'](n)[2]-h['bounds'](n)[0])-77)<3 and abs((h['bounds'](n)[3]-h['bounds'](n)[1])-77)<3]
  choices=[]
  for label in labels:
   lx,ly,lrx,lby=h['bounds'](label)
   for circle in circles:
    x1,y1,x2,y2=h['bounds'](circle)
    if ly<=(y1+y2)//2<=lby and x2<lx:choices.append((circle,label))
  if choices:break
  h['scroll'](True,ns)
 else:raise RuntimeError('Observed checkbox geometry not available')
 circle,label=choices[-1];x1,y1,x2,y2=h['bounds'](circle)
 x=x2+28;assert x<h['bounds'](label)[0],'Point must be outside both the visible circle and task label'
 u['run']('shell','uitest uiInput click %d %d'%(x,(y1+y2)//2));time.sleep(.8)
 assert next(r for r in task_rows(id) if r['id']==target['id'])['done']==1
 shot('large-task-response-outside-icon')
 tap(v['common_undo']);assert all(r['done']==0 for r in task_rows(id))
 # A real child/grandchild branch, without changing the data model.
 branch=next(r for r in rows if r['title'].startswith('UX19-Step-00'))
 tap(v['experience_action']);
 # Make the first root rows visible; More describes the particular task.
 more(branch['title']);tap(v['task_add_child'],True)
 shot('child-editor-focus')
 h['fill']('detailTaskName','UX19-Child');tap(v['common_add'],True)
 child=next(r for r in task_rows(id) if r['title']=='UX19-Child');assert child['parent']==branch['id']
 tap(v['experience_action']);more('UX19-Child');tap(v['task_add_child'],True)
 h['fill']('detailTaskName','UX19-Grandchild');tap(v['common_add'],True)
 rows=task_rows(id);grand=next(r for r in rows if r['title']=='UX19-Grandchild');assert grand['parent']==child['id']
 assert initial<={r['id'] for r in rows};assert len(rows)==len({r['id'] for r in rows})
 tap(v['experience_action']);shot('large-task-tree')
 (OUT/'large-task-results.json').write_text(json.dumps({'nodes':len(rows),'original_task_ids_preserved':True,
  'checkbox_hit_8vp_outside_visual_mark':True,'undo_restores_state':True,'child_grandchild_preserved':True,'duplicate_tasks':0},indent=2))
elif sys.argv[1]=='eight':
 # One long automatic work object plus seven auxiliary records.
 u['restart']();h['wait'](v['settings_title'])
 specs=[('H1',120),('H2',120),('U1',0),('U2',0),('O1',0),('O2',0),('C1',0)]
 for key,hours in specs:
  name='UX19-Edge-'+key
  existing=[r for r in h['remember']() if r['name']==name]
  if existing:continue
  h['home']('zh_CN');tap('+');h['fill']('deadlineName',name);tap(v['experience_tomorrow'])
  if hours:tap(v['experience_add_details'],True);h['fill']('totalEstimate',str(hours))
  tap(v['create_save'],True);h['wait'](v['settings_title']);h['record'](name)
  count=int(h['sql']('SELECT count(*) FROM deadlines;'));print('Project count',count,flush=True)
  if count==3:shot('edge-three-today')
 assert h['sql']('SELECT count(*) FROM deadlines;')=='8'
 h['home']('zh_CN');shot('edge-eight-priority');tap(v['experience_deadlines']);shot('edge-eight-list')
 for key in ['O1','O2']:
  tap('UX19-Edge-'+key,True);tap(v['common_edit']);h['click'](h['ensure']('deadlineDate'))
  select_day(17);o['system_tap']('确定');tap(v['create_save_changes'],True)
  shot('edge-overdue-'+key);u['back']();h['home']('zh_CN');tap(v['experience_deadlines'])
 for key in ['C1','H2']:
  tap('UX19-Edge-'+key,True);tap(v['detail_mark_complete'],True);shot('edge-completed-'+key);u['back']();h['home']('zh_CN');tap(v['experience_deadlines'])
 h['home']('zh_CN');shot('edge-eight-mixed-today')
 states={'projects':int(h['sql']('SELECT count(*) FROM deadlines;')),'completed':int(h['sql']('SELECT count(*) FROM deadlines WHERE completed=1;')),
  'unknown':int(h['sql']('SELECT count(*) FROM deadlines WHERE estimated_hours=0 AND completed=0;')),
  'overdue':int(h['sql']('SELECT count(*) FROM deadlines WHERE deadline_at<'+str(int(time.time()*1000))+' AND completed=0;'))}
 assert states['projects']==8 and states['completed']==2 and states['overdue']==2
 tap(v['experience_deadlines']);h['scroll']();h['scroll']();u['back']();shot('edge-list-back-to-today')
 states['back_from_scrolled_list_exposes_home_header']=any(n.get('id')=='homeAddDeadline' for n in u['nodes']())
 states['back_from_scrolled_list_exposes_primary_action']=v['experience_now'] in u['texts']()
 (OUT/'edge-results.json').write_text(json.dumps(states,indent=2))
else:raise RuntimeError('Unknown extra phase')
print('PASS:',sys.argv[1],flush=True)
