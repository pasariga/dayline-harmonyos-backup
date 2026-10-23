import { Deadline, DeadlineSubtask, DeadlineTaskView } from '../models/Deadline';
import { DeadlineInsight, DeadlineInsightService } from './DeadlineInsightService';
import { DeadlineProgressService } from './DeadlineProgressService';
import { DeadlineScheduleDay, DeadlineScheduleService, ScheduleAgendaDay, ScheduleAgendaItem } from
  './DeadlineScheduleService';
import { LocalizationService } from './LocalizationService';
import { DeadlineOverdueRuntime } from './DeadlineOverdueService';
import { DeadlineTime } from './DeadlineTime';

export class TodayAction {
  deadlineId: string;
  deadlineName: string;
  deadlineAt: number;
  taskId: string;
  title: string;
  context: string;
  reason: string;
  suggestion: string;
  riskLevel: string;
  riskLabel: string;
  kind: string;
  canComplete: boolean;
  priorityScore: number;

  constructor(deadlineId: string, deadlineName: string, deadlineAt: number, taskId: string,
    title: string, context: string, reason: string, suggestion: string, riskLevel: string,
    riskLabel: string, kind: string, canComplete: boolean, priorityScore: number) {
    this.deadlineId = deadlineId;
    this.deadlineName = deadlineName;
    this.deadlineAt = deadlineAt;
    this.taskId = taskId;
    this.title = title;
    this.context = context;
    this.reason = reason;
    this.suggestion = suggestion;
    this.riskLevel = riskLevel;
    this.riskLabel = riskLabel;
    this.kind = kind;
    this.canComplete = canComplete;
    this.priorityScore = priorityScore;
  }
}

export class TodayPlan {
  actions: TodayAction[];
  highRiskDeadlines: Deadline[];
  laterDeadlines: Deadline[];

  constructor(actions: TodayAction[], highRiskDeadlines: Deadline[], laterDeadlines: Deadline[]) {
    this.actions = actions;
    this.highRiskDeadlines = highRiskDeadlines;
    this.laterDeadlines = laterDeadlines;
  }
}

export class TodayActionService {
  private static groupTasksByDeadline(tasks: DeadlineSubtask[]): Map<string, DeadlineSubtask[]> {
    const groupedTasks: Map<string, DeadlineSubtask[]> = new Map<string, DeadlineSubtask[]>();
    for (let index: number = 0; index < tasks.length; index++) {
      const deadlineTasks: DeadlineSubtask[] | undefined = groupedTasks.get(tasks[index].deadlineId);
      if (deadlineTasks === undefined) {
        groupedTasks.set(tasks[index].deadlineId, [tasks[index]]);
      } else {
        deadlineTasks.push(tasks[index]);
      }
    }
    return groupedTasks;
  }

