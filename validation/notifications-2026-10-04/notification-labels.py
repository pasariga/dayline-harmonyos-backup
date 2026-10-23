from pathlib import Path
import json
labels={
 'base':['A daily summary when there is something to do, with extra alerts when risk clearly rises.','Schedules summaries further ahead and checks in sooner when risk rises, without repeating the same alert.'],
 'en_US':['A daily summary when there is something to do, with extra alerts when risk clearly rises.','Schedules summaries further ahead and checks in sooner when risk rises, without repeating the same alert.'],
 'zh_CN':['有行动时每日一份摘要，风险明显上升时另行提醒。','提前安排更多天的摘要，风险上升时提醒更及时，避免重复打扰。'],
 'zh_TW':['有行動時每日一份摘要，風險明顯上升時另行提醒。','提前安排更多天的摘要，風險上升時更及時提醒，避免重複打擾。'],
 'de_DE':['Eine Tagesübersicht, wenn etwas ansteht. Zusätzliche Hinweise nur bei deutlich steigendem Risiko.','Übersichten werden weiter voraus geplant. Bei steigendem Risiko erinnern wir früher, ohne denselben Hinweis zu wiederholen.'],
 'es_ES':['Un resumen diario si hay algo que hacer, con avisos adicionales cuando el riesgo aumenta claramente.','Programa resúmenes con más antelación y avisa antes si aumenta el riesgo, sin repetir el mismo aviso.'],
 'fr_FR':['Un résumé quotidien s’il reste quelque chose à faire, avec des alertes supplémentaires si le risque augmente nettement.','Les résumés sont prévus plus à l’avance. Si le risque augmente, les alertes arrivent plus tôt, sans répéter la même alerte.'],
 'ja_JP':['取り組むことがある日に要約を送り、リスクが明らかに高まったときは追加でお知らせします。','数日先まで要約を予約し、リスクが高まったときは早めにお知らせします。同じ通知は繰り返しません。'],
 'ko_KR':['할 일이 있는 날에 요약을 보내고, 위험이 뚜렷하게 높아지면 추가로 알려 드립니다.','더 먼 날짜까지 요약을 예약하고 위험이 높아지면 더 빨리 알려 드립니다. 같은 알림은 반복하지 않습니다.']}
for locale,values in labels.items():
 p=Path('entry/src/main/resources')/locale/'element/messages.json';s=p.read_text(encoding='utf-8')
 rows=json.loads(s)['string']
 for key,value in zip(['notification_intensity_standard_desc','notification_intensity_active_desc'],values):
  old=next(r['value'] for r in rows if r['name']==key)
  start=s.index('"name": "'+key+'"');end=s.index('\n    }',start)
  block=s[start:end];needle=json.dumps(old,ensure_ascii=False);assert needle in block
  s=s[:start]+block.replace(needle,json.dumps(value,ensure_ascii=False),1)+s[end:]
 p.write_text(s,encoding='utf-8')
print('9 localized preset descriptions now match daily/risk policy.')
