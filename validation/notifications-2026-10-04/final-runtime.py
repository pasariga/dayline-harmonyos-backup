from pathlib import Path
import runpy,tempfile,json,xml.etree.ElementTree as ET,hashlib
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'));run=h['call']
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
checks={}
with tempfile.TemporaryDirectory() as folder:
 for name in ['dayline_app_settings','ddl_notification_settings','dayline_overdue_choices']:
  local=Path(folder)/name;run('file','recv',base+name,str(local))
  values={node.get('key'):(node.get('value') if node.get('value') is not None else node.text or '') for node in ET.parse(local).getroot()}
  if name=='dayline_app_settings':
   assert values['theme_mode']=='system' and values['language_mode']=='system'
   assert float(values['daily_available_hours'])==3 and float(values['weekend_available_hours'])==5
  elif name=='ddl_notification_settings':
   assert values['intensity']=='standard' and values['quiet_enabled']=='true'
   assert float(values['summary_hour'])==8 and float(values['summary_minute'])==30
   assert float(values['quiet_start'])==1350 and float(values['quiet_end'])==480
   assert values.get('last_activity_deadline_id','')=='' and float(values.get('last_activity_at',0))==0
   assert json.loads(values.get('risk_marks','[]'))==[] and values.get('last_plan_task_ids','')==''
  else:assert json.loads(values['choices'])==[]
  checks[name]='restored / no acceptance runtime'
dump=run('shell','bm dump -n com.gary.ddl')
bundle=json.JSONDecoder().raw_decode(dump[dump.index('{'):])[0]
assert 'entry_test' not in [module['moduleName'] for module in bundle['hapModuleInfos']]
checks['test_module']='absent'
record=json.loads((OUT/'signed-hap.json').read_text(encoding='utf-8-sig'))
assert hashlib.sha256(Path(record['Path']).read_bytes()).hexdigest().upper()==record['Hash']
checks['final_signed_hap_sha256']=record['Hash']
(OUT/'runtime-final.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps(checks))
