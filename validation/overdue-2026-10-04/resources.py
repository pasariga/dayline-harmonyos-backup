from pathlib import Path
import json

keys = ['overdue_pending','overdue_continue','overdue_stopped','overdue_no_forecast',
        'overdue_capacity_unknown','overdue_continue_reason','overdue_review_action','overdue_choose_hint',
        'overdue_continue_button','overdue_edit_button','overdue_stop_button','overdue_reconsider_button',
        'overdue_stopped_hint','overdue_save_failed','overdue_less_hour','overdue_hours_one','overdue_hours_other',
        'overdue_days_one','overdue_days_other','overdue_complete_button']
translations = {
'zh_CN': ['已逾期 · 需要处理','已逾期 · 继续完成','不再追踪','原截止时间已过。调整截止时间后才能重新倒排，不预测仍能按时完成。','仍有逾期项目继续进行，但没有新的截止时间。暂不能判断所有工作能否按时完成。','原截止时间已过，仍可推进任务；暂不预测完工时间。','处理已逾期的「{0}」','决定是否继续，或调整截止时间。','继续完成','调整截止时间','不再追踪','重新处理','本机不再推荐此项目。原记录与任务保留，可以重新处理。','选择未保存，原记录仍在。请重试。','逾期不足 1 小时','已逾期 {0} 小时','已逾期 {0} 小时','已逾期 {0} 天','已逾期 {0} 天','标记完成'],
'zh_TW': ['已逾期 · 需要處理','已逾期 · 繼續完成','不再追蹤','原截止時間已過。調整截止時間後才能重新排程，不預測仍能如期完成。','仍有逾期項目繼續進行，但沒有新的截止時間。暫時無法判斷所有工作能否如期完成。','原截止時間已過，仍可推進任務；暫不預測完成時間。','處理已逾期的「{0}」','決定是否繼續，或調整截止時間。','繼續完成','調整截止時間','不再追蹤','重新處理','此裝置不再推薦此項目。原紀錄與任務保留，可以重新處理。','選擇未儲存，原紀錄仍在。請重試。','逾期未滿 1 小時','已逾期 {0} 小時','已逾期 {0} 小時','已逾期 {0} 天','已逾期 {0} 天','標記完成'],
'en_US': ['Overdue · Decide next step','Overdue · Still working','No longer tracking','The due time has passed. Set a new date to plan towards it; finishing on time is no longer a valid forecast.','You are still working on overdue items without new due dates. Whether all work can fit in time is uncertain.','The due time has passed. You can still work on tasks, without a completion forecast.','Decide what to do with overdue “{0}”','Keep working or change the due date.','Keep working','Change due date','Stop tracking','Reconsider','This device no longer recommends this item. Its record and tasks are kept; you can reconsider.','Your choice was not saved. The record is safe; try again.','Less than 1 hour overdue','{0} hour overdue','{0} hours overdue','{0} day overdue','{0} days overdue','Mark complete'],
'ja_JP': ['期限超過 · 対応を選択','期限超過 · 継続中','追跡を終了','元の期限は過ぎています。新しい期限を設定するまで、期限内の完了予測や逆算予定は表示しません。','新しい期限がない超過項目を継続中です。すべての作業が期限内に収まるかは判断できません。','期限は過ぎていますが、タスクは進められます。完了時期は予測しません。','期限を過ぎた「{0}」の対応を選ぶ','続けるか、期限を変更してください。','続ける','期限を変更','追跡を終了','対応を見直す','この端末ではおすすめに表示しません。記録とタスクは残り、対応を見直せます。','選択を保存できませんでした。記録は残っています。再試行してください。','期限超過から1時間未満','期限超過から{0}時間','期限超過から{0}時間','期限超過から{0}日','期限超過から{0}日','完了にする'],
'ko_KR': ['기한 지남 · 처리 필요','기한 지남 · 계속 진행','더 이상 추적하지 않음','기존 기한이 지났습니다. 새 기한을 정해야 다시 일정을 세울 수 있으며, 기한 내 완료를 예측하지 않습니다.','새 기한 없이 계속 진행하는 지난 항목이 있습니다. 전체 작업을 제때 끝낼 수 있는지는 판단할 수 없습니다.','기한은 지났지만 작업은 계속할 수 있습니다. 완료 시점은 예측하지 않습니다.','기한이 지난 “{0}” 처리하기','계속 진행하거나 기한을 바꾸세요.','계속 진행','기한 변경','추적 중단','다시 결정','이 기기에서는 더 이상 추천하지 않습니다. 기록과 작업은 유지되며 다시 결정할 수 있습니다.','선택을 저장하지 못했습니다. 기록은 안전합니다. 다시 시도하세요.','기한이 지난 지 1시간 미만','기한이 지난 지 {0}시간','기한이 지난 지 {0}시간','기한이 지난 지 {0}일','기한이 지난 지 {0}일','완료로 표시'],
'de_DE': ['Überfällig · Entscheidung nötig','Überfällig · In Arbeit','Nicht mehr verfolgen','Der Termin ist verstrichen. Erst mit einem neuen Termin ist eine Rückwärtsplanung möglich; eine pünktliche Fertigstellung wird nicht mehr vorhergesagt.','Überfällige Vorhaben laufen ohne neuen Termin weiter. Ob alle Arbeiten rechtzeitig möglich sind, bleibt unklar.','Der Termin ist verstrichen. Aufgaben können weitergehen, ohne Prognose zum Abschluss.','Überfälliges Vorhaben „{0}“ klären','Weiterarbeiten oder den Termin ändern.','Weiterarbeiten','Termin ändern','Nicht mehr verfolgen','Neu entscheiden','Dieses Gerät empfiehlt das Vorhaben nicht mehr. Eintrag und Aufgaben bleiben erhalten; die Entscheidung ist änderbar.','Auswahl nicht gespeichert. Der Eintrag bleibt erhalten. Bitte erneut versuchen.','Weniger als 1 Stunde überfällig','Seit {0} Stunde überfällig','Seit {0} Stunden überfällig','Seit {0} Tag überfällig','Seit {0} Tagen überfällig','Als erledigt markieren'],
'es_ES': ['Vencido · Decidir qué hacer','Vencido · En curso','Dejar de seguir','La fecha ya pasó. Cambia el plazo para volver a planificar; no se puede prever una entrega a tiempo.','Sigues trabajando en proyectos vencidos sin una nueva fecha. No se puede saber si todo cabe dentro de los plazos.','La fecha ya pasó. Puedes seguir con las tareas, sin una previsión de finalización.','Decide qué hacer con «{0}», ya vencido','Sigue trabajando o cambia la fecha.','Seguir trabajando','Cambiar fecha','Dejar de seguir','Revisar decisión','Este dispositivo ya no recomienda este proyecto. Se conservan el registro y las tareas; puedes revisar la decisión.','No se guardó tu elección. El registro sigue intacto. Inténtalo de nuevo.','Vencido hace menos de 1 hora','Vencido hace {0} hora','Vencido hace {0} horas','Vencido hace {0} día','Vencido hace {0} días','Marcar como completado'],
'fr_FR': ['Échu · Décision à prendre','Échu · Travail poursuivi','Ne plus suivre','L’échéance est passée. Choisissez une nouvelle date pour planifier ; une fin dans les délais ne peut plus être prévue.','Des projets échus continuent sans nouvelle date. Impossible de savoir si tout peut être terminé dans les délais.','L’échéance est passée. Vous pouvez poursuivre les tâches, sans prévision de fin.','Décider quoi faire de « {0} », dont l’échéance est passée','Poursuivez ou changez l’échéance.','Poursuivre','Changer l’échéance','Ne plus suivre','Revoir la décision','Cet appareil ne recommande plus ce projet. Le projet et ses tâches sont conservés ; la décision reste modifiable.','Votre choix n’a pas été enregistré. Le projet est conservé. Réessayez.','Échéance passée depuis moins d’une heure','Échéance passée depuis {0} heure','Échéance passée depuis {0} heures','Échéance passée depuis {0} jour','Échéance passée depuis {0} jours','Marquer comme terminé']
}
translations['base'] = translations['zh_CN']
empty = {'zh_CN':'今天没有待推荐的行动。保留的项目可在全部 Deadline 中查看。',
 'zh_TW':'今天沒有待推薦的行動。保留的項目可在全部 Deadline 中查看。',
 'en_US':'No actions to recommend today. Kept items are available in the full Deadline list.',
 'ja_JP':'今日のおすすめはありません。残した項目はDeadlineの全件一覧で確認できます。',
 'ko_KR':'오늘 추천할 작업이 없습니다. 보관된 항목은 전체 Deadline 목록에서 볼 수 있습니다.',
 'de_DE':'Heute gibt es keine Empfehlung. Erhaltene Vorhaben sind in der vollständigen Deadline-Liste sichtbar.',
 'es_ES':'Hoy no hay acciones que recomendar. Los proyectos conservados están en la lista completa de Deadline.',
 'fr_FR':'Aucune action à recommander aujourd’hui. Les projets conservés restent dans la liste complète des Deadline.'}
empty['base']=empty['zh_CN']
decide={'base':'需要处理','zh_CN':'需要处理','zh_TW':'需要處理','en_US':'Decide next step',
 'ja_JP':'対応を選択','ko_KR':'처리 필요','de_DE':'Entscheidung nötig','es_ES':'Decidir qué hacer','fr_FR':'Décision à prendre'}
root=Path('entry/src/main/resources')
for locale, values in translations.items():
    assert len(values)==len(keys)
    path=root/locale/'element/messages.json'
    data=json.loads(path.read_text(encoding='utf-8'))
    items=data['string']; names={item['name'] for item in items}
    for key,value in zip(keys,values):
        if key in names:
            next(item for item in items if item['name']==key)['value']=value
        else: items.append({'name':key,'value':value})
    key='overdue_no_actions'
    if key in names: next(item for item in items if item['name']==key)['value']=empty[locale]
    else: items.append({'name':key,'value':empty[locale]})
    key='overdue_decide_label'
    if key in names: next(item for item in items if item['name']==key)['value']=decide[locale]
    else: items.append({'name':key,'value':decide[locale]})
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Updated',len(translations),'resource sets;',len(keys),'localized keys each.')
