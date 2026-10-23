from pathlib import Path
p=Path('entry/src/main/ets/pages/DeadlineDetail.ets')
s=p.read_text(encoding='utf-8')
s=s.replace('  private workspaceInitialized: boolean = false;', '  private workspaceInitialized: boolean = false;\n  private workScroller: Scroller = new Scroller();',1)
s=s.replace('    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => { this.workspace = value; });',
'''    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => { this.workspace = value; });
    this.workScroller.scrollEdge(Edge.Top);''',1)
s=s.replace("this.workspace = 1; this.remainingEditorVisible = true;", "this.switchWorkspace(1); this.remainingEditorVisible = true;",1)
# A leaf-task receipt remains visible even when the user completes a deep row.
a=s.index('      if (this.undoTaskId.length > 0)',s.index('  NextStep()'))
b=s.index('        if (!this.completed && this.workspace === 0)',a)
receipt=s[a:b]
s=s[:a]+s[b:]
pos=s.index('  @Builder\n  NextStep()')
s=s[:pos]+'''  @Builder
  TaskReceipt() {
'''+receipt+'''  }

  private async changeCompletionFromUI(): Promise<void> {
    const previous: boolean = this.completed;
    await this.toggleCompleted();
    if (this.pageVisible && previous !== this.completed) { this.workScroller.scrollEdge(Edge.Top); }
  }

'''+s[pos:]
# Replace UI handlers only; the original transaction/completion method is unchanged.
s=s.replace('onClick(() => { this.toggleCompleted(); })','onClick(() => { this.changeCompletionFromUI(); })')
s=s.replace('''        .onClick(() => {
          this.toggleCompleted();
        })''','''        .onClick(() => {
          this.changeCompletionFromUI();
        })''')
s=s.replace('        this.WorkspaceTabs()\n', '        this.WorkspaceTabs()\n        this.TaskReceipt()\n',1)
s=s.replace('      Scroll() {\n', '      Scroll(this.workScroller) {\n',1)
p.write_text(s,encoding='utf-8')

p=Path('entry/src/main/ets/pages/CreateDeadline.ets')
s=p.read_text(encoding='utf-8')
a=s.index('          Text(this.tasks.length === 0 ?')
b=s.index('        }\n        .alignItems',a)
s=s[:a]+'''          if (this.tasks.length === 0) {
            Text(LocalizationService.text('tasks_empty_save_later')).fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
'''+s[b:]
# Adding a draft item is subordinate to saving the complete Deadline.
a=s.index('  AutomaticTaskDraftEditor()')
b=s.index('  build() {',a)
part=s[a:b]
part=part.replace('          .fontColor(Color.White)\n          .backgroundColor($r(\'app.color.brand\'))',
'''          .fontColor($r('app.color.brand_accent'))
          .backgroundColor($r('app.color.surface_muted'))''',1)
s=s[:a]+part+s[b:]
p.write_text(s,encoding='utf-8')
print('Workspace switches reset the working surface; task receipts stay reachable; draft percentages removed.')
