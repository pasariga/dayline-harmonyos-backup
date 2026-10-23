"""Reorganize the three presentation builders, preserving original domain methods."""
from pathlib import Path
OUT=Path(__file__).parent
PAGES=Path('entry/src/main/ets/pages')
def original(name): return (OUT/(name+'.before.ets')).read_text(encoding='utf-8')
def write(name,s): (PAGES/(name+'.ets')).write_text(s,encoding='utf-8')

s=original('Index')
s=s.replace("import { ReleaseScope }", "import { ExperiencePresentation, ExperienceRouteParams, CreationReceipt, TodayContext } from '../services/ExperiencePresentation';\nimport { ReleaseScope }",1)
s=s.replace("  @State deadlines:","  @State homeSpace: number = 0;\n  @State createdName: string = '';\n  @State createdId: string = '';\n  @State showActionReason: boolean = false;\n  @State deadlines:",1)
s=s.replace('    this.pageVisible = true;','''    this.pageVisible = true;
    const receipt: CreationReceipt | undefined = ExperiencePresentation.consumeCreated();
    this.createdName = receipt?.name ?? '';
    this.createdId = receipt?.deadlineId ?? '';
    if (receipt !== undefined) { this.homeSpace = 0; }''',1)
s=s.replace('private openDeadlineDetail(deadlineId: string): void','private openDeadlineDetail(deadlineId: string, workspace: number = 0): void')
s=s.replace('params: new DeadlineRouteParams(deadlineId)','params: new ExperienceRouteParams(deadlineId, workspace)',1)
start=s.index('  @Builder\n  PriorityActionCard(')
end=s.index('  @Builder\n  TodayActionRow(',start)
s=s[:start]+'''  private switchHome(space: number): void {
    if (this.updatingActionId.length > 0) { return; }
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.homeSpace = space;
    });
  }

  onBackPress(): boolean {
    if (this.homeSpace !== 0) { this.switchHome(0); return true; }
    return false;
  }

  private todayPlanText(): string {
    const context: TodayContext = ExperiencePresentation.todayContext(this.scheduleAgenda, Date.now());
    if (!context.hasSchedule) { return ''; }
    if (context.scheduledHours > 0 && context.scheduledHours < 0.5) {
      return LocalizationService.text('experience_short_plan');
    }
    if (context.scheduledHours >= 0.5) {
      return LocalizationService.text('experience_planned_today',
        DeadlineInsightService.normalizeHours(context.scheduledHours)) +
        (context.hasUnknownWork ? ' · ' + LocalizationService.text('experience_partial_plan') : '');
    }
    return context.hasUnknownWork ? LocalizationService.text('experience_hours_pending') : '';
  }

  @Builder
  PriorityActionCard(action: TodayAction) {
    Column({ space: 16 }) {
      Text(LocalizationService.text('experience_now'))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
      Text(action.title)
        .width('100%').fontSize(29).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).maxLines(4)
        .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
      Column({ space: 5 }) {
        Text(action.deadlineName).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_body')).maxLines(2)
        Text(LocalizationService.formatDateTime(new Date(action.deadlineAt)))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%').alignItems(HorizontalAlign.Start)
        .onClick(() => { this.openDeadlineDetail(action.deadlineId); })
      Row({ space: 8 }) {
        Text(action.riskLabel).fontSize(13).fontColor(this.getActionColor(action))
        Text('›').fontSize(18).fontColor($r('app.color.text_secondary'))
      }.constraintSize({ minHeight: 40 }).onClick(() => {
        this.openDeadlineDetail(action.deadlineId, action.kind === 'overdue-review' ? 0 : 1);
      })
      Button(this.heldDeadlineIds.includes(action.deadlineId) ? LocalizationService.text('review_open') :
        LocalizationService.text(action.kind === 'overdue-review' ? 'experience_decide' : 'experience_start'))
        .width('100%').height(50).type(ButtonType.Normal).borderRadius(10)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
        .backgroundColor($r('app.color.brand')).enabled(this.updatingActionId.length === 0)
        .onClick(() => { this.openDeadlineDetail(action.deadlineId); })
      if (action.canComplete && !this.heldDeadlineIds.includes(action.deadlineId)) {
        Button(this.updatingActionId === action.taskId ? LocalizationService.text('common_updating') :
          LocalizationService.text('home_complete_task'))
          .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
          .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
          .enabled(this.updatingActionId.length === 0)
          .onClick(() => { this.completeRecommendedTask(action); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 24, bottom: 16 })
  }

''' + s[end:]
# Remove the surface wrappers for secondary rows and agenda days, without changing their data.
s=s.replace('.backgroundColor($r(\'app.color.surface\'))\n    .borderRadius(16)', '.backgroundColor(Color.Transparent)')
start=s.index('  build() {')
s=s[:start]+'''  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row() {
          Text($r('app.string.app_name')).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body'))
          Blank()
          Button('+').type(ButtonType.Normal).width(44).height(44).fontSize(26)
            .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
            .accessibilityText(LocalizationService.text('home_add_deadline'))
            .onClick(() => { this.openCreateDeadline(); })
          Button($r('app.string.settings_title')).type(ButtonType.Normal).height(44).fontSize(13)
            .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
            .onClick(() => { this.openSettings(); })
        }.width('100%')
        Row({ space: 24 }) {
          Button(LocalizationService.text('experience_today')).type(ButtonType.Normal)
            .height(48).fontSize(this.homeSpace === 0 ? 25 : 18)
            .fontWeight(this.homeSpace === 0 ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.homeSpace === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent).onClick(() => { this.switchHome(0); })
          Button(LocalizationService.text('experience_deadlines')).type(ButtonType.Normal)
            .height(48).fontSize(this.homeSpace === 1 ? 25 : 18)
            .fontWeight(this.homeSpace === 1 ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.homeSpace === 1 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent).onClick(() => { this.switchHome(1); })
        }.width('100%').margin({ top: 18 })
        Text(this.getDateText()).fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%').margin({ top: 6, bottom: 8 })
        if (this.createdName.length > 0) {
          Text(LocalizationService.text('experience_created', this.createdName))
            .width('100%').fontSize(13).fontColor($r('app.color.success')).maxLines(2)
            .padding({ top: 12, bottom: 8 }).onClick(() => { this.openDeadlineDetail(this.createdId); })
        }
        if (this.syncWarning.length > 0) {
          Text(this.syncWarning).width('100%').fontSize(13).fontColor($r('app.color.text_secondary'))
            .padding({ top: 14, bottom: 8 })
            .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/ConflictRecovery' }); })
        }
        if (this.recoveryEntries.length > 0) {
          Button(LocalizationService.text('review_home_status', this.recoveryEntries.length))
            .type(ButtonType.Normal).constraintSize({ minHeight: 44 }).width('100%').fontSize(13)
            .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
            .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/ConflictRecovery' }); })
        }
        if (this.isLoading) {
          this.MessageCard(LocalizationService.text('home_loading'))
        } else if (this.loadError.length > 0) {
          this.ErrorCard(this.loadError)
        } else if (this.deadlines.length === 0) {
          this.EmptyState()
        } else if (this.homeSpace === 0) {
          if (this.todayPlanText().length > 0) {
            Text(this.todayPlanText()).width('100%').fontSize(13)
              .fontColor($r('app.color.text_body')).margin({ top: 14 })
          }
          if (this.undoActionTaskId.length > 0) {
            Row({ space: 12 }) {
              Text(LocalizationService.text('task_just_completed', this.undoActionTaskTitle))
                .layoutWeight(1).fontSize(13).fontColor($r('app.color.success')).maxLines(2)
              Button($r('app.string.common_undo')).type(ButtonType.Normal).height(44).fontSize(13)
                .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
                .enabled(this.updatingActionId.length === 0).onClick(() => { this.undoRecommendedTask(); })
            }.width('100%').padding({ top: 16, bottom: 4 })
          }
          if (this.todayActions.length === 0) {
            if (this.deadlines.some((item: Deadline) => !item.completed)) {
              this.MessageCard(LocalizationService.text('overdue_no_actions'))
            } else { this.AllDoneState() }
          } else {
            ForEach(this.todayActions.slice(0, 1), (action: TodayAction) => {
              this.PriorityActionCard(action)
            }, (action: TodayAction) => `${action.deadlineId}:${action.taskId}:${action.title}:${action.riskLabel}`)
          }
          if (this.getSecondaryActions().length > 0) {
            Divider().color($r('app.color.divider')).margin({ top: 18, bottom: 22 })
            this.SectionHeader(LocalizationService.text('experience_after'))
            ForEach(this.getSecondaryActions(), (action: TodayAction) => {
              this.TodayActionRow(action)
            }, (action: TodayAction) => `${action.deadlineId}:${action.taskId}:${action.kind}:${action.title}`)
          }
          if (this.scheduleAgenda.length > 0 && this.todayActions.length > 0) {
            Row() {
              Text(LocalizationService.text('experience_upcoming')).fontSize(14)
                .fontColor($r('app.color.text_body'))
              Blank()
              Text(this.showHomeSchedule ? '−' : '+').fontSize(20).fontColor($r('app.color.brand_accent'))
            }.width('100%').padding({ top: 18, bottom: 16 })
              .onClick(() => { this.showHomeSchedule = !this.showHomeSchedule; })
            if (this.showHomeSchedule) {
              ForEach(this.scheduleAgenda, (day: ScheduleAgendaDay) => { this.ScheduleAgendaCard(day) },
                (day: ScheduleAgendaDay) => this.getAgendaRenderKey(day))
            }
          }
        } else {
          Text(LocalizationService.text('experience_objects_hint')).width('100%').fontSize(13)
            .fontColor($r('app.color.text_secondary')).margin({ top: 20, bottom: 10 })
          ForEach(this.getVisibleDeadlines(), (deadline: Deadline) => {
            this.DeadlineCard(deadline)
            Divider().color($r('app.color.divider'))
          }, (deadline: Deadline) => this.getDeadlineRenderKey(deadline))
          if (this.deadlines.length > INITIAL_DEADLINE_RENDER_LIMIT || this.deadlines.some((item: Deadline) =>
            DeadlineOverdueRuntime.state(item) === 'stopped')) {
            Button(this.showAllDeadlines ? LocalizationService.text('home_collapse_list') :
              LocalizationService.count('home_view_all', this.deadlines.length))
              .type(ButtonType.Normal).height(44).fontSize(13).fontColor($r('app.color.brand_accent'))
              .backgroundColor(Color.Transparent).onClick(() => { this.showAllDeadlines = !this.showAllDeadlines; })
          }
        }
        Blank().height(32)
      }.width('100%').constraintSize({ minHeight: '100%' }).alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 12 })
    }.width('100%').height('100%').scrollBar(BarState.Off)
      .backgroundColor($r('app.color.app_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
'''
write('Index',s)

