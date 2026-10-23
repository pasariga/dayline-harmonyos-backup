from pathlib import Path
import json
keys=['today','deadlines','now','start','decide','after','upcoming','objects_hint','planned_today',
      'partial_plan','hours_pending','short_plan','action','plan','calibrate','calibration_hint',
      'record','task_count','name','due','tomorrow','due_clock','add_details','hide_details','create_hint','created']
translations={
'base': ['Today','Deadlines','Start with this','Start here','Decide what to do','After that','The next few days',
 'Open a deadline to pick up where you left off.','About {0} hr scheduled today','some estimates still need checking',
 'Today’s hours need an estimate','A short work session is scheduled','Action','Workload & plan','Re-estimate',
 'When your judgment changes, check how much time you still need. No daily time log required.',
 'Deadline details','{0} of {1} leaf tasks complete','What needs doing?','When is it due?','Tomorrow','Due at {0} · Change',
 'Add workload or tasks (optional)','Hide optional details','A name and due date are enough to start.','Saved: {0}'],
'zh_CN': ['今天','Deadlines','先从这一步开始','开始这一步','处理这件事','之后再做','接下来几天',
 '打开一项 Deadline，接着往前推进。','今天已安排约 {0} 小时','另有工作量待确认',
 '今日工时待确认','今天已安排一小段工作','行动','工作量与计划','校准剩余时间',
 '判断有变化时，再确认大概还需多久。不用每天记工时。','Deadline 资料','最末级任务已完成 {0} / {1}',
 '要完成什么？','什么时候截止？','明天','截止于 {0} · 更改','补充工时或任务（可选）','收起补充信息',
 '先记下名称和截止日期，就可以开始。','已记录：{0}'],
'zh_TW': ['今天','Deadlines','先從這一步開始','開始這一步','處理這件事','之後再做','接下來幾天',
 '開啟一項 Deadline，接著往前推進。','今天已安排約 {0} 小時','另有工作量待確認',
 '今日工時待確認','今天已安排一小段工作','行動','工作量與計畫','調整剩餘時間',
 '判斷有變化時，再確認大概還需多久。不必每天記工時。','Deadline 資料','最末級任務已完成 {0} / {1}',
 '要完成什麼？','什麼時候截止？','明天','截止於 {0} · 更改','補充工時或任務（選填）','收起補充資訊',
 '先記下名稱和截止日期，就可以開始。','已記錄：{0}'],
'de_DE': ['Heute','Deadlines','Damit anfangen','Jetzt beginnen','Entscheidung treffen','Danach','Die nächsten Tage',
 'Deadline öffnen und dort weitermachen.','Heute etwa {0} Std. eingeplant','weitere Schätzungen noch offen',
 'Zeitbedarf für heute noch offen','Eine kurze Arbeitseinheit ist eingeplant','Aktion','Aufwand & Plan','Restaufwand prüfen',
 'Bei einer neuen Einschätzung angeben, wie viel Zeit noch nötig ist. Kein tägliches Zeitprotokoll.',
 'Deadline-Details','{0} von {1} Teilaufgaben erledigt','Was ist zu tun?','Wann ist es fällig?','Morgen','Fällig um {0} · Ändern',
 'Aufwand oder Aufgaben ergänzen (optional)','Zusatzangaben ausblenden','Name und Termin reichen für den Anfang.','Gespeichert: {0}'],
'ja_JP': ['今日','Deadlines','まずはこの一歩から','ここから始める','対応を決める','そのあとに','これから数日',
 'Deadlineを開いて、続きに取り組みましょう。','今日は約{0}時間を予定','見積もりの確認が必要な作業もあります',
 '今日の作業時間は未確認','今日は短い作業を予定','取り組む','作業量と計画','残り時間を見直す',
 '見通しが変わったときに、あとどのくらい必要か確認します。毎日の時間記録は不要です。',
 'Deadlineの情報','末端タスク {0} / {1} 完了','何を終わらせますか？','締め切りはいつですか？','明日','{0}まで · 変更',
 '作業時間やタスクを追加（任意）','追加情報を閉じる','名前と締め切りだけで始められます。','保存しました：{0}'],
'ko_KR': ['오늘','Deadlines','이것부터 시작해요','이 단계 시작','처리 방법 결정','그다음 할 일','앞으로 며칠',
 'Deadline을 열고 이어서 진행하세요.','오늘 약 {0}시간 배정','남은 시간을 확인할 작업도 있어요',
 '오늘 필요한 시간은 확인 중','오늘 짧은 작업이 배정됐어요','진행','작업량과 계획','남은 시간 확인',
 '예상이 달라졌을 때 얼마나 더 필요한지 확인하세요. 매일 시간을 기록할 필요는 없어요.',
 'Deadline 정보','마지막 단계 작업 {0} / {1} 완료','무엇을 끝내야 하나요?','언제까지인가요?','내일','마감 {0} · 변경',
 '시간이나 작업 추가 (선택)','추가 정보 접기','이름과 마감일만으로 시작할 수 있어요.','저장됨: {0}'],
'es_ES': ['Hoy','Deadlines','Empieza por aquí','Empezar','Decidir qué hacer','Después','Los próximos días',
 'Abre un Deadline para seguir avanzando.','Unas {0} h programadas hoy','hay otras estimaciones pendientes',
 'Falta estimar el tiempo de hoy','Hay una sesión breve programada','Acción','Trabajo y plan','Revisar tiempo restante',
 'Si cambia tu previsión, confirma cuánto tiempo falta. No hace falta registrar horas a diario.',
 'Datos del Deadline','{0} de {1} subtareas finales completadas','¿Qué hay que hacer?','¿Para cuándo?','Mañana','Vence a las {0} · Cambiar',
 'Añadir tiempo o tareas (opcional)','Ocultar datos opcionales','Un nombre y una fecha bastan para empezar.','Guardado: {0}'],
'fr_FR': ['Aujourd’hui','Deadlines','Commencer par ceci','Commencer ici','Décider de la suite','Ensuite','Les prochains jours',
 'Ouvrez un Deadline pour reprendre là où vous en étiez.','Environ {0} h prévues aujourd’hui','d’autres estimations restent à confirmer',
 'Le temps nécessaire aujourd’hui reste à estimer','Une courte séance est prévue','Action','Charge et plan','Réévaluer le temps restant',
 'Si votre estimation change, indiquez le temps encore nécessaire. Aucun suivi quotidien des heures.',
 'Détails du Deadline','{0} sous-tâches finales sur {1} terminées','Que faut-il faire ?','Pour quand ?','Demain','Échéance à {0} · Modifier',
 'Ajouter du temps ou des tâches (facultatif)','Masquer les détails facultatifs','Un nom et une échéance suffisent pour commencer.','Enregistré : {0}']
}
translations['en_US']=translations['base']
for folder,values in translations.items():
    assert len(values)==len(keys),(folder,len(values),len(keys))
    path=Path('entry/src/main/resources')/folder/'element/messages.json'
    text=path.read_text(encoding='utf-8')
    data=json.loads(text)
    assert not any(row['name'].startswith('experience_') for row in data['string'])
    rows=[{'name':'experience_'+k,'value':v} for k,v in zip(keys,values)]
    index=text.rfind(']')
    text=text[:index].rstrip()+',\n'+',\n'.join('    '+json.dumps(row,ensure_ascii=False) for row in rows)+'\n  '+text[index:]
    json.loads(text)
    path.write_text(text,encoding='utf-8')
print('26 experience strings added in all nine resource sets.')
