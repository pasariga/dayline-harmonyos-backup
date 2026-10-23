import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Deadline, DeadlineRouteParams, DeadlineSubtask, DeadlineTaskView } from '../models/Deadline';
import { DeadlineSyncHeldError, DeadlineDataConflictError, DeadlineDatabaseService } from '../services/DeadlineDatabaseService';
import { DeadlineProgressService } from '../services/DeadlineProgressService';
import { DeadlineReminderResult, DeadlineReminderService } from '../services/DeadlineReminderService';
import { NotificationSettingsService } from '../services/NotificationSettingsService';
import { AppSettingsRuntime } from '../services/AppSettingsService';
import { LocalizationService } from '../services/LocalizationService';
import { DeadlineOverdueService } from '../services/DeadlineOverdueService';
import { AppLogger } from '../services/AppLogger';
import { ExperiencePresentation, ExperienceRouteParams } from '../services/ExperiencePresentation';
import { DeadlineTime } from '../services/DeadlineTime';

const INITIAL_DRAFT_TASK_RENDER_LIMIT: number = 30;

@Entry
@Component
struct CreateDeadline {
  @State deadlineName: string = '';
  @State deadlineType: string = '作业';
  @State selectedTypeIndex: number = 0;
  @State deadlineDate: string = '';
  @State deadlineDateValue: string = '';
  @State deadlineTime: string = '23:59';
  @State note: string = '';
  @State estimatedHoursText: string = '';
  @State progress: number = 0;
  @State progressMode: string = 'manual';
  @State reminderOffsetMinutes: number = 0;
  @State nameError: string = '';
  @State dateError: string = '';
  @State hoursError: string = '';
  @State isSaving: boolean = false;
  @State isLoadingDeadline: boolean = false;
  @State loadError: string = '';
  @State isEditMode: boolean = false;
  @State tasks: DeadlineSubtask[] = [];
  @State taskTitle: string = '';
  @State taskParentId: string = '';
  @State editingTaskId: string = '';
  @State taskActionsId: string = '';
  @State showAllDraftTasks: boolean = false;
  @State showMoreOptions: boolean = false;
  @State showTaskOptions: boolean = false;
  @State showAdvancedOptions: boolean = false;
  @State removedDraftTitle: string = '';

  private returnWorkspace: number = 0;
  private selectedDate: Date = new Date();
  private selectedTime: Date = new Date(2026, 0, 1, 23, 59);
  private editingId: string = '';
  private originalCreatedAt: number = 0;
  private originalCompleted: boolean = false;
  private originalDeadline: Deadline | undefined = undefined;
  private loadedLocalDate: string = '';
  private loadedLocalTime: string = '';
  private originalTasks: DeadlineSubtask[] = [];
  private removedDraftTasks: DeadlineSubtask[] = [];
  private routeInitialized: boolean = false;
  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;
  private saveInFlight: boolean = false;
  private taskViewsSource: DeadlineSubtask[] | undefined = undefined;
  private taskViewsCache: DeadlineTaskView[] = [];
  private removeTaskDialogVisible: boolean = false;
  private permissionGuideVisible: boolean = false;
  private permissionGuideHandledInSession: boolean = false;
  private permissionGuideCheckInFlight: boolean = false;
  private discardDialogVisible: boolean = false;
  private allowLeave: boolean = false;
  private readonly deadlineTypes: string[] = ['作业', '考试', '竞赛', '项目', '生活', '其他'];
  private readonly clockChanged = (): void => {
    if (this.pageVisible && this.originalDeadline !== undefined &&
      this.deadlineDateValue === this.loadedLocalDate && this.deadlineTime === this.loadedLocalTime) {
      this.applyLocalDue(this.originalDeadline.deadlineAt);
    }
  };

  private applyLocalDue(at: number): void {
    this.loadedLocalDate = DeadlineTime.dateKey(at);
    this.loadedLocalTime = DeadlineTime.timeKey(at);
    this.deadlineDateValue = this.loadedLocalDate;
    this.deadlineTime = this.loadedLocalTime;
    this.selectedDate = new Date(at);
    this.selectedTime = new Date(at);
    this.deadlineDate = this.formatDate(this.selectedDate);
  }

  onPageShow(): void {
    this.pageVisible = true;
    DeadlineTime.onClockChanged(this.clockChanged);
    this.clockChanged();
    this.isNavigating = false;
    this.removeTaskDialogVisible = false;
    this.isSaving = this.saveInFlight;
    const deadlineId: string = this.readRouteDeadlineId();
    if (deadlineId.length > 0) {
      if (!this.routeInitialized || !this.isEditMode || deadlineId !== this.editingId || this.isLoadingDeadline) {
        this.loadDeadlineForEdit(deadlineId);
      }
      this.routeInitialized = true;
      return;
    }
    if (!this.routeInitialized || this.isEditMode) {
      this.resetForCreate();
    }
    this.routeInitialized = true;
  }

  onPageHide(): void {
    this.pageVisible = false;
    DeadlineTime.offClockChanged(this.clockChanged);
    this.loadVersion++;
  }

  private readRouteDeadlineId(): string {
    try {
      const params: DeadlineRouteParams = this.getUIContext().getRouter().getParams() as DeadlineRouteParams;
      if (params === undefined || params === null) {
        return '';
      }
      this.returnWorkspace = (params as ExperienceRouteParams).workspace === 1 ? 1 : 0;
      return typeof params.deadlineId === 'string' ? params.deadlineId : '';
    } catch (error) {
      console.error(`Failed to read create page route params: ${CloudDiagnostic.code(error as Object)}`);
      return '';
    }
  }