# Detail: move the original builder blocks, retaining every handler and draft.
s=original('DeadlineDetail')
s=s.replace("import { DeadlineTime }", "import { ExperienceRouteParams } from '../services/ExperiencePresentation';\nimport { DeadlineTime }",1)
s=s.replace('  @State deadline:', '  @State workspace: number = 0;\n  private workspaceInitialized: boolean = false;\n  @State deadline:',1)
s=s.replace('        this.deadlineId = params.deadlineId;','''        this.deadlineId = params.deadlineId;
        if (!this.workspaceInitialized) {
          this.workspace = (params as ExperienceRouteParams).workspace === 1 ? 1 : 0;
          this.workspaceInitialized = true;
        }''',1)
s=s.replace('params: new DeadlineRouteParams(this.deadline.id)','params: new ExperienceRouteParams(this.deadline.id, this.workspace)',1)
start=s.index('  @Builder\n  DetailContent()')
build=s.index('  build() {',start)
content=s[start:build]
header_start=content.index('      Column({ space: 10 })')
undo_start=content.index('      if (this.undoTaskId.length > 0)')
status_start=content.index('      Column({ space: 14 })',undo_start)
task_start=content.index("      if (this.deadline.progressMode === 'manual')",status_start)
details_start=content.index('      Row() {\n        Text(this.showMoreDetails',task_start)
plan_start=content.index('      Text(this.getInsight().riskReason)',details_start)
metadata_start=content.index('      Column() {\n        this.InfoRow',plan_start)
footer_start=content.index('      Button(this.completed ? $r(\'app.string.detail_restore\')',metadata_start)
header=content[header_start:undo_start]
undo=content[undo_start:status_start]
status=content[status_start:task_start]
tasks=content[task_start:details_start]
plan=content[plan_start:metadata_start]
metadata=content[metadata_start:footer_start]
# Remove old if(showMoreDetails) closing brace carried with metadata.
assert metadata.rstrip().endswith('}')
metadata=metadata.rstrip()[:-1].rstrip()+'\n'
footer=content[footer_start:]
# Peel the enclosing DetailContent column and builder closings.
suffix="    }\n    .width('100%')\n  }\n\n"
assert footer.endswith(suffix)
footer=footer[:-len(suffix)]
def unbox(block):
    return block.replace(".backgroundColor($r('app.color.surface'))",'.backgroundColor(Color.Transparent)').replace('.padding(18)', '.padding({ top: 16, bottom: 16 })')
