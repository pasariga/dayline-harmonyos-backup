import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Deadline, DeadlineReminderState, DeadlineSubtask } from '../models/Deadline';
import { AppLogger } from './AppLogger';
import { DeadlineDatabaseService, DeadlineDataSnapshot } from './DeadlineDatabaseService';
import { DeadlineInsight, DeadlineInsightService } from './DeadlineInsightService';
import { DeadlineProgressService } from './DeadlineProgressService';
import { NotificationRuntimeState, NotificationSettings, NotificationSettingsService } from
  './NotificationSettingsService';
import { TodayAction, TodayActionService, TodayPlan } from './TodayActionService';
import { LocalizationService } from './LocalizationService';
import { NotificationPolicy, NotificationRiskMark } from './NotificationPolicy';
import { DeadlineOverdueRuntime, DeadlineOverdueService } from './DeadlineOverdueService';
import { DeadlineTime } from './DeadlineTime';

const MINUTE_MILLISECONDS: number = 60 * 1000;
const DAY_MILLISECONDS: number = 24 * 60 * 60 * 1000;
const SMART_PREFIX: string = 'smart:';
const MAX_MANAGED_REMINDERS: number = 28;

export class DesiredReminder {
  key: string;
  scheduledAt: number;
  title: string;
  content: string;
  expiredContent: string;
  autoDeletedAt: number;
  groupId: string;
  signature: string;
  riskMarks: NotificationRiskMark[] = [];

  constructor(key: string, scheduledAt: number, title: string, content: string, expiredContent: string,
    autoDeletedAt: number, groupId: string) {
    this.key = key;
    this.scheduledAt = scheduledAt;
    this.title = title;
    this.content = content;
    this.expiredContent = expiredContent;
    this.autoDeletedAt = autoDeletedAt;
    this.groupId = groupId;
    this.signature = `${key}|${scheduledAt}|${title}|${content}|${autoDeletedAt}|${new Date(scheduledAt).getTimezoneOffset()}`;
  }
}

export class DeadlineReminderResult {
  code: string;
  message: string;

  constructor(code: string, message: string) {
    this.code = code;
    this.message = message;
  }

  isPermissionDisabled(): boolean {
    return this.code === 'permission_disabled';
  }

  isFailure(): boolean {
    return this.code === 'failed';
  }
}

export class DeadlineReminderService {
  private static reconcilePromise: Promise<void> | undefined = undefined;
  private static reconcileAgain: boolean = false;

  static getOffsetLabel(offsetMinutes: number): string {
    if (offsetMinutes === 60) {
      return LocalizationService.text('reminder_hour');
    }
    if (offsetMinutes === 1440) {
      return LocalizationService.text('reminder_day');
    }
    if (offsetMinutes === 4320) {
      return LocalizationService.text('reminder_three_days');
    }
    return LocalizationService.text('reminder_none');
  }

  static getOffsetIndex(offsetMinutes: number): number {
    if (offsetMinutes === 60) {
      return 1;
    }
    if (offsetMinutes === 1440) {
      return 2;
    }
    if (offsetMinutes === 4320) {
      return 3;
    }
    return 0;
  }

  static getOffsetByIndex(index: number): number {
    if (index === 1) {
      return 60;
    }
    if (index === 2) {
      return 1440;
    }
    if (index === 3) {
      return 4320;
    }
    return 0;
  }

  private static getScheduledAt(deadline: Deadline): number {
    return DeadlineTime.reminderAt(deadline.deadlineAt, deadline.reminderOffsetMinutes);
  }

  private static shouldScheduleBasic(deadline: Deadline, now: number = Date.now()): boolean {
    return deadline.reminderOffsetMinutes > 0 && !deadline.completed && deadline.deadlineAt > now &&
      DeadlineReminderService.getScheduledAt(deadline) > now;
  }

  private static getNotificationId(key: string): number {
    let hash: number = 0;
    for (let index: number = 0; index < key.length; index++) {
      hash = ((hash * 31) + key.charCodeAt(index)) & 0x7FFFFFFF;
    }
    return hash === 0 ? 1 : hash;
  }

  private static startOfDay(value: number): number {
    return DeadlineTime.calendarDay(value);
  }

  private static getDateKey(value: number): string {
    return DeadlineTime.dateKey(value);
  }

  private static atMinuteOfDay(dayAt: number, minuteOfDay: number): number {
    return DeadlineTime.atMinute(dayAt, minuteOfDay);
  }

  private static ceilToMinute(value: number): number {
    return Math.ceil(value / MINUTE_MILLISECONDS) * MINUTE_MILLISECONDS;
  }

  private static truncate(value: string, maximumLength: number): string {
    if (value.length <= maximumLength) {
      return value;
    }
    return `${value.substring(0, Math.max(1, maximumLength - 1))}…`;
  }

  private static moveProactiveAfterQuiet(value: number, settings: NotificationSettings): number {
    return NotificationPolicy.afterQuiet(value, settings);
  }

