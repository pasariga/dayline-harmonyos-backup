import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Deadline, DeadlineRouteParams, DeadlineSubtask, DeadlineTaskView } from '../models/Deadline';
import { DeadlineSyncHeldError, DeadlineDataConflictError, DeadlineDatabaseService, DeadlineDataSnapshot } from
  '../services/DeadlineDatabaseService';
import { DeadlineInsight, DeadlineInsightService } from '../services/DeadlineInsightService';
import { DeadlineProgressService } from '../services/DeadlineProgressService';
import { DeadlineReminderResult, DeadlineReminderService } from '../services/DeadlineReminderService';
import { DeadlineScheduleDay, DeadlineSchedulePlan, DeadlineScheduleService } from
  '../services/DeadlineScheduleService';
import { AppLogger } from '../services/AppLogger';
import { LocalizationService } from '../services/LocalizationService';
import { CloudSyncService } from '../services/CloudSyncService';
import { DeadlineOverdueRuntime, DeadlineOverdueService } from '../services/DeadlineOverdueService';
import { DeadlineTime } from '../services/DeadlineTime';

const INITIAL_DETAIL_TASK_RENDER_LIMIT: number = 30;

@Entry
@Component
struct DeadlineDetail {
  @State deadline: Deadline = new Deadline('', '', '', '', '', '', 0, 0, false);
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @State isProcessing: boolean = false;
  @State completed: boolean = false;
  @State progress: number = 0;
  @State subtasks: DeadlineSubtask[] = [];
  @State taskActionsId: string = '';
  @State subtaskTitle: string = '';
  @State isSavingProgress: boolean = false;
  @State remainingEditorVisible: boolean = false;
  @State remainingHoursText: string = '';
  @State remainingHoursError: string = '';
  @State isSavingRemaining: boolean = false;
  @State subtaskBusyId: string = '';
  @State taskParentId: string = '';
  @State editingTaskId: string = '';
  @State showAllTasks: boolean = false;
  @State showMoreDetails: boolean = false;
  @State syncHeld: boolean = false;
  @State undoTaskId: string = '';
  @State undoTaskTitle: string = '';
  @State undoTaskWasCompleted: boolean = false;
  @State overdueState: string = 'normal';
  @State clockNow: number = Date.now();
  private deadlineClock: number = -1;

  private deadlineId: string = '';
  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;
  private taskViewsSource: DeadlineSubtask[] | undefined = undefined;
  private taskViewsCache: DeadlineTaskView[] = [];
  private insightDeadlineSource: Deadline | undefined = undefined;
  private insightCompletedSource: boolean = false;
  private insightProgressSource: number = -1;
  private insightCache: DeadlineInsight | undefined = undefined;
  private insightClockSource: number = -1;
  private scheduleDeadlineSource: Deadline | undefined = undefined;
  private scheduleTasksSource: DeadlineSubtask[] | undefined = undefined;
  private scheduleCompletedSource: boolean = false;
  private scheduleProgressSource: number = -1;
  private scheduleCache: DeadlineSchedulePlan | undefined = undefined;
  private scheduleClockSource: number = -1;
  private portfolioDeadlines: Deadline[] = [];
  private portfolioTasks: DeadlineSubtask[] = [];
  private persistedProgress: number = 0;
  private taskDeleteDialogVisible: boolean = false;
  private deadlineDeleteDialogVisible: boolean = false;
  private discardDialogVisible: boolean = false;
  private allowLeave: boolean = false;
  private readonly syncDataChanged = (): void => {
    // Never discard a draft. Its existing transaction snapshot check handles conflicts.
    if (this.pageVisible && !this.hasPendingDraft() && !this.isProcessing &&
      !this.isSavingProgress && !this.isSavingRemaining && this.subtaskBusyId.length === 0) {
      this.loadDeadline();
    }
  };
  private readonly clockChanged = (): void => {
    if (!this.pageVisible) { return; }
    this.clockNow = Date.now();
    this.overdueState = DeadlineOverdueRuntime.state(this.deadline, this.clockNow);
    this.insightCache = undefined;
    this.scheduleCache = undefined;
    this.armDeadlineClock();
  };

  onPageShow(): void {
    this.pageVisible = true;
    DeadlineTime.onClockChanged(this.clockChanged);
    CloudSyncService.onDataChanged(this.syncDataChanged);
    this.isNavigating = false;
    this.undoTaskId = '';
    this.taskDeleteDialogVisible = false;
    this.deadlineDeleteDialogVisible = false;
    this.discardDialogVisible = false;
    this.allowLeave = false;
    try {
      const params: DeadlineRouteParams = this.getUIContext().getRouter().getParams() as DeadlineRouteParams;
      if (params !== undefined && typeof params.deadlineId === 'string' && params.deadlineId.length > 0) {
        this.deadlineId = params.deadlineId;
      }
      if (this.deadlineId.length === 0) {
        this.loadError = LocalizationService.text('message_detail_missing_id');
        this.isLoading = false;
        return;
      }
      if (this.deadline.id === this.deadlineId && !this.isLoading && this.hasPendingDraft()) {
        // Foreground time refresh must resume even while a draft is preserved.
        this.clockNow = Date.now();
        this.overdueState = DeadlineOverdueRuntime.state(this.deadline, this.clockNow);
        this.insightCache = undefined;
        this.scheduleCache = undefined;
        this.armDeadlineClock();
        return;
      }
      this.loadDeadline(++this.loadVersion);
    } catch (error) {
      console.error(`Failed to read detail route params: ${CloudDiagnostic.code(error as Object)}`);
      this.loadError = LocalizationService.text('message_open_detail_failed');
      this.isLoading = false;
    }
  }

  onPageHide(): void {
    clearTimeout(this.deadlineClock);
    this.pageVisible = false;
    DeadlineTime.offClockChanged(this.clockChanged);
    CloudSyncService.offDataChanged(this.syncDataChanged);
    this.loadVersion++;
  }

