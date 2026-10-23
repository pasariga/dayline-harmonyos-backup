from pathlib import Path
import json
values={
'base': ['Dismiss', 'Adds plan changes to the next daily summary. Requires daily summaries.', 'Summaries and risk alerts avoid quiet hours. Due reminders move earlier when possible; urgent cutoffs are not delayed.', 'Reminder preferences saved. This reminder has not yet been scheduled.'],
'en_US': ['Dismiss', 'Adds plan changes to the next daily summary. Requires daily summaries.', 'Summaries and risk alerts avoid quiet hours. Due reminders move earlier when possible; urgent cutoffs are not delayed.', 'Reminder preferences saved. This reminder has not yet been scheduled.'],
'zh_CN': ['关闭', '计划调整并入下一次每日摘要，需开启每日摘要。', '摘要和风险提醒避开免打扰；截止提醒尽量提前。来不及提前的紧迫截止提醒不会推迟。', '提醒设置已保存，但这条提醒尚未排入系统。'],
'zh_TW': ['關閉', '計畫調整會併入下次每日摘要，需開啟每日摘要。', '摘要和風險提醒避開免打擾；到期提醒盡量提前。來不及提前的緊迫到期提醒不會延後。', '提醒設定已儲存，但這則提醒尚未排入系統。'],
'de_DE': ['Schließen', 'Planänderungen erscheinen in der nächsten Tagesübersicht. Tagesübersichten müssen aktiviert sein.', 'Übersichten und Risikohinweise meiden die Ruhezeit. Fälligkeitshinweise erscheinen möglichst vorher; dringende Fristen werden nicht verschoben.', 'Die Erinnerungseinstellung ist gespeichert. Die Erinnerung ist noch nicht im System eingeplant.'],
'es_ES': ['Cerrar', 'Los cambios del plan se incluyen en el próximo resumen diario. Requiere activar los resúmenes.', 'Los resúmenes y avisos de riesgo respetan el silencio. Los avisos de vencimiento se adelantan si es posible; los urgentes no se retrasan.', 'Los ajustes se guardaron, pero el recordatorio aún no está programado en el sistema.'],
'fr_FR': ['Fermer', 'Les changements du plan figurent dans le prochain résumé quotidien. Les résumés doivent être activés.', 'Les résumés et alertes de risque respectent la plage silencieuse. Les rappels sont avancés si possible ; les échéances urgentes ne sont pas retardées.', 'Les préférences sont enregistrées, mais ce rappel n’est pas encore programmé dans le système.'],
'ja_JP': ['閉じる', '計画の変更は次の毎日の要約にまとめます。毎日の要約をオンにしてください。', '要約とリスク通知はおやすみ時間を避けます。期限通知はできるだけ前倒しにしますが、直前の重要な通知は遅らせません。', '通知設定は保存されましたが、この通知はまだシステムに予約されていません。'],
'ko_KR': ['닫기', '계획 변경은 다음 일일 요약에 포함됩니다. 일일 요약을 켜 주세요.', '요약과 위험 알림은 방해 금지 시간을 피합니다. 마감 알림은 가능하면 앞당기지만, 임박한 마감 알림은 미루지 않습니다.', '알림 설정은 저장되었지만, 이 알림은 아직 시스템에 예약되지 않았습니다.']}
keys=['notification_action_done','notification_replan_desc','notification_quiet_desc','reminder_result_queued']
for locale,strings in values.items():
    p=Path('entry/src/main/resources')/locale/'element/messages.json'
    # Preserve formatting and unrelated translations exactly.
    s=p.read_text(encoding='utf-8'); rows=json.loads(s)['string']
    for key,value in zip(keys,strings):
        old=next(r['value'] for r in rows if r['name']==key)
        needle=json.dumps(old,ensure_ascii=False)
        # Older resources sometimes escape control characters; JSON dump agrees.
        start=s.index('"name": "'+key+'"'); end=s.index('\n    }',start)
        block=s[start:end]; assert needle in block,(locale,key)
        s=s[:start]+block.replace(needle,json.dumps(value,ensure_ascii=False),1)+s[end:]
    p.write_text(s,encoding='utf-8')
print('Updated close-button, digest/replan, quiet-hour exception and unscheduled feedback in all 9 resource sets.')
