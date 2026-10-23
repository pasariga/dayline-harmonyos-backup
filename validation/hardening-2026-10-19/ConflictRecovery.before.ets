import { common } from '@kit.AbilityKit';
import { DeadlineRouteParams, DeadlineSubtask } from '../models/Deadline';
import { DeadlineDatabaseService, DeadlineDataConflictError, SyncRecoveryEntry } from '../services/DeadlineDatabaseService';
import { ConflictReview, DeletionNotice, RecoveryField, RecoverySelection } from '../services/DeadlineConflictRecovery';
import { LocalizationService } from '../services/LocalizationService';
import { DeadlineReminderService } from '../services/DeadlineReminderService';

@Entry
@Component
struct ConflictRecovery {
  @State entries: SyncRecoveryEntry[] = [];
  @State review: ConflictReview = new ConflictReview();
  @State notice: DeletionNotice | undefined = undefined;
  @State selections: RecoverySelection[] = [];
  @State step: number = 0;
  @State busy: boolean = false;
  @State error: string = '';
  @State loaded: boolean = false;
  @State success: boolean = false;
  @State selectedId: string = '';
  @State expandedValue: string = '';
  private visible: boolean = false;
  private generation: number = 0;
  private openedFromList: boolean = false;
  private scroller: Scroller = new Scroller();

  private scrollTop(): void {
    try { this.scroller.scrollEdge(Edge.Top); } catch (error) { console.error('Unable to scroll review to top'); }
  }

