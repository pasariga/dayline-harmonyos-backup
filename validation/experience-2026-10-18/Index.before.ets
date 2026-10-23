import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { Deadline, DeadlineRouteParams, DeadlineSubtask } from '../models/Deadline';
import { DeadlineSyncHeldError, DeadlineDataConflictError, DeadlineDatabaseService, DeadlineDataSnapshot, SyncRecoveryEntry } from
  '../services/DeadlineDatabaseService';
import { DeadlineInsight, DeadlineInsightService } from '../services/DeadlineInsightService';
import { DeadlineProgressService } from '../services/DeadlineProgressService';
import { DeadlineScheduleService, ScheduleAgendaDay, ScheduleAgendaItem } from
  '../services/DeadlineScheduleService';
import { CloudSyncResult, CloudSyncService } from '../services/CloudSyncService';
import { LegacyDeadlineMigrationService } from '../services/LegacyDeadlineMigrationService';
import { TodayAction, TodayActionService, TodayPlan } from '../services/TodayActionService';
import { AppLogger } from '../services/AppLogger';
import { DeadlineReminderService } from '../services/DeadlineReminderService';
import { LocalizationService } from '../services/LocalizationService';
import { AppSettingsRuntime } from '../services/AppSettingsService';
import { DeadlineOverdueRuntime, DeadlineOverdueService } from '../services/DeadlineOverdueService';
import { DeadlineTime } from '../services/DeadlineTime';
import { ReleaseScope } from '../services/ReleaseScope';

const INITIAL_DEADLINE_RENDER_LIMIT: number = 12;
const AGENDA_ITEM_RENDER_LIMIT: number = 3;

@Entry
@Component
struct Index {
  @State deadlines: Deadline[] = [];
  @State subtasks: DeadlineSubtask[] = [];
  @State todayActions: TodayAction[] = [];
  @State highRiskDeadlines: Deadline[] = [];
  @State laterDeadlines: Deadline[] = [];
  @State scheduleAgenda: ScheduleAgendaDay[] = [];
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @State syncWarning: string = '';
  @State heldDeadlineIds: string[] = [];
  @State recoveryEntries: SyncRecoveryEntry[] = [];
  @State updatingActionId: string = '';
  @State overallProgress: number = 0;
  @State showAllDeadlines: boolean = false;
  @State showHomeSchedule: boolean = false;
  @State undoActionTaskId: string = '';
  @State undoActionTaskTitle: string = '';

  private pageVisible: boolean = false;
  private refreshVersion: number = 0;
  private isNavigating: boolean = false;
  private hasLoadedOnce: boolean = false;
  private deadlineClock: number = -1;
  private insightById: Map<string, DeadlineInsight> = new Map<string, DeadlineInsight>();
  private undoActionDeadline: Deadline | undefined = undefined;
  private undoActionTasks: DeadlineSubtask[] = [];
  private readonly syncDataChanged = (): void => {
    if (this.pageVisible) {
      this.loadDeadlines(false, ++this.refreshVersion);
    }
  };
  private readonly clockChanged = (): void => {
    if (this.pageVisible && this.updatingActionId.length === 0) {
      this.loadDeadlines(false, ++this.refreshVersion);
    }
  };

  onPageShow(): void {
    this.pageVisible = true;
    DeadlineTime.onClockChanged(this.clockChanged);
    CloudSyncService.onDataChanged(this.syncDataChanged);
    this.isNavigating = false;
    this.undoActionTaskId = '';
    const version: number = ++this.refreshVersion;
    this.refreshHome(version, !this.hasLoadedOnce);
  }

  onPageHide(): void {
    clearTimeout(this.deadlineClock);
    this.pageVisible = false;
    DeadlineTime.offClockChanged(this.clockChanged);
    CloudSyncService.offDataChanged(this.syncDataChanged);
    this.refreshVersion++;
  }

  private isCurrentRefresh(version: number): boolean {
    return this.pageVisible && version === this.refreshVersion;
  }

