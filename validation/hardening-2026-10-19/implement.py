from pathlib import Path
import re
pages=Path('entry/src/main/ets/pages')
for name in ['Index','DeadlineDetail','CreateDeadline','Settings','AppearanceLanguageSettings','PlanningSettings','NotificationSettings']:
 p=pages/(name+'.ets');s=p.read_text(encoding='utf-8')
 # These are existing short action buttons, not a new control or visual system.
 s=re.sub(r'\.height\((38|40|42)\)',r'.constraintSize({ minHeight: 44 })',s)
 if name=='Index':
  s=s.replace(".width(44).height(44).fontSize(26)",".width(44).height(44).fontSize(26).padding(0).maxFontScale(1)")
  s=s.replace('.width(40)\n        .height(44)', '.width(44)\n        .height(44)\n        .accessibilityRole(AccessibilityRoleType.CHECKBOX)\n        .accessibilityText(action.title)\n        .accessibilityChecked(false)')
  s=s.replace('.height(48).fontSize(this.homeSpace === 0 ? 25 : 18)', '.height(48).fontSize(this.homeSpace === 0 ? 25 : 18)\n            .accessibilitySelected(this.homeSpace === 0)')
  s=s.replace('.height(48).fontSize(this.homeSpace === 1 ? 25 : 18)', '.height(48).fontSize(this.homeSpace === 1 ? 25 : 18)\n            .accessibilitySelected(this.homeSpace === 1)')
  a=s.index('  DeadlineCard(');b=s.index('  private switchHome',a)
  part=s[a:b].replace("          .maxLines(2)\n          .textOverflow({ overflow: TextOverflow.Ellipsis })",' ',1)
  s=s[:a]+part+s[b:]
  s=s.replace(".fontColor($r('app.color.text_primary')).maxLines(4)",".fontColor($r('app.color.text_primary'))")
  s=s.replace(".fontColor($r('app.color.text_body')).maxLines(2)\n        Text(LocalizationService.formatDateTime", ".fontColor($r('app.color.text_body'))\n        Text(LocalizationService.formatDateTime")
 if name in ['DeadlineDetail','CreateDeadline']:
  # Keep the 22vp visual mark; the actual hit target is 44vp and exposes its state.
  marker='.width(22)\n'
  i=s.index(marker);end=s.index('.onClick(() => { this.toggleTask',i)
  part=s[i:end]
  insertion=".responseRegion({ x: -11, y: -11, width: 44, height: 44 })\n                  .accessibilityRole(AccessibilityRoleType.CHECKBOX)\n                  .accessibilityText(view.task.title)\n                  .accessibilityChecked(view.progress === 100)\n                  "
  s=s[:end]+insertion+s[end:]
  a=s.index('Text(view.task.title)',end);b=s.index('.decoration(',a)
  part=s[a:b];part=re.sub(r'\s*\.maxLines\(2\)\s*\.textOverflow\(\{ overflow: TextOverflow.Ellipsis \}\)', '',part)
  s=s[:a]+part+s[b:]
  # Icon glyphs must not be clipped by the native text button's default padding.
  a=s.index("Button('⋯')");b=s.index('.onClick',a)
  part=s[a:b].replace('.fontSize(20)', '.fontSize(20)\n                .padding(0).maxFontScale(1)')
  s=s[:a]+part+s[b:]
 if name=='DeadlineDetail':
  a=s.index('  ObjectHeader()');b=s.index('  TaskReceipt()',a)
  part=s[a:b].replace("          .maxLines(3)\n          .textOverflow({ overflow: TextOverflow.Ellipsis })",'')
  s=s[:a]+part+s[b:]
  s=s.replace("Button(LocalizationService.text('experience_action')).type(ButtonType.Normal)","Button(LocalizationService.text('experience_action')).type(ButtonType.Normal)\n        .accessibilitySelected(this.workspace === 0)")
  s=s.replace("Button(LocalizationService.text('experience_plan')).type(ButtonType.Normal)","Button(LocalizationService.text('experience_plan')).type(ButtonType.Normal)\n        .accessibilitySelected(this.workspace === 1)")
 if name=='CreateDeadline':
  s=s.replace("Button($r('app.string.core_automatic_progress'))", "Button($r('app.string.core_automatic_progress'))\n                .accessibilitySelected(this.progressMode === 'automatic')")
  s=s.replace("Button($r('app.string.core_manual_progress'))", "Button($r('app.string.core_manual_progress'))\n                .accessibilitySelected(this.progressMode === 'manual')")
 p.write_text(s,encoding='utf-8')
 print('Hardened existing presentation:',name)