  onPageShow(): void {
    this.visible = true;
    const params: DeadlineRouteParams = this.getUIContext().getRouter().getParams() as DeadlineRouteParams;
    this.selectedId = params?.deadlineId ?? '';
    this.openedFromList = this.selectedId.length === 0;
    this.load();
  }
  onPageHide(): void { this.visible = false; this.generation++; }
  onBackPress(): boolean { this.back(); return true; }
  private back(): void {
    if (this.busy) { return; }
    if (this.openedFromList && this.selectedId.length > 0) {
      this.selectedId = ''; this.success = false; this.notice = undefined; this.load();
    } else { this.getUIContext().getRouter().back(); }
  }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async load(): Promise<void> {
    this.scrollTop();
    const generation: number = ++this.generation;
    this.busy = true; this.error = ''; this.loaded = false;
    try {
      await DeadlineDatabaseService.reconcileSyncJournal(this.context());
      if (this.selectedId.length > 0) {
        const review: ConflictReview = await DeadlineDatabaseService.getConflictReview(this.context(), this.selectedId);
        const notice: DeletionNotice | undefined = await DeadlineDatabaseService.getSyncDeletionNotice(this.context(), this.selectedId);
        if (!this.visible || generation !== this.generation) { return; }
        this.review = review; this.notice = notice; this.selections = []; this.step = 0;
      } else {
        const entries: SyncRecoveryEntry[] = await DeadlineDatabaseService.getSyncRecoveryEntries(this.context());
        if (!this.visible || generation !== this.generation) { return; }
        this.entries = entries;
      }
      this.loaded = true;
    } catch (error) {
      if (this.visible && generation === this.generation) { this.error = LocalizationService.text('review_load_failed'); }
    } finally { if (this.visible && generation === this.generation) { this.busy = false; } }
  }
  private field(): RecoveryField { return this.review.fields[this.step]; }
  private choose(value: string): void {
    const key: string = this.field().key;
    this.selections = this.selections.filter((s: RecoverySelection) => s.key !== key).concat([new RecoverySelection(key, value)]);
    this.error = '';
  }
  private chosen(value: string): boolean {
    return this.selections.some((s: RecoverySelection) => s.key === this.field().key && s.value === value);
  }
  private taskParent(task: DeadlineSubtask, tasks: DeadlineSubtask[]): string {
    const path: string[] = [];
    const seen: Set<string> = new Set<string>();
    let id: string = task.parentId;
    while (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      const parent: DeadlineSubtask | undefined = tasks.find((t: DeadlineSubtask) => t.id === id);
      if (parent === undefined) { path.unshift(LocalizationService.text('review_other_task')); break; }
      path.unshift(parent.title); id = parent.parentId;
    }
    return path.length === 0 ? LocalizationService.text('review_root_task') : path.join(' › ');
  }
  private tasksForContext(): DeadlineSubtask[] {
    const tasks: DeadlineSubtask[] = [];
    this.review.safeValues.forEach((s: RecoverySelection) => {
      if (s.key.startsWith('task:')) { tasks.push(JSON.parse(s.value) as DeadlineSubtask); }
    });
    this.review.fields.forEach((f: RecoveryField) => {
      if (f.key.startsWith('task:')) { tasks.push(JSON.parse(f.currentValue || f.values[0]) as DeadlineSubtask); }
    });
    return tasks;
  }
  private describeTask(task: DeadlineSubtask, tasks: DeadlineSubtask[]): string {
    return `${task.title}\n${LocalizationService.text(task.completed ? 'common_completed' : 'review_unfinished')} · ` +
      `${this.taskParent(task, tasks)} · ${LocalizationService.text('review_task_position', task.sortOrder + 1)}`;
  }
  private valueText(key: string, value: string): string {
    if (key.startsWith('task:')) { return this.describeTask(JSON.parse(value) as DeadlineSubtask, this.tasksForContext()); }
    if (key === 'tasks') {
      const tasks: DeadlineSubtask[] = JSON.parse(value) as DeadlineSubtask[];
      const visible: DeadlineSubtask[] = this.expandedValue === value ? tasks : tasks.slice(0, 5);
      return LocalizationService.text('review_task_count', tasks.length) + '\n\n' +
        visible.map((t: DeadlineSubtask) => this.describeTask(t, tasks)).join('\n\n');
    }
    if (key === 'due') {
      const tuple: (string | number)[] = JSON.parse(value) as (string | number)[];
      return LocalizationService.formatDateTime(new Date(tuple[2] as number));
    }
    if (key === 'remaining') {
      const tuple: (string | number)[] = JSON.parse(value) as (string | number)[];
      const status: string = tuple[1] as string;
      const text: string = status === 'unknown' ? LocalizationService.text('review_unknown') :
        LocalizationService.text('review_hours', tuple[0] as number);
      return text + (status === 'initial' ? '\n' + LocalizationService.text('review_initial') :
        status === 'confirmed' ? '\n' + LocalizationService.text('review_confirmed_at',
          LocalizationService.formatDateTime(new Date(tuple[2] as number))) : '');
    }
    if (key === 'type') { return LocalizationService.deadlineType(JSON.parse(value) as string); }
    if (key === 'mode') { return LocalizationService.text(JSON.parse(value) === 'automatic' ? 'review_auto' : 'review_manual'); }
    if (key === 'completed') { return LocalizationService.text(JSON.parse(value) ? 'common_completed' : 'review_unfinished'); }
    if (key === 'created') { return LocalizationService.formatDateTime(new Date(JSON.parse(value) as number)); }
    if (key === 'total') { return LocalizationService.text('review_hours', JSON.parse(value) as number); }
    if (key === 'progress') { return LocalizationService.text('review_percent', JSON.parse(value) as number); }
    if (key === 'reminder') {
      const minutes: number = JSON.parse(value) as number;
      return minutes === 0 ? LocalizationService.text('review_no_reminder') : LocalizationService.text('review_reminder_minutes', minutes);
    }
    const text: string = JSON.parse(value) as string;
    return text.length > 0 ? text : LocalizationService.text('review_empty');
  }
  private label(key: string): string {
    return LocalizationService.text(key.startsWith('task:') ? 'review_field_task' : `review_field_${key}`);
  }
  private async save(): Promise<void> {
    if (this.busy) { return; }
    const generation: number = this.generation;
    this.busy = true; this.error = '';
    try {
      await DeadlineDatabaseService.resolveSyncConflict(this.context(), this.review, this.selections);
      this.scrollTop();
      this.success = true;
      this.busy = false;
      // A committed choice must never be reported as unsaved if reminder coordination fails.
      try { await DeadlineReminderService.reconcileAll(this.context()); } catch (error) { console.error('Reminders deferred after reviewed data saved'); }
    } catch (error) {
      this.scrollTop();
      this.error = LocalizationService.text(error instanceof DeadlineDataConflictError ? 'review_changed' : 'review_save_failed');
    } finally { if (generation === this.generation) { this.busy = false; } }
  }
  private async acknowledge(): Promise<void> {
    if (this.notice === undefined || this.busy) { return; }
    this.busy = true;
    try { await DeadlineDatabaseService.acknowledgeSyncDeletion(this.context(), this.notice); this.scrollTop(); this.success = true; }
    catch (error) { this.error = LocalizationService.text('review_save_failed'); }
    finally { this.busy = false; }
  }