  private static groupTasks(tasks: DeadlineSubtask[]): Map<string, DeadlineSubtask[]> {
    const grouped: Map<string, DeadlineSubtask[]> = new Map<string, DeadlineSubtask[]>();
    for (let index: number = 0; index < tasks.length; index++) {
      const existing: DeadlineSubtask[] | undefined = grouped.get(tasks[index].deadlineId);
      if (existing === undefined) {
        grouped.set(tasks[index].deadlineId, [tasks[index]]);
      } else {
        existing.push(tasks[index]);
      }
    }
    return grouped;
  }

  private static getIncompleteLeafCount(tasks: DeadlineSubtask[]): number {
    if (tasks.length === 0) {
      return 0;
    }
    const parentIds: Map<string, boolean> = new Map<string, boolean>();
    for (let index: number = 0; index < tasks.length; index++) {
      if (tasks[index].parentId.length > 0) {
        parentIds.set(tasks[index].parentId, true);
      }
    }
    const views = DeadlineProgressService.flattenTasks(tasks);
    return views.filter((view) => !parentIds.has(view.task.id) && view.progress < 100).length;
  }

  private static getDeadlineDistance(deadlineAt: number, reminderAt: number): string {
    const remainingMinutes: number = Math.max(1, Math.ceil((deadlineAt - reminderAt) / MINUTE_MILLISECONDS));
    if (remainingMinutes < 120) {
      return LocalizationService.text('reminder_due_minutes', remainingMinutes);
    }
    if (remainingMinutes < 48 * 60) {
      return LocalizationService.text('reminder_due_hours', Math.ceil(remainingMinutes / 60));
    }
    return LocalizationService.text('reminder_due_days', Math.max(1,
      DeadlineTime.daysBetween(reminderAt, deadlineAt)));
  }