  private static calculatePriority(deadline: Deadline, taskCount: number, now: number,
    deadlines: Deadline[]): number {
    const insight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(deadline, deadlines, now);
    let urgencyScore: number = 0;
    if (deadline.deadlineAt < now) {
      urgencyScore = 220;
    } else if (insight.remainingHoursToDeadline <= 24) {
      urgencyScore = 140;
    } else if (insight.remainingHoursToDeadline <= 72) {
      urgencyScore = 90;
    } else if (insight.remainingHoursToDeadline <= 168) {
      urgencyScore = 45;
    }
    const remainingProgressScore: number = (100 - insight.progress) * 0.35;
    const workloadScore: number = DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence) ?
      Math.min(80, insight.remainingHours * 5) : 0;
    const breakdownScore: number = deadline.progressMode === 'automatic' && taskCount === 0 ? 55 : 0;
    return insight.riskScore + urgencyScore + remainingProgressScore + workloadScore + breakdownScore;
  }

  private static getDeadlineReason(deadline: Deadline, insight: DeadlineInsight, now: number): string {
    if (deadline.deadlineAt < now) {
      return LocalizationService.text('overdue_continue_reason');
    }
    if (insight.riskLevel === 'high' || insight.riskLevel === 'medium') {
      const riskReason: string = insight.riskReason.trim().replace(/[.!?。！？]+$/, '');
      return LocalizationService.text(
        'action_risk_with_remaining',
        riskReason,
        TodayActionService.getRemainingText(deadline.deadlineAt, now)
      );
    }
    if (insight.riskLevel === 'unknown') {
      return insight.riskReason;
    }
    if (insight.remainingHours > 0) {
      return insight.workloadConfidence === 'rough' ?
        LocalizationService.text('action_rough_remaining',
          TodayActionService.getRemainingText(deadline.deadlineAt, now), insight.remainingHours) :
        LocalizationService.text('action_remaining_hours',
          TodayActionService.getRemainingText(deadline.deadlineAt, now), insight.remainingHours);
    }
    return LocalizationService.text('action_current_progress',
      TodayActionService.getRemainingText(deadline.deadlineAt, now), insight.progress);
  }

  private static getRemainingText(deadlineAt: number, now: number): string {
    if (deadlineAt < now) {
      return LocalizationService.text('common_overdue');
    }
    const remainingHours: number = (deadlineAt - now) / 3600000;
    if (remainingHours <= 24) {
      return LocalizationService.text('action_due_hours', Math.max(1, Math.ceil(remainingHours)));
    }
    return LocalizationService.text('action_due_days', Math.max(1, DeadlineTime.daysBetween(now, deadlineAt)));
  }

  private static getTaskPath(taskMap: Map<string, DeadlineSubtask>, task: DeadlineSubtask): string {
    const titles: string[] = [task.title];
    let parentId: string = task.parentId;
    const visitedIds: string[] = [task.id];
    while (parentId.length > 0 && visitedIds.indexOf(parentId) < 0) {
      const parent: DeadlineSubtask | undefined = taskMap.get(parentId);
      if (parent === undefined) {
        break;
      }
      titles.unshift(parent.title);
      visitedIds.push(parent.id);
      parentId = parent.parentId;
    }
    return titles.join(' › ');
  }

  private static getManualSuggestion(deadline: Deadline, insight: DeadlineInsight,
    scheduleDay: DeadlineScheduleDay | undefined): string {
    if (insight.progress >= 100) {
      return LocalizationService.text('action_review_complete');
    }
    if (scheduleDay !== undefined && scheduleDay.dayType === 'work') {
      if (scheduleDay.targetProgress >= 0) {
        return LocalizationService.text('action_schedule_hours_progress',
          DeadlineInsightService.normalizeHours(scheduleDay.estimatedHours),
          scheduleDay.targetProgress);
      }
      return LocalizationService.text('action_schedule_hours',
        DeadlineInsightService.normalizeHours(scheduleDay.estimatedHours));
    }
    return LocalizationService.text('action_focus_then_update');
  }

  private static buildDeadlineActions(deadline: Deadline, tasks: DeadlineSubtask[], now: number,
    deadlines: Deadline[], agendaDay: ScheduleAgendaDay | undefined): TodayAction[] {
    const actions: TodayAction[] = [];
    const insight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(deadline, deadlines, now);
    const priority: number = TodayActionService.calculatePriority(deadline, tasks.length, now, deadlines);
    if (DeadlineOverdueRuntime.state(deadline, now) === 'pending') {
      return [new TodayAction(deadline.id, deadline.name, deadline.deadlineAt, '',
        LocalizationService.text('overdue_review_action', deadline.name), deadline.name,
        DeadlineOverdueRuntime.elapsedText(deadline, now), LocalizationService.text('overdue_choose_hint'),
        'overdue', LocalizationService.text('overdue_pending'), 'overdue-review', false, 0)];
    }
    const reason: string = TodayActionService.getDeadlineReason(deadline, insight, now);
    const agendaItem: ScheduleAgendaItem | undefined = agendaDay?.items.find((item: ScheduleAgendaItem) =>
      item.deadlineId === deadline.id && item.dayType === 'work');
    const todaySchedule: DeadlineScheduleDay | undefined = agendaItem === undefined ? undefined :
      new DeadlineScheduleDay(agendaDay?.dateAt ?? now, agendaDay?.label ?? '',
        agendaItem.estimatedHours, [], [], agendaItem.summary, -1, 'work');

    if (deadline.progressMode !== 'automatic') {
      actions.push(new TodayAction(
        deadline.id, deadline.name, deadline.deadlineAt, '',
        LocalizationService.text('action_advance_deadline', deadline.name), deadline.name,
        reason, TodayActionService.getManualSuggestion(deadline, insight, todaySchedule), insight.riskLevel,
        insight.riskLabel, 'manual', false, priority
      ));
      return actions;
    }

    if (tasks.length === 0) {
      actions.push(new TodayAction(
        deadline.id, deadline.name, deadline.deadlineAt, '',
        LocalizationService.text('action_break_down_deadline', deadline.name), deadline.name,
        LocalizationService.text('action_no_tasks_reason'),
        todaySchedule !== undefined ?
          LocalizationService.text('action_break_down_with_hours',
            DeadlineInsightService.normalizeHours(todaySchedule.estimatedHours)) :
          LocalizationService.text('action_create_tasks_suggestion'), insight.riskLevel,
        insight.riskLabel, 'breakdown', false, priority
      ));
      return actions;
    }

    const views: DeadlineTaskView[] = DeadlineProgressService.flattenTasks(tasks);
    const taskMap: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
    const taskIdsWithChildren: Map<string, boolean> = new Map<string, boolean>();
    for (let taskIndex: number = 0; taskIndex < tasks.length; taskIndex++) {
      taskMap.set(tasks[taskIndex].id, tasks[taskIndex]);
      if (tasks[taskIndex].parentId.length > 0) {
        taskIdsWithChildren.set(tasks[taskIndex].parentId, true);
      }
    }
    const leafViews: DeadlineTaskView[] = views.filter((view: DeadlineTaskView) => {
      return !taskIdsWithChildren.has(view.task.id) && view.progress < 100;
    });
    const scheduledLeafViews: DeadlineTaskView[] = leafViews;
    const recommendationCount: number = Math.min(2, scheduledLeafViews.length);
    for (let index: number = 0; index < recommendationCount; index++) {
      const task: DeadlineSubtask = scheduledLeafViews[index].task;
      actions.push(new TodayAction(
        deadline.id, deadline.name, deadline.deadlineAt, task.id,
        LocalizationService.text('action_complete_task', task.title),
        `${deadline.name} · ${TodayActionService.getTaskPath(taskMap, task)}`, reason,
        todaySchedule !== undefined ?
          LocalizationService.text('action_today_schedule_recalculates',
            DeadlineInsightService.normalizeHours(todaySchedule.estimatedHours)) :
          LocalizationService.count('action_tasks_left', leafViews.length), insight.riskLevel,
        insight.riskLabel, 'task', true, priority - index * 6
      ));
    }

    if (actions.length === 0) {
      actions.push(new TodayAction(
        deadline.id, deadline.name, deadline.deadlineAt, '',
        LocalizationService.text('action_review_deadline', deadline.name), deadline.name,
        LocalizationService.text('action_all_tasks_done_reason'),
        LocalizationService.text('action_mark_deadline_complete'), insight.riskLevel,
        insight.riskLabel, 'review', false, priority
      ));
    }
    return actions;
  }

  private static containsDeadlineId(actions: TodayAction[], deadlineId: string): boolean {
    return actions.some((action: TodayAction) => action.deadlineId === deadlineId);
  }

  static buildPlan(deadlines: Deadline[], tasks: DeadlineSubtask[], now: number = Date.now()): TodayPlan {
    const activeDeadlines: Deadline[] = deadlines.filter((deadline: Deadline) => !deadline.completed &&
      DeadlineOverdueRuntime.state(deadline, now) !== 'stopped');
    const deadlinePriorities: Deadline[] = activeDeadlines.slice();
    const tasksByDeadline: Map<string, DeadlineSubtask[]> = TodayActionService.groupTasksByDeadline(tasks);
    const agenda: ScheduleAgendaDay[] = DeadlineScheduleService.buildAgenda(activeDeadlines, tasks, 1, now);
    deadlinePriorities.sort((first: Deadline, second: Deadline) => {
      const group = (item: Deadline): number => item.deadlineAt >= now ? 0 :
        (DeadlineOverdueRuntime.state(item, now) === 'continue' ? 1 : 2);
      const groupDifference: number = group(first) - group(second);
      if (groupDifference !== 0) { return groupDifference; }
      if (group(first) === 2) { return second.deadlineAt - first.deadlineAt; }
      const firstTasks: DeadlineSubtask[] = tasksByDeadline.get(first.id) ?? [];
      const secondTasks: DeadlineSubtask[] = tasksByDeadline.get(second.id) ?? [];
      const difference: number = TodayActionService.calculatePriority(second, secondTasks.length, now,
        activeDeadlines) - TodayActionService.calculatePriority(first, firstTasks.length, now, activeDeadlines);
      return difference !== 0 ? difference : first.deadlineAt - second.deadlineAt;
    });

    let actionCandidates: TodayAction[] = [];
    let actionCandidateDeadlineCount: number = 0;
    for (let index: number = 0; index < deadlinePriorities.length && actionCandidateDeadlineCount < 12; index++) {
      const deadline: Deadline = deadlinePriorities[index];
      const hasTodayWork: boolean = agenda[0]?.items.some((item: ScheduleAgendaItem) =>
        item.deadlineId === deadline.id && item.dayType === 'work') ?? false;
      const confidence: string = DeadlineInsightService.analyze(deadline, now).workloadConfidence;
      const needsEstimate: boolean = !DeadlineInsightService.hasUsableRemainingEstimate(confidence);
      const isOverdueOrDueToday: boolean = deadline.deadlineAt <
        DeadlineTime.calendarDay(now, 1);
      if (!hasTodayWork && !needsEstimate && !isOverdueOrDueToday) {
        continue;
      }
      actionCandidateDeadlineCount++;
      actionCandidates = actionCandidates.concat(TodayActionService.buildDeadlineActions(
        deadline,
        tasksByDeadline.get(deadline.id) ?? [],
        now,
        activeDeadlines,
        agenda[0]
      ));
    }
    if (!actionCandidates.some((item: TodayAction) => item.deadlineAt >= now)) {
      const nextFuture = deadlinePriorities.find((item: Deadline) => item.deadlineAt >= now);
      if (nextFuture !== undefined) {
        actionCandidates = actionCandidates.concat(TodayActionService.buildDeadlineActions(nextFuture,
          tasksByDeadline.get(nextFuture.id) ?? [], now, activeDeadlines, undefined));
      }
    }
    actionCandidates.sort((first: TodayAction, second: TodayAction) => {
      const group = (item: TodayAction): number => item.deadlineAt >= now ? 0 :
        (item.kind === 'overdue-review' ? 2 : 1);
      const groupDifference: number = group(first) - group(second);
      if (groupDifference !== 0) { return groupDifference; }
      if (group(first) === 2) { return second.deadlineAt - first.deadlineAt; }
      const difference: number = second.priorityScore - first.priorityScore;
      return difference !== 0 ? difference : first.deadlineAt - second.deadlineAt;
    });
    // Late items stay discoverable in the list; at most one undecided reminder
    // enters the action area, after actionable work.
    const pending: TodayAction | undefined = actionCandidates.find((item: TodayAction) => item.kind === 'overdue-review');
    const actions: TodayAction[] = actionCandidates.filter((item: TodayAction) => item.kind !== 'overdue-review').slice(0, 4);
    if (pending !== undefined && actions.length < 4) { actions.push(pending); }

    const highRiskDeadlines: Deadline[] = deadlinePriorities.filter((deadline: Deadline) => {
      const level: string = DeadlineInsightService.analyzePortfolio(deadline, activeDeadlines, now).riskLevel;
      return level === 'high' || level === 'medium';
    }).slice(0, 3);

    const focusedActions: TodayAction[] = actions.slice(0, 3);
    const laterDeadlines: Deadline[] = deadlinePriorities.filter((deadline: Deadline) => {
      const insight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(deadline, activeDeadlines, now);
      return insight.riskLevel === 'low' && insight.remainingHoursToDeadline > 72 &&
        !TodayActionService.containsDeadlineId(focusedActions, deadline.id);
    }).sort((first: Deadline, second: Deadline) => second.deadlineAt - first.deadlineAt).slice(0, 2);

    return new TodayPlan(actions, highRiskDeadlines, laterDeadlines);
  }
}
