from pathlib import Path
import json
p=Path('entry/src/main/ets/pages/CreateDeadline.ets')
s=p.read_text(encoding='utf-8')
s=s.replace('  @State showMoreOptions: boolean = false;', '  @State showMoreOptions: boolean = false;\n  @State showTaskOptions: boolean = false;\n  @State showAdvancedOptions: boolean = false;',1)
s=s.replace('    this.showMoreOptions = false;', '    this.showMoreOptions = false;\n    this.showTaskOptions = false;\n    this.showAdvancedOptions = false;',1)
s=s.replace('      this.showMoreOptions = true;', '      this.showMoreOptions = true;\n      this.showTaskOptions = true;\n      this.showAdvancedOptions = true;',1)
# Preserve pending task input instead of silently discarding it on Save.
s=s.replace('  private async saveDeadline(): Promise<void> {','''  private async saveDeadline(): Promise<void> {
    if (this.taskTitle.trim().length > 0 && (this.editingTaskId.length === 0 ||
      this.taskTitle.trim() !== this.findTaskTitle(this.editingTaskId))) {
      this.showMoreOptions = true;
      this.showTaskOptions = true;
      this.showMessage(LocalizationService.text('experience_pending_task'));
      return;
    }''',1)
s=s.replace("    if (this.nameError.length > 0 || this.dateError.length > 0 || this.hoursError.length > 0 || this.isSaving ||", "    if (this.hoursError.length > 0) { this.showMoreOptions = true; }\n    if (this.nameError.length > 0 || this.dateError.length > 0 || this.hoursError.length > 0 || this.isSaving ||",1)
# The clock control belongs to the two-field flow in edit mode too.
clock="            Button(LocalizationService.text('experience_due_clock', LocalizationService.formatClockTime(this.deadlineTime)))"
a=s.index(clock)
b=s.index('          if (!this.showMoreOptions)',a)
chunk=s[a:b]
assert chunk.rstrip().endswith('}')
chunk=chunk.rstrip()[:-1].rstrip()+'\n\n'
s=s[:a]+'          }\n'+chunk+s[b:]
type_start=s.index("          Column({ space: 9 }) {\n            this.FieldLabel($r('app.string.field_type')")
mode_start=s.index("          Column({ space: 10 }) {\n            this.FieldLabel($r('app.string.field_progress_mode')", type_start)
time_start=s.index("          Column({ space: 9 }) {\n            this.FieldLabel($r('app.string.field_due_time')", mode_start)
reminder_start=s.index("          Column({ space: 9 }) {\n            this.FieldLabel($r('app.string.field_reminder')",time_start)
note_end=s.index("        .width('100%')\n        .margin({ top: 24 })",reminder_start)
# Last two braces before the outer form's width close advanced details + outer form.
tail=s[reminder_start:note_end]
assert tail.endswith('          }\n        }\n')
tail=tail[:-len('          }\n        }\n')]
type_block=s[type_start:mode_start]
mode_block=s[mode_start:time_start]
def toggle(key,field):
 return '''          Row() {
            Text(LocalizationService.text('%s')).fontSize(14).fontColor($r('app.color.text_body'))
            Blank()
            Text(this.%s ? '−' : '+').fontSize(18).fontColor($r('app.color.brand_accent'))
          }.width('100%%').padding({ top: 12, bottom: 12 })
            .onClick(() => { this.%s = !this.%s; })
'''%(key,field,field,field)
new=toggle('experience_task_options','showTaskOptions')+'          if (this.showTaskOptions) {\n'+mode_block+'          }\n'
new+=toggle('experience_advanced_options','showAdvancedOptions')+'          if (this.showAdvancedOptions) {\n'+type_block+tail+'          }\n          }\n        }\n'
s=s[:type_start]+new+s[note_end:]
p.write_text(s,encoding='utf-8')

p=Path('entry/src/main/ets/pages/DeadlineDetail.ets')
s=p.read_text(encoding='utf-8')
# Put the receipt before the new next step, rather than below the tabs.
a=s.index('      if (this.undoTaskId.length > 0)',s.index('  DetailContent()'))
b=s.index("        if (this.deadline.progressMode === 'automatic')",a)
receipt=s[a:b]
s=s[:a]+s[b:]
receipt=receipt.replace(".fontColor($r('app.color.text_body'))", ".fontColor(this.undoTaskWasCompleted ? $r('app.color.success') : $r('app.color.text_body'))",1)
s=s.replace('        if (!this.completed && this.workspace === 0) {',receipt+'        if (!this.completed && this.workspace === 0) {',1)
p.write_text(s,encoding='utf-8')

