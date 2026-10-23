from pathlib import Path
import json, re

# Operational data information, not a substitute for the owner's privacy policy.
copy = {
 'zh_CN': [
  '云同步暂未开放。已保存的数据仍可在本机使用。',
  '保存在本机；系统备份取决于设备设置',
  'Deadline、任务和设置保存在本机。本版本不提供账号登录或应用云同步。若设备开启系统备份，系统可能备份应用数据，具体取决于设备设置。通知是可选的，关闭通知不影响本地使用。卸载或清除应用数据可能丢失记录。',
  '提醒送达受系统权限、设备和后台调度影响。请在 App 内核对截止日期。',
  '尝试按所选时间安排提醒，送达受系统限制。请以 App 内截止日期为准。',
  '{0}。提醒尚未登记，请稍后打开 Dayline 查看。',
  '状态已保存。提醒尚未更新，请稍后打开 Dayline 查看。',
  'Deadline 已删除，系统提醒取消尚未确认。请稍后重新打开 Dayline。'],
 'zh_TW': [
  '雲端同步尚未開放。已儲存的資料仍可在此裝置使用。',
  '儲存在此裝置；系統備份依裝置設定',
  'Deadline、任務與設定儲存在此裝置。本版本不提供帳號登入或應用程式雲端同步。若裝置開啟系統備份，系統可能備份應用程式資料，依裝置設定而定。通知為選用功能，關閉不影響本機使用。解除安裝或清除應用程式資料可能遺失紀錄。',
  '提醒是否送達取決於系統權限、裝置與背景排程。請在 App 內確認截止日期。',
  '嘗試依所選時間安排提醒，送達受系統限制。請以 App 內截止日期為準。',
  '{0}。提醒尚未排入系統，請稍後開啟 Dayline 查看。',
  '狀態已儲存。提醒尚未更新，請稍後開啟 Dayline 查看。',
  'Deadline 已刪除，系統提醒取消尚未確認。請稍後重新開啟 Dayline。'],
 'en_US': [
  'Cloud sync is not available yet. Your saved data remains usable on this device.',
  'On-device storage; system backup depends on device settings',
  'Deadlines, tasks and settings are saved on this device. This version offers no account sign-in or app cloud sync. If system backup is enabled, the system may back up app data according to device settings. Notifications are optional; turning them off does not affect local use. Uninstalling or clearing app data may erase your records.',
  'Reminder delivery depends on system permission, the device and background scheduling. Check due dates in the app.',
  'Dayline attempts to schedule the selected time. Delivery is subject to system limits; check the due date in the app.',
  '{0}. The reminder is not scheduled yet. Open Dayline later to check.',
  'Status saved. Reminders have not updated yet. Open Dayline later to check.',
  'Deadline deleted. System reminder cancellation is not confirmed yet. Reopen Dayline later.'],
 'ja_JP': [
  'クラウド同期はまだ利用できません。保存済みのデータはこの端末で引き続き使えます。',
  '端末に保存・システムのバックアップは端末設定によります',
  'Deadline、タスク、設定はこの端末に保存されます。このバージョンではログインやアプリのクラウド同期は利用できません。システムのバックアップが有効な場合、端末設定に応じてアプリのデータがバックアップされることがあります。通知は任意で、無効にしても端末での利用に影響しません。アンインストールやアプリデータの消去で記録が失われることがあります。',
  '通知の配信はシステムの許可、端末、バックグラウンド処理に左右されます。アプリ内で締切を確認してください。',
  '選んだ時刻で通知の登録を試みます。配信はシステムの制限を受けるため、アプリ内の締切を確認してください。',
  '{0}。通知はまだ登録されていません。後でDaylineを開いて確認してください。',
  '状態を保存しました。通知はまだ更新されていません。後でDaylineを開いて確認してください。',
  'Deadlineを削除しました。システム通知の取り消しはまだ確認できていません。後でDaylineを開いてください。'],
 'ko_KR': [
  '클라우드 동기화는 아직 제공되지 않습니다. 저장된 데이터는 이 기기에서 계속 사용할 수 있습니다.',
  '기기에 저장 · 시스템 백업은 기기 설정에 따름',
  'Deadline, 작업, 설정은 이 기기에 저장됩니다. 이 버전에서는 계정 로그인이나 앱 클라우드 동기화를 제공하지 않습니다. 시스템 백업이 켜져 있으면 기기 설정에 따라 앱 데이터가 백업될 수 있습니다. 알림은 선택 사항이며 꺼도 기기 내 사용에는 영향이 없습니다. 앱을 삭제하거나 데이터를 지우면 기록이 사라질 수 있습니다.',
  '알림 도착 여부는 시스템 권한, 기기, 백그라운드 일정 처리에 따라 달라집니다. 앱에서 마감일을 확인하세요.',
  '선택한 시간에 알림 등록을 시도합니다. 시스템 제한으로 전달되지 않을 수 있으니 앱의 마감일을 확인하세요.',
  '{0}. 알림이 아직 예약되지 않았습니다. 나중에 Dayline을 열어 확인하세요.',
  '상태가 저장되었습니다. 알림은 아직 갱신되지 않았습니다. 나중에 Dayline을 열어 확인하세요.',
  'Deadline이 삭제되었습니다. 시스템 알림 취소는 아직 확인되지 않았습니다. 나중에 Dayline을 다시 열어 주세요.'],
 'de_DE': [
  'Cloud-Synchronisierung ist noch nicht verfügbar. Gespeicherte Daten bleiben auf diesem Gerät nutzbar.',
  'Auf dem Gerät gespeichert; Systemsicherung nach Geräteeinstellung',
  'Deadlines, Aufgaben und Einstellungen werden auf diesem Gerät gespeichert. Diese Version bietet keine Anmeldung oder Cloud-Synchronisierung der App. Bei aktivierter Systemsicherung kann das System App-Daten gemäß den Geräteeinstellungen sichern. Benachrichtigungen sind optional; ohne sie bleibt die lokale Nutzung möglich. Deinstallieren oder Löschen der App-Daten kann Ihre Einträge entfernen.',
  'Ob Erinnerungen ankommen, hängt von Systemberechtigung, Gerät und Hintergrundplanung ab. Prüfen Sie Termine in der App.',
  'Dayline versucht, die gewählte Zeit einzuplanen. Die Zustellung unterliegt Systemgrenzen; prüfen Sie den Termin in der App.',
  '{0}. Die Erinnerung ist noch nicht eingeplant. Öffnen Sie Dayline später zur Kontrolle.',
  'Status gespeichert. Erinnerungen sind noch nicht aktualisiert. Öffnen Sie Dayline später zur Kontrolle.',
  'Deadline gelöscht. Die Aufhebung der Systemerinnerung ist noch nicht bestätigt. Öffnen Sie Dayline später erneut.'],
 'es_ES': [
  'La sincronización en la nube aún no está disponible. Los datos guardados siguen disponibles en este dispositivo.',
  'Datos en el dispositivo; copia del sistema según sus ajustes',
  'Los plazos, las tareas y los ajustes se guardan en este dispositivo. Esta versión no ofrece inicio de sesión ni sincronización de la app en la nube. Si la copia del sistema está activada, el sistema puede copiar los datos de la app según los ajustes del dispositivo. Las notificaciones son opcionales; desactivarlas no afecta al uso local. Desinstalar o borrar los datos de la app puede eliminar tus registros.',
  'La entrega de avisos depende de los permisos, el dispositivo y la programación en segundo plano. Consulta los plazos en la app.',
  'Dayline intenta programar la hora elegida. La entrega depende de los límites del sistema; consulta el plazo en la app.',
  '{0}. El aviso aún no está programado. Abre Dayline más tarde para comprobarlo.',
  'Estado guardado. Los avisos aún no se han actualizado. Abre Dayline más tarde para comprobarlo.',
  'Plazo eliminado. La cancelación del aviso del sistema aún no está confirmada. Vuelve a abrir Dayline más tarde.'],
 'fr_FR': [
  'La synchronisation cloud n’est pas encore disponible. Les données enregistrées restent utilisables sur cet appareil.',
  'Données sur l’appareil ; sauvegarde selon ses réglages',
  'Les échéances, tâches et réglages sont enregistrés sur cet appareil. Cette version ne propose ni connexion à un compte ni synchronisation cloud de l’app. Si la sauvegarde système est activée, le système peut sauvegarder les données de l’app selon les réglages de l’appareil. Les notifications sont facultatives ; les désactiver ne gêne pas l’usage local. Désinstaller l’app ou effacer ses données peut supprimer vos éléments.',
  'La réception des rappels dépend des autorisations, de l’appareil et de la planification en arrière-plan. Vérifiez les échéances dans l’app.',
  'Dayline tente de programmer l’heure choisie. La réception dépend des limites du système ; vérifiez l’échéance dans l’app.',
  '{0}. Le rappel n’est pas encore programmé. Ouvrez Dayline plus tard pour vérifier.',
  'État enregistré. Les rappels ne sont pas encore actualisés. Ouvrez Dayline plus tard pour vérifier.',
  'Échéance supprimée. L’annulation du rappel système n’est pas encore confirmée. Rouvrez Dayline plus tard.']
}
copy['base'] = copy['en_US']
keys=['cloud_release_unavailable','settings_privacy_summary','settings_privacy_desc',
 'notification_delivery_notice','create_reminder_on_desc','message_saved_reminder_retry',
 'message_status_updated_reminder_retry','message_deadline_deleted_reminder_retry']
for folder,values in copy.items():
    for kind in ['string','messages']:
        p=Path('entry/src/main/resources')/folder/'element'/(kind+'.json')
        text=p.read_text(encoding='utf-8')
        data=json.loads(text)
        for key,value in zip(keys,values):
            exists=any(r['name']==key for r in data['string'])
            if not exists and key not in ['cloud_release_unavailable','notification_delivery_notice']:
                continue
            if not exists and kind!='messages':
                continue
            if exists:
                pattern=r'("name":\s*"'+key+r'",\s*"value":\s*)"(?:[^"\\]|\\.)*"'
                text,n=re.subn(pattern,lambda m:m.group(1)+json.dumps(value,ensure_ascii=False),text)
                assert n==1
            else:
                # Append without reformatting unrelated resource rows.
                end=text.rfind(']')
                text=text[:end].rstrip()+',\n    '+json.dumps({'name':key,'value':value},ensure_ascii=False)+'\n  '+text[end:]
        json.loads(text)
        p.write_text(text,encoding='utf-8')
print('Updated eight scope/data/reminder messages in nine locale resource sets.')
