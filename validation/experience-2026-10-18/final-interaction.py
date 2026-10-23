from pathlib import Path
import json
p=Path('entry/src/main/ets/pages/DeadlineDetail.ets')
s=p.read_text(encoding='utf-8')
a=s.index('        Text(this.completed ?',s.index('  ObjectHeader()'))
b=s.index('\n          .fontSize(13)',a)
text=s[a:b]
assert text.endswith(')')
body=text[len('        Text('):-1]
s=s[:a]+"        Text(("+body+") + (this.hasPendingDraft() ? ' · ' + LocalizationService.text('experience_unsaved') : ''))"+s[b:]
p.write_text(s,encoding='utf-8')

p=Path('entry/src/main/ets/pages/Index.ets')
s=p.read_text(encoding='utf-8')
s=s.replace('    return this.todayActions.slice(1);','''    return this.todayActions.slice(1).filter((action: TodayAction) =>
      action.kind !== 'overdue-review' && !this.heldDeadlineIds.includes(action.deadlineId));''',1)
pos=s.index('  private getVisibleDeadlines()')
s=s[:pos]+'''  private getAttentionActions(): TodayAction[] {
    return this.todayActions.slice(1).filter((action: TodayAction) =>
      action.kind === 'overdue-review' || this.heldDeadlineIds.includes(action.deadlineId));
  }

'''+s[pos:]
pos=s.index('          if (this.scheduleAgenda.length > 0 && this.todayActions.length > 0)')
s=s[:pos]+'''          if (this.getAttentionActions().length > 0) {
            Divider().color($r('app.color.divider')).margin({ top: 18, bottom: 22 })
            this.SectionHeader(LocalizationService.text('overdue_decide_label'))
            ForEach(this.getAttentionActions(), (action: TodayAction) => { this.TodayActionRow(action) },
              (action: TodayAction) => `${action.deadlineId}:${action.kind}:${action.title}`)
          }
'''+s[pos:]
s=s.replace("  @State showActionReason: boolean = false;\n",'')
p.write_text(s,encoding='utf-8')

values={'base':'Changes not saved','en_US':'Changes not saved','zh_CN':'更改未保存','zh_TW':'變更未儲存',
 'de_DE':'Änderungen noch nicht gespeichert','ja_JP':'変更は未保存です','ko_KR':'변경 사항이 저장되지 않음',
 'es_ES':'Cambios sin guardar','fr_FR':'Modifications non enregistrées'}
for folder,value in values.items():
 p=Path('entry/src/main/resources')/folder/'element/messages.json'
 text=p.read_text(encoding='utf-8');idx=text.rfind(']')
 text=text[:idx].rstrip()+',\n    '+json.dumps({'name':'experience_unsaved','value':value},ensure_ascii=False)+'\n  '+text[idx:]
 json.loads(text);p.write_text(text,encoding='utf-8')
print('Unsaved work stays explicit across workspace changes; decisions stay separate from executable steps.')