p=Path('entry/src/main/ets/pages/Index.ets')
s=p.read_text(encoding='utf-8')
s=s.replace("Text($r('app.string.home_empty_tagline'))", "Text($r('app.string.experience_empty_title'))",1)
s=s.replace("Text($r('app.string.home_empty_body'))", "Text($r('app.string.experience_empty_body'))",1)
# Add real current work to the project object, using existing insight semantics.
s=s.replace('        Text(this.getDeadlineDateText(deadline))','''        if (!deadline.completed) {
          Text(DeadlineInsightService.hasUsableRemainingEstimate(this.getInsight(deadline).workloadConfidence) ?
            LocalizationService.text('experience_remaining', this.getInsight(deadline).remainingHours) :
            LocalizationService.text('work_remaining_pending'))
            .fontSize(13).fontColor($r('app.color.text_body')).maxLines(2)
        }
        Text(this.getDeadlineDateText(deadline))''',1)
p.write_text(s,encoding='utf-8')

keys=['pending_task','task_options','advanced_options','empty_title','empty_body','remaining']
locales={
'base':['Add the task you are typing, or clear it before saving.','Tasks & progress','Type, reminders & notes',
 'Today starts with one thing.','What is the next thing you need to hand in or finish?','About {0} hr left'],
'zh_CN':['请先添加正在填写的任务，或清空输入后保存。','任务与进度','类型、提醒与备注',
 '今天，从一件事开始。','最近要交什么、完成什么？先记下来。','剩余约 {0} 小时'],
'zh_TW':['請先新增正在填寫的任務，或清空輸入後儲存。','任務與進度','類型、提醒與備註',
 '今天，從一件事開始。','最近要交什麼、完成什麼？先記下來。','剩餘約 {0} 小時'],
'de_DE':['Die eingegebene Aufgabe erst hinzufügen oder vor dem Speichern leeren.','Aufgaben & Fortschritt','Typ, Erinnerungen & Notizen',
 'Heute beginnt mit einer Sache.','Was musst du als Nächstes abgeben oder fertigstellen?','Noch etwa {0} Std.'],
'ja_JP':['入力中のタスクを追加するか、入力を消してから保存してください。','タスクと進捗','種類・リマインダー・メモ',
 '今日の一歩を、ひとつ。','次に提出するもの、終わらせたいことは何ですか？','残り約{0}時間'],
'ko_KR':['입력 중인 작업을 추가하거나 입력을 지운 후 저장하세요.','작업과 진행률','유형, 알림과 메모',
 '오늘은 한 가지부터.','다음으로 제출하거나 끝내야 할 일을 기록해 보세요.','약 {0}시간 남음'],
'es_ES':['Añade la tarea que estás escribiendo o borra el texto antes de guardar.','Tareas y progreso','Tipo, recordatorios y notas',
 'Hoy empieza con una cosa.','¿Qué es lo próximo que tienes que entregar o terminar?','Quedan unas {0} h'],
'fr_FR':['Ajoutez la tâche en cours de saisie ou effacez-la avant d’enregistrer.','Tâches et progression','Type, rappels et notes',
 'Aujourd’hui commence par une chose.','Que devez-vous rendre ou terminer ensuite ?','Environ {0} h restantes']}
locales['en_US']=locales['base']
for folder,values in locales.items():
 p=Path('entry/src/main/resources')/folder/'element/messages.json'
 text=p.read_text(encoding='utf-8');idx=text.rfind(']')
 rows=[{'name':'experience_'+key,'value':value} for key,value in zip(keys,values)]
 text=text[:idx].rstrip()+',\n'+',\n'.join('    '+json.dumps(row,ensure_ascii=False) for row in rows)+'\n  '+text[idx:]
 json.loads(text);p.write_text(text,encoding='utf-8')
print('Optional creation groups and in-context feedback refined; 32 messages per locale.')