header=unbox(header)
tasks=unbox(tasks)
status=unbox(status)
plan=unbox(plan)
metadata=unbox(metadata)
# Three side-by-side schedule statistics are replaced by one honest remaining summary.
summary_start=plan.index('          Row() {\n            Column({ space: 3 })')
summary_end=plan.index('          Text(this.getSchedulePlan().bufferMessage)',summary_start)
plan=plan[:summary_start]+'''          Text(LocalizationService.text('common_about_hours', this.getSchedulePlan().totalRemainingHours))
            .fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_strong'))

'''+plan[summary_end:]
new='''  private switchWorkspace(value: number): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => { this.workspace = value; });
  }

  @Builder
  WorkspaceTabs() {
    Row({ space: 8 }) {
      Button(LocalizationService.text('experience_action')).type(ButtonType.Normal)
        .layoutWeight(1).constraintSize({ minHeight: 48 }).fontSize(14)
        .fontWeight(this.workspace === 0 ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.workspace === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .backgroundColor(this.workspace === 0 ? $r('app.color.surface_muted') : Color.Transparent)
        .borderRadius(8).onClick(() => { this.switchWorkspace(0); })
      Button(LocalizationService.text('experience_plan')).type(ButtonType.Normal)
        .layoutWeight(1.5).constraintSize({ minHeight: 48 }).fontSize(14)
        .fontWeight(this.workspace === 1 ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.workspace === 1 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .backgroundColor(this.workspace === 1 ? $r('app.color.surface_muted') : Color.Transparent)
        .borderRadius(8).onClick(() => { this.switchWorkspace(1); })
    }.width('100%').margin({ top: 16, bottom: 10 })
  }

  @Builder
  ObjectHeader() {
'''+header.replace('        if (!this.completed) {','        if (!this.completed && this.workspace === 0) {',1)+'''  }

  @Builder
  WorkActions() {
'''+tasks+'''  }

  @Builder
  WorkAssessment() {
'''+status+plan+'''  }

  @Builder
  DetailContent() {
    Column({ space: 0 }) {
      this.ObjectHeader()
      this.WorkspaceTabs()
      if (this.workspace === 0) {
'''+undo+'''        if (this.deadline.progressMode === 'automatic') {
          Text(LocalizationService.text('experience_task_count', this.getCompletedTaskCount(), this.getLeafTaskCount()))
            .width('100%').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 14 })
        }
        this.WorkActions()
        if (!this.completed) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.getRemainingEstimateText()).fontSize(14).fontColor($r('app.color.text_body'))
              Text(this.getInsight().riskLabel).fontSize(12).fontColor(this.getRiskColor())
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button(LocalizationService.text('experience_calibrate')).type(ButtonType.Normal)
              .constraintSize({ minHeight: 48 }).fontSize(14).fontColor($r('app.color.brand_accent'))
              .backgroundColor(Color.Transparent).enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
              .onClick(() => { this.workspace = 1; this.remainingEditorVisible = true; })
          }.width('100%').padding({ top: 16, bottom: 16 })
        }
      } else {
        Text(LocalizationService.text('experience_calibration_hint')).width('100%').fontSize(13)
          .fontColor($r('app.color.text_secondary')).margin({ top: 12 })
        this.WorkAssessment()
      }
      Row() {
        Text(LocalizationService.text('experience_record')).fontSize(14).fontColor($r('app.color.text_body'))
        Blank()
        Text(this.showMoreDetails ? '−' : '+').fontSize(20).fontColor($r('app.color.brand_accent'))
      }.width('100%').padding({ top: 20, bottom: 16 }).onClick(() => { this.showMoreDetails = !this.showMoreDetails; })
      if (this.showMoreDetails) {
'''+metadata+'''      }
'''+footer+'''    }.width('100%')
  }

'''
s=s[:start]+new+s[build:]
s=s.replace("Text($r('app.string.detail_title'))", "Text($r('app.string.app_name'))",1)
write('DeadlineDetail',s)

