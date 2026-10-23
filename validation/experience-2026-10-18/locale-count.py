from pathlib import Path
import json,re
values={'base':'Tasks: {0} / {1} done','en_US':'Tasks: {0} / {1} done','zh_CN':'任务进度：{0} / {1}',
 'zh_TW':'任務進度：{0} / {1}','de_DE':'Aufgaben: {0} / {1} erledigt','ja_JP':'タスク進捗 {0} / {1} 完了',
 'ko_KR':'작업 진행 {0} / {1} 완료','es_ES':'Tareas: {0} / {1} completadas','fr_FR':'Tâches : {0} / {1} terminées'}
for folder,value in values.items():
 p=Path('entry/src/main/resources')/folder/'element/messages.json'
 text=p.read_text(encoding='utf-8')
 text,n=re.subn(r'\{"name": "experience_task_count", "value": "[^"\n]*"\}',json.dumps({'name':'experience_task_count','value':value},ensure_ascii=False),text)
 assert n==1
 p.write_text(text,encoding='utf-8')
print('Task counts use ordinary language; their leaf-task definition remains in the explanation.')
