from pathlib import Path
p=Path('entry/src/main/ets/pages/DeadlineDetail.ets')
s=p.read_text(encoding='utf-8')
s=s.replace('  @State workspace: number = 0;', '  @State workspace: number = 0;\n  @State compactWorkspace: boolean = false;',1)
a=s.index('  @Builder\n  ObjectHeader()')
b=s.index('  @Builder\n  WorkActions()',a)
header=s[a:b]
split=header.index('      if (this.undoTaskId.length > 0)')
head=header[:split]
tail=header[split:]
# Both builders use independent columns. The business handlers remain untouched.
head += "      }\n      .width('100%').alignItems(HorizontalAlign.Start).padding({ top: 14, bottom: 8 })\n  }\n\n"
head=head.replace('.maxLines(3)', '.maxLines(2)',1)
tail='''  @Builder
  NextStep() {
    Column({ space: 10 }) {
'''+tail
s=s[:a]+head+tail+s[b:]
s=s.replace('      this.ObjectHeader()\n      this.WorkspaceTabs()', '      this.NextStep()',1)
# Keep occasional calibration above a possibly very long task tree.
content=s.index('  DetailContent()')
a=s.index('        this.WorkActions()',content)
b=s.index('      } else {\n        Text(LocalizationService.text(\'experience_calibration_hint\'))',a)
workarea=s[a:b]
assert workarea.startswith('        this.WorkActions()\n')
workarea=workarea[len('        this.WorkActions()\n'):]
workarea=workarea.replace(".onClick(() => { this.workspace = 1; this.remainingEditorVisible = true; })",
 " .onClick(() => { if (this.syncHeld) { this.openConflictReview(); } else { this.workspace = 1; this.remainingEditorVisible = true; } })")
s=s[:a]+workarea+'        this.WorkActions()\n'+s[b:]
start=s.index('  build() {')
# Reuse the exact existing navigation, loading, conflict and error handlers.
old=s[start:]
nav_a=old.index('        Row({ space: 14 })')
nav_b=old.index('        if (this.syncHeld)',nav_a)
navigation=old[nav_a:nav_b]
navigation=navigation.replace("Text($r('app.string.app_name'))", "Text(this.compactWorkspace && this.deadline.id.length > 0 ? this.deadline.name : LocalizationService.text('app_name'))",1)
navigation=navigation.replace('.maxLines(2)', '.maxLines(1)',1)
states_a=nav_b
states_b=old.index("      }\n      .width('100%')",states_a)
states=old[states_a:states_b]
states=states.replace('.margin({ top: 22 })','.margin({ top: 8 })')
s=s[:start]+'''  build() {
    Column({ space: 0 }) {
'''+navigation+'''      if (!this.isLoading && this.loadError.length === 0) {
        if (!this.compactWorkspace) { this.ObjectHeader() }
        this.WorkspaceTabs()
      }
      Scroll() {
        Column({ space: 0 }) {
'''+states+'''        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 12 })
      .alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.app_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onAreaChange((previous: Area, current: Area) => {
        const compact: boolean = Number(current.width) > Number(current.height);
        if (this.compactWorkspace !== compact) { this.compactWorkspace = compact; }
      })
  }
}
'''
p.write_text(s,encoding='utf-8')

p=Path('entry/src/main/ets/pages/CreateDeadline.ets')
s=p.read_text(encoding='utf-8')
# Main create actions use the same quiet shape as Today; no extra container.
start=s.index('  build() {')
s=s[:start]+s[start:].replace('.type(ButtonType.Capsule)', '.type(ButtonType.Normal)\n          .borderRadius(10)')
p.write_text(s,encoding='utf-8')
print('Deadline context and workspaces remain reachable while the working surface scrolls.')
