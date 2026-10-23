"""Restore captured non-sensitive preferences; clear only known test runtime."""
from pathlib import Path
import runpy,xml.etree.ElementTree as ET
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
run=h['call'];run('shell','aa force-stop com.gary.ddl')
base='/data/app/el2/100/base/com.gary.ddl/haps/entry/preferences/'
for name in ['dayline_app_settings','ddl_notification_settings']:
 tree=ET.parse(OUT/(name+'.before.xml'))
 if name=='ddl_notification_settings':
  root=tree.getroot()
  activity=root.find("string[@key='last_activity_deadline_id']")
  assert activity is not None and activity.text=='overdue-acceptance-final-1'
  activity.text=''
  root.find("double[@key='last_activity_at']").set('value','0.000000')
  root.find("string[@key='last_plan_date']").text=''
  root.find("string[@key='last_plan_task_ids']").text=''
  ET.SubElement(root,'string',key='risk_marks').text='[]'
  ET.SubElement(root,'double',key='last_risk_at',value='0.000000')
 local=OUT/(name+'.restored.xml');tree.write(local,encoding='utf-8',xml_declaration=True)
 names=run('shell','ls '+base).split()
 assert name in names
 run('file','send',str(local),base+name)
 if name+'.bak' in names:run('file','send',str(local),base+name+'.bak')
print('Restored original preference choices; known acceptance activity/plan/risk runtime cleared.')