# Creation: first name/date/time + save, with optional workload below a disclosure.
s=original('CreateDeadline')
s=s.replace("import { DeadlineTime }", "import { ExperiencePresentation, ExperienceRouteParams } from '../services/ExperiencePresentation';\nimport { DeadlineTime }",1)
s=s.replace("  private selectedDate:", "  private returnWorkspace: number = 0;\n  private selectedDate:",1)
s=s.replace("      return typeof params.deadlineId", "      this.returnWorkspace = (params as ExperienceRouteParams).workspace === 1 ? 1 : 0;\n      return typeof params.deadlineId",1)
s=s.replace('params: new DeadlineRouteParams(deadlineId)','params: new ExperienceRouteParams(deadlineId, this.returnWorkspace)',1)
s=s.replace('''      } else {
        this.allowLeave = true;
        this.navigateBack();''','''      } else {
        ExperiencePresentation.recordCreated(deadline.id, deadline.name);
        this.allowLeave = true;
        this.navigateBack();''',1)
pos=s.index('  @Builder\n  FieldLabel(')
s=s[:pos]+'''  private chooseRelativeDate(offset: number): void {
    const day: Date = new Date(DeadlineTime.calendarDay(Date.now(), offset));
    this.selectedDate = day;
    this.deadlineDate = this.formatDate(day);
    this.deadlineDateValue = this.formatStorageDate(day);
    this.dateError = '';
  }

'''+s[pos:]
s=s.replace("Text(this.isEditMode ? $r('app.string.create_edit_helper') : $r('app.string.create_new_helper'))", "Text(this.isEditMode ? $r('app.string.create_edit_helper') : $r('app.string.experience_create_hint'))",1)
s=s.replace("this.FieldLabel($r('app.string.field_name'), true)", "this.FieldLabel($r('app.string.experience_name'), false)",1)
s=s.replace("this.FieldLabel($r('app.string.field_due_date'), true)", "this.FieldLabel($r('app.string.experience_due'), false)",1)
s=s.replace(".type(InputType.Normal)\n              .fontSize(15)", ".type(InputType.Normal)\n              .id('deadlineName')\n              .fontSize(20)",1)
# Move total workload into optional details; keep validation and all entered values.
a=s.index("          Column({ space: 9 }) {\n            this.FieldLabel($r('app.string.field_workload')")
b=s.index('          Row() {\n            Text(this.showMoreOptions',a)
workload=s[a:b]
s=s[:a]+s[b:]
s=s.replace('          if (this.showMoreOptions) {\n', '          if (this.showMoreOptions) {\n'+workload,1)
# Default clock is visible without understanding advanced settings.
date_end=s.index("          Row() {\n            Text(this.showMoreOptions")
s=s[:date_end]+'''          if (!this.isEditMode) {
            Row({ space: 8 }) {
              Button(LocalizationService.text('common_today')).type(ButtonType.Normal).layoutWeight(1).height(44)
                .fontSize(14).fontColor($r('app.color.brand_accent')).backgroundColor($r('app.color.surface_muted'))
                .borderRadius(8).onClick(() => { this.chooseRelativeDate(0); })
              Button(LocalizationService.text('experience_tomorrow')).type(ButtonType.Normal).layoutWeight(1).height(44)
                .fontSize(14).fontColor($r('app.color.brand_accent')).backgroundColor($r('app.color.surface_muted'))
                .borderRadius(8).onClick(() => { this.chooseRelativeDate(1); })
            }.width('100%')
            Button(LocalizationService.text('experience_due_clock', LocalizationService.formatClockTime(this.deadlineTime)))
              .type(ButtonType.Normal).width('100%').constraintSize({ minHeight: 44 }).fontSize(13)
              .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
              .onClick(() => { this.openTimePicker(); })
          }

'''+s[date_end:]
s=s.replace("Text(this.showMoreOptions ? $r('app.string.create_fewer_options') :\n              $r('app.string.create_more_options'))", "Text(this.showMoreOptions ? $r('app.string.experience_hide_details') :\n              $r('app.string.experience_add_details'))",1)
# Preserve the original save handler, but place its primary action before optional details when collapsed.
start=s.index("        Button(this.isSaving ? $r('app.string.common_saving')")
end=s.index("        Text(this.isEditMode ? $r('app.string.create_edit_footer')",start)
save=s[start:end]
inner_save=save.replace('        Button(', '          Button(',1).rstrip()+'\n'
start_options=s.index('          Row() {\n            Text(this.showMoreOptions')
s=s[:start_options]+'''          if (!this.showMoreOptions) {
'''+inner_save+'''          }
'''+s[start_options:]
# The second primary save is shown only when optional fields are expanded.
start=s.index("        Button(this.isSaving ? $r('app.string.common_saving')", s.index('  build() {'))
# The first match above is the indented inserted button; locate original by full newline indentation.
start=s.index("\n        Button(this.isSaving ? $r('app.string.common_saving')",start)+1
end=s.index("        Text(this.isEditMode ? $r('app.string.create_edit_footer')",start)
s=s[:start]+'''        if (this.showMoreOptions) {
'''+s[start:end]+'''        }

'''+s[end:]
write('CreateDeadline',s)
print('Presentation builders reorganized; business services/models not edited.')