  private async refreshHome(version: number, showLoading: boolean): Promise<void> {
    await this.loadDeadlines(showLoading, version);
    if (!this.isCurrentRefresh(version) || !ReleaseScope.CLOUD_SYNC_AVAILABLE) {
      return;
    }
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const syncResult: CloudSyncResult | undefined = await CloudSyncService.syncIfDue(context);
      if (!this.isCurrentRefresh(version)) {
        return;
      }
      if (syncResult !== undefined) {
        await this.loadDeadlines(false, version);
      }
    } catch (error) {
      console.error(`Background cloud sync failed: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private openSettings(): void {
    if (this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/Settings'
      }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to open settings page: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(LocalizationService.text('message_open_settings_failed'));
        }
      });
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate to settings: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_settings_failed'));
    }
  }

  private async loadDeadlines(showLoading: boolean = true,
    version: number = this.refreshVersion): Promise<void> {
    const startedAt: number = Date.now();
    if (showLoading && this.isCurrentRefresh(version)) {
      this.isLoading = true;
    }
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await LegacyDeadlineMigrationService.migrateIfNeeded(context);
      let snapshot: DeadlineDataSnapshot = await DeadlineDatabaseService.getDeadlineDataSnapshot(context);
      snapshot = await this.reconcileAutomaticProgress(context, snapshot);
      if (!this.isCurrentRefresh(version)) {
        return;
      }
      const heldIds: string[] = await DeadlineDatabaseService.getSyncProblemIds(context);
      const recoveryEntries: SyncRecoveryEntry[] = await DeadlineDatabaseService.getSyncRecoveryEntries(context);
      if (!this.isCurrentRefresh(version)) { return; }
      this.heldDeadlineIds = heldIds;
      this.recoveryEntries = recoveryEntries;
      this.syncWarning = heldIds.includes('__projection__') ? LocalizationService.text('review_waiting') : '';
      const storedDeadlines: Deadline[] = snapshot.deadlines;
      await DeadlineOverdueService.load(context);
      if (!this.isCurrentRefresh(version)) { return; }
      const storedSubtasks: DeadlineSubtask[] = snapshot.subtasks;
      const insightById: Map<string, DeadlineInsight> = new Map<string, DeadlineInsight>();
      const now: number = Date.now();
      let completedCount: number = 0;
      for (let index: number = 0; index < storedDeadlines.length; index++) {
        const deadline: Deadline = storedDeadlines[index];
        const insight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(deadline, storedDeadlines, now);
        insightById.set(deadline.id, insight);
        if (deadline.completed) {
          completedCount++;
        }
      }
      storedDeadlines.sort((first: Deadline, second: Deadline) => {
        const group = (item: Deadline): number => item.completed ? 3 :
          (DeadlineOverdueRuntime.state(item, now) === 'stopped' ? 4 : (item.deadlineAt < now ? 1 : 0));
        if (group(first) !== group(second)) { return group(first) - group(second); }
        if (group(first) === 1) { return second.deadlineAt - first.deadlineAt; }
        const firstInsight: DeadlineInsight = insightById.get(first.id) as DeadlineInsight;
        const secondInsight: DeadlineInsight = insightById.get(second.id) as DeadlineInsight;
        const riskDifference: number = secondInsight.riskScore - firstInsight.riskScore;
        if (riskDifference !== 0) {
          return riskDifference;
        }
        return first.deadlineAt - second.deadlineAt;
      });
      const plan: TodayPlan = TodayActionService.buildPlan(storedDeadlines, storedSubtasks, now);
      this.insightById = insightById;
      this.deadlines = storedDeadlines;
      this.subtasks = storedSubtasks;
      this.todayActions = plan.actions;
      this.highRiskDeadlines = plan.highRiskDeadlines;
      this.laterDeadlines = plan.laterDeadlines;
      this.scheduleAgenda = AppSettingsRuntime.shouldShowHomeSchedule() ?
        DeadlineScheduleService.buildAgenda(storedDeadlines, storedSubtasks, 3, now) : [];
      this.overallProgress = storedDeadlines.length > 0 ?
        Math.round(completedCount / storedDeadlines.length * 100) : 0;
      this.loadError = '';
      this.hasLoadedOnce = true;
      this.armDeadlineClock();
      const duration: number = Date.now() - startedAt;
      const performanceMessage: string =
        `Home ready in ${duration} ms (${storedDeadlines.length} deadlines, ${storedSubtasks.length} tasks)`;
      if (duration >= 500) {
        AppLogger.warn('Performance', performanceMessage);
      } else {
        AppLogger.info('Performance', performanceMessage);
      }
    } catch (error) {
      console.error(`Failed to load deadlines: ${CloudDiagnostic.code(error as Object)}`);
      AppLogger.error('Home', 'Failed to load local deadline snapshot', error as Object);
      if (this.isCurrentRefresh(version)) {
        this.loadError = LocalizationService.text('message_load_deadlines_failed');
      }
    } finally {
      if (showLoading && this.isCurrentRefresh(version)) {
        this.isLoading = false;
      }
    }
  }

  private armDeadlineClock(): void {
    clearTimeout(this.deadlineClock);
    const now: number = Date.now();
    const delay: number = DeadlineTime.refreshDelay(now,
      this.deadlines.filter((item: Deadline) => !item.completed).map((item: Deadline) => item.deadlineAt));
    this.deadlineClock = setTimeout(() => {
      if (!this.pageVisible) { return; }
      if (this.updatingActionId.length > 0) { this.armDeadlineClock(); return; }
      this.loadDeadlines(false, ++this.refreshVersion);
    }, Math.max(100, delay));
  }

  private async reconcileAutomaticProgress(context: common.UIAbilityContext,
    initialSnapshot: DeadlineDataSnapshot): Promise<DeadlineDataSnapshot> {
    let snapshot: DeadlineDataSnapshot = initialSnapshot;
    for (let attempt: number = 0; attempt < 2; attempt++) {
      let changed: boolean = false;
      let conflicted: boolean = false;
      const tasksByDeadline: Map<string, DeadlineSubtask[]> = new Map<string, DeadlineSubtask[]>();
      for (let taskIndex: number = 0; taskIndex < snapshot.subtasks.length; taskIndex++) {
        const task: DeadlineSubtask = snapshot.subtasks[taskIndex];
        const deadlineTasks: DeadlineSubtask[] | undefined = tasksByDeadline.get(task.deadlineId);
        if (deadlineTasks === undefined) {
          tasksByDeadline.set(task.deadlineId, [task]);
        } else {
          deadlineTasks.push(task);
        }
      }
      for (let index: number = 0; index < snapshot.deadlines.length; index++) {
        const deadline: Deadline = snapshot.deadlines[index];
        if (deadline.completed || deadline.progressMode !== 'automatic') {
          continue;
        }
        const previousTasks: DeadlineSubtask[] = tasksByDeadline.get(deadline.id) ?? [];
        const nextTasks: DeadlineSubtask[] = DeadlineProgressService.deriveParentStates(previousTasks);
        const progress: number = DeadlineProgressService.calculateDeadlineProgress(nextTasks);
        const stateChanged: boolean = nextTasks.some((task: DeadlineSubtask, taskIndex: number) =>
          task.completed !== previousTasks[taskIndex].completed);
        if (!stateChanged && progress === deadline.progress) {
          continue;
        }
        try {
          await DeadlineDatabaseService.commitTaskChanges(context, deadline.id,
            previousTasks, nextTasks, progress, deadline);
          changed = true;
        } catch (error) {
          if (error instanceof DeadlineDataConflictError) {
            conflicted = true;
            break;
          }
          throw new Error(`Unable to reconcile automatic progress: ${JSON.stringify(error)}`);
        }
      }
      if (!changed && !conflicted) {
        return snapshot;
      }
      snapshot = await DeadlineDatabaseService.getDeadlineDataSnapshot(context);
      if (!conflicted) {
        return snapshot;
      }
    }
    return snapshot;
  }

  private getDateText(): string {
    return LocalizationService.formatDate(new Date(), 'full');
  }

  private getDeadlineDateText(deadline: Deadline): string {
    return LocalizationService.formatDateTime(new Date(deadline.deadlineAt));
  }

  private getRemainingText(deadlineAt: number): string {
    const now: Date = new Date();
    if (deadlineAt < now.getTime()) {
      return LocalizationService.text('common_overdue');
    }

    const remainingDays: number = DeadlineTime.daysBetween(now.getTime(), deadlineAt);
    return remainingDays === 0 ? LocalizationService.text('common_today') :
      LocalizationService.text('common_days_value', remainingDays);
  }

  private getCardStatusText(deadline: Deadline): string {
    if (this.heldDeadlineIds.includes(deadline.id)) { return LocalizationService.text('review_needed'); }
    if (DeadlineOverdueRuntime.isOverdue(deadline)) { return DeadlineOverdueRuntime.statusText(deadline); }
    return deadline.completed ? LocalizationService.text('common_completed') : this.getInsight(deadline).riskLabel;
  }

  private getDeadlineRenderKey(deadline: Deadline): string {
    const now: Date = new Date();
    const localDay: number = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    return `${deadline.id}:${deadline.name}:${deadline.type}:${deadline.deadlineAt}:` +
      `${deadline.completed}:${deadline.estimatedHours}:${deadline.progress}:${deadline.progressMode}:` +
      `${deadline.remainingHours}:${deadline.remainingState}:${deadline.remainingUpdatedAt}:${this.heldDeadlineIds.includes(deadline.id)}:` +
      `${DeadlineOverdueRuntime.state(deadline)}:${this.getInsight(deadline).riskLevel}:` +
      `${this.getInsight(deadline).workloadConfidence}:${localDay}:${now.getTimezoneOffset()}`;
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show home message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private async completeRecommendedTask(action: TodayAction): Promise<void> {
    if (!action.canComplete || action.taskId.length === 0) {
      this.openDeadlineDetail(action.deadlineId);
      return;
    }
    if (this.updatingActionId.length > 0) {
      return;
    }
    const deadlineTasks: DeadlineSubtask[] = this.subtasks.filter((task: DeadlineSubtask) => {
      return task.deadlineId === action.deadlineId;
    });
    const task: DeadlineSubtask | undefined = deadlineTasks.find((item: DeadlineSubtask) => {
      return item.id === action.taskId;
    });
    if (task === undefined) {
      this.showMessage(LocalizationService.text('message_task_changed'));
      await this.loadDeadlines(false);
      return;
    }
    this.updatingActionId = action.taskId;
    this.undoActionTaskId = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const nextTasks: DeadlineSubtask[] = DeadlineProgressService.toggleTaskTree(
        deadlineTasks,
        task.id,
        true
      );
      const progress: number = DeadlineProgressService.calculateDeadlineProgress(nextTasks);
      const currentDeadline: Deadline | undefined = this.deadlines.find((item: Deadline) =>
        item.id === action.deadlineId);
      if (currentDeadline === undefined) {
        throw new Error('Deadline changed before task completion.');
      }
      await DeadlineDatabaseService.commitTaskChanges(
        context,
        action.deadlineId,
        deadlineTasks,
        nextTasks,
        progress,
        currentDeadline
      );
      DeadlineReminderService.onUserDataChanged(context, action.deadlineId);
      await this.loadDeadlines(false);
      if (this.pageVisible && this.loadError.length === 0 &&
        DeadlineProgressService.getDescendantIds(nextTasks, task.id).length === 1) {
        this.undoActionDeadline = this.deadlines.find((item: Deadline) => item.id === action.deadlineId);
        this.undoActionTasks = this.subtasks.filter((item: DeadlineSubtask) => item.deadlineId === action.deadlineId);
        this.undoActionTaskTitle = task.title;
        this.undoActionTaskId = task.id;
      }
    } catch (error) {
      console.error(`Failed to complete recommended task: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_task_conflict' : 'message_task_update_failed'));
      await this.loadDeadlines(false);
    } finally {
      this.updatingActionId = '';
    }
  }