  private resetForCreate(): void {
    const defaultDeadlineTime: string = AppSettingsRuntime.getDefaultDeadlineTime();
    const defaultTimeParts: string[] = defaultDeadlineTime.split(':');
    this.isEditMode = false;
    this.editingId = '';
    this.originalCreatedAt = 0;
    this.originalCompleted = false;
    this.originalDeadline = undefined;
    this.originalTasks = [];
    this.deadlineName = '';
    this.deadlineType = '作业';
    this.selectedTypeIndex = 0;
    this.deadlineDate = '';
    this.deadlineDateValue = '';
    this.deadlineTime = defaultDeadlineTime;
    this.note = '';
    this.estimatedHoursText = '';
    this.progress = 0;
    this.progressMode = AppSettingsRuntime.getDefaultProgressMode();
    this.reminderOffsetMinutes = 0;
    this.tasks = [];
    this.taskTitle = '';
    this.taskParentId = '';
    this.editingTaskId = '';
    this.showAllDraftTasks = false;
    this.showMoreOptions = false;
    this.showTaskOptions = false;
    this.showAdvancedOptions = false;
    this.removedDraftTitle = '';
    this.allowLeave = false;
    this.nameError = '';
    this.dateError = '';
    this.hoursError = '';
    this.loadError = '';
    this.isSaving = false;
    this.isLoadingDeadline = false;
    this.selectedDate = new Date();
    this.selectedTime = new Date(2026, 0, 1, Number(defaultTimeParts[0]), Number(defaultTimeParts[1]));
  }

  private getTypeIndex(type: string): number {
    switch (type) {
      case '作业':
        return 0;
      case '考试':
        return 1;
      case '竞赛':
        return 2;
      case '项目':
        return 3;
      case '生活':
        return 4;
      default:
        return 5;
    }
  }

  private async loadDeadlineForEdit(deadlineId: string): Promise<void> {
    const version: number = ++this.loadVersion;
    this.isLoadingDeadline = true;
    this.isEditMode = true;
    this.editingId = deadlineId;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const snapshot = await DeadlineDatabaseService.getDeadlineDataSnapshot(context);
      const deadline: Deadline | undefined = snapshot.deadlines.find((item: Deadline) => item.id === deadlineId);
      if (!this.pageVisible || version !== this.loadVersion || deadlineId !== this.editingId) {
        return;
      }
      if (deadline === undefined) {
        this.loadError = LocalizationService.text('message_deadline_not_found');
        return;
      }

      this.deadlineName = deadline.name;
      this.deadlineType = deadline.type;
      this.selectedTypeIndex = this.getTypeIndex(deadline.type);
      this.applyLocalDue(deadline.deadlineAt);
      this.note = deadline.note;
      this.estimatedHoursText = deadline.estimatedHours > 0 ? `${deadline.estimatedHours}` : '';
      this.progress = deadline.progress;
      this.progressMode = deadline.progressMode;
      this.reminderOffsetMinutes = deadline.reminderOffsetMinutes;
      this.originalCreatedAt = deadline.createdAt;
      this.originalCompleted = deadline.completed;
      const storedTasks: DeadlineSubtask[] = snapshot.subtasks.filter((task: DeadlineSubtask) =>
        task.deadlineId === deadlineId);
      if (!this.pageVisible || version !== this.loadVersion || deadlineId !== this.editingId) {
        return;
      }
      this.tasks = storedTasks;
      this.originalDeadline = deadline;
      this.originalTasks = storedTasks.slice();
      this.showAllDraftTasks = false;
      this.showMoreOptions = true;
      this.showTaskOptions = true;
      this.showAdvancedOptions = true;
      this.allowLeave = false;

      this.loadError = '';
    } catch (error) {
      console.error(`Failed to load deadline for editing: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('message_load_deadline_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoadingDeadline = false;
      }
    }
  }

  private padNumber(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private formatDate(value: Date): string {
    return LocalizationService.formatDate(value, 'long');
  }

  private getTypeDisplayLabel(): string {
    const keys: string[] = [
      'type_assignment', 'type_exam', 'type_competition', 'type_project', 'type_life', 'type_other'
    ];
    return LocalizationService.text(keys[this.selectedTypeIndex]);
  }

  private getReminderDisplayLabel(): string {
    if (this.reminderOffsetMinutes === 60) {
      return LocalizationService.text('reminder_hour');
    }
    if (this.reminderOffsetMinutes === 1440) {
      return LocalizationService.text('reminder_day');
    }
    if (this.reminderOffsetMinutes === 4320) {
      return LocalizationService.text('reminder_three_days');
    }
    return LocalizationService.text('reminder_none');
  }

  private formatStorageDate(value: Date): string {
    return `${value.getFullYear()}-${this.padNumber(value.getMonth() + 1)}-${this.padNumber(value.getDate())}`;
  }

  private openDatePicker(): void {
    const startDate: Date = this.isEditMode ? new Date(1900, 0, 1) : new Date();
    startDate.setHours(0, 0, 0, 0);
    const endDate: Date = new Date();
    endDate.setFullYear(endDate.getFullYear() + 10);

    try {
      this.getUIContext().showDatePickerDialog({
        start: startDate,
        end: endDate,
        selected: this.selectedDate,
        lunar: false,
        onDateAccept: (value: Date) => {
          if (!this.pageVisible) {
            return;
          }
          this.selectedDate = value;
          this.deadlineDate = this.formatDate(value);
          this.deadlineDateValue = this.formatStorageDate(value);
          this.dateError = '';
        }
      })
    } catch (error) {
      console.error(`Failed to show date picker: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_date_picker_failed'));
    }
  }

