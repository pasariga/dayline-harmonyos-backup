from pathlib import Path
p=Path('entry/src/main/ets/pages/DeadlineDetail.ets')
s=p.read_text(encoding='utf-8')
a=s.index('  WorkAssessment()')
b=s.index('  @Builder\n  DetailContent()',a)
part=s[a:b]
automatic=part.index("        if (this.deadline.progressMode === 'automatic')")
risk=part.index("        Row({ space: 12 }) {\n          Text($r('app.string.core_risk_level'))",automatic)
part=part[:automatic]+part[risk:]
risk=part.index("        Row({ space: 12 }) {\n          Text($r('app.string.core_risk_level'))")
remaining=part.index("        Row({ space: 12 }) {\n          Text($r('app.string.core_remaining_work'))",risk)
status=part.index('        Text(this.getRemainingEstimateStatus())',remaining)
risk_block=part[risk:remaining]
remaining_block=part[remaining:status]
part=part[:risk]+remaining_block+risk_block+part[status:]
part=part.replace('        Text(this.getRemainingEstimateStatus())','        if (!this.remainingEditorVisible) {\n        Text(this.getRemainingEstimateStatus())',1)
part=part.replace('        if (!this.completed) {','        }\n        if (!this.completed) {',1)
part=part.replace("          Button(LocalizationService.text('remaining_update_button'))", "          if (!this.remainingEditorVisible) {\n          Button(LocalizationService.text('experience_calibrate'))",1)
part=part.replace('          if (this.remainingEditorVisible) {','          }\n          if (this.remainingEditorVisible) {\n            Button(LocalizationService.text(\'common_cancel\'))\n              .type(ButtonType.Normal).height(40).fontSize(13).fontColor($r(\'app.color.text_body\'))\n              .backgroundColor(Color.Transparent).enabled(!this.isSavingRemaining)\n              .onClick(() => {\n                this.remainingEditorVisible = false;\n                this.remainingHoursText = this.deadline.remainingHours > 0 ? `${this.deadline.remainingHours}` : \'\';\n                this.remainingHoursError = \'\';\n              })',1)
# No stale/empty schedule warning underneath an active calibration form.
reason=part.index('      Text(this.getInsight().riskReason)')
part=part[:reason]+'''      if (!this.remainingEditorVisible) {
      if (this.getInsight().riskLevel !== 'unknown') {
'''+part[reason:]
pos=part.index("      if (this.deadline.progressMode === 'automatic')",part.index('      Text(this.getInsight().riskReason)'))
part=part[:pos]+'''      }
      if (this.getInsight().riskLevel === 'high' || this.getInsight().riskLevel === 'medium' ||
        this.getInsight().riskLevel === 'overdue') {
        Button(LocalizationService.text('overdue_edit_button')).type(ButtonType.Normal).height(44)
          .fontSize(14).fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
          .onClick(() => { this.openEditor(); })
      }
'''+part[pos:]
plan=part.index('      Column({ space: 12 })',part.index('      Text(this.getInsight().riskReason)'))
part=part[:plan]+"      if (this.getSchedulePlan().days.length > 0 || this.completed) {\n"+part[plan:]
part=part.replace("            Text($r('app.string.detail_schedule_hint'))\n              .fontSize(12)\n              .fontColor($r('app.color.text_tertiary'))",'')
part=part.rstrip()
assert part.endswith('  }')
part=part[:-3]+'      }\n      }\n  }\n\n'
s=s[:a]+part+s[b:]
s=s.replace("        Text(LocalizationService.text('experience_calibration_hint')).width('100%').fontSize(13)\n          .fontColor($r('app.color.text_secondary')).margin({ top: 12 })\n",'')
# Retain the original allowance for long project names in the portrait context.
head=s.index('  ObjectHeader()')
tail=s.index('  NextStep()',head)
s=s[:head]+s[head:tail].replace('.maxLines(2)', '.maxLines(3)',1)+s[tail:]
p.write_text(s,encoding='utf-8')
print('Calibration is one focused form; risk and plans resume after a successful confirmation.')