  private async loadDeadline(version: number = ++this.loadVersion): Promise<void> {
    const startedAt: number = Date.now();
    if (this.pageVisible) {
      this.isLoading = true;
    }
    const requestedId: string = this.deadlineId;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const snapshot: DeadlineDataSnapshot = await DeadlineDatabaseService.getDeadlineDataSnapshot(context);
      await DeadlineOverdueService.load(context);
      const heldIds: string[] = await DeadlineDatabaseService.getSyncProblemIds(context);
      const storedDeadline: Deadline | undefined = snapshot.deadlines.find((item: Deadline) => item.id === requestedId);
      if (!this.pageVisible || version !== this.loadVersion || requestedId !== this.deadlineId) {
        return;
      }
      if (storedDeadline === undefined) {
        const notice = await DeadlineDatabaseService.getSyncDeletionNotice(context, requestedId);
        this.loadError = LocalizationService.text(notice?.deleted ? 'review_deleted_explanation' : 'message_deadline_not_found');
        return;
      }
      this.syncHeld = heldIds.includes(requestedId) || heldIds.includes('__projection__');
      this.applyDeadline(storedDeadline);
      const storedTasks: DeadlineSubtask[] = snapshot.subtasks.filter((task: DeadlineSubtask) =>
        task.deadlineId === requestedId);
      if (!this.pageVisible || version !== this.loadVersion || requestedId !== this.deadlineId) {
        return;
      }
      this.subtasks = storedTasks;
      this.portfolioDeadlines = snapshot.deadlines;
      this.portfolioTasks = snapshot.subtasks;
      this.insightCache = undefined;
      this.scheduleCache = undefined;
      this.showAllTasks = false;
      await this.synchronizeAutomaticProgress(context, version);
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      this.loadError = '';
      this.armDeadlineClock();
      const duration: number = Date.now() - startedAt;
      const performanceMessage: string = `Detail ready in ${duration} ms (${storedTasks.length} tasks)`;
      if (duration >= 500) {
        AppLogger.warn('Performance', performanceMessage);
      } else {
        AppLogger.info('Performance', performanceMessage);
      }
    } catch (error) {
      console.error(`Failed to load deadline detail: ${CloudDiagnostic.code(error as Object)}`);
      AppLogger.error('DeadlineDetail', 'Failed to load deadline and tasks', error as Object);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('message_load_deadline_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoading = false;
      }
    }
  }

  private applyDeadline(deadline: Deadline): void {
    this.clockNow = Date.now();
    this.overdueState = DeadlineOverdueRuntime.state(deadline);
    this.deadline = new Deadline(
      deadline.id,
      deadline.name,
      deadline.type,
      deadline.deadlineDate,
      deadline.deadlineTime,
      deadline.note,
      deadline.createdAt,
      deadline.deadlineAt,
      deadline.completed,
      deadline.estimatedHours,
      deadline.progress,
      deadline.progressMode,
      deadline.taskCount,
      deadline.reminderOffsetMinutes,
      deadline.remainingHours,
      deadline.remainingState,
      deadline.remainingUpdatedAt
    );
    this.completed = deadline.completed;
    this.progress = deadline.progress;
    this.persistedProgress = deadline.progress;
    this.remainingEditorVisible = false;
    this.remainingHoursText = deadline.remainingHours > 0 ? `${deadline.remainingHours}` : '';
    this.remainingHoursError = '';
    this.loadError = '';
  }

  private getRemainingText(deadlineAt: number): string {
    const now: Date = new Date(this.clockNow);
    if (deadlineAt < now.getTime()) {
      return LocalizationService.text('common_overdue');
    }
    const remainingDays: number = DeadlineTime.daysBetween(now.getTime(), deadlineAt);
    return remainingDays === 0 ? LocalizationService.text('common_today') :
      LocalizationService.text('common_days_value', remainingDays);
  }

  private formatCreatedAt(createdAt: number): string {
    const createdDate: Date = new Date(createdAt);
    return LocalizationService.formatDate(createdDate, 'medium');
  }

  private formatDeadlineTime(): string {
    return LocalizationService.formatTime(new Date(this.deadline.deadlineAt));
  }

  private getInsight(): DeadlineInsight {
    const now: number = this.clockNow;
    if (this.insightCache !== undefined && this.insightDeadlineSource === this.deadline &&
      this.insightCompletedSource === this.completed && this.insightProgressSource === this.progress &&
      this.insightClockSource === now) {
      return this.insightCache;
    }
    const currentDeadline: Deadline = new Deadline(
      this.deadline.id,
      this.deadline.name,
      this.deadline.type,
      this.deadline.deadlineDate,
      this.deadline.deadlineTime,
      this.deadline.note,
      this.deadline.createdAt,
      this.deadline.deadlineAt,
      this.completed,
      this.deadline.estimatedHours,
      this.progress,
      this.deadline.progressMode,
      this.subtasks.length,
      this.deadline.reminderOffsetMinutes,
      this.deadline.remainingHours,
      this.deadline.remainingState,
      this.deadline.remainingUpdatedAt
    );
    const portfolio: Deadline[] = this.portfolioDeadlines.filter((item: Deadline) => item.id !== currentDeadline.id);
    portfolio.push(currentDeadline);
    const insight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(currentDeadline, portfolio, now);
    this.insightDeadlineSource = this.deadline;
    this.insightCompletedSource = this.completed;
    this.insightProgressSource = this.progress;
    this.insightClockSource = now;
    this.insightCache = insight;
    return insight;
  }

  private getSchedulePlan(): DeadlineSchedulePlan {
    const now: number = this.clockNow;
    if (this.scheduleCache !== undefined && this.scheduleDeadlineSource === this.deadline &&
      this.scheduleTasksSource === this.subtasks && this.scheduleCompletedSource === this.completed &&
      this.scheduleProgressSource === this.progress && this.scheduleClockSource === now) {
      return this.scheduleCache;
    }
    const currentDeadline: Deadline = new Deadline(
      this.deadline.id,
      this.deadline.name,
      this.deadline.type,
      this.deadline.deadlineDate,
      this.deadline.deadlineTime,
      this.deadline.note,
      this.deadline.createdAt,
      this.deadline.deadlineAt,
      this.completed,
      this.deadline.estimatedHours,
      this.progress,
      this.deadline.progressMode,
      this.subtasks.length,
      this.deadline.reminderOffsetMinutes,
      this.deadline.remainingHours,
      this.deadline.remainingState,
      this.deadline.remainingUpdatedAt
    );
    const portfolio: Deadline[] = this.portfolioDeadlines.filter((item: Deadline) => item.id !== currentDeadline.id);
    portfolio.push(currentDeadline);
    const portfolioTasks: DeadlineSubtask[] = this.portfolioTasks.filter((task: DeadlineSubtask) =>
      task.deadlineId !== currentDeadline.id).concat(this.subtasks);
    const plan: DeadlineSchedulePlan = DeadlineScheduleService.buildPortfolioPlan(
      currentDeadline, portfolio, portfolioTasks, now);
    this.scheduleDeadlineSource = this.deadline;
    this.scheduleTasksSource = this.subtasks;
    this.scheduleCompletedSource = this.completed;
    this.scheduleProgressSource = this.progress;
    this.scheduleClockSource = now;
    this.scheduleCache = plan;
    return plan;
  }

  private getVisibleScheduleDays(): DeadlineScheduleDay[] {
    return this.getSchedulePlan().days.slice(0, 14);
  }

  private getScheduleDayTypeText(day: DeadlineScheduleDay): string {
    if (day.dayType === 'buffer') {
      return LocalizationService.text('schedule_buffer');
    }
    if (day.dayType === 'flex') {
      return LocalizationService.text('schedule_flex');
    }
    return day.estimatedHours > 0 ? LocalizationService.text('common_about_hours',
      DeadlineInsightService.normalizeHours(day.estimatedHours)) :
      LocalizationService.text('common_completed');
  }

  private formatHours(hours: number): string {
    if (hours <= 0) {
      return LocalizationService.text('common_hours_value', 0);
    }
    const roundedHours: number = Math.round(hours * 10) / 10;
    return LocalizationService.text('common_hours_value', roundedHours);
  }

  private getRiskColor(): ResourceColor {
    const level: string = this.getInsight().riskLevel;
    if (level === 'high') {
      return $r('app.color.danger');
    }
    if (level === 'medium') {
      return $r('app.color.warning');
    }
    return this.completed ? $r('app.color.success') : $r('app.color.text_secondary');
  }

  private replaceDeadlineProgress(progress: number): void {
    this.progress = progress;
    this.persistedProgress = progress;
    this.deadline = new Deadline(
      this.deadline.id,
      this.deadline.name,
      this.deadline.type,
      this.deadline.deadlineDate,
      this.deadline.deadlineTime,
      this.deadline.note,
      this.deadline.createdAt,
      this.deadline.deadlineAt,
      this.completed,
      this.deadline.estimatedHours,
      progress,
      this.deadline.progressMode,
      this.subtasks.length,
      this.deadline.reminderOffsetMinutes,
      this.deadline.remainingHours,
      this.deadline.remainingState,
      this.deadline.remainingUpdatedAt
    );
  }

  private async synchronizeAutomaticProgress(context: common.UIAbilityContext,
    version: number = this.loadVersion): Promise<void> {
    if (this.syncHeld || this.deadline.progressMode !== 'automatic') {
      return;
    }
    const derivedTasks: DeadlineSubtask[] = DeadlineProgressService.deriveParentStates(this.subtasks);
    let taskStatesChanged: boolean = false;
    for (let index: number = 0; index < derivedTasks.length; index++) {
      if (derivedTasks[index].completed !== this.subtasks[index].completed) {
        taskStatesChanged = true;
        break;
      }
    }
    const automaticProgress: number = DeadlineProgressService.calculateDeadlineProgress(derivedTasks);
    if (taskStatesChanged || automaticProgress !== this.deadline.progress) {
      await DeadlineDatabaseService.commitTaskChanges(
        context,
        this.deadline.id,
        this.subtasks,
        derivedTasks,
        automaticProgress,
        this.deadline
      );
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
    }
    this.subtasks = derivedTasks;
    this.replaceDeadlineProgress(automaticProgress);
  }

  private getCompletedTaskCount(): number {
    const parentIds: Set<string> = new Set<string>();
    for (let index: number = 0; index < this.subtasks.length; index++) {
      if (this.subtasks[index].parentId.length > 0) {
        parentIds.add(this.subtasks[index].parentId);
      }
    }
    return this.subtasks.filter((task: DeadlineSubtask) => !parentIds.has(task.id) && task.completed).length;
  }

  private getLeafTaskCount(): number {
    const parentIds: Set<string> = new Set<string>();
    for (let index: number = 0; index < this.subtasks.length; index++) {
      if (this.subtasks[index].parentId.length > 0) {
        parentIds.add(this.subtasks[index].parentId);
      }
    }
    return this.subtasks.filter((task: DeadlineSubtask) => !parentIds.has(task.id)).length;
  }

  private getTaskViews(): DeadlineTaskView[] {
    if (this.taskViewsSource !== this.subtasks) {
      this.taskViewsSource = this.subtasks;
      this.taskViewsCache = DeadlineProgressService.flattenTasks(this.subtasks);
    }
    return this.taskViewsCache;
  }

  private getVisibleTaskViews(): DeadlineTaskView[] {
    const views: DeadlineTaskView[] = this.getTaskViews();
    return this.showAllTasks ? views : views.slice(0, INITIAL_DETAIL_TASK_RENDER_LIMIT);
  }

  private getNextTask(): DeadlineSubtask | undefined {
    const parentIds: Set<string> = new Set<string>();
    this.subtasks.forEach((task: DeadlineSubtask) => { if (task.parentId.length > 0) { parentIds.add(task.parentId); } });
    return this.getTaskViews().find((view: DeadlineTaskView) =>
      !parentIds.has(view.task.id) && !view.task.completed)?.task;
  }

  private getNextActionText(): string {
    if (this.overdueState === 'pending') { return LocalizationService.text('overdue_choose_hint'); }
    if (this.overdueState === 'stopped') { return LocalizationService.text('overdue_stopped_hint'); }
    if (this.deadline.progressMode !== 'automatic') {
      return LocalizationService.text('action_focus_then_update');
    }
    const task: DeadlineSubtask | undefined = this.getNextTask();
    if (task !== undefined) { return task.title; }
    return LocalizationService.text(this.subtasks.length === 0 ?
      'action_create_tasks_suggestion' : 'action_mark_deadline_complete');
  }

  private getTaskRenderKey(view: DeadlineTaskView): string {
    return `${view.task.id}:${view.task.title}:${view.task.completed}:${view.level}:${view.progress}`;
  }

  private findTaskTitle(taskId: string): string {
    const task: DeadlineSubtask | undefined = this.subtasks.find((item: DeadlineSubtask) => item.id === taskId);
    return task === undefined ? '' : task.title;
  }

  private getTaskEditorHint(): string {
    if (this.editingTaskId.length > 0) {
      return LocalizationService.text('task_edit_name_hint');
    }
    if (this.taskParentId.length > 0) {
      return LocalizationService.text('task_add_to_hint', this.findTaskTitle(this.taskParentId));
    }
    return LocalizationService.text('task_add_top_hint');
  }

  private cancelTaskEditor(): void {
    this.subtaskTitle = '';
    this.taskParentId = '';
    this.editingTaskId = '';
  }

  private beginAddChild(task: DeadlineSubtask): void {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.subtaskBusyId.length > 0 || this.isProcessing || this.isSavingProgress) {
      return;
    }
    this.subtaskTitle = '';
    this.editingTaskId = '';
    this.taskParentId = task.id;
  }

  private beginEditTask(task: DeadlineSubtask): void {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.subtaskBusyId.length > 0 || this.isProcessing || this.isSavingProgress) {
      return;
    }
    this.subtaskTitle = task.title;
    this.taskParentId = task.parentId;
    this.editingTaskId = task.id;
  }

  private async saveProgress(): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.isSavingProgress || this.isProcessing) {
      return;
    }
    const normalizedProgress: number = DeadlineInsightService.clampProgress(this.progress);
    if (normalizedProgress === this.persistedProgress) {
      return;
    }
    this.isSavingProgress = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const updatedRows: number = await DeadlineDatabaseService.updateProgress(
        context,
        this.deadline,
        normalizedProgress
      );
      if (updatedRows === 0) {
        throw new Error('No deadline progress was updated.');
      }
      this.replaceDeadlineProgress(normalizedProgress);
      DeadlineReminderService.onUserDataChanged(context, this.deadline.id);
    } catch (error) {
      console.error(`Failed to save progress: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_edit_conflict' : 'message_progress_save_failed'));
      await this.loadDeadline();
    } finally {
      this.isSavingProgress = false;
    }
  }

  private async saveTask(): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    const title: string = this.subtaskTitle.trim();
    if (title.length === 0 || this.subtaskBusyId.length > 0 || this.isProcessing || this.isSavingProgress) {
      return;
    }
    const operationId: string = this.editingTaskId.length > 0 ? this.editingTaskId : util.generateRandomUUID();
    this.subtaskBusyId = operationId;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let nextTasks: DeadlineSubtask[] = this.subtasks;
      if (this.editingTaskId.length > 0) {
        nextTasks = this.subtasks.map((task: DeadlineSubtask) => {
          if (task.id !== this.editingTaskId) {
            return task;
          }
          return new DeadlineSubtask(
            task.id, task.deadlineId, title, task.completed, task.createdAt, task.parentId, task.sortOrder
          );
        });
      } else {
        const createdAt: number = Date.now();
        const task: DeadlineSubtask = new DeadlineSubtask(
          operationId,
          this.deadline.id,
          title,
          false,
          createdAt,
          this.taskParentId,
          createdAt
        );
        nextTasks = this.subtasks.concat([task]);
      }
      nextTasks = DeadlineProgressService.deriveParentStates(nextTasks);
      const nextProgress: number = this.deadline.progressMode === 'automatic' ?
        DeadlineProgressService.calculateDeadlineProgress(nextTasks) : this.deadline.progress;
      await DeadlineDatabaseService.commitTaskChanges(context, this.deadline.id, this.subtasks,
        nextTasks, nextProgress, this.deadline);
      this.subtasks = nextTasks;
      this.replaceDeadlineProgress(nextProgress);
      if (this.subtasks.length > INITIAL_DETAIL_TASK_RENDER_LIMIT) {
        this.showAllTasks = true;
      }
      this.cancelTaskEditor();
      this.undoTaskId = '';
      DeadlineReminderService.onUserDataChanged(context, this.deadline.id);
    } catch (error) {
      console.error(`Failed to save task: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_task_conflict' : 'message_task_save_failed'));
      if (error instanceof DeadlineDataConflictError) {
        await this.loadDeadline();
      }
    } finally {
      this.subtaskBusyId = '';
    }
  }

  private async toggleTask(task: DeadlineSubtask, offerUndo: boolean = true): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.subtaskBusyId.length > 0 || this.isProcessing || this.isSavingProgress) {
      return;
    }
    const previousTasks: DeadlineSubtask[] = this.subtasks;
    this.undoTaskId = '';
    this.subtaskBusyId = task.id;
    try {
      const currentProgress: number = DeadlineProgressService.getTaskProgress(this.subtasks, task.id);
      const nextTasks: DeadlineSubtask[] = DeadlineProgressService.toggleTaskTree(
        this.subtasks,
        task.id,
        currentProgress < 100
      );
      this.subtasks = nextTasks;
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const automaticProgress: number = this.deadline.progressMode === 'automatic' ?
        DeadlineProgressService.calculateDeadlineProgress(nextTasks) : this.deadline.progress;
      await DeadlineDatabaseService.commitTaskChanges(
        context,
        this.deadline.id,
        previousTasks,
        nextTasks,
        automaticProgress,
        this.deadline
      );
      this.replaceDeadlineProgress(automaticProgress);
      DeadlineReminderService.onUserDataChanged(context, this.deadline.id);
      if (offerUndo && DeadlineProgressService.getDescendantIds(previousTasks, task.id).length === 1) {
        this.undoTaskId = task.id;
        this.undoTaskTitle = task.title;
        this.undoTaskWasCompleted = currentProgress < 100;
      }
    } catch (error) {
      console.error(`Failed to toggle task: ${CloudDiagnostic.code(error as Object)}`);
      this.subtasks = previousTasks;
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_task_conflict' : 'message_task_status_failed'));
      if (error instanceof DeadlineDataConflictError) {
        await this.loadDeadline();
      }
    } finally {
      this.subtaskBusyId = '';
    }
  }

  private undoTaskChange(): void {
    const task: DeadlineSubtask | undefined = this.subtasks.find((item: DeadlineSubtask) =>
      item.id === this.undoTaskId);
    if (task !== undefined && this.subtaskBusyId.length === 0) {
      this.toggleTask(task, false);
    }
  }

  private confirmRemoveTask(task: DeadlineSubtask): void {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.taskDeleteDialogVisible || this.subtaskBusyId.length > 0 || this.isProcessing ||
      this.isSavingProgress) {
      return;
    }
    this.taskDeleteDialogVisible = true;
    try {
      const affectedCount: number = DeadlineProgressService.getDescendantIds(this.subtasks, task.id).length;
      this.getUIContext().showAlertDialog({
        title: LocalizationService.text('task_delete_title'),
        cancel: () => { this.taskDeleteDialogVisible = false; },
        message: affectedCount > 1 ?
          LocalizationService.count('task_delete_children_confirm', affectedCount - 1, task.title) :
          LocalizationService.text('task_delete_confirm', task.title),
        primaryButton: {
          value: LocalizationService.text('common_cancel'),
          action: () => {
            this.taskDeleteDialogVisible = false;
          }
        },
        secondaryButton: {
          value: LocalizationService.text('common_delete'),
          fontColor: $r('app.color.danger'),
          action: () => {
            this.taskDeleteDialogVisible = false;
            this.removeTask(task.id);
          }
        }
      })
    } catch (error) {
      this.taskDeleteDialogVisible = false;
      console.error(`Failed to show task deletion confirmation: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_delete_confirm_failed'));
    }
  }

  private async removeTask(taskId: string): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.subtaskBusyId.length > 0) {
      return;
    }
    this.subtaskBusyId = taskId;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const affectedIds: string[] = DeadlineProgressService.getDescendantIds(this.subtasks, taskId);
      const nextTasks: DeadlineSubtask[] = DeadlineProgressService.deriveParentStates(
        this.subtasks.filter((task: DeadlineSubtask) => affectedIds.indexOf(task.id) < 0)
      );
      const nextProgress: number = this.deadline.progressMode === 'automatic' ?
        DeadlineProgressService.calculateDeadlineProgress(nextTasks) : this.deadline.progress;
      await DeadlineDatabaseService.commitTaskChanges(context, this.deadline.id, this.subtasks,
        nextTasks, nextProgress, this.deadline);
      this.subtasks = nextTasks;
      this.replaceDeadlineProgress(nextProgress);
      this.undoTaskId = '';
      if (this.subtasks.length <= INITIAL_DETAIL_TASK_RENDER_LIMIT) {
        this.showAllTasks = false;
      }
      if (this.editingTaskId === taskId || this.taskParentId === taskId) {
        this.cancelTaskEditor();
      }
      DeadlineReminderService.onUserDataChanged(context, this.deadline.id);
    } catch (error) {
      console.error(`Failed to remove task: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_task_conflict' : 'message_task_delete_failed'));
      if (error instanceof DeadlineDataConflictError) {
        await this.loadDeadline();
      }
    } finally {
      this.subtaskBusyId = '';
    }
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show detail message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private retryLoad(): void {
    if (this.isLoading || !this.pageVisible || this.deadlineId.length === 0) {
      return;
    }
    this.loadDeadline();
  }

  private openEditor(): void {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.deadline.id.length === 0 || this.isNavigating || this.isProcessing ||
      this.subtaskBusyId.length > 0 || this.isSavingProgress) {
      return;
    }
    if (this.confirmDiscardChanges(() => { this.openEditor(); })) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/CreateDeadline',
        params: new DeadlineRouteParams(this.deadline.id)
      }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to open deadline editor: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(LocalizationService.text('message_open_edit_failed'));
        }
      })
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate to deadline editor: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_edit_failed'));
    }
  }

  private getRemainingEstimateText(): string {
    if (this.completed) {
      return LocalizationService.text('common_about_hours', 0);
    }
    return DeadlineInsightService.hasUsableRemainingEstimate(this.getInsight().workloadConfidence) ?
      LocalizationService.text('common_about_hours', this.getInsight().remainingHours) :
      LocalizationService.text('work_remaining_pending');
  }

  private armDeadlineClock(): void {
    clearTimeout(this.deadlineClock);
    const delay: number = DeadlineTime.refreshDelay(Date.now(), this.completed ? [] : [this.deadline.deadlineAt]);
    this.deadlineClock = setTimeout(() => {
      if (!this.pageVisible) { return; }
      this.clockNow = Date.now();
      this.overdueState = DeadlineOverdueRuntime.state(this.deadline, this.clockNow);
      this.insightCache = undefined;
      this.scheduleCache = undefined;
      this.armDeadlineClock();
    }, Math.max(100, delay));
  }

  private openConflictReview(): void {
    if (this.isNavigating || this.isProcessing || this.isSavingRemaining || this.isSavingProgress ||
      this.subtaskBusyId.length > 0) { return; }
    if (this.confirmDiscardChanges(() => { this.openConflictReview(); })) { return; }
    this.cancelTaskEditor();
    this.remainingEditorVisible = false;
    this.progress = this.persistedProgress;
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ConflictRecovery',
        params: new DeadlineRouteParams(this.deadlineId) }, (error) => {
        if (error) { this.isNavigating = false; this.showMessage(LocalizationService.text('review_load_failed')); }
      });
    } catch (error) { this.isNavigating = false; this.showMessage(LocalizationService.text('review_load_failed')); }
  }

  private getRemainingEstimateStatus(): string {
    if (this.completed) {
      return LocalizationService.text('common_completed');
    }
    const confidence: string = this.getInsight().workloadConfidence;
    if (confidence === 'stale') {
      return LocalizationService.text('remaining_status_stale');
    }
    if (confidence === 'missing' || confidence === 'unmeasured') {
      return LocalizationService.text('remaining_status_unknown');
    }
    return LocalizationService.text(this.deadline.remainingState === 'initial' ?
      'remaining_status_initial' : 'remaining_status_confirmed');
  }

  private async saveRemainingEstimate(mode: string): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.isSavingRemaining || this.isProcessing || this.isSavingProgress ||
      this.subtaskBusyId.length > 0 || this.deadline.id.length === 0) {
      return;
    }
    const parsedHours: number = Number(this.remainingHoursText.trim());
    if (mode === 'edit' && (this.remainingHoursText.trim().length === 0 ||
      !Number.isFinite(parsedHours) || parsedHours <= 0 || parsedHours > 10000)) {
      this.remainingHoursError = LocalizationService.text('validation_hours_range');
      return;
    }
    if (mode === 'keep' && this.deadline.remainingHours <= 0) {
      this.remainingHoursError = LocalizationService.text('remaining_no_previous_estimate');
      return;
    }
    const hours: number = mode === 'edit' ? parsedHours : this.deadline.remainingHours;
    const state: string = mode === 'unknown' ? 'unknown' : 'confirmed';
    const updatedAt: number = Date.now();
    const previous: Deadline = this.deadline;
    this.isSavingRemaining = true;
    this.isProcessing = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await DeadlineDatabaseService.updateRemainingEstimate(context, previous, hours, state, updatedAt);
      // The saved confirmation is newer than the last visible-page clock tick.
      // Recompute against the current clock before presenting risk and plans.
      this.clockNow = Date.now();
      const updated: Deadline = new Deadline(previous.id, previous.name, previous.type,
        previous.deadlineDate, previous.deadlineTime, previous.note, previous.createdAt,
        previous.deadlineAt, previous.completed, previous.estimatedHours, previous.progress,
        previous.progressMode, previous.taskCount, previous.reminderOffsetMinutes, hours, state, updatedAt);
      this.deadline = updated;
      this.portfolioDeadlines = this.portfolioDeadlines.map((item: Deadline) => item.id === updated.id ? updated : item);
      this.insightCache = undefined;
      this.scheduleCache = undefined;
      this.remainingEditorVisible = false;
      this.remainingHoursText = hours > 0 ? `${hours}` : '';
      this.remainingHoursError = '';
      await DeadlineReminderService.onUserDataChanged(context, updated.id);
    } catch (error) {
      console.error(`Failed to update remaining estimate: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_edit_conflict' : 'message_remaining_save_failed'));
      if (error instanceof DeadlineDataConflictError) {
        this.loadDeadline();
      }
    } finally {
      this.isSavingRemaining = false;
      this.isProcessing = false;
    }
  }

  private async toggleCompleted(): Promise<void> {
    if (this.syncHeld) { this.showMessage(LocalizationService.text('cloud_data_held')); return; }
    if (this.isProcessing || this.isSavingProgress || this.subtaskBusyId.length > 0) {
      return;
    }
    const previousCompleted: boolean = this.completed;
    const nextCompleted: boolean = !previousCompleted;
    this.isProcessing = true;
    this.completed = nextCompleted;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // Restoration is a new decision, never silently resume an old late intent.
      // Clear durably before restoring; if this fails no business write happens.
      if (!nextCompleted) { await DeadlineOverdueService.choose(context, this.deadline, 'pending'); }
      const updatedRows: number = await DeadlineDatabaseService.updateCompleted(
        context,
        this.deadline,
        nextCompleted
      );
      if (updatedRows === 0) {
        throw new Error('No deadline completion state was updated.');
      }
      this.deadline = new Deadline(
        this.deadline.id,
        this.deadline.name,
        this.deadline.type,
        this.deadline.deadlineDate,
        this.deadline.deadlineTime,
        this.deadline.note,
        this.deadline.createdAt,
        this.deadline.deadlineAt,
        nextCompleted,
        this.deadline.estimatedHours,
        this.deadline.progress,
        this.deadline.progressMode,
        this.subtasks.length,
        this.deadline.reminderOffsetMinutes,
        this.deadline.remainingHours,
        'unknown',
        this.deadline.remainingUpdatedAt
      );
      this.progress = this.deadline.progress;
      this.overdueState = DeadlineOverdueRuntime.state(this.deadline);
      this.insightCache = undefined;
      this.scheduleCache = undefined;
      this.undoTaskId = '';
      const reminderResult: DeadlineReminderResult = await DeadlineReminderService.applyDeadline(
        context,
        this.deadline,
        false
      );
      if (reminderResult.isFailure()) {
        this.showMessage(LocalizationService.text('message_status_updated_reminder_retry'));
      }
    } catch (error) {
      console.error(`Failed to update completion state: ${CloudDiagnostic.code(error as Object)}`);
      this.completed = previousCompleted;
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_edit_conflict' : 'message_status_update_failed'));
      if (error instanceof DeadlineDataConflictError) {
        await this.loadDeadline();
      }
    } finally {
      this.isProcessing = false;
    }
  }

  private async chooseOverdue(mode: string): Promise<void> {
    if (this.isProcessing || this.isSavingProgress || this.isSavingRemaining || this.subtaskBusyId.length > 0 || this.syncHeld) { return; }
    this.isProcessing = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const snapshot = await DeadlineDatabaseService.getDeadlineDataSnapshot(context);
      const current = snapshot.deadlines.find((item: Deadline) => item.id === this.deadline.id);
      if (current === undefined || current.completed || current.deadlineAt !== this.deadline.deadlineAt) {
        this.showMessage(LocalizationService.text('message_edit_conflict'));
        await this.loadDeadline();
        return;
      }
      await DeadlineOverdueService.choose(context, current, mode);
      this.overdueState = DeadlineOverdueRuntime.state(current);
      this.insightCache = undefined;
      this.scheduleCache = undefined;
      // Update existing summaries when the user starts/stops following overdue work.
      await DeadlineReminderService.onUserDataChanged(context, current.id);
    } catch (error) {
      this.showMessage(LocalizationService.text('overdue_save_failed'));
    } finally { this.isProcessing = false; }
  }

  private confirmDelete(): void {
    if (this.deadlineDeleteDialogVisible || this.isProcessing || this.isSavingProgress ||
      this.subtaskBusyId.length > 0) {
      return;
    }
    this.deadlineDeleteDialogVisible = true;
    try {
      this.getUIContext().showAlertDialog({
        title: LocalizationService.text('deadline_delete_title'),
        cancel: () => { this.deadlineDeleteDialogVisible = false; },
        message: LocalizationService.text('deadline_delete_confirm', this.deadline.name),
        primaryButton: {
          value: LocalizationService.text('common_cancel'),
          action: () => {
            this.deadlineDeleteDialogVisible = false;
          }
        },
        secondaryButton: {
          value: LocalizationService.text('common_delete'),
          fontColor: $r('app.color.danger'),
          action: () => {
            this.deadlineDeleteDialogVisible = false;
            this.deleteDeadline();
          }
        }
      })
    } catch (error) {
      this.deadlineDeleteDialogVisible = false;
      console.error(`Failed to show delete confirmation: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_delete_confirm_failed'));
    }
  }

  private async deleteDeadline(): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    let context: common.UIAbilityContext | undefined = undefined;
    let reminderCanceled: boolean = false;
    try {
      context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      reminderCanceled = await DeadlineReminderService.cancelForDeadline(context, this.deadline.id);
      const deletedRows: number = await DeadlineDatabaseService.deleteDeadline(context, this.deadline);
      if (deletedRows === 0) {
        throw new Error('No deadline was deleted.');
      }
      DeadlineReminderService.onUserDataChanged(context, this.deadline.id);
      if (!this.pageVisible) {
        return;
      }
      this.showMessage(reminderCanceled ? LocalizationService.text('message_deadline_deleted') :
        LocalizationService.text('message_deadline_deleted_reminder_retry'));
      this.isProcessing = false;
      this.navigateBack();
    } catch (error) {
      console.error(`Failed to delete deadline: ${CloudDiagnostic.code(error as Object)}`);
      if (error instanceof DeadlineDataConflictError) {
        await this.loadDeadline();
      }
      if (context !== undefined && reminderCanceled) {
        await DeadlineReminderService.applyDeadline(context, this.deadline, false);
      }
      this.showMessage(LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : error instanceof DeadlineDataConflictError ?
        'message_edit_conflict' : 'message_delete_failed'));
    } finally {
      if (this.pageVisible) {
        this.isProcessing = false;
      }
    }
  }

  onBackPress(): boolean {
    if (this.isProcessing || this.isSavingProgress || this.subtaskBusyId.length > 0) {
      this.showMessage(LocalizationService.text('message_processing'));
      return true;
    }
    this.navigateBack();
    return true;
  }

  private hasPendingDraft(): boolean {
    const taskChanged: boolean = this.editingTaskId.length > 0 ?
      this.subtaskTitle.trim() !== this.findTaskTitle(this.editingTaskId) : this.subtaskTitle.trim().length > 0;
    const remainingChanged: boolean = this.remainingEditorVisible &&
      this.remainingHoursText.trim() !== (this.deadline.remainingHours > 0 ? `${this.deadline.remainingHours}` : '');
    return taskChanged || remainingChanged || this.progress !== this.persistedProgress;
  }

  private confirmDiscardChanges(onLeave: () => void): boolean {
    if (this.allowLeave || !this.hasPendingDraft()) {
      return false;
    }
    if (!this.discardDialogVisible) {
      this.discardDialogVisible = true;
      try {
        this.getUIContext().showAlertDialog({
          title: LocalizationService.text('editor_discard_title'),
          message: LocalizationService.text('editor_discard_body'),
          cancel: () => { this.discardDialogVisible = false; },
          primaryButton: {
            value: LocalizationService.text('common_cancel'),
            action: () => { this.discardDialogVisible = false; }
          },
          secondaryButton: {
            value: LocalizationService.text('editor_discard_action'),
            fontColor: $r('app.color.danger'),
            action: () => {
              this.discardDialogVisible = false;
              this.allowLeave = true;
              onLeave();
            }
          }
        });
      } catch (error) {
        this.discardDialogVisible = false;
        this.showMessage(LocalizationService.text('message_go_back_failed'));
      }
    }
    return true;
  }

  private navigateBack(): void {
    if (this.isNavigating || this.isProcessing || this.isSavingProgress || this.subtaskBusyId.length > 0) {
      return;
    }
    if (this.confirmDiscardChanges(() => { this.navigateBack(); })) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to leave deadline detail: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_go_back_failed'));
    }
  }

  @Builder
  InfoRow(label: ResourceStr, value: string) {
    Row({ space: 16 }) {
      Text(label)
        .width(104)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)

      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_strong'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  @Builder
  ScheduleDayRow(day: DeadlineScheduleDay) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(day.label)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))

        Text(this.getScheduleDayTypeText(day))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(68)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text(day.summary)
          .width('100%')
          .fontSize(14)
          .fontWeight(day.dayType === 'work' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(day.dayType === 'flex' ? $r('app.color.text_secondary') : $r('app.color.text_strong'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (day.taskTitles.length > 0) {
          Text(LocalizationService.count('schedule_specific_tasks', day.taskTitles.length))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(day.dayType === 'work' ? $r('app.string.schedule_work') :
        (day.dayType === 'buffer' ? $r('app.string.schedule_buffer') : $r('app.string.schedule_flex')))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .constraintSize({ maxWidth: '25%' })
        .maxLines(3)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  DetailContent() {
    Column({ space: 0 }) {
      Column({ space: 10 }) {
        Text(this.deadline.name)
          .width('100%')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.completed ? LocalizationService.text('common_completed') :
          (DeadlineOverdueRuntime.isOverdue(this.deadline, this.clockNow) ? DeadlineOverdueRuntime.elapsedText(this.deadline, this.clockNow) +
            ' · ' + LocalizationService.text(this.overdueState === 'continue' ? 'overdue_continue_button' :
              (this.overdueState === 'stopped' ? 'overdue_stop_button' : 'overdue_decide_label')) :
            this.getRemainingText(this.deadline.deadlineAt)))
          .fontSize(13)
          .fontColor(this.completed ? $r('app.color.success') :
            $r('app.color.text_secondary'))
        if (!this.completed) {
          Divider().color($r('app.color.divider')).margin({ top: 4, bottom: 4 })
          Text(LocalizationService.text('detail_next_action'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.getNextActionText())
            .width('100%')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_title'))
          if (this.overdueState === 'pending' && !this.syncHeld) {
            Button(LocalizationService.text('overdue_continue_button'))
              .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
              .fontColor(Color.White).backgroundColor($r('app.color.brand')).borderRadius(12)
              .enabled(!this.isProcessing).onClick(() => { this.chooseOverdue('continue'); })
            Button(LocalizationService.text('overdue_edit_button'))
              .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
              .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing).onClick(() => { this.openEditor(); })
            Button(LocalizationService.text('overdue_complete_button'))
              .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
              .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing).onClick(() => { this.toggleCompleted(); })
            Button(LocalizationService.text('overdue_stop_button'))
              .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
              .fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing).onClick(() => { this.chooseOverdue('stopped'); })
          } else if (this.overdueState === 'stopped') {
            Button(LocalizationService.text('overdue_reconsider_button'))
              .type(ButtonType.Normal).width('100%').height(44).fontSize(14)
              .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing).onClick(() => { this.chooseOverdue('pending'); })
          } else if (this.deadline.progressMode === 'automatic' && this.getNextTask() !== undefined && !this.syncHeld) {
            Button(LocalizationService.text('home_complete_task'))
              .type(ButtonType.Capsule)
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor(this.remainingEditorVisible ? $r('app.color.text_body') : Color.White)
              .backgroundColor(this.remainingEditorVisible ? $r('app.color.surface_muted') : $r('app.color.brand'))
              .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
              .onClick(() => {
                const task: DeadlineSubtask | undefined = this.getNextTask();
                if (task !== undefined) { this.toggleTask(task); }
              })
          }
          if (this.overdueState === 'continue' && !this.syncHeld) {
            Text(LocalizationService.text('overdue_continue_reason'))
              .fontSize(12).fontColor($r('app.color.text_secondary'))
            Button(LocalizationService.text('overdue_reconsider_button'))
              .type(ButtonType.Normal).height(40).fontSize(13)
              .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing).onClick(() => { this.chooseOverdue('pending'); })
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      if (this.undoTaskId.length > 0) {
        Row({ space: 8 }) {
          Text(LocalizationService.text(this.undoTaskWasCompleted ? 'task_just_completed' :
            'task_just_reopened', this.undoTaskTitle))
            .fontSize(12)
            .fontColor($r('app.color.text_body'))
            .layoutWeight(1)
            .maxLines(2)
          Button($r('app.string.common_undo'))
            .type(ButtonType.Normal)
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.brand_accent'))
            .backgroundColor($r('app.color.surface_muted'))
            .enabled(this.subtaskBusyId.length === 0)
            .onClick(() => {
              this.undoTaskChange();
            })
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }


      Column({ space: 14 }) {
        if (this.deadline.progressMode === 'automatic') {
          Row({ space: 12 }) {
            Text($r('app.string.task_progress_label'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .constraintSize({ maxWidth: '45%' })
            Text(`${this.getCompletedTaskCount()} / ${this.getLeafTaskCount()}`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_strong'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
        }
        Row({ space: 12 }) {
          Text($r('app.string.core_risk_level'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(this.getInsight().riskLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getRiskColor())
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')

        Row({ space: 12 }) {
          Text($r('app.string.core_remaining_work'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .constraintSize({ maxWidth: '45%' })
          Text(this.getRemainingEstimateText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_strong'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')

        Text(this.getRemainingEstimateStatus())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        if (!this.completed) {
          Button(LocalizationService.text('remaining_update_button'))
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor($r('app.color.brand_accent'))
            .backgroundColor(Color.Transparent)
            .height(44)
            .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
            .onClick(() => {
              this.remainingEditorVisible = !this.remainingEditorVisible;
              this.remainingHoursError = '';
            })

          if (this.remainingEditorVisible) {
            Text(LocalizationService.text('remaining_editor_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ placeholder: LocalizationService.text('remaining_hours_placeholder'), text: this.remainingHoursText })
              .type(InputType.Number)
              .height(48)
              .backgroundColor($r('app.color.app_background'))
              .onChange((value: string) => {
                this.remainingHoursText = value;
                this.remainingHoursError = '';
              })
            if (this.remainingHoursError.length > 0) {
              Text(this.remainingHoursError).fontSize(12).fontColor($r('app.color.danger'))
            }
            Column({ space: 8 }) {
              if (this.deadline.remainingHours > 0) {
                Button(LocalizationService.text('remaining_keep_button'))
                  .type(ButtonType.Normal)
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .fontColor($r('app.color.text_body'))
                  .backgroundColor($r('app.color.surface_muted'))
                  .borderRadius(12)
                  .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
                 .onClick(() => { this.saveRemainingEstimate('keep'); })
              }
              Button(LocalizationService.text('remaining_save_button'))
                .type(ButtonType.Normal)
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.brand'))
                .borderRadius(12)
                .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
                .onClick(() => { this.saveRemainingEstimate('edit'); })
              Button(LocalizationService.text('remaining_unknown_button'))
                .type(ButtonType.Normal)
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontColor($r('app.color.text_body'))
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius(12)
                .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
                .onClick(() => { this.saveRemainingEstimate('unknown'); })
            }
            .width('100%')
          }
        }
      }
      .width('100%')
      .margin({ top: 16 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      if (this.deadline.progressMode === 'manual') {
        Column({ space: 12 }) {
          Row() {
            Text($r('app.string.detail_manual_update'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_strong'))
            Blank()
            Text(`${this.progress}%`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand_accent'))
          }
          .width('100%')

          Slider({ value: this.progress, min: 0, max: 100, step: 5 })
            .width('100%')
            .selectedColor($r('app.color.brand_accent'))
            .trackColor($r('app.color.progress_track'))
            .blockColor($r('app.color.brand_accent'))
            .enabled(!this.completed && !this.isSavingProgress)
            .onChange((value: number) => {
              this.progress = Math.round(value);
            })

          Button(this.isSavingProgress ? LocalizationService.text('common_saving') :
            (DeadlineInsightService.clampProgress(this.progress) === this.persistedProgress ?
              LocalizationService.text('detail_progress_saved') : LocalizationService.text('detail_save_progress')))
            .type(ButtonType.Capsule)
            .width('100%')
            .height(42)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_accent'))
            .backgroundColor(Color.Transparent)
            .enabled(!this.completed && !this.isSavingProgress &&
              DeadlineInsightService.clampProgress(this.progress) !== this.persistedProgress)
            .opacity(this.completed ? 0.55 : 1)
            .onClick(() => {
              this.saveProgress();
            })

          if (this.completed) {
            Text($r('app.string.detail_completed_progress_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 16 })
        .padding(18)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      } else {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text($r('app.string.detail_tasks'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_strong'))

            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

          }
              .width('100%')

          if (this.taskParentId.length > 0 || this.editingTaskId.length > 0) {
            Row() {
              Text(this.editingTaskId.length > 0 ? LocalizationService.text('task_editing',
                this.findTaskTitle(this.editingTaskId)) : LocalizationService.text('task_adding_child',
                this.findTaskTitle(this.taskParentId)))
                .fontSize(12)
                .fontColor($r('app.color.brand_accent'))
                .layoutWeight(1)
              Text($r('app.string.common_cancel'))
                .fontSize(12)
                .fontColor($r('app.color.text_body'))
                .padding({ left: 8, right: 8, top: 12, bottom: 12 })
                .onClick(() => {
                  this.cancelTaskEditor();
                })
            }
            .width('100%')
          }

          Row({ space: 10 }) {
            TextInput({ placeholder: this.getTaskEditorHint(), text: this.subtaskTitle })
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .fontColor($r('app.color.text_strong'))
              .placeholderColor($r('app.color.text_tertiary'))
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(12)
              .maxLength(80)
              .onChange((value: string) => {
                this.subtaskTitle = value;
              })
              .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)

            Button(this.editingTaskId.length > 0 ? $r('app.string.common_save') : $r('app.string.common_add'))
              .type(ButtonType.Capsule)
              .height(42)
              .fontSize(14)
              .fontColor($r('app.color.brand_accent'))
              .backgroundColor($r('app.color.surface_muted'))
              .enabled(this.subtaskTitle.trim().length > 0 && this.subtaskBusyId.length === 0)
              .onClick(() => {
                this.saveTask();
              })
          }
          .width('100%')

          if (this.subtasks.length === 0) {
            Text($r('app.string.detail_tasks_empty'))
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .padding({ top: 10, bottom: 6 })
          } else {
            ForEach(this.getVisibleTaskViews(), (view: DeadlineTaskView) => {
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  Row() {
                    if (view.progress === 100) {
                      Text('✓')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                    }
                  }
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .border({ width: 1.5, color: $r('app.color.text_tertiary') })
                  .backgroundColor(view.progress === 100 ? $r('app.color.brand') : Color.Transparent)
                  .justifyContent(FlexAlign.Center)
                 .onClick(() => { this.toggleTask(view.task); })

                  Column({ space: 3 }) {
                    Text(view.task.title)
                      .width('100%')
                      .fontSize(14)
                      .fontWeight(view.level === 0 ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(view.progress === 100 ? $r('app.color.text_tertiary') : $r('app.color.text_strong'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .decoration({
                        type: view.progress === 100 ? TextDecorationType.LineThrough : TextDecorationType.None
                      })

                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                 .onClick(() => { this.toggleTask(view.task); })
                  Button('⋯')
                    .type(ButtonType.Normal)
                    .width(44)
                    .height(44)
                    .fontSize(20)
                    .fontColor($r('app.color.text_secondary'))
                    .backgroundColor(Color.Transparent)
                    .accessibilityText(LocalizationService.text('task_actions_label'))
                    .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
                   .onClick(() => {
                      this.taskActionsId = this.taskActionsId === view.task.id ? '' : view.task.id;
                    })

                }
                .width('100%')
                .constraintSize({ minHeight: 44 })
                .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
                

                if (this.taskActionsId === view.task.id) {
                  Row({ space: 8 }) {
                    Button($r('app.string.task_add_child'))
                      .type(ButtonType.Normal)
                      .layoutWeight(1.6)
                      .height(44)
                      .fontSize(11)
                      .labelStyle({ maxLines: 2, minFontSize: 9, maxFontSize: 11,
                        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                      .fontColor($r('app.color.brand_accent'))
                      .backgroundColor(Color.Transparent)
                      .borderRadius(10)
                      .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
                    .onClick(() => {
                        this.taskActionsId = '';
                        this.beginAddChild(view.task);
                      })
                    Button($r('app.string.common_edit'))
                      .type(ButtonType.Normal)
                      .layoutWeight(1)
                      .height(44)
                      .fontSize(11)
                      .labelStyle({ maxLines: 2, minFontSize: 9, maxFontSize: 11,
                        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                      .fontColor($r('app.color.text_body'))
                      .backgroundColor($r('app.color.surface_muted'))
                      .borderRadius(10)
                      .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
                    .onClick(() => {
                        this.taskActionsId = '';
                        this.beginEditTask(view.task);
                      })
                    Button($r('app.string.common_delete'))
                      .type(ButtonType.Normal)
                      .layoutWeight(1)
                      .height(44)
                      .fontSize(11)
                      .labelStyle({ maxLines: 2, minFontSize: 9, maxFontSize: 11,
                        heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                      .fontColor($r('app.color.danger'))
                      .backgroundColor(Color.Transparent)
                      .borderRadius(10)
                      .enabled(this.subtaskBusyId.length === 0 && !this.isProcessing && !this.isSavingProgress)
                    .onClick(() => {
                        this.taskActionsId = '';
                        this.confirmRemoveTask(view.task);
                      })
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .padding({ left: 8 + Math.min(view.level, 6) * 18, right: 2, top: 10, bottom: 10 })
              .backgroundColor(Color.Transparent)
              .borderRadius(12)
            }, (view: DeadlineTaskView) => this.getTaskRenderKey(view))

            if (this.subtasks.length > INITIAL_DETAIL_TASK_RENDER_LIMIT) {
              Button(this.showAllTasks ? LocalizationService.text('tasks_collapse') :
                LocalizationService.count('tasks_view_all', this.subtasks.length))
                .type(ButtonType.Capsule)
                .height(38)
                .fontSize(12)
                .fontColor($r('app.color.text_body'))
                .backgroundColor($r('app.color.surface_muted'))
                .onClick(() => {
                  this.showAllTasks = !this.showAllTasks;
                })
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 16 })
        .padding(18)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      }

      Row() {
        Text(this.showMoreDetails ? $r('app.string.detail_less_info') : $r('app.string.detail_more_info'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand_accent'))
        Blank()
        Text(this.showMoreDetails ? '-' : '+')
          .fontSize(18)
          .fontColor($r('app.color.brand_accent'))
      }
      .width('100%')
      .margin({ top: 18 })
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        this.showMoreDetails = !this.showMoreDetails;
      })

      if (this.showMoreDetails) {
      Text(this.getInsight().riskReason)
        .width('100%')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.deadline.progressMode === 'automatic') {
        Text($r('app.string.detail_equal_weight'))
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
      }
      Column({ space: 12 }) {
        Row() {
          Column({ space: 3 }) {
            Text($r('app.string.detail_schedule'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_strong'))

            Text($r('app.string.detail_schedule_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          if (this.getSchedulePlan().days.length > 0) {
            Text(this.getInsight().riskLevel === 'overdue' ? LocalizationService.text('common_overdue') :
              (this.getInsight().riskLevel === 'unknown' ? LocalizationService.text('risk_unknown') :
              (this.getSchedulePlan().isFeasible ? LocalizationService.text('schedule_feasible') :
                LocalizationService.text('schedule_tight'))))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getSchedulePlan().isFeasible ? $r('app.color.success') : $r('app.color.danger'))
.constraintSize({ maxWidth: '34%' })
              .maxLines(3)
          }
        }
        .width('100%')

        if (this.getSchedulePlan().days.length === 0) {
          Text(this.completed ? LocalizationService.text('schedule_completed_empty') :
            (this.getSchedulePlan().estimateNote.length > 0 ? this.getSchedulePlan().estimateNote :
              LocalizationService.text('schedule_no_remaining')))
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 16 })
        } else {
          Row() {
            Column({ space: 3 }) {
              Text(LocalizationService.text('common_about_hours', this.getSchedulePlan().totalRemainingHours))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_body'))
              Text(LocalizationService.text('schedule_required_work'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 3 }) {
              Text(LocalizationService.text('common_days_value', this.getSchedulePlan().activeWorkDays))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_body'))
              Text($r('app.string.schedule_work_days'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 3 }) {
              Text(LocalizationService.text('common_about_hours',
                DeadlineInsightService.normalizeHours(this.getSchedulePlan().dailyAverageHours)))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_body'))
              Text($r('app.string.schedule_daily_average'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.app_background'))
          .borderRadius(12)

          Text(this.getSchedulePlan().bufferMessage)
            .width('100%')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding({ top: 8, bottom: 8, left: 10, right: 10 })


          if (this.getSchedulePlan().estimateNote.length > 0) {
            Text(this.getSchedulePlan().estimateNote)
              .width('100%')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }

          Column() {
            ForEach(this.getVisibleScheduleDays(), (day: DeadlineScheduleDay, index: number) => {
              this.ScheduleDayRow(day)

              if (index < this.getVisibleScheduleDays().length - 1) {
                Divider().color($r('app.color.divider'))
              }
            }, (day: DeadlineScheduleDay) => `${day.dateAt}:${day.dayType}:${day.summary}`)
          }
          .width('100%')

          if (this.getSchedulePlan().days.length > 14 || this.getSchedulePlan().isTruncated) {
            Text($r('app.string.schedule_rolling_hint'))
              .width('100%')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 16 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Column() {
        this.InfoRow($r('app.string.detail_total_work'), this.deadline.estimatedHours > 0 ?
          this.formatHours(this.deadline.estimatedHours) : LocalizationService.text('risk_not_estimated'))
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.field_type'), LocalizationService.deadlineType(this.deadline.type))
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.field_due_date'), LocalizationService.formatDate(new Date(this.deadline.deadlineAt), 'long'))
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.field_due_time'), this.formatDeadlineTime())
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.field_reminder'), DeadlineReminderService.getOffsetLabel(this.deadline.reminderOffsetMinutes))
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.detail_remaining_time'), this.getRemainingText(this.deadline.deadlineAt))
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.field_progress_mode'), this.deadline.progressMode === 'automatic' ?
          LocalizationService.text('task_progress_label') : LocalizationService.text('core_manual_progress'))
        Divider().color($r('app.color.divider'))
        Row({ space: 16 }) {
          Text($r('app.string.detail_status'))
            .width(104)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)

          Text(this.completed ? $r('app.string.common_completed') : $r('app.string.common_incomplete'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_strong'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        Divider().color($r('app.color.divider'))
        this.InfoRow($r('app.string.detail_created_at'), this.formatCreatedAt(this.deadline.createdAt))
      }
      .width('100%')
      .margin({ top: 20 })
      .padding({ left: 18, right: 18 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Column({ space: 8 }) {
        Text($r('app.string.detail_note'))
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        Text(this.deadline.note.length > 0 ? this.deadline.note : $r('app.string.detail_no_note'))
          .width('100%')
          .fontSize(15)
          .fontColor(this.deadline.note.length > 0 ? $r('app.color.text_strong') : $r('app.color.text_tertiary'))
          .lineHeight(22)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 16 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      }

      Button(this.completed ? $r('app.string.detail_restore') : $r('app.string.detail_mark_complete'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(50)
        .margin({ top: 24 })
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.completed ? Color.White : $r('app.color.text_body'))
        .backgroundColor(this.completed ? $r('app.color.brand') : $r('app.color.surface_muted'))
        .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
        .onClick(() => {
          this.toggleCompleted();
        })

      Button($r('app.string.common_delete'))
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .backgroundColor(Color.Transparent)
        .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0)
        .onClick(() => {
          this.confirmDelete();
        })
      .margin({ top: 12, bottom: 24 })
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row({ space: 14 }) {
          Button($r('app.string.common_back'))
            .type(ButtonType.Normal)
            .height(38)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(18)
            .padding({ left: 13, right: 14 })
            .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0 &&
              !this.isNavigating)
            .onClick(() => {
              this.navigateBack();
            })

          Text($r('app.string.detail_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(2)

          if (!this.isLoading && this.loadError.length === 0) {
            Button($r('app.string.common_edit'))
              .type(ButtonType.Normal)
              .height(38)
              .fontSize(14)
              .fontColor($r('app.color.brand_accent'))
              .backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing && !this.isSavingProgress && this.subtaskBusyId.length === 0 &&
                !this.isNavigating)
              .onClick(() => {
                this.openEditor();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.syncHeld) {
          Row({ space: 12 }) {
            Text(LocalizationService.text('review_needed'))
              .fontSize(14).fontColor($r('app.color.text_body')).layoutWeight(1)
            Button(LocalizationService.text('review_open'))
              .type(ButtonType.Normal).constraintSize({ minHeight: 44 })
              .fontColor($r('app.color.brand_accent')).backgroundColor(Color.Transparent)
              .enabled(!this.isLoading && !this.isProcessing)
              .onClick(() => { this.openConflictReview(); })
          }.width('100%').padding({ top: 14, bottom: 8 })
        }
        if (this.isLoading) {
          Text($r('app.string.detail_loading'))
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 80 })
        } else if (this.loadError.length > 0) {
          Column({ space: 14 }) {
            Text(this.loadError)
              .width('100%')
              .fontSize(14)
              .fontColor($r('app.color.danger'))
              .textAlign(TextAlign.Center)

            if (this.deadlineId.length > 0) {
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
          }
          .width('100%')
          .margin({ top: 80 })
        } else {
          Column() {
            this.DetailContent()
          }
          .width('100%')
          .margin({ top: 22 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