  private openTimePicker(): void {
    try {
      this.getUIContext().showTimePickerDialog({
        selected: new Date(this.selectedDate.getFullYear(), this.selectedDate.getMonth(), this.selectedDate.getDate(),
          Number(this.deadlineTime.split(':')[0]), Number(this.deadlineTime.split(':')[1])),
        useMilitaryTime: LocalizationService.uses24HourClock(),
        onAccept: (value: TimePickerResult) => {
          if (!this.pageVisible) {
            return;
          }
          this.selectedTime.setHours(value.hour, value.minute);
          this.deadlineTime = `${this.padNumber(value.hour)}:${this.padNumber(value.minute)}`;
          this.dateError = '';
        }
      })
    } catch (error) {
      console.error(`Failed to show time picker: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_time_picker_failed'));
    }
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private async rememberPermissionGuideHandled(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await NotificationSettingsService.markPermissionGuideHandled(context);
    } catch (error) {
      console.error(`Failed to remember notification guidance choice: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private async requestNotificationAfterGuide(): Promise<void> {
    this.permissionGuideHandledInSession = true;
    await this.rememberPermissionGuideHandled();
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const enabled: boolean = await DeadlineReminderService.requestNotificationPermission(context);
      if (enabled) {
        await DeadlineReminderService.reconcileAll(context);
      }
      if (this.pageVisible) {
        this.showMessage(enabled ? LocalizationService.text('message_notifications_enabled') :
          LocalizationService.text('message_notifications_not_enabled'));
      }
    } catch (error) {
      console.error(`Failed to request notification after guidance: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private async offerNotificationPermissionOnce(): Promise<void> {
    if (this.reminderOffsetMinutes <= 0 || this.permissionGuideVisible ||
      this.permissionGuideHandledInSession || this.permissionGuideCheckInFlight || !this.pageVisible) {
      return;
    }
    this.permissionGuideCheckInFlight = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const values = await Promise.all([
        DeadlineReminderService.isNotificationPermissionEnabled(),
        NotificationSettingsService.hasHandledPermissionGuide(context)
      ]);
      if (!this.pageVisible || this.reminderOffsetMinutes <= 0) {
        return;
      }
      const enabled: boolean = values[0] as boolean;
      const handled: boolean = values[1] as boolean;
      if (enabled) {
        this.permissionGuideHandledInSession = true;
        await this.rememberPermissionGuideHandled();
        return;
      }
      if (handled) {
        this.permissionGuideHandledInSession = true;
        return;
      }
      this.permissionGuideVisible = true;
      this.getUIContext().showAlertDialog({
        title: LocalizationService.text('notification_permission_prompt_title'),
        message: LocalizationService.text('notification_permission_prompt_body'),
        cancel: () => {
          this.permissionGuideVisible = false;
          this.permissionGuideHandledInSession = true;
          this.rememberPermissionGuideHandled();
        },
        primaryButton: {
          value: LocalizationService.text('notification_not_now'),
          action: () => {
            this.permissionGuideVisible = false;
            this.permissionGuideHandledInSession = true;
            this.rememberPermissionGuideHandled();
          }
        },
        secondaryButton: {
            value: LocalizationService.text('notification_enable'),
            action: () => {
              this.permissionGuideVisible = false;
              this.permissionGuideHandledInSession = true;
              this.requestNotificationAfterGuide();
          }
        }
      });
    } catch (error) {
      this.permissionGuideVisible = false;
      console.error(`Failed to offer notification permission: ${CloudDiagnostic.code(error as Object)}`);
    } finally {
      this.permissionGuideCheckInFlight = false;
    }
  }

  private returnToDetail(deadlineId: string): void {
    if (deadlineId.length === 0 || this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/DeadlineDetail',
        params: new ExperienceRouteParams(deadlineId, this.returnWorkspace)
      }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to return to deadline detail: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(LocalizationService.text('message_return_detail_failed'));
        }
      })
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate back to deadline detail: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_return_detail_failed'));
    }
  }

  onBackPress(): boolean {
    if (this.isSaving) {
      this.showMessage(LocalizationService.text('message_save_in_progress'));
      return true;
    }
    this.navigateBack();
    return true;
  }

  private hasUnsavedChanges(): boolean {
    if (this.taskTitle.trim().length > 0 && (this.editingTaskId.length === 0 ||
      this.taskTitle.trim() !== this.findTaskTitle(this.editingTaskId))) {
      return true;
    }
    const original: Deadline | undefined = this.originalDeadline;
    if (original === undefined) {
      return this.deadlineName.trim().length > 0 || this.deadlineDateValue.length > 0 ||
        this.estimatedHoursText.trim().length > 0 || this.note.trim().length > 0 || this.tasks.length > 0 ||
        this.progress > 0 || this.deadlineType !== '作业' ||
        this.progressMode !== AppSettingsRuntime.getDefaultProgressMode() ||
        this.reminderOffsetMinutes !== 0 || this.deadlineTime !== AppSettingsRuntime.getDefaultDeadlineTime();
    }
    if (this.deadlineName.trim() !== original.name || this.deadlineType !== original.type ||
      this.deadlineDateValue !== this.loadedLocalDate || this.deadlineTime !== this.loadedLocalTime ||
      this.note.trim() !== original.note ||
      this.estimatedHoursText.trim() !== (original.estimatedHours > 0 ? `${original.estimatedHours}` : '') ||
      this.progressMode !== original.progressMode || this.reminderOffsetMinutes !== original.reminderOffsetMinutes ||
      (this.progressMode === 'manual' && this.progress !== original.progress) ||
      this.tasks.length !== this.originalTasks.length) {
      return true;
    }
    for (let index: number = 0; index < this.tasks.length; index++) {
      const current: DeadlineSubtask = this.tasks[index];
      const saved: DeadlineSubtask = this.originalTasks[index];
      if (current.id !== saved.id || current.title !== saved.title || current.completed !== saved.completed ||
        current.parentId !== saved.parentId || current.sortOrder !== saved.sortOrder) {
        return true;
      }
    }
    return false;
  }

  private navigateBack(): void {
    if (this.isSaving || this.isNavigating) {
      return;
    }
    if (!this.allowLeave && this.hasUnsavedChanges()) {
      if (this.discardDialogVisible) {
        return;
      }
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
              this.navigateBack();
            }
          }
        });
      } catch (error) {
        this.discardDialogVisible = false;
        this.showMessage(LocalizationService.text('message_go_back_failed'));
      }
      return;
    }
    if (this.isEditMode && this.editingId.length > 0) {
      this.returnToDetail(this.editingId);
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to leave deadline editor: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_go_back_failed'));
    }
  }

  private getTaskViews(): DeadlineTaskView[] {
    if (this.taskViewsSource !== this.tasks) {
      this.taskViewsSource = this.tasks;
      this.taskViewsCache = DeadlineProgressService.flattenTasks(this.tasks);
    }
    return this.taskViewsCache;
  }

  private getTaskRenderKey(view: DeadlineTaskView): string {
    return `${view.task.id}:${view.task.title}:${view.task.completed}:${view.level}:${view.progress}`;
  }

  private getVisibleTaskViews(): DeadlineTaskView[] {
    const views: DeadlineTaskView[] = this.getTaskViews();
    return this.showAllDraftTasks ? views : views.slice(0, INITIAL_DRAFT_TASK_RENDER_LIMIT);
  }

  private findTaskTitle(taskId: string): string {
    const task: DeadlineSubtask | undefined = this.tasks.find((item: DeadlineSubtask) => item.id === taskId);
    return task === undefined ? '' : task.title;
  }

  private getTaskInputHint(): string {
    if (this.editingTaskId.length > 0) {
      return LocalizationService.text('task_edit_name_hint');
    }
    if (this.taskParentId.length > 0) {
      return LocalizationService.text('task_add_to_hint', this.findTaskTitle(this.taskParentId));
    }
    return LocalizationService.text('task_add_top_hint');
  }

  private cancelTaskEditor(): void {
    this.taskTitle = '';
    this.taskParentId = '';
    this.editingTaskId = '';
  }

  private beginAddChild(task: DeadlineSubtask): void {
    this.taskTitle = '';
    this.editingTaskId = '';
    this.taskParentId = task.id;
  }

  private beginEditTask(task: DeadlineSubtask): void {
    this.taskTitle = task.title;
    this.taskParentId = task.parentId;
    this.editingTaskId = task.id;
  }

  private saveTaskDraft(): void {
    const title: string = this.taskTitle.trim();
    if (title.length === 0) {
      return;
    }
    this.removedDraftTitle = '';
    if (this.editingTaskId.length > 0) {
      this.tasks = this.tasks.map((task: DeadlineSubtask) => {
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
        util.generateRandomUUID(),
        this.editingId,
        title,
        false,
        createdAt,
        this.taskParentId,
        createdAt
      );
      this.tasks = this.tasks.concat([task]);
      if (this.tasks.length > INITIAL_DRAFT_TASK_RENDER_LIMIT) {
        this.showAllDraftTasks = true;
      }
    }
    this.tasks = DeadlineProgressService.deriveParentStates(this.tasks);
    this.cancelTaskEditor();
  }

  private toggleTaskDraft(task: DeadlineSubtask): void {
    this.removedDraftTitle = '';
    const currentProgress: number = DeadlineProgressService.getTaskProgress(this.tasks, task.id);
    this.tasks = DeadlineProgressService.toggleTaskTree(this.tasks, task.id, currentProgress < 100);
  }

  private confirmRemoveTaskDraft(task: DeadlineSubtask): void {
    if (this.removeTaskDialogVisible || this.isSaving) {
      return;
    }
    const affectedIds: string[] = DeadlineProgressService.getDescendantIds(this.tasks, task.id);
    if (affectedIds.length === 1) {
      this.removeTaskDraft(affectedIds);
      return;
    }
    this.removeTaskDialogVisible = true;
    try {
      this.getUIContext().showAlertDialog({
        title: LocalizationService.text('task_remove_title'),
        cancel: () => { this.removeTaskDialogVisible = false; },
        message: affectedIds.length > 1 ?
          LocalizationService.count('task_remove_children_confirm', affectedIds.length - 1, task.title) :
          LocalizationService.text('task_remove_confirm', task.title),
        primaryButton: {
          value: LocalizationService.text('common_cancel'),
          action: () => {
            this.removeTaskDialogVisible = false;
          }
        },
        secondaryButton: {
          value: LocalizationService.text('common_remove'),
          fontColor: $r('app.color.danger'),
          action: () => {
            this.removeTaskDialogVisible = false;
            this.removeTaskDraft(affectedIds);
          }
        }
      })
    } catch (error) {
      this.removeTaskDialogVisible = false;
      console.error(`Failed to show draft task removal confirmation: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_open_task_remove_failed'));
    }
  }

  private removeTaskDraft(affectedIds: string[]): void {
    this.removedDraftTasks = this.tasks;
    this.removedDraftTitle = this.findTaskTitle(affectedIds[0]);
    this.tasks = this.tasks.filter((item: DeadlineSubtask) => affectedIds.indexOf(item.id) < 0);
    this.tasks = DeadlineProgressService.deriveParentStates(this.tasks);
    if (affectedIds.indexOf(this.editingTaskId) >= 0 || affectedIds.indexOf(this.taskParentId) >= 0) {
      this.cancelTaskEditor();
    }
    if (this.tasks.length <= INITIAL_DRAFT_TASK_RENDER_LIMIT) {
      this.showAllDraftTasks = false;
    }
  }

  private undoDraftRemoval(): void {
    if (this.removedDraftTitle.length === 0 || this.isSaving) {
      return;
    }
    this.tasks = this.removedDraftTasks;
    this.removedDraftTitle = '';
  }

  private async saveDeadline(): Promise<void> {
    if (this.taskTitle.trim().length > 0 && (this.editingTaskId.length === 0 ||
      this.taskTitle.trim() !== this.findTaskTitle(this.editingTaskId))) {
      this.showMoreOptions = true;
      this.showTaskOptions = true;
      this.showMessage(LocalizationService.text('experience_pending_task'));
      return;
    }
    this.nameError = this.deadlineName.trim().length === 0 ? LocalizationService.text('validation_name_required') : '';
    this.dateError = this.deadlineDateValue.length === 0 ? LocalizationService.text('validation_date_required') : '';
    const estimatedHours: number = this.estimatedHoursText.trim().length === 0 ? 0 :
      Number(this.estimatedHoursText.trim());
    this.hoursError = this.estimatedHoursText.trim().length > 0 &&
      (!Number.isFinite(estimatedHours) || estimatedHours <= 0 || estimatedHours > 10000) ?
      LocalizationService.text('validation_hours_range') : '';

    if (this.hoursError.length > 0) { this.showMoreOptions = true; }
    if (this.nameError.length > 0 || this.dateError.length > 0 || this.hoursError.length > 0 || this.isSaving ||
      this.isLoadingDeadline || this.loadError.length > 0) {
      return;
    }

    const unchangedDue: boolean = this.isEditMode && this.originalDeadline !== undefined &&
      this.deadlineDateValue === this.loadedLocalDate && this.deadlineTime === this.loadedLocalTime;
    // Preserve the entire stored due triple on ordinary edits, including the
    // second occurrence of a repeated hour and legacy source-local strings.
    const timeError = unchangedDue ? '' : DeadlineTime.inputError(
      this.deadlineDateValue, this.deadlineTime, this.isEditMode, Date.now());
    if (timeError.length > 0) {
      this.dateError = LocalizationService.text(timeError);
      this.showMessage(this.dateError);
      return;
    }
    const deadlineAt: number = unchangedDue && this.originalDeadline !== undefined ?
      this.originalDeadline.deadlineAt : DeadlineTime.fromLocal(this.deadlineDateValue, this.deadlineTime);
    const createdAt: number = this.isEditMode ? this.originalCreatedAt : Date.now();
    this.tasks = DeadlineProgressService.deriveParentStates(this.tasks);
    const deadlineId: string = this.isEditMode ? this.editingId : util.generateRandomUUID();
    const savedProgress: number = this.progressMode === 'automatic' ?
      DeadlineProgressService.calculateDeadlineProgress(this.tasks) : this.progress;
    const deadline: Deadline = new Deadline(
      deadlineId,
      this.deadlineName.trim(),
      this.deadlineType,
      unchangedDue && this.originalDeadline !== undefined ? this.originalDeadline.deadlineDate : this.deadlineDateValue,
      unchangedDue && this.originalDeadline !== undefined ? this.originalDeadline.deadlineTime : this.deadlineTime,
      this.note.trim(),
      createdAt,
      deadlineAt,
      this.isEditMode ? this.originalCompleted : false,
      estimatedHours,
      savedProgress,
      this.progressMode,
      this.tasks.length,
      this.reminderOffsetMinutes,
      this.isEditMode && this.originalDeadline !== undefined ?
        ((this.originalDeadline.remainingState === 'initial' ||
          (this.originalDeadline.remainingState === 'unknown' && this.originalDeadline.estimatedHours <= 0)) &&
          this.originalDeadline.progress === 0 &&
          estimatedHours !== this.originalDeadline.estimatedHours ? estimatedHours :
          this.originalDeadline.remainingHours) : estimatedHours,
      this.isEditMode && this.originalDeadline !== undefined ?
        ((this.originalDeadline.remainingState === 'initial' ||
          (this.originalDeadline.remainingState === 'unknown' && this.originalDeadline.estimatedHours <= 0)) &&
          savedProgress === 0 && estimatedHours > 0 ?
          'initial' : this.originalDeadline.remainingState) :
        (savedProgress === 0 && estimatedHours > 0 ? 'initial' : 'unknown'),
      this.isEditMode && this.originalDeadline !== undefined ? this.originalDeadline.remainingUpdatedAt : createdAt
    );
    const tasksToSave: DeadlineSubtask[] = this.tasks.map((task: DeadlineSubtask) => {
      return new DeadlineSubtask(
        task.id,
        deadlineId,
        task.title,
        task.completed,
        task.createdAt,
        task.parentId,
        task.sortOrder
      );
    });

    this.isSaving = true;
    this.saveInFlight = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await DeadlineDatabaseService.saveDeadlineWithSubtasks(
        context,
        deadline,
        tasksToSave,
        this.isEditMode,
        this.originalDeadline,
        this.originalTasks
      );
      // The new due date already invalidates the old local intent. Auxiliary
      // cleanup must not turn a committed edit into a reported save failure.
      if (this.originalDeadline !== undefined && this.originalDeadline.deadlineAt !== deadline.deadlineAt) {
        try {
          await DeadlineOverdueService.load(context);
          await DeadlineOverdueService.choose(context, this.originalDeadline, 'pending');
        } catch (choiceError) { AppLogger.warn('Overdue', 'Edited deadline saved; local choice cleanup requires retry.'); }
      }
      let reminderFailed: boolean = false;
      let reminderDisabled: boolean = false;
      let reminderQueued: string = '';
      try {
        const reminderResult: DeadlineReminderResult = await DeadlineReminderService.applyDeadline(
          context, deadline, false
        );
        reminderFailed = reminderResult.isFailure();
        reminderDisabled = reminderResult.isPermissionDisabled();
        if (reminderResult.code === 'queued') { reminderQueued = reminderResult.message; }
      } catch (reminderError) {
        console.error(`Saved deadline but reminder refresh failed: ${CloudDiagnostic.code(reminderError as Object)}`);
        reminderFailed = true;
      }
      if (!this.pageVisible) {
        return;
      }
      let saveMessage: string = this.isEditMode ? LocalizationService.text('message_deadline_updated') :
        LocalizationService.text('message_deadline_saved');
      if (reminderFailed) {
        saveMessage = LocalizationService.text('message_saved_reminder_retry', saveMessage);
      }
      if (reminderDisabled) {
        saveMessage += ` ${LocalizationService.text('reminder_result_permission_disabled')}`;
      }
      if (reminderQueued.length > 0) { saveMessage += ` ${reminderQueued}`; }
      if (reminderFailed || reminderDisabled || reminderQueued.length > 0) {
        this.showMessage(saveMessage);
      }
      this.isSaving = false;
      this.saveInFlight = false;
      if (this.isEditMode) {
        this.returnToDetail(deadline.id);
      } else {
        ExperiencePresentation.recordCreated(deadline.id, deadline.name);
        this.allowLeave = true;
        this.navigateBack();
      }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) {
        this.loadError = LocalizationService.text(error instanceof DeadlineSyncHeldError ? 'cloud_data_held' : 'message_edit_conflict');
        this.showMessage(this.loadError);
        return;
      }
      console.error(`Failed to save deadline: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_save_failed'));
    } finally {
      this.saveInFlight = false;
      if (this.pageVisible) {
        this.isSaving = false;
      }
    }
  }

  private chooseRelativeDate(offset: number): void {
    const day: Date = new Date(DeadlineTime.calendarDay(Date.now(), offset));
    this.selectedDate = day;
    this.deadlineDate = this.formatDate(day);
    this.deadlineDateValue = this.formatStorageDate(day);
    this.dateError = '';
  }

  @Builder
  FieldLabel(title: ResourceStr, required: boolean) {
    Row({ space: 4 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_strong'))

      if (required) {
        Text('*')
          .fontSize(15)
          .fontColor($r('app.color.danger'))
      }
    }
    .width('100%')
  }

  @Builder
  AutomaticTaskDraftEditor() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.tasks_breakdown'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_strong'))

          if (this.tasks.length === 0) {
            Text(LocalizationService.text('tasks_empty_save_later')).fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      if (this.removedDraftTitle.length > 0) {
        Row({ space: 8 }) {
          Text(LocalizationService.text('task_just_removed', this.removedDraftTitle))
            .layoutWeight(1)
            .fontSize(12)
            .fontColor($r('app.color.text_body'))
            .maxLines(2)
          Button($r('app.string.common_undo'))
            .type(ButtonType.Normal)
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.brand_accent'))
            .backgroundColor($r('app.color.surface_muted'))
            .enabled(!this.isSaving)
            .onClick(() => { this.undoDraftRemoval(); })
        }
        .width('100%')
      }

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
        TextInput({ placeholder: this.getTaskInputHint(), text: this.taskTitle })
          .id('deadlineTaskName')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .fontColor($r('app.color.text_strong'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.app_background'))
          .borderRadius(12)
          .maxLength(80)
          .onChange((value: string) => {
            this.taskTitle = value;
          })
          .enabled(!this.isSaving)

        Button(this.editingTaskId.length > 0 ? $r('app.string.common_save') : $r('app.string.common_add'))
          .type(ButtonType.Capsule)
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.brand_accent'))
          .backgroundColor($r('app.color.surface_muted'))
          .enabled(this.taskTitle.trim().length > 0 && !this.isSaving)
          .onClick(() => {
            this.saveTaskDraft();
          })
      }
      .width('100%')

      if (this.tasks.length > 0) {
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
                  .onClick(() => { this.toggleTaskDraft(view.task); })

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
                  .onClick(() => { this.toggleTaskDraft(view.task); })
              Button('⋯')
                .type(ButtonType.Normal)
                .width(44)
                .height(44)
                .fontSize(20)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor(Color.Transparent)
                .accessibilityText(LocalizationService.text('task_actions_label'))
                .enabled(!this.isSaving)
                 .onClick(() => {
                                    this.taskActionsId = this.taskActionsId === view.task.id ? '' : view.task.id;
                })

            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .enabled(!this.isSaving)
            

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
                  .enabled(!this.isSaving)
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
                  .enabled(!this.isSaving)
                  .onClick(() => {
                    this.taskActionsId = '';
                    this.beginEditTask(view.task);
                  })
                Button($r('app.string.common_remove'))
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(44)
                  .fontSize(11)
                  .labelStyle({ maxLines: 2, minFontSize: 9, maxFontSize: 11,
                    heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                  .fontColor($r('app.color.danger'))
                  .backgroundColor(Color.Transparent)
                  .borderRadius(10)
                  .enabled(!this.isSaving)
                  .onClick(() => {
                    this.taskActionsId = '';
                    this.confirmRemoveTaskDraft(view.task);
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

        if (this.tasks.length > INITIAL_DRAFT_TASK_RENDER_LIMIT) {
          Button(this.showAllDraftTasks ? LocalizationService.text('tasks_collapse') :
            LocalizationService.count('tasks_view_all', this.tasks.length))
            .type(ButtonType.Capsule)
            .height(38)
            .fontSize(12)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .onClick(() => {
              this.showAllDraftTasks = !this.showAllDraftTasks;
            })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.app_background'))
    .borderRadius(16)
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row({ space: 14 }) {
          Button($r('app.string.common_back'))
            .type(ButtonType.Normal)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(18)
            .height(38)
            .padding({ left: 13, right: 14 })
            .enabled(!this.isSaving && !this.isNavigating)
            .onClick(() => {
              this.navigateBack();
            })

          Text(this.isEditMode ? $r('app.string.create_edit_title') : $r('app.string.create_new_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(2)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.isEditMode ? $r('app.string.create_edit_helper') : $r('app.string.experience_create_hint'))
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })

        if (this.isLoadingDeadline) {
          Text($r('app.string.create_loading'))
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })
        } else if (this.loadError.length > 0) {
          Text(this.loadError)
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })
        }

        Column({ space: 20 }) {
          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.experience_name'), false)

            TextInput({
              placeholder: $r('app.string.create_name_placeholder'),
              text: this.deadlineName
            })
              .type(InputType.Normal)
              .id('deadlineName')
              .fontSize(20)
              .fontColor($r('app.color.text_strong'))
              .placeholderColor($r('app.color.text_tertiary'))
              .caretColor($r('app.color.brand_accent'))
              .height(50)
              .padding({ left: 15, right: 15 })
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .maxLength(60)
              .onChange((value: string) => {
                this.deadlineName = value;
                if (value.trim().length > 0) {
                  this.nameError = '';
                }
              })

            if (this.nameError.length > 0) {
              Text(this.nameError)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.experience_due'), false)

            Row() {
              Text(this.deadlineDate.length > 0 ? this.deadlineDate : $r('app.string.create_choose_date'))
                .fontSize(15)
                .fontColor(this.deadlineDate.length > 0 ? $r('app.color.text_strong') : $r('app.color.text_tertiary'))

              Blank()

              Text('›')
                .fontSize(24)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height(50)
            .padding({ left: 15, right: 15 })
            .backgroundColor($r('app.color.app_background'))
            .borderRadius(14)
            .onClick(() => {
              this.openDatePicker();
            })

            if (this.dateError.length > 0) {
              Text(this.dateError)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (!this.isEditMode) {
            Row({ space: 8 }) {
              Button(LocalizationService.text('common_today')).type(ButtonType.Normal).layoutWeight(1).height(44)
                .fontSize(14).fontColor($r('app.color.brand_accent')).backgroundColor($r('app.color.surface_muted'))
                .borderRadius(8).onClick(() => { this.chooseRelativeDate(0); })
              Button(LocalizationService.text('experience_tomorrow')).type(ButtonType.Normal).layoutWeight(1).height(44)
                .fontSize(14).fontColor($r('app.color.brand_accent')).backgroundColor($r('app.color.surface_muted'))
                .borderRadius(8).onClick(() => { this.chooseRelativeDate(1); })
            }.width('100%')
          }
            Button(LocalizationService.text('experience_due_clock', LocalizationService.formatClockTime(this.deadlineTime)))
              .type(ButtonType.Normal).width('100%').constraintSize({ minHeight: 44 }).fontSize(13)
              .fontColor($r('app.color.text_body')).backgroundColor(Color.Transparent)
              .onClick(() => { this.openTimePicker(); })

          if (!this.showMoreOptions) {
          Button(this.isSaving ? $r('app.string.common_saving') : (this.isEditMode ? $r('app.string.create_save_changes') : $r('app.string.create_save')))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .width('100%')
          .height(50)
          .margin({ top: 24 })
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand'))
          .enabled(!this.isSaving && !this.isLoadingDeadline && this.loadError.length === 0)
          .opacity(this.isSaving || this.isLoadingDeadline || this.loadError.length > 0 ? 0.65 : 1)
          .onClick(() => {
            this.saveDeadline();
          })
          }
          Row() {
            Text(this.showMoreOptions ? $r('app.string.experience_hide_details') :
              $r('app.string.experience_add_details'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand_accent'))
            Blank()
            Text(this.showMoreOptions ? '-' : '+')
              .fontSize(18)
              .fontColor($r('app.color.brand_accent'))
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.showMoreOptions = !this.showMoreOptions;
          })

          if (this.showMoreOptions) {
          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.field_workload'), false)

            TextInput({
              placeholder: $r('app.string.create_hours_placeholder'),
              text: this.estimatedHoursText
            })
              .id('totalEstimate')
              .type(InputType.Number)
              .fontSize(15)
              .fontColor($r('app.color.text_strong'))
              .placeholderColor($r('app.color.text_tertiary'))
              .caretColor($r('app.color.brand_accent'))
              .height(50)
              .padding({ left: 15, right: 15 })
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .maxLength(7)
              .onChange((value: string) => {
                this.estimatedHoursText = value;
                this.hoursError = '';
              })

            if (this.hoursError.length > 0) {
              Text(this.hoursError)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
            }
            Text(LocalizationService.text(this.isEditMode ? 'workload_total_edit_hint' : 'workload_total_create_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row() {
            Text(LocalizationService.text('experience_task_options')).fontSize(14).fontColor($r('app.color.text_body'))
            Blank()
            Text(this.showTaskOptions ? '−' : '+').fontSize(18).fontColor($r('app.color.brand_accent'))
          }.width('100%').padding({ top: 12, bottom: 12 })
            .onClick(() => { this.showTaskOptions = !this.showTaskOptions; })
          if (this.showTaskOptions) {
          Column({ space: 10 }) {
            this.FieldLabel($r('app.string.field_progress_mode'), false)

            Row({ space: 10 }) {
              Button($r('app.string.core_automatic_progress'))
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(56)
                .fontSize(14)
                .labelStyle({ maxLines: 2, minFontSize: 12, maxFontSize: 14,
                  heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                .fontWeight(FontWeight.Medium)
                .fontColor(this.progressMode === 'automatic' ? Color.White : $r('app.color.text_body'))
                .backgroundColor(this.progressMode === 'automatic' ? $r('app.color.brand') : $r('app.color.surface_muted'))
                .borderRadius(12)
                .onClick(() => {
                  this.progressMode = 'automatic';
                })

              Button($r('app.string.core_manual_progress'))
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(56)
                .fontSize(14)
                .labelStyle({ maxLines: 2, minFontSize: 12, maxFontSize: 14,
                  heightAdaptivePolicy: TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST })
                .fontWeight(FontWeight.Medium)
                .fontColor(this.progressMode === 'manual' ? Color.White : $r('app.color.text_body'))
                .backgroundColor(this.progressMode === 'manual' ? $r('app.color.brand') : $r('app.color.surface_muted'))
                .borderRadius(12)
                .onClick(() => {
                  this.progressMode = 'manual';
                })
            }
            .width('100%')

            Text(this.progressMode === 'automatic' ? $r('app.string.create_auto_progress_desc') :
              $r('app.string.create_manual_progress_desc'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.progressMode === 'manual') {
            Column({ space: 10 }) {
            Row() {
              Text($r('app.string.field_progress'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_strong'))
                .layoutWeight(1)
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
              .onChange((value: number) => {
                this.progress = Math.round(value);
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          } else {
            this.AutomaticTaskDraftEditor()
          }

          }
          Row() {
            Text(LocalizationService.text('experience_advanced_options')).fontSize(14).fontColor($r('app.color.text_body'))
            Blank()
            Text(this.showAdvancedOptions ? '−' : '+').fontSize(18).fontColor($r('app.color.brand_accent'))
          }.width('100%').padding({ top: 12, bottom: 12 })
            .onClick(() => { this.showAdvancedOptions = !this.showAdvancedOptions; })
          if (this.showAdvancedOptions) {
          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.field_type'), false)

            Select([
              { value: LocalizationService.text('type_assignment') },
              { value: LocalizationService.text('type_exam') },
              { value: LocalizationService.text('type_competition') },
              { value: LocalizationService.text('type_project') },
              { value: LocalizationService.text('type_life') },
              { value: LocalizationService.text('type_other') }
            ])
              .selected(this.selectedTypeIndex)
              .value(this.getTypeDisplayLabel())
              .font({ size: 15 })
              .fontColor($r('app.color.text_strong'))
              .selectedOptionFontColor($r('app.color.brand_accent'))
              .selectedOptionBgColor($r('app.color.surface_accent'))
              .height(50)
              .width('100%')
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .onSelect((index: number) => {
                this.selectedTypeIndex = index;
                this.deadlineType = this.deadlineTypes[index];
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.field_reminder'), false)

            Select([
              { value: LocalizationService.text('reminder_none') },
              { value: LocalizationService.text('reminder_hour') },
              { value: LocalizationService.text('reminder_day') },
              { value: LocalizationService.text('reminder_three_days') }
            ])
              .selected(DeadlineReminderService.getOffsetIndex(this.reminderOffsetMinutes))
              .value(this.getReminderDisplayLabel())
              .font({ size: 15 })
              .fontColor($r('app.color.text_strong'))
              .selectedOptionFontColor($r('app.color.brand_accent'))
              .selectedOptionBgColor($r('app.color.surface_accent'))
              .height(50)
              .width('100%')
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .onSelect((index: number) => {
                this.reminderOffsetMinutes = DeadlineReminderService.getOffsetByIndex(index);
                this.offerNotificationPermissionOnce();
              })

            Text(this.reminderOffsetMinutes > 0 ? $r('app.string.create_reminder_on_desc') :
              $r('app.string.create_reminder_off_desc'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 9 }) {
            this.FieldLabel($r('app.string.field_note'), false)

            TextArea({
              placeholder: $r('app.string.create_note_placeholder'),
              text: this.note
            })
              .fontSize(15)
              .fontColor($r('app.color.text_strong'))
              .placeholderColor($r('app.color.text_tertiary'))
              .caretColor($r('app.color.brand_accent'))
              .height(110)
              .padding(15)
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .maxLength(300)
              .onChange((value: string) => {
                this.note = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          }
          }
        }
        .width('100%')
        .margin({ top: 24 })
        .padding({ top: 6, bottom: 6 })

        if (this.showMoreOptions) {
        Button(this.isSaving ? $r('app.string.common_saving') : (this.isEditMode ? $r('app.string.create_save_changes') : $r('app.string.create_save')))
          .type(ButtonType.Normal)
          .borderRadius(10)
          .width('100%')
          .height(50)
          .margin({ top: 24 })
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand'))
          .enabled(!this.isSaving && !this.isLoadingDeadline && this.loadError.length === 0)
          .opacity(this.isSaving || this.isLoadingDeadline || this.loadError.length > 0 ? 0.65 : 1)
          .onClick(() => {
            this.saveDeadline();
          })

        }

        Text(this.isEditMode ? $r('app.string.create_edit_footer') : $r('app.string.create_new_footer'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 12, bottom: 24 })
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
