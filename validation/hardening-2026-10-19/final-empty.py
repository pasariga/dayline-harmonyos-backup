from pathlib import Path
import runpy,json,re,time
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];v=h['values']('zh_CN')
assert h['sql']('SELECT count(*) FROM deadlines;')=='0'
u['restart']();h['wait'](v['experience_empty_title']);h['shot']('final-empty-cold-home')
n=h['ensure']('homeAddDeadline',False);x,y=u['center'](n['bounds'])
u['run']('shell','uitest uiInput doubleClick %d %d'%(x,y));h['wait'](v['create_new_title'])
u['back']();h['wait'](v['settings_title'])
assert h['sql']('SELECT count(*) FROM deadlines;')=='0'
u['run']('shell','uitest uiInput keyEvent Home')
u['run']('shell','aa start -a EntryAbility -b com.gary.ddl');h['wait'](v['settings_title'])
u['restart']();h['wait'](v['experience_empty_title']);h['shot']('final-empty-restarted-home')
dump=u['run']('shell','bm dump -n com.gary.ddl')
assert not re.search(r'"(?:name|moduleName)"\s*:\s*"entry_test"',dump),'Remove instrumentation module'
result={'empty_cold_start':True,'double_click_add_then_one_back_returns_home':True,
 'empty_background_resume':True,'empty_force_stop_restart':True,'test_module_absent':True,
 'integrity':h['sql']('PRAGMA integrity_check;'),'database_version':int(h['sql']('PRAGMA user_version;'))}
assert result['integrity']=='ok' and result['database_version']==8
(OUT/'final-empty.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