  @Builder
  Option(value: string, index: number) {
    Column({ space: 9 }) {
      Text(`${this.chosen(value) ? '●' : '○'}  ${value === this.field().currentValue ?
        LocalizationService.text('review_current') : LocalizationService.text('review_alternative', index + 1)}`)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_body')).width('100%')
      Text(this.valueText(this.field().key, value))
        .fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
      if (this.field().key === 'tasks' && (JSON.parse(value) as DeadlineSubtask[]).length > 5) {
        Button(LocalizationService.text(this.expandedValue === value ? 'review_collapse' : 'review_show_tasks'))
          .type(ButtonType.Normal).fontSize(13).fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
          .onClick(() => { this.expandedValue = this.expandedValue === value ? '' : value; })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(16)
    .backgroundColor($r('app.color.surface')).borderRadius(10)
    .border({ width: this.chosen(value) ? 1 : 0, color: $r('app.color.brand_accent') })
    .onClick(() => { this.choose(value); })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          Button($r('app.string.common_back')).type(ButtonType.Normal).height(40)
            .fontColor($r('app.color.text_body')).backgroundColor($r('app.color.surface_muted')).borderRadius(18)
            .enabled(!this.busy).onClick(() => { this.back(); })
          Text(LocalizationService.text('review_title')).fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
        }.width('100%')
        if (this.error.length > 0) {
          Text(this.error).fontSize(14).fontColor($r('app.color.danger')).width('100%')
          Button(LocalizationService.text('review_reload')).type(ButtonType.Normal).constraintSize({ minHeight: 44 })
            .fontColor($r('app.color.brand_accent')).backgroundColor($r('app.color.surface_muted')).borderRadius(12)
            .enabled(!this.busy).onClick(() => { this.load(); })
        }
        if (this.busy) {
          Text(LocalizationService.text('review_working')).fontColor($r('app.color.text_secondary')).width('100%')
        } else if (this.success) {
          Text(LocalizationService.text('review_success')).fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).width('100%')
          Button($r('app.string.common_back')).type(ButtonType.Normal).width('100%').height(46)
            .fontColor(Color.White).backgroundColor($r('app.color.brand_accent')).borderRadius(12)
            .onClick(() => { this.back(); })
        } else if (this.loaded && this.selectedId.length === 0) {
          ForEach(this.entries, (entry: SyncRecoveryEntry) => {
            Row({ space: 12 }) {
              Text(entry.name || LocalizationService.text('review_waiting')).fontSize(16)
                .fontColor($r('app.color.text_primary')).layoutWeight(1)
              Text(LocalizationService.text(entry.kind === 'review' ? 'review_needed' : entry.kind === 'waiting' ?
                'review_waiting' : 'review_removed')).fontSize(13).fontColor($r('app.color.text_secondary'))
              Text('›').fontColor($r('app.color.text_secondary'))
            }.width('100%').padding({ top: 14, bottom: 14 }).onClick(() => {
              this.selectedId = entry.id; this.load();
            })
            Divider().color($r('app.color.divider'))
          }, (entry: SyncRecoveryEntry) => entry.id)
          if (this.entries.length === 0) { Text(LocalizationService.text('review_none')).fontColor($r('app.color.text_secondary')) }
        } else if (this.loaded) {
          Text(this.review.name || this.notice?.name || LocalizationService.text('review_title'))
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          if (this.review.blocked) {
            Text(LocalizationService.text(this.review.requiresUpgrade ? 'review_upgrade' : 'review_incomplete'))
              .fontSize(15).fontColor($r('app.color.text_body')).width('100%')
          } else if (this.review.fields.length > 0) {
            Text(LocalizationService.text('review_intro')).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            Text(LocalizationService.text('review_step', this.step + 1, this.review.fields.length))
              .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            Text(this.label(this.field().key)).fontSize(20).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%')
            if (this.field().key === 'tasks') {
              Text(LocalizationService.text('review_tree_choice')).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            }
            ForEach(this.field().values, (value: string, index: number) => { this.Option(value, index) }, (value: string) => value)
            Row({ space: 12 }) {
              if (this.step > 0) {
                Button(LocalizationService.text('review_previous')).type(ButtonType.Normal).height(44).layoutWeight(1)
                  .fontColor($r('app.color.text_body')).backgroundColor($r('app.color.surface_muted')).borderRadius(12)
                  .onClick(() => { this.scrollTop(); this.step--; this.expandedValue = ''; })
              }
              Button(LocalizationService.text(this.step < this.review.fields.length - 1 ? 'review_next' : 'review_save'))
                .type(ButtonType.Normal).constraintSize({ minHeight: 46 }).layoutWeight(1).padding(12)
                .fontColor(Color.White).backgroundColor($r('app.color.brand_accent')).borderRadius(12)
                .enabled(this.selections.some((s: RecoverySelection) => s.key === this.field().key))
                .onClick(() => {
                  if (this.step < this.review.fields.length - 1) { this.scrollTop(); this.step++; this.expandedValue = ''; }
                  else { this.save(); }
                })
            }.width('100%')
          } else if (this.notice !== undefined) {
            Text(LocalizationService.text(this.notice.deleted ? 'review_deleted_explanation' : 'review_tasks_deleted_explanation'))
              .fontSize(15).fontColor($r('app.color.text_body')).width('100%')
            ForEach(this.notice.titles, (title: string) => {
              Text(title).fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
            }, (title: string) => title)
            Button(LocalizationService.text('review_understood')).type(ButtonType.Normal).constraintSize({ minHeight: 46 })
              .width('100%').fontColor(Color.White).backgroundColor($r('app.color.brand_accent')).borderRadius(12)
              .onClick(() => { this.acknowledge(); })
          } else { Text(LocalizationService.text('review_none')).fontColor($r('app.color.text_secondary')) }
          Button(LocalizationService.text('review_later')).type(ButtonType.Normal).width('100%').height(44)
            .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
            .onClick(() => { this.back(); })
        }
      }.width('100%').constraintSize({ minHeight: '100%' }).alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start).padding({ left: 20, right: 20, top: 18, bottom: 32 })
    }.width('100%').height('100%').backgroundColor($r('app.color.app_background')).scrollBar(BarState.Off)
  }
}