  private async undoRecommendedTask(): Promise<void> {
    const expected: Deadline | undefined = this.undoActionDeadline;
    const taskId: string = this.undoActionTaskId;
    if (expected === undefined || taskId.length === 0 || this.updatingActionId.length > 0) {
      return;
    }
    this.updatingActionId = taskId;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const nextTasks: DeadlineSubtask[] = DeadlineProgressService.toggleTaskTree(this.undoActionTasks, taskId, false);
      const progress: number = DeadlineProgressService.calculateDeadlineProgress(nextTasks);
      await DeadlineDatabaseService.commitTaskChanges(context, expected.id, this.undoActionTasks,
        nextTasks, progress, expected);
      DeadlineReminderService.onUserDataChanged(context, expected.id);
      this.undoActionTaskId = '';
      await this.loadDeadlines(false);
    } catch (error) {
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_task_conflict' : 'message_task_status_failed'));
      if (error instanceof DeadlineDataConflictError) {
        this.undoActionTaskId = '';
        await this.loadDeadlines(false);
      }
    } finally {
      this.updatingActionId = '';
    }
  }

  private openDeadlineDetail(deadlineId: string): void {
    if (deadlineId.length === 0 || this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/DeadlineDetail',
        params: new DeadlineRouteParams(deadlineId)
      }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to open deadline detail: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(LocalizationService.text('message_open_detail_failed'));
        }
      })
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate to deadline detail: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_detail_failed'));
    }
  }

  private openCreateDeadline(): void {
    if (this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/CreateDeadline',
        params: new DeadlineRouteParams('')
      }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to open deadline creator: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(LocalizationService.text('message_open_create_failed'));
        }
      });
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate to deadline creator: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_create_failed'));
    }
  }

  private isExpired(deadlineAt: number): boolean {
    return deadlineAt < Date.now();
  }

  private getAccentColor(deadline: Deadline): ResourceColor {
    if (deadline.completed) {
      return $r('app.color.success');
    }
    const level: string = this.getInsight(deadline).riskLevel;
    if (level === 'high') {
      return $r('app.color.danger');
    }
    if (level === 'medium') {
      return $r('app.color.warning');
    }
    return $r('app.color.text_secondary');
  }

  private getAgendaRenderKey(day: ScheduleAgendaDay): string {
    const items: string = day.items.map((item: ScheduleAgendaItem) =>
      `${item.deadlineId}:${item.estimatedHours}:${item.summary}:${item.riskLevel}`).join('|');
    return `${day.dateAt}:${day.capacityHours}:${day.estimatedHours}:${day.deferredHours}:${items}`;
  }

  private retryLoad(): void {
    if (this.isLoading || !this.pageVisible) {
      return;
    }
    const version: number = ++this.refreshVersion;
    this.refreshHome(version, true);
  }

  private getInsight(deadline: Deadline): DeadlineInsight {
    return this.insightById.get(deadline.id) ?? DeadlineInsightService.analyze(deadline);
  }

  private getSecondaryActions(): TodayAction[] {
    return this.todayActions.slice(1);
  }

  private getVisibleDeadlines(): Deadline[] {
    return this.showAllDeadlines ? this.deadlines : this.deadlines.filter((item: Deadline) =>
      DeadlineOverdueRuntime.state(item) !== 'stopped').slice(0, INITIAL_DEADLINE_RENDER_LIMIT);
  }

  private getVisibleAgendaItems(day: ScheduleAgendaDay): ScheduleAgendaItem[] {
    return day.items.slice(0, AGENDA_ITEM_RENDER_LIMIT);
  }

  private getActionColor(action: TodayAction): ResourceColor {
    if (action.riskLevel === 'high') {
      return $r('app.color.danger');
    }
    if (action.riskLevel === 'medium') {
      return $r('app.color.warning');
    }
    return $r('app.color.text_secondary');
  }

  private getActionButtonText(action: TodayAction): string {
    if (this.updatingActionId === action.taskId && action.taskId.length > 0) {
      return LocalizationService.text('common_updating');
    }
    if (action.canComplete) {
      return LocalizationService.text('home_complete_task');
    }
    if (action.kind === 'breakdown') {
      return LocalizationService.text('home_break_down');
    }
    return LocalizationService.text('home_view_details');
  }

  private getAgendaItemColor(item: ScheduleAgendaItem): ResourceColor {
    if (item.dayType === 'deferred') {
      return $r('app.color.danger');
    }
    if (item.dayType === 'unknown') {
      return $r('app.color.text_secondary');
    }
    if (item.dayType === 'buffer') {
      return $r('app.color.text_secondary');
    }
    if (item.riskLevel === 'high') {
      return $r('app.color.danger');
    }
    if (item.riskLevel === 'medium') {
      return $r('app.color.warning');
    }
    return $r('app.color.text_secondary');
  }

  private getAgendaHoursText(day: ScheduleAgendaDay): string {
    if (day.deferredHours > 0) {
      return LocalizationService.text('schedule_unallocated_hours',
        DeadlineInsightService.normalizeHours(day.deferredHours));
    }
    if (day.estimatedHours > 0) {
      return LocalizationService.text('common_about_hours',
        DeadlineInsightService.normalizeHours(day.estimatedHours));
    }
    return day.items.some((item: ScheduleAgendaItem) => item.dayType === 'unknown') ?
      LocalizationService.text('risk_unknown') : LocalizationService.text('schedule_flex_buffer');
  }

  @Builder
  SectionHeader(title: ResourceStr) {
    Column() {
      Text(title)
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DeadlineCard(deadline: Deadline) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(deadline.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_strong'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getDeadlineDateText(deadline))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.getCardStatusText(deadline))
        .fontSize(12)
        .fontColor(this.heldDeadlineIds.includes(deadline.id) ? $r('app.color.text_secondary') : this.getAccentColor(deadline))
        .constraintSize({ maxWidth: '34%' })
        .maxLines(3)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ top: 15, bottom: 15 })
    .constraintSize({ minHeight: 72 })
    .onClick(() => { this.openDeadlineDetail(deadline.id); })
  }

  @Builder
  PriorityActionCard(action: TodayAction) {
    Column({ space: 14 }) {
      Row() {
        Text($r('app.string.home_today_priority'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        Text(action.riskLabel)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getActionColor(action))
          .constraintSize({ maxWidth: '40%' })
          .maxLines(3)
      }
      .width('100%')

      Column({ space: 6 }) {
        Text(action.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(action.deadlineName)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onClick(() => { this.openDeadlineDetail(action.deadlineId); })

      Text(action.reason)
        .width('100%')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Button(this.heldDeadlineIds.includes(action.deadlineId) ? LocalizationService.text('review_open') : this.getActionButtonText(action))
          .type(ButtonType.Capsule)
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand'))
          .height(38)
          .padding({ left: 15, right: 15 })
          .enabled(this.updatingActionId.length === 0)
          .onClick(() => {
            if (this.heldDeadlineIds.includes(action.deadlineId)) { this.openDeadlineDetail(action.deadlineId); }
            else { this.completeRecommendedTask(action); }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
  }

  @Builder
  TodayActionRow(action: TodayAction) {
    Row({ space: 12 }) {
      if (action.canComplete && !this.heldDeadlineIds.includes(action.deadlineId)) {
        Row() {
          Text('')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand_accent'))
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .border({ width: 1.5, color: $r('app.color.text_tertiary') })
        }
        .width(40)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .enabled(this.updatingActionId.length === 0)
        .onClick(() => {
          this.completeRecommendedTask(action);
        })
      } else {
        Text(action.kind === 'breakdown' ? LocalizationService.text('task_breakdown_mark') : '→')
          .width(24)
          .height(24)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_accent'))
          .textAlign(TextAlign.Center)
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
      }

      Column({ space: 4 }) {
        Text(action.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(action.deadlineName)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openDeadlineDetail(action.deadlineId);
      })

      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 8, right: 8 })
        .constraintSize({ minHeight: 44 })
        .onClick(() => {
          this.openDeadlineDetail(action.deadlineId);
        })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  @Builder
  ScheduleAgendaItemRow(item: ScheduleAgendaItem) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(item.deadlineName)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_strong'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.summary)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(item.dayType === 'unknown' ? LocalizationService.text('risk_unknown') :
        (item.dayType === 'deferred' ? LocalizationService.text('schedule_unallocated_hours',
          DeadlineInsightService.normalizeHours(item.estimatedHours)) : (item.estimatedHours > 0 ?
          LocalizationService.text('common_about_hours',
            DeadlineInsightService.normalizeHours(item.estimatedHours)) :
          LocalizationService.text('schedule_buffer'))))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getAgendaItemColor(item))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openDeadlineDetail(item.deadlineId);
    })
  }

  @Builder
  ScheduleAgendaCard(day: ScheduleAgendaDay) {
    Column({ space: 8 }) {
      Row() {
        Text(day.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_strong'))

        Blank()

        Text(this.getAgendaHoursText(day))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(day.deferredHours > 0 ? $r('app.color.danger') :
            $r('app.color.text_secondary'))
      }
      .width('100%')

      if (day.items.length === 0) {
        Text($r('app.string.schedule_open_day'))
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.getVisibleAgendaItems(day), (item: ScheduleAgendaItem) => {
          this.ScheduleAgendaItemRow(item)
        }, (item: ScheduleAgendaItem) => `${day.dateAt}:${item.deadlineId}:${item.summary}`)

        if (day.items.length > AGENDA_ITEM_RENDER_LIMIT) {
          Text(LocalizationService.count('schedule_more_items', day.items.length - AGENDA_ITEM_RENDER_LIMIT))
            .width('100%')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ top: 6, bottom: 4 })
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
  }

  @Builder
  AllDoneState() {
    Column({ space: 8 }) {
      Text('✓')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.success'))

      Text($r('app.string.home_all_done'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_strong'))

      Text($r('app.string.home_all_done_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
  }

  @Builder
  EmptyState() {
    Column({ space: 0 }) {
      Text($r('app.string.home_empty_tagline'))
        .width('100%')
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .textAlign(TextAlign.Start)

      Text($r('app.string.home_empty_body'))
        .width('100%')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
        .textAlign(TextAlign.Start)
        .margin({ top: 10 })

      Button($r('app.string.home_create_first'))
        .width('100%')
        .type(ButtonType.Capsule)
        .height(48)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand'))
        .margin({ top: 24 })
        .onClick(() => {
          this.openCreateDeadline();
        })

      Text($r('app.string.home_empty_hint'))
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Start)
        .margin({ top: 11 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 20, bottom: 20 })
  }

  @Builder
  MessageCard(message: string) {
    Text(message)
      .width('100%')
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .padding({ top: 24, bottom: 24 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
  }

  @Builder
  ErrorCard(message: string) {
    Column({ space: 14 }) {
      Text(message)
        .width('100%')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)

      Button($r('app.string.common_retry'))
        .type(ButtonType.Capsule)
        .height(38)
        .fontSize(13)
        .fontColor($r('app.color.brand_accent'))
        .backgroundColor($r('app.color.surface_accent'))
        .onClick(() => {
          this.retryLoad();
        })
    }
    .width('100%')
    .padding({ top: 22, bottom: 22, left: 18, right: 18 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row() {
          Column({ space: 4 }) {
            Text($r('app.string.app_name'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          if (this.deadlines.length > 0) {
            Button('+')
              .type(ButtonType.Normal)
              .width(44)
              .height(44)
              .fontSize(24)
              .fontColor($r('app.color.text_body'))
              .backgroundColor(Color.Transparent)
              .accessibilityText(LocalizationService.text('home_add_deadline'))
              .onClick(() => { this.openCreateDeadline(); })
          }

          Text($r('app.string.settings_title'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(14)
            .padding({ left: 13, right: 13, top: 7, bottom: 7 })
            .constraintSize({ minHeight: 38 })
            .onClick(() => {
              this.openSettings();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.syncWarning.length > 0) {
          Text(this.syncWarning)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 14, bottom: 8 })
            .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/ConflictRecovery' }); })
        }
        if (this.recoveryEntries.length > 0) {
          Button(LocalizationService.text('review_home_status', this.recoveryEntries.length))
            .type(ButtonType.Normal).constraintSize({ minHeight: 44 }).width('100%')
            .fontSize(13).fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
            .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/ConflictRecovery' }); })
        }
        Column() {
          if (this.isLoading) {
            this.MessageCard(LocalizationService.text('home_loading'))
          } else if (this.loadError.length > 0) {
            this.ErrorCard(this.loadError)
          } else if (this.deadlines.length === 0) {
            this.EmptyState()
          } else if (this.todayActions.length === 0) {
            if (this.deadlines.some((item: Deadline) => !item.completed)) {
              this.MessageCard(LocalizationService.text('overdue_no_actions'))
            } else { this.AllDoneState() }
          } else {
            ForEach(this.todayActions.slice(0, 1), (action: TodayAction) => {
              this.PriorityActionCard(action)
            }, (action: TodayAction) => {
              return `${action.deadlineId}:${action.taskId}:${action.title}:${action.context}:${action.reason}:${action.suggestion}:${action.riskLabel}`
            })
          }
        }
        .width('100%')
        .margin({ top: 24 })

        if (!this.isLoading && this.loadError.length === 0 && this.undoActionTaskId.length > 0) {
          Row({ space: 8 }) {
            Text(LocalizationService.text('task_just_completed', this.undoActionTaskTitle))
              .layoutWeight(1)
              .fontSize(13)
              .fontColor($r('app.color.text_body'))
              .maxLines(2)
            Button($r('app.string.common_undo'))
              .type(ButtonType.Normal)
              .height(38)
              .fontSize(13)
              .fontColor($r('app.color.brand_accent'))
              .backgroundColor($r('app.color.surface_muted'))
              .enabled(this.updatingActionId.length === 0)
              .onClick(() => { this.undoRecommendedTask(); })
          }
          .width('100%')
          .margin({ top: 12 })
        }

        if (!this.isLoading && this.loadError.length === 0 && this.getSecondaryActions().length > 0) {
          Column({ space: 0 }) {
            this.SectionHeader($r('app.string.home_next'))

            Column() {
              ForEach(this.getSecondaryActions(), (action: TodayAction, index: number) => {
                this.TodayActionRow(action)

                if (index < this.getSecondaryActions().length - 1) {
                  Divider()
                    .color($r('app.color.divider'))
                    .margin({ left: 36 })
                }
              }, (action: TodayAction) => `${action.deadlineId}:${action.taskId}:${action.kind}:${action.title}:${action.context}`)
            }
            .width('100%')
            .margin({ top: 12 })
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(14)
          }
          .width('100%')
          .margin({ top: 28 })
        }

        if (!this.isLoading && this.loadError.length === 0 && this.deadlines.length > 0) {
          Column({ space: 12 }) {
            this.SectionHeader($r('app.string.home_all_deadlines'))

            Column() {
              ForEach(this.getVisibleDeadlines(), (deadline: Deadline, index: number) => {
                this.DeadlineCard(deadline)
                if (index < this.getVisibleDeadlines().length - 1) {
                  Divider().color($r('app.color.divider'))
                }
              }, (deadline: Deadline) => this.getDeadlineRenderKey(deadline))
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)

            if (this.deadlines.length > INITIAL_DEADLINE_RENDER_LIMIT || this.deadlines.some((item: Deadline) =>
              DeadlineOverdueRuntime.state(item) === 'stopped')) {
              Button(this.showAllDeadlines ? LocalizationService.text('home_collapse_list') :
                LocalizationService.count('home_view_all', this.deadlines.length))
                .type(ButtonType.Capsule)
                .height(40)
                .fontSize(13)
                .fontColor($r('app.color.text_body'))
                .backgroundColor($r('app.color.surface_muted'))
                .margin({ top: 2 })
                .onClick(() => {
                  this.showAllDeadlines = !this.showAllDeadlines;
                })
            }
          }
          .width('100%')
          .margin({ top: 28 })
        }

        if (!this.isLoading && this.loadError.length === 0 && this.scheduleAgenda.length > 0 &&
          this.todayActions.length > 0) {
          Column({ space: 10 }) {
            Row() {
              Text($r('app.string.home_auto_schedule'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_body'))
              Blank()
              Text(this.showHomeSchedule ? '-' : '+')
                .fontSize(18)
                .fontColor($r('app.color.brand_accent'))
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .onClick(() => {
              this.showHomeSchedule = !this.showHomeSchedule;
            })

            if (this.showHomeSchedule) {
              ForEach(this.scheduleAgenda, (day: ScheduleAgendaDay) => {
                this.ScheduleAgendaCard(day)
              }, (day: ScheduleAgendaDay) => this.getAgendaRenderKey(day))
            }
          }
          .width('100%')
          .margin({ top: 20 })
        }

        Blank().height(24)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