  private static getBasicContent(deadline: Deadline, tasks: DeadlineSubtask[], scheduledAt: number): string {
    const insight: DeadlineInsight = DeadlineInsightService.analyze(deadline, scheduledAt);
    const distance: string = DeadlineReminderService.getDeadlineDistance(deadline.deadlineAt, scheduledAt);
    if (deadline.progressMode === 'automatic') {
      const incompleteLeafCount: number = DeadlineReminderService.getIncompleteLeafCount(tasks);
      if (tasks.length === 0) {
        return LocalizationService.text('reminder_content_no_tasks', distance);
      }
      return LocalizationService.count('reminder_content_tasks', incompleteLeafCount, distance, insight.progress);
    }
    if (DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence)) {
      return LocalizationService.text('reminder_content_hours', distance, insight.progress, insight.remainingHours);
    }
    return LocalizationService.text('reminder_content_progress', distance, insight.progress);
  }

  private static async isNotificationEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (error) {
      AppLogger.error('DeadlineReminder', 'Unable to read notification permission state', error);
      return false;
    }
  }

  static async requestNotificationPermission(context: common.UIAbilityContext): Promise<boolean> {
    if (await DeadlineReminderService.isNotificationEnabled()) {
      return true;
    }
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (error) {
      AppLogger.warn('DeadlineReminder', `Notification permission was not enabled: ${JSON.stringify(error)}`);
      return false;
    }
    return await DeadlineReminderService.isNotificationEnabled();
  }

  static async isNotificationPermissionEnabled(): Promise<boolean> {
    return await DeadlineReminderService.isNotificationEnabled();
  }

  static async openNotificationSettings(context: common.UIAbilityContext): Promise<void> {
    try { await notificationManager.openNotificationSettings(context); }
    catch (_) { throw new Error('System notification settings could not be opened.'); }
  }

  private static async ensureNotificationSlot(): Promise<void> {
    try {
      const slot: notificationManager.NotificationSlot = {
        notificationType: notificationManager.SlotType.SERVICE_INFORMATION,
        desc: LocalizationService.text('notification_slot_desc'),
        badgeFlag: false,
        bypassDnd: false
      };
      await reminderAgentManager.addNotificationSlot(slot);
    } catch (error) {
      AppLogger.warn('DeadlineReminder', `Unable to prepare notification slot: ${JSON.stringify(error)}`);
    }
  }

  private static async cancelSystemReminder(reminderId: number): Promise<boolean> {
    if (reminderId < 0) {
      return true;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
      return true;
    } catch (error) {
      const serializedError: string = JSON.stringify(error);
      if (serializedError.indexOf('1700003') >= 0) {
        return true;
      }
      AppLogger.error('DeadlineReminder', `Unable to cancel reminder ${reminderId}`, error);
      return false;
    }
  }

  private static async publishDesired(context: common.UIAbilityContext,
    desired: DesiredReminder, settings: NotificationSettings): Promise<DeadlineReminderState> {
    await DeadlineReminderService.ensureNotificationSlot();
    // Calendar API has no offset/fold selector. Never silently encode the
    // second occurrence as the earlier one during an autumn clock transition.
    if (!DeadlineTime.calendarCanRepresent(desired.scheduledAt)) {
      throw new Error('System calendar cannot represent this repeated clock instant safely.');
    }
    const scheduledDate: Date = new Date(desired.scheduledAt);
    const buttons: [reminderAgentManager.ActionButton?, reminderAgentManager.ActionButton?,
      reminderAgentManager.ActionButton?] = [{
      title: LocalizationService.text('notification_action_done'),
      type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
    }];
    const snoozeAt = desired.scheduledAt + 30 * MINUTE_MILLISECONDS;
    const allowSnooze = snoozeAt < desired.autoDeletedAt && !NotificationPolicy.inQuiet(snoozeAt, settings);
    if (allowSnooze) {
      buttons.push({ title: LocalizationService.text('notification_action_snooze'),
        type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE });
    }
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: scheduledDate.getFullYear(),
        month: scheduledDate.getMonth() + 1,
        day: scheduledDate.getDate(),
        hour: scheduledDate.getHours(),
        minute: scheduledDate.getMinutes(),
        second: scheduledDate.getSeconds()
      },
      actionButton: buttons,
      snoozeTimes: allowSnooze ? 1 : 0,
      timeInterval: 30 * 60,
      title: DeadlineReminderService.truncate(desired.title, 80),
      content: DeadlineReminderService.truncate(desired.content, 160),
      expiredContent: desired.expiredContent,
      snoozeContent: LocalizationService.text('notification_snooze_content'),
      notificationId: DeadlineReminderService.getNotificationId(desired.key),
      groupId: `dayline:${desired.key}`,
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      tapDismissed: true,
      autoDeletedTime: desired.autoDeletedAt,
      wantAgent: {
        pkgName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }
    };
    try {
      const reminderId: number = await reminderAgentManager.publishReminder(request);
      return new DeadlineReminderState(desired.key, reminderId, desired.scheduledAt, desired.signature);
    } catch (error) {
      throw new Error(`System reminder publish failed: ${JSON.stringify(error)}`);
    }
  }

  private static async publishAndSave(context: common.UIAbilityContext,
    desired: DesiredReminder, settings: NotificationSettings): Promise<void> {
    const state: DeadlineReminderState = await DeadlineReminderService.publishDesired(context, desired, settings);
    try {
      await DeadlineDatabaseService.saveReminderState(context, state);
    } catch (error) {
      await DeadlineReminderService.cancelSystemReminder(state.reminderId);
      throw new Error(`Reminder state persistence failed: ${JSON.stringify(error)}`);
    }
  }

  private static async cancelStoredState(context: common.UIAbilityContext,
    state: DeadlineReminderState): Promise<boolean> {
    const canceled: boolean = await DeadlineReminderService.cancelSystemReminder(state.reminderId);
    if (!canceled) {
      return false;
    }
    try {
      await DeadlineDatabaseService.deleteReminderState(context, state.deadlineId);
      return true;
    } catch (error) {
      AppLogger.error('DeadlineReminder', `Unable to remove reminder state for ${state.deadlineId}`, error);
      return false;
    }
  }

  private static buildBasicReminders(deadlines: Deadline[], tasksByDeadline: Map<string, DeadlineSubtask[]>,
    settings: NotificationSettings, runtime: NotificationRuntimeState, now: number): DesiredReminder[] {
    const candidates: Deadline[] = deadlines.filter((deadline: Deadline) => {
      return DeadlineReminderService.shouldScheduleBasic(deadline, now);
    });
    candidates.sort((first: Deadline, second: Deadline) => {
      return DeadlineReminderService.getScheduledAt(first) - DeadlineReminderService.getScheduledAt(second);
    });
    const selectedCount: number = Math.min(
      NotificationSettingsService.getBasicReminderLimit(settings),
      candidates.length
    );
    const desired: DesiredReminder[] = [];
    for (let index: number = 0; index < selectedCount; index++) {
      const deadline: Deadline = candidates[index];
      const scheduledAt: number = NotificationPolicy.basicTime(
        DeadlineReminderService.getScheduledAt(deadline), deadline.deadlineAt, settings, now);
      if (scheduledAt <= now || scheduledAt >= deadline.deadlineAt) {
        continue;
      }
      const reminder = new DesiredReminder(
        deadline.id,
        scheduledAt,
        `Dayline · ${deadline.name}`,
        DeadlineReminderService.getBasicContent(deadline, tasksByDeadline.get(deadline.id) ?? [], scheduledAt),
        LocalizationService.text('notification_deadline_expired'),
        deadline.deadlineAt,
        'ddl_deadlines'
      );
      reminder.signature += `|cutoff=${deadline.deadlineAt}:${deadline.reminderOffsetMinutes}`;
      desired.push(reminder);
    }
    return desired;
  }

  private static getActionSummary(plan: TodayPlan): string {
    if (plan.actions.length === 0) {
      return '';
    }
    const primary: TodayAction = plan.actions[0];
    return plan.actions.length > 1 ? LocalizationService.count('notification_action_summary_more',
      plan.actions.length - 1, primary.title, primary.suggestion) :
      LocalizationService.text('notification_action_summary', primary.title, primary.suggestion);
  }

  private static getActionDeadlines(deadlines: Deadline[], at: number): Deadline[] {
    return deadlines.filter((deadline: Deadline) => !deadline.completed &&
      (deadline.deadlineAt > at || DeadlineOverdueRuntime.state(deadline, at) === 'continue'));
  }

  private static buildDailySummaries(deadlines: Deadline[], tasks: DeadlineSubtask[], settings: NotificationSettings,
    runtime: NotificationRuntimeState, plannedTaskIds: string[], now: number): DesiredReminder[] {
    const horizon: number = NotificationSettingsService.getDailyHorizon(settings);
    const desired: DesiredReminder[] = [];
    const todayAt: number = DeadlineReminderService.startOfDay(now);
    const cooldownUntil: number = runtime.lastActivityAt + NotificationSettingsService.getActivityCooldown(settings);
    for (let dayOffset: number = 0; dayOffset < horizon; dayOffset++) {
      const dayAt: number = NotificationPolicy.calendarDay(todayAt, dayOffset);
      let scheduledAt: number = DeadlineReminderService.atMinuteOfDay(
        dayAt,
        settings.summaryHour * 60 + settings.summaryMinute
      );
      scheduledAt = DeadlineReminderService.moveProactiveAfterQuiet(scheduledAt, settings);
      if (scheduledAt < cooldownUntil) {
        scheduledAt = DeadlineReminderService.moveProactiveAfterQuiet(
          DeadlineReminderService.ceilToMinute(cooldownUntil),
          settings
        );
      }
      if ((dayOffset === 0 && NotificationPolicy.finishedToday(runtime, DeadlineReminderService.getDateKey(now), deadlines, tasks)) ||
        scheduledAt <= now || DeadlineReminderService.getDateKey(scheduledAt) !== DeadlineReminderService.getDateKey(dayAt)) {
        continue;
      }
      const plan: TodayPlan = TodayActionService.buildPlan(
        DeadlineReminderService.getActionDeadlines(deadlines, scheduledAt),
        tasks,
        scheduledAt
      );
      let content: string = DeadlineReminderService.getActionSummary(plan);
      if (content.length === 0) {
        continue;
      }
      let title: string = plan.actions.some((action: TodayAction) => action.riskLevel === 'high') ?
        LocalizationService.text('notification_daily_title_risk') :
        LocalizationService.text('notification_daily_title');
      if (settings.replanAlertsEnabled && runtime.lastPlanDate.length > 0 &&
        runtime.lastPlanDate < DeadlineReminderService.getDateKey(scheduledAt)) {
        const taskMap: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
        const activeDeadlineIds: Map<string, boolean> = new Map<string, boolean>();
        const activeDeadlines: Deadline[] = DeadlineReminderService.getActionDeadlines(deadlines, scheduledAt);
        for (let deadlineIndex: number = 0; deadlineIndex < activeDeadlines.length; deadlineIndex++) {
          activeDeadlineIds.set(activeDeadlines[deadlineIndex].id, true);
        }
        for (let taskIndex: number = 0; taskIndex < tasks.length; taskIndex++) {
          taskMap.set(tasks[taskIndex].id, tasks[taskIndex]);
        }
        let unfinishedPlannedCount: number = 0;
        for (let taskIdIndex: number = 0; taskIdIndex < runtime.lastPlanTaskIds.length; taskIdIndex++) {
          const task: DeadlineSubtask | undefined = taskMap.get(runtime.lastPlanTaskIds[taskIdIndex]);
          if (task !== undefined && !task.completed && activeDeadlineIds.has(task.deadlineId)) {
            unfinishedPlannedCount++;
          }
        }
        if (unfinishedPlannedCount > 0) {
          title = LocalizationService.text('notification_replan_title');
          content = LocalizationService.count('notification_replan_prefix', unfinishedPlannedCount, content);
        }
      }
      const dateKey: string = DeadlineReminderService.getDateKey(scheduledAt);
      desired.push(new DesiredReminder(
        `${SMART_PREFIX}daily:${dateKey}`,
        scheduledAt,
        title,
        content,
        LocalizationService.text('notification_daily_expired'),
        NotificationPolicy.calendarDay(scheduledAt, 1),
        'ddl_smart_actions'
      ));
    }
    return desired;
  }

  private static findActionForDeadline(plan: TodayPlan, deadlineId: string): TodayAction | undefined {
    for (let index: number = 0; index < plan.actions.length; index++) {
      if (plan.actions[index].deadlineId === deadlineId) {
        return plan.actions[index];
      }
    }
    return undefined;
  }

  private static buildRiskReminders(deadlines: Deadline[], tasks: DeadlineSubtask[], settings: NotificationSettings,
    runtime: NotificationRuntimeState, states: DeadlineReminderState[], now: number): DesiredReminder[] {
    if (NotificationSettingsService.getRiskReminderLimit(settings) === 0) { return []; }
    const marks = NotificationPolicy.readRiskMarks(runtime.riskMarks);
    const pending = states.find((state: DeadlineReminderState) => state.deadlineId.startsWith(`${SMART_PREFIX}risk:`) &&
      state.scheduledAt > now);
    const pendingMarks = pending === undefined ? [] : DeadlineReminderService.riskMarksFromSignature(pending.signature);
    const risky = deadlines.filter((deadline: Deadline) => {
      const signal = NotificationPolicy.riskSignal(deadline, deadlines, now);
      const previous = marks.find((mark: NotificationRiskMark) => mark.id === deadline.id)?.signal ?? 'none';
      return NotificationPolicy.worsened(signal, previous) ||
        pendingMarks.some((mark: NotificationRiskMark) => mark.id === deadline.id && mark.signal === signal && signal !== 'none');
    });
    if (risky.length === 0) { return []; }
    risky.sort((left: Deadline, right: Deadline) => left.deadlineAt - right.deadlineAt);
    const cooldown = runtime.lastActivityAt + NotificationSettingsService.getActivityCooldown(settings);
    for (let offset = 0; offset < 7; offset++) {
      let at = pending !== undefined ? pending.scheduledAt :
        DeadlineReminderService.atMinuteOfDay(NotificationPolicy.calendarDay(now, offset), 18 * 60 + 30);
      if (pending === undefined) { at = DeadlineReminderService.moveProactiveAfterQuiet(Math.max(at,
        DeadlineReminderService.ceilToMinute(cooldown)), settings); }
      const key = `${SMART_PREFIX}risk:${DeadlineReminderService.getDateKey(at)}`;
      if (at <= now || (pending === undefined && states.some((state: DeadlineReminderState) => state.deadlineId === key)) ||
        (pending === undefined && runtime.lastRiskAt > 0 && at - runtime.lastRiskAt <
          (settings.intensity === 'active' ? 2 : 3) * DAY_MILLISECONDS)) { continue; }
      const eligible = risky.filter((deadline: Deadline) => deadline.deadlineAt > at);
      if (eligible.length === 0) { continue; }
      const primary = eligible[0];
      const insight = DeadlineInsightService.analyzePortfolio(primary, deadlines, at);
      const plan = TodayActionService.buildPlan(DeadlineReminderService.getActionDeadlines(deadlines, at), tasks, at);
      const action = DeadlineReminderService.findActionForDeadline(plan, primary.id);
      const desired = new DesiredReminder(key, at, LocalizationService.text('notification_risk_title'),
        LocalizationService.text('notification_risk_content', primary.name, action?.suggestion ?? insight.riskReason),
        LocalizationService.text('notification_risk_expired'), NotificationPolicy.calendarDay(at, 1), 'ddl_smart_risk');
      desired.riskMarks = eligible.map((deadline: Deadline) => new NotificationRiskMark(deadline.id,
        NotificationPolicy.riskSignal(deadline, deadlines, now)));
      desired.signature += `|signals=${JSON.stringify(desired.riskMarks)}`;
      return [desired];
    }
    return [];
  }

  private static riskMarksFromSignature(signature: string): NotificationRiskMark[] {
    const separator = signature.lastIndexOf('|signals=');
    return separator < 0 ? [] : NotificationPolicy.readRiskMarks(signature.substring(separator + 9));
  }

  private static getTodayPlannedTaskIds(deadlines: Deadline[], tasks: DeadlineSubtask[], now: number): string[] {
    const plan: TodayPlan = TodayActionService.buildPlan(
      DeadlineReminderService.getActionDeadlines(deadlines, now),
      tasks,
      now
    );
    const taskIds: string[] = [];
    for (let index: number = 0; index < plan.actions.length; index++) {
      if (plan.actions[index].canComplete && plan.actions[index].taskId.length > 0) {
        taskIds.push(plan.actions[index].taskId);
      }
    }
    return taskIds;
  }

  static buildDesiredReminders(snapshot: DeadlineDataSnapshot, states: DeadlineReminderState[],
    settings: NotificationSettings, runtime: NotificationRuntimeState, now: number): DesiredReminder[] {
    const tasksByDeadline: Map<string, DeadlineSubtask[]> = DeadlineReminderService.groupTasks(snapshot.subtasks);
    const plannedTaskIds: string[] = DeadlineReminderService.getTodayPlannedTaskIds(
      snapshot.deadlines,
      snapshot.subtasks,
      now
    );
    let desired: DesiredReminder[] = DeadlineReminderService.buildBasicReminders(
      snapshot.deadlines,
      tasksByDeadline,
      settings,
      runtime,
      now
    );
    desired = desired.concat(DeadlineReminderService.buildDailySummaries(
      snapshot.deadlines,
      snapshot.subtasks,
      settings,
      runtime,
      plannedTaskIds,
      now
    ));
    desired = desired.concat(DeadlineReminderService.buildRiskReminders(
      snapshot.deadlines, snapshot.subtasks, settings, runtime, states, now));
    desired = desired.filter((item: DesiredReminder) => !item.key.startsWith(`${SMART_PREFIX}risk:`) ||
      !desired.some((summary: DesiredReminder) => summary.key.startsWith(`${SMART_PREFIX}daily:`) &&
        Math.abs(summary.scheduledAt - item.scheduledAt) <= 30 * MINUTE_MILLISECONDS));
    // A quiet-hours advance can fire before the original offset time. Retain
    // its local receipt so ordinary task edits cannot schedule it a second time.
    desired = desired.filter((item: DesiredReminder) => !states.some((state: DeadlineReminderState) => {
      const deadline = snapshot.deadlines.find((value: Deadline) => value.id === item.key);
      return state.deadlineId === item.key && deadline !== undefined &&
        NotificationPolicy.sameCutoff(state, deadline) && NotificationPolicy.keepReceipt(state, deadline, now);
    }));
    desired.sort((first: DesiredReminder, second: DesiredReminder) => first.scheduledAt - second.scheduledAt);
    return desired.slice(0, MAX_MANAGED_REMINDERS);
  }

  private static ownsReminder(info: reminderAgentManager.ReminderInfo): boolean {
    const group = info.reminderReq.groupId ?? '';
    return group.startsWith('dayline:') || ['ddl_deadlines', 'ddl_smart_actions', 'ddl_smart_risk', 'ddl_smart_replan'].includes(group);
  }

  private static matchesSystem(info: reminderAgentManager.ReminderInfo, desired: DesiredReminder): boolean {
    if (info.reminderReq.reminderType !== reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR ||
      info.reminderReq.notificationId !== DeadlineReminderService.getNotificationId(desired.key) ||
      info.reminderReq.title !== DeadlineReminderService.truncate(desired.title, 80) ||
      info.reminderReq.content !== DeadlineReminderService.truncate(desired.content, 160)) { return false; }
    const time = (info.reminderReq as reminderAgentManager.ReminderRequestCalendar).dateTime;
    return new Date(time.year, time.month - 1, time.day, time.hour, time.minute, time.second ?? 0).getTime() === desired.scheduledAt;
  }

  private static async performReconcile(context: common.UIAbilityContext): Promise<void> {
    const values = await Promise.all([
      DeadlineDatabaseService.getDeadlineDataSnapshot(context), DeadlineDatabaseService.getAllReminderStates(context),
      NotificationSettingsService.getSettings(context), NotificationSettingsService.getRuntimeState(context)
    ]);
    const snapshot = values[0] as DeadlineDataSnapshot;
    const states = values[1] as DeadlineReminderState[];
    const settings = values[2] as NotificationSettings;
    const runtime = values[3] as NotificationRuntimeState;
    const now = Date.now();
    if (snapshot.deadlines.some((deadline: Deadline) => DeadlineOverdueRuntime.isOverdue(deadline, now))) {
      // Cold-start reconciliation must read the existing local decision before
      // creating an action summary; opening Index is not a prerequisite.
      await DeadlineOverdueService.load(context);
    }
    // Requiring a system inventory before publishing prevents a crash between
    // publishing and local persistence from creating a second system reminder.
    const system = await DeadlineReminderService.getSystemReminders();
    const enabled = await DeadlineReminderService.isNotificationEnabled();
    let failed = false;
    if (!enabled) {
      for (const state of states) {
        const deadline = snapshot.deadlines.find((item: Deadline) => item.id === state.deadlineId);
        if (NotificationPolicy.keepReceipt(state, deadline, now)) {
          try { await DeadlineReminderService.clearDeliveredReminder(context, state); }
          catch (_) { failed = true; }
        } else if (!await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; }
      }
      for (const info of system) {
        if (DeadlineReminderService.ownsReminder(info) && !await DeadlineReminderService.cancelSystemReminder(info.reminderId)) { failed = true; }
      }
      if (failed) { throw new Error('Notification permission is off; old reminder cancellation needs retry.'); }
      const cancelledMarks = states.filter((state: DeadlineReminderState) => state.scheduledAt > now)
        .map((state: DeadlineReminderState) => DeadlineReminderService.riskMarksFromSignature(state.signature));
      const history = NotificationPolicy.readRiskMarks(runtime.riskMarks).filter((mark: NotificationRiskMark) =>
        !cancelledMarks.some((group: NotificationRiskMark[]) => group.some((item: NotificationRiskMark) => item.id === mark.id)));
      await NotificationSettingsService.saveRiskHistory(context, JSON.stringify(history),
        runtime.lastRiskAt > now ? 0 : runtime.lastRiskAt);
      return;
    }

    let marks = NotificationPolicy.readRiskMarks(runtime.riskMarks);
    for (const state of states) {
      if (state.deadlineId.startsWith(`${SMART_PREFIX}risk:`)) {
        runtime.lastRiskAt = Math.max(runtime.lastRiskAt, state.scheduledAt);
      }
      for (const mark of DeadlineReminderService.riskMarksFromSignature(state.signature)) {
        if (!marks.some((existing: NotificationRiskMark) => existing.id === mark.id)) { marks.push(mark); }
      }
    }
    marks = marks.filter((mark: NotificationRiskMark) => snapshot.deadlines.some((deadline: Deadline) => deadline.id === mark.id));
    for (const mark of marks) {
      const deadline = snapshot.deadlines.find((item: Deadline) => item.id === mark.id) as Deadline;
      const signal = NotificationPolicy.riskSignal(deadline, snapshot.deadlines, now);
      if (signal === 'none' || (signal === 'medium' && mark.signal === 'high')) { mark.signal = signal; }
    }
    runtime.riskMarks = JSON.stringify(marks);
    await NotificationSettingsService.saveRiskHistory(context, runtime.riskMarks, runtime.lastRiskAt);
    const desired = DeadlineReminderService.buildDesiredReminders(snapshot, states, settings, runtime, now);
    const desiredMap = new Map<string, DesiredReminder>();
    desired.forEach((item: DesiredReminder) => desiredMap.set(item.key, item));
    const retainedIds = new Set<number>();
    const stateMap = new Map<string, DeadlineReminderState>();
    for (const state of states) {
      const deadline = snapshot.deadlines.find((item: Deadline) => item.id === state.deadlineId);
      const retainDelivered = NotificationPolicy.keepReceipt(state, deadline, now);
      if (retainDelivered && !state.signature.endsWith('|due_seen')) {
        state.signature += '|due_seen';
        await DeadlineDatabaseService.saveReminderState(context, state);
      }
      if (!desiredMap.has(state.deadlineId) && !retainDelivered) {
        if (!await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; retainedIds.add(state.reminderId); }
      } else { stateMap.set(state.deadlineId, state); retainedIds.add(state.reminderId); }
    }
    for (const info of system) {
      if (!DeadlineReminderService.ownsReminder(info) || retainedIds.has(info.reminderId)) { continue; }
      const adopt = desired.find((item: DesiredReminder) => DeadlineReminderService.matchesSystem(info, item));
      if (adopt !== undefined && !stateMap.has(adopt.key)) {
        const state = new DeadlineReminderState(adopt.key, info.reminderId, adopt.scheduledAt, adopt.signature);
        await DeadlineDatabaseService.saveReminderState(context, state);
        stateMap.set(adopt.key, state); retainedIds.add(info.reminderId);
      } else if (!await DeadlineReminderService.cancelSystemReminder(info.reminderId)) { failed = true; }
    }
    for (const item of desired) {
      const state = stateMap.get(item.key);
      const valid = state !== undefined && system.some((info: reminderAgentManager.ReminderInfo) => info.reminderId === state.reminderId);
      if (state !== undefined && valid && state.signature === item.signature && state.scheduledAt === item.scheduledAt) { continue; }
      if (state !== undefined && !await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; continue; }
      if (item.scheduledAt <= Date.now()) { continue; } // never catch up expired reminders
      try {
        await DeadlineReminderService.publishAndSave(context, item, settings);
        for (const mark of item.riskMarks) {
          const existing = marks.find((value: NotificationRiskMark) => value.id === mark.id);
          if (existing === undefined) { marks.push(mark); } else { existing.signal = mark.signal; }
        }
        if (item.riskMarks.length > 0) {
          runtime.lastRiskAt = item.scheduledAt;
          await NotificationSettingsService.saveRiskHistory(context, JSON.stringify(marks), runtime.lastRiskAt);
        }
      } catch (error) { failed = true; AppLogger.error('DeadlineReminder', 'System reminder reconciliation needs retry', error); }
    }
    const today = DeadlineReminderService.getDateKey(now);
    if (runtime.lastPlanDate !== today || runtime.lastPlanTaskIds.length === 0) {
      await NotificationSettingsService.savePlanSnapshot(context, today,
        DeadlineReminderService.getTodayPlannedTaskIds(snapshot.deadlines, snapshot.subtasks, now));
    }
    if (failed) { throw new Error('One or more system reminders were not updated; local Deadline data is saved.'); }
    AppLogger.info('DeadlineReminder', `Reconciled ${desired.length} local reminders`);
  }

  static async reconcileAll(context: common.UIAbilityContext): Promise<void> {
    if (DeadlineReminderService.reconcilePromise !== undefined) {
      DeadlineReminderService.reconcileAgain = true;
      await DeadlineReminderService.reconcilePromise;
      return;
    }
    DeadlineReminderService.reconcilePromise = DeadlineReminderService.performReconcileLoop(context);
    try {
      await DeadlineReminderService.reconcilePromise;
    } catch (error) {
      AppLogger.error('DeadlineReminder', 'Reminder reconciliation failed', error);
      throw new Error('System reminders could not refresh; local data remains saved.');
    } finally {
      DeadlineReminderService.reconcilePromise = undefined;
    }
  }

  private static async performReconcileLoop(context: common.UIAbilityContext): Promise<void> {
    do {
      DeadlineReminderService.reconcileAgain = false;
      await DeadlineReminderService.performReconcile(context);
    } while (DeadlineReminderService.reconcileAgain);
  }

  static async onUserDataChanged(context: common.UIAbilityContext, deadlineId: string): Promise<void> {
    try {
      await NotificationSettingsService.recordUserActivity(context, deadlineId);
      const previous = await DeadlineDatabaseService.getReminderState(context, deadlineId);
      if (previous !== undefined && (previous.scheduledAt <= Date.now() || previous.signature.endsWith('|due_seen'))) {
        await DeadlineReminderService.clearDeliveredReminder(context, previous);
      }
      await DeadlineReminderService.cancelStatesWithPrefix(context, `${SMART_PREFIX}replan:`);
      await DeadlineReminderService.reconcileAll(context);
    } catch (error) {
      AppLogger.error('DeadlineReminder', `Unable to refresh reminders after ${deadlineId} changed`, error);
    }
  }

  private static async getSystemReminders(): Promise<reminderAgentManager.ReminderInfo[]> {
    try { return await reminderAgentManager.getAllValidReminders(); }
    catch (error) {
      AppLogger.error('DeadlineReminder', 'System reminder inventory unavailable; publishing skipped to avoid duplicates', error);
      throw new Error('System reminders could not be verified.');
    }
  }

  private static async clearDeliveredReminder(context: common.UIAbilityContext, state: DeadlineReminderState): Promise<void> {
    if (!await DeadlineReminderService.cancelSystemReminder(state.reminderId)) {
      throw new Error('The previously displayed reminder could not be cleared.');
    }
    await DeadlineDatabaseService.saveReminderState(context,
      new DeadlineReminderState(state.deadlineId, -1, state.scheduledAt, state.signature));
  }

  private static async cancelStatesWithPrefix(context: common.UIAbilityContext, prefix: string): Promise<void> {
    const states: DeadlineReminderState[] = await DeadlineDatabaseService.getAllReminderStates(context);
    for (let index: number = 0; index < states.length; index++) {
      if (states[index].deadlineId.startsWith(prefix)) {
        await DeadlineReminderService.cancelStoredState(context, states[index]);
      }
    }
  }

  static async cancelForDeadline(context: common.UIAbilityContext, deadlineId: string): Promise<boolean> {
    try {
      const state: DeadlineReminderState | undefined = await DeadlineDatabaseService.getReminderState(
        context,
        deadlineId
      );
      if (state === undefined) {
        return true;
      }
      return await DeadlineReminderService.cancelStoredState(context, state);
    } catch (error) {
      AppLogger.error('DeadlineReminder', `Unable to cancel reminder for ${deadlineId}`, error);
      return false;
    }
  }

  static async applyDeadline(context: common.UIAbilityContext, deadline: Deadline,
    requestPermission: boolean = false): Promise<DeadlineReminderResult> {
    try {
      if (requestPermission && !await DeadlineReminderService.requestNotificationPermission(context)) {
        return new DeadlineReminderResult('permission_disabled',
          LocalizationService.text('reminder_result_permission_disabled'));
      }
      await NotificationSettingsService.recordUserActivity(context, deadline.id);
      const previous = await DeadlineDatabaseService.getReminderState(context, deadline.id);
      if (previous !== undefined && (previous.scheduledAt <= Date.now() || previous.signature.endsWith('|due_seen'))) {
        await DeadlineReminderService.clearDeliveredReminder(context, previous);
      }
      await DeadlineReminderService.cancelStatesWithPrefix(context, `${SMART_PREFIX}replan:`);
      await DeadlineReminderService.reconcileAll(context);
      if (deadline.reminderOffsetMinutes <= 0 || deadline.completed || deadline.deadlineAt <= Date.now()) {
        return new DeadlineReminderResult('not_needed', LocalizationService.text('reminder_result_not_needed'));
      }
      if (!await DeadlineReminderService.isNotificationEnabled()) {
        return new DeadlineReminderResult('permission_disabled',
          LocalizationService.text('reminder_result_permission_disabled'));
      }
      const state: DeadlineReminderState | undefined = await DeadlineDatabaseService.getReminderState(
        context,
        deadline.id
      );
      if (state === undefined) {
        if (DeadlineReminderService.getScheduledAt(deadline) <= Date.now()) {
          return new DeadlineReminderResult('not_needed', LocalizationService.text('reminder_result_not_needed'));
        }
        return new DeadlineReminderResult('queued', LocalizationService.text('reminder_result_queued'));
      }
      if (state.reminderId < 0) {
        return new DeadlineReminderResult('not_needed', LocalizationService.text('reminder_result_not_needed'));
      }
      return new DeadlineReminderResult('scheduled', LocalizationService.text('reminder_result_scheduled'));
    } catch (error) {
      AppLogger.error('DeadlineReminder', `Unable to apply reminder for ${deadline.id}`, error);
      return new DeadlineReminderResult('failed', LocalizationService.text('reminder_result_failed'));
    }
  }
}
