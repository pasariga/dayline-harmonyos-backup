import { Deadline, DeadlineSubtask, DeadlineTaskView } from '../models/Deadline';
import { DeadlineInsight, DeadlineInsightService } from './DeadlineInsightService';
import { DeadlineProgressService } from './DeadlineProgressService';
import { AppSettingsRuntime } from './AppSettingsService';
import { LocalizationService } from './LocalizationService';
import { DeadlineTime } from './DeadlineTime';

const MAX_VISIBLE_PLAN_DAYS: number = 30;

export class DeadlineScheduleDay {
  dateAt: number;
  label: string;
  estimatedHours: number;
  taskIds: string[];
  taskTitles: string[];
  summary: string;
  targetProgress: number;
  dayType: string;

  constructor(dateAt: number, label: string, estimatedHours: number, taskIds: string[], taskTitles: string[],
    summary: string, targetProgress: number, dayType: string) {
    this.dateAt = dateAt;
    this.label = label;
    this.estimatedHours = estimatedHours;
    this.taskIds = taskIds;
    this.taskTitles = taskTitles;
    this.summary = summary;
    this.targetProgress = targetProgress;
    this.dayType = dayType;
  }
}

export class DeadlineSchedulePlan {
  deadlineId: string;
  days: DeadlineScheduleDay[];
  totalRemainingHours: number;
  activeWorkDays: number;
  bufferDays: number;
  dailyAverageHours: number;
  bufferMessage: string;
  estimateNote: string;
  isFeasible: boolean;
  isTruncated: boolean;

  constructor(deadlineId: string, days: DeadlineScheduleDay[], totalRemainingHours: number,
    activeWorkDays: number, bufferDays: number, dailyAverageHours: number, bufferMessage: string,
    estimateNote: string, isFeasible: boolean, isTruncated: boolean) {
    this.deadlineId = deadlineId;
    this.days = days;
    this.totalRemainingHours = totalRemainingHours;
    this.activeWorkDays = activeWorkDays;
    this.bufferDays = bufferDays;
    this.dailyAverageHours = dailyAverageHours;
    this.bufferMessage = bufferMessage;
    this.estimateNote = estimateNote;
    this.isFeasible = isFeasible;
    this.isTruncated = isTruncated;
  }
}

export class ScheduleAgendaItem {
  deadlineId: string;
  deadlineName: string;
  summary: string;
  estimatedHours: number;
  dayType: string;
  riskLevel: string;

  constructor(deadlineId: string, deadlineName: string, summary: string, estimatedHours: number,
    dayType: string, riskLevel: string) {
    this.deadlineId = deadlineId;
    this.deadlineName = deadlineName;
    this.summary = summary;
    this.estimatedHours = estimatedHours;
    this.dayType = dayType;
    this.riskLevel = riskLevel;
  }
}

export class ScheduleAgendaDay {
  dateAt: number;
  label: string;
  estimatedHours: number;
  capacityHours: number;
  deferredHours: number;
  items: ScheduleAgendaItem[];

  constructor(dateAt: number, label: string, estimatedHours: number, capacityHours: number,
    deferredHours: number, items: ScheduleAgendaItem[]) {
    this.dateAt = dateAt;
    this.label = label;
    this.estimatedHours = estimatedHours;
    this.capacityHours = capacityHours;
    this.deferredHours = deferredHours;
    this.items = items;
  }
}

export class DeadlineScheduleService {
  private static startOfDay(value: number): number {
    return DeadlineTime.calendarDay(value);
  }

  private static addCalendarDays(dayAt: number, days: number): number {
    return DeadlineTime.calendarDay(dayAt, days);
  }

  private static roundHours(value: number): number {
    return Math.round(Math.max(0, value) * 10) / 10;
  }

  private static getDateLabel(dateAt: number, todayAt: number): string {
    const difference: number = DeadlineTime.daysBetween(todayAt, dateAt);
    if (difference === 0) {
      return LocalizationService.text('schedule_today');
    }
    if (difference === 1) {
      return LocalizationService.text('schedule_tomorrow');
    }
    const date: Date = new Date(dateAt);
    return LocalizationService.formatDate(date, 'short');
  }

  private static getIncompleteLeaves(tasks: DeadlineSubtask[]): DeadlineSubtask[] {
    const views: DeadlineTaskView[] = DeadlineProgressService.flattenTasks(tasks);
    const taskIdsWithChildren: Map<string, boolean> = new Map<string, boolean>();
    for (let index: number = 0; index < tasks.length; index++) {
      if (tasks[index].parentId.length > 0) {
        taskIdsWithChildren.set(tasks[index].parentId, true);
      }
    }
    return views.filter((view: DeadlineTaskView) => {
      return !taskIdsWithChildren.has(view.task.id) && view.progress < 100;
    }).map((view: DeadlineTaskView) => view.task);
  }

  private static containsNumber(values: number[], value: number): boolean {
    return values.indexOf(value) >= 0;
  }

  private static buildActiveDayIndices(workDayCapacity: number, activeWorkDays: number): number[] {
    const indices: number[] = [];
    for (let index: number = 0; index < activeWorkDays; index++) {
      const dayIndex: number = Math.floor(index * workDayCapacity / activeWorkDays);
      if (!DeadlineScheduleService.containsNumber(indices, dayIndex)) {
        indices.push(dayIndex);
      }
    }
    return indices;
  }

  private static getPlanDayCapacity(dateAt: number, now: number, deadlineAt: number): number {
    const date: Date = new Date(dateAt);
    const dayStartAt: number = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const nextDayAt: number = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
    const availableStartAt: number = Math.max(now, dayStartAt);
    const availableEndAt: number = Math.min(deadlineAt, nextDayAt);
    return AppSettingsRuntime.getAvailableHoursBetween(availableStartAt, availableEndAt);
  }

  private static sumPlanCapacity(todayAt: number, dayCount: number, now: number, deadlineAt: number): number {
    let totalHours: number = 0;
    for (let dayIndex: number = 0; dayIndex < dayCount; dayIndex++) {
      totalHours += DeadlineScheduleService.getPlanDayCapacity(
        DeadlineScheduleService.addCalendarDays(todayAt, dayIndex),
        now,
        deadlineAt
      );
    }
    return DeadlineScheduleService.roundHours(totalHours);
  }

  static buildPlan(deadline: Deadline, tasks: DeadlineSubtask[], now: number = Date.now(),
    requestedVisibleDays: number = MAX_VISIBLE_PLAN_DAYS): DeadlineSchedulePlan {
    if (deadline.completed) {
      return new DeadlineSchedulePlan(
        deadline.id, [], 0, 0, 0, 0, LocalizationService.text('schedule_completed_empty'), '', true, false
      );
    }
    if (deadline.deadlineAt < now) {
      return new DeadlineSchedulePlan(deadline.id, [], 0, 0, 0, 0, '',
        LocalizationService.text('overdue_no_forecast'), false, false);
    }

    const todayAt: number = DeadlineScheduleService.startOfDay(now);
    const deadlineDayAt: number = DeadlineScheduleService.startOfDay(deadline.deadlineAt);
    const isOverdue: boolean = deadline.deadlineAt < now;
    const calendarDays: number = isOverdue ? 1 :
      Math.max(1, DeadlineTime.daysBetween(todayAt, deadlineDayAt) + 1);
    const insight: DeadlineInsight = DeadlineInsightService.analyze(deadline, now);
    const incompleteLeaves: DeadlineSubtask[] = DeadlineScheduleService.getIncompleteLeaves(tasks);

    if ((deadline.progressMode === 'automatic' && tasks.length > 0 && incompleteLeaves.length === 0) ||
      (deadline.progressMode === 'manual' && insight.progress >= 100)) {
      const reviewDay: DeadlineScheduleDay = new DeadlineScheduleDay(
        todayAt, LocalizationService.text('schedule_today'), 0, [], [],
        LocalizationService.text('schedule_review_and_complete'), 100, 'work'
      );
      return new DeadlineSchedulePlan(
        deadline.id, [reviewDay], 0, 1, 0, 0, LocalizationService.text('schedule_tasks_done'), '', true, false
      );
    }

    let remainingHours: number = insight.remainingHours;
    let estimateNote: string = insight.workloadConfidence === 'rough' ?
      LocalizationService.text('schedule_rough_workload') : '';
    if (!DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence)) {
      return new DeadlineSchedulePlan(deadline.id, [], 0, 0, 0, 0, '',
        LocalizationService.text(insight.workloadConfidence === 'missing' ? 'schedule_need_workload' :
          'schedule_unmeasured_work'), false, false);
    }
    remainingHours = DeadlineScheduleService.roundHours(remainingHours);

    let bufferDays: number = calendarDays >= 4 ? Math.max(1, Math.min(3, Math.floor(calendarDays * 0.15))) : 0;
    let workDayCapacity: number = Math.max(1, calendarDays - bufferDays);
    let availableWorkHours: number = DeadlineScheduleService.sumPlanCapacity(
      todayAt,
      workDayCapacity,
      now,
      deadline.deadlineAt
    );
    let bufferRejectedForWorkload: boolean = false;
    if (bufferDays > 0 && remainingHours > availableWorkHours) {
      bufferDays = 0;
      workDayCapacity = calendarDays;
      availableWorkHours = DeadlineScheduleService.sumPlanCapacity(
        todayAt,
        workDayCapacity,
        now,
        deadline.deadlineAt
      );
      bufferRejectedForWorkload = true;
    }

    const averageAvailableHours: number = Math.max(0.5, availableWorkHours / workDayCapacity);
    const workloadDays: number = Math.max(1, Math.ceil(remainingHours / averageAvailableHours));
    let activeWorkDays: number = Math.min(workDayCapacity, workloadDays);
    let activeDayIndices: number[] = DeadlineScheduleService.buildActiveDayIndices(
      workDayCapacity,
      activeWorkDays
    );
    let activeAvailableHours: number = 0;
    for (let activeIndex: number = 0; activeIndex < activeDayIndices.length; activeIndex++) {
      activeAvailableHours += DeadlineScheduleService.getPlanDayCapacity(
        DeadlineScheduleService.addCalendarDays(todayAt, activeDayIndices[activeIndex]),
        now,
        deadline.deadlineAt
      );
    }
    while (activeWorkDays < workDayCapacity && activeAvailableHours < remainingHours) {
      activeWorkDays++;
      activeDayIndices = DeadlineScheduleService.buildActiveDayIndices(workDayCapacity, activeWorkDays);
      activeAvailableHours = 0;
      for (let activeIndex: number = 0; activeIndex < activeDayIndices.length; activeIndex++) {
        activeAvailableHours += DeadlineScheduleService.getPlanDayCapacity(
          DeadlineScheduleService.addCalendarDays(todayAt, activeDayIndices[activeIndex]),
          now,
          deadline.deadlineAt
        );
      }
    }
    const dailyAverageHours: number = DeadlineScheduleService.roundHours(remainingHours / activeWorkDays);
    const visibleDays: number = Math.min(
      calendarDays,
      MAX_VISIBLE_PLAN_DAYS,
      Math.max(1, requestedVisibleDays)
    );
    const days: DeadlineScheduleDay[] = [];
    let allocatedHours: number = 0;

    for (let dayIndex: number = 0; dayIndex < visibleDays; dayIndex++) {
      const dateAt: number = DeadlineScheduleService.addCalendarDays(todayAt, dayIndex);
      const label: string = DeadlineScheduleService.getDateLabel(dateAt, todayAt);
      if (dayIndex >= workDayCapacity) {
        days.push(new DeadlineScheduleDay(
          dateAt, label, 0, [], [], LocalizationService.text('schedule_buffer_summary'), -1, 'buffer'
        ));
        continue;
      }
      if (!DeadlineScheduleService.containsNumber(activeDayIndices, dayIndex)) {
        days.push(new DeadlineScheduleDay(
          dateAt, label, 0, [], [], LocalizationService.text('schedule_flex_summary'), -1, 'flex'
        ));
        continue;
      }

      const activeIndex: number = activeDayIndices.indexOf(dayIndex);
      const isLastActiveDay: boolean = activeIndex === activeDayIndices.length - 1;
      const planDayCapacity: number = DeadlineScheduleService.getPlanDayCapacity(
        dateAt,
        now,
        deadline.deadlineAt
      );
      const plannedHours: number = isLastActiveDay ?
        DeadlineScheduleService.roundHours(remainingHours - allocatedHours) :
        DeadlineScheduleService.roundHours(remainingHours * planDayCapacity / Math.max(0.5, activeAvailableHours));
      allocatedHours = DeadlineScheduleService.roundHours(allocatedHours + plannedHours);
      const taskIds: string[] = [];
      const taskTitles: string[] = [];
      let targetProgress: number = -1;
      let summary: string = '';
      if (deadline.progressMode === 'automatic' && tasks.length === 0 && activeIndex === 0) {
        summary = LocalizationService.text('schedule_break_down_start');
      } else if (deadline.progressMode === 'automatic') {
        summary = LocalizationService.text('schedule_advance_deadline', deadline.name);
      } else {
        summary = LocalizationService.text('schedule_advance_deadline', deadline.name);
      }
      days.push(new DeadlineScheduleDay(
        dateAt, label, plannedHours, taskIds, taskTitles, summary, targetProgress, 'work'
      ));
    }

    let bufferMessage: string = '';
    if (isOverdue) {
      bufferMessage = LocalizationService.text('schedule_buffer_overdue');
    } else if (bufferDays > 0) {
      bufferMessage = LocalizationService.text('schedule_buffer_days', bufferDays);
    } else if (bufferRejectedForWorkload) {
      bufferMessage = LocalizationService.text('schedule_no_safe_buffer');
    } else {
      bufferMessage = LocalizationService.text('schedule_no_buffer_near_due');
    }
    const isFeasible: boolean = !isOverdue && remainingHours <= availableWorkHours + 0.01;
    return new DeadlineSchedulePlan(
      deadline.id, days, remainingHours, activeWorkDays, bufferDays, dailyAverageHours,
      bufferMessage, estimateNote, isFeasible, calendarDays > visibleDays
    );
  }

  static buildAgenda(deadlines: Deadline[], tasks: DeadlineSubtask[], horizonDays: number = 3,
    now: number = Date.now()): ScheduleAgendaDay[] {
    const todayAt: number = DeadlineScheduleService.startOfDay(now);
    const agenda: ScheduleAgendaDay[] = [];
    for (let dayIndex: number = 0; dayIndex < horizonDays; dayIndex++) {
      const dateAt: number = DeadlineScheduleService.addCalendarDays(todayAt, dayIndex);
      const nextDayAt: number = DeadlineScheduleService.addCalendarDays(dateAt, 1);
      agenda.push(new ScheduleAgendaDay(
        dateAt,
        DeadlineScheduleService.getDateLabel(dateAt, todayAt),
        0,
        AppSettingsRuntime.getAvailableHoursBetween(Math.max(now, dateAt), nextDayAt),
        0,
        []
      ));
    }
    const active: Deadline[] = deadlines.filter((deadline: Deadline) => !deadline.completed && deadline.deadlineAt >= now);
    active.sort((first: Deadline, second: Deadline) => first.deadlineAt - second.deadlineAt);
    const remainingById: Map<string, number> = new Map<string, number>();
    for (let index: number = 0; index < active.length; index++) {
      const insight: DeadlineInsight = DeadlineInsightService.analyze(active[index], now);
      if (DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence)) {
        remainingById.set(active[index].id, insight.remainingHours);
      }
    }
    for (let dayIndex: number = 0; dayIndex < agenda.length; dayIndex++) {
      const day: ScheduleAgendaDay = agenda[dayIndex];
      const nextDayAt: number = DeadlineScheduleService.addCalendarDays(day.dateAt, 1);
      let usedHours: number = 0;
      if (dayIndex === 0) {
        for (let index: number = 0; index < active.length; index++) {
          const deadline: Deadline = active[index];
          if (!remainingById.has(deadline.id)) {
            day.items.push(new ScheduleAgendaItem(deadline.id, deadline.name,
              LocalizationService.text(DeadlineInsightService.analyze(deadline, now).workloadConfidence ===
                'missing' ? 'schedule_need_workload' : 'schedule_unmeasured_work'),
              0, 'unknown', 'unknown'));
          }
        }
      }
      for (let index: number = 0; index < active.length; index++) {
        const deadline: Deadline = active[index];
        const remaining: number | undefined = remainingById.get(deadline.id);
        if (remaining === undefined || remaining <= 0.01 || deadline.deadlineAt < Math.max(now, day.dateAt)) {
          continue;
        }
        const beforeDueCapacity: number = DeadlineScheduleService.getPlanDayCapacity(
          day.dateAt, now, deadline.deadlineAt
        );
        const hours: number = DeadlineScheduleService.roundHours(Math.min(
          remaining, Math.max(0, beforeDueCapacity - usedHours), Math.max(0, day.capacityHours - usedHours)
        ));
        if (hours <= 0) {
          continue;
        }
        usedHours = DeadlineScheduleService.roundHours(usedHours + hours);
        remainingById.set(deadline.id, DeadlineScheduleService.roundHours(remaining - hours));
        const summary: string = deadline.progressMode === 'automatic' && deadline.taskCount === 0 ?
          LocalizationService.text('schedule_break_down_start') :
          LocalizationService.text('schedule_advance_deadline', deadline.name);
        day.items.push(new ScheduleAgendaItem(deadline.id, deadline.name, summary, hours, 'work',
          DeadlineInsightService.analyzePortfolio(deadline, deadlines, now).riskLevel));
      }
      day.estimatedHours = usedHours;
      for (let index: number = 0; index < active.length; index++) {
        const deadline: Deadline = active[index];
        const remaining: number = remainingById.get(deadline.id) ?? 0;
        if (remaining > 0.01 && deadline.deadlineAt < nextDayAt) {
          day.deferredHours = DeadlineScheduleService.roundHours(day.deferredHours + remaining);
          day.items.push(new ScheduleAgendaItem(deadline.id, deadline.name,
            LocalizationService.text('schedule_unallocated'), remaining, 'deferred', 'high'));
          remainingById.set(deadline.id, 0);
        }
      }
    }
    return agenda;
  }

  static buildPortfolioPlan(deadline: Deadline, deadlines: Deadline[], tasks: DeadlineSubtask[],
    now: number = Date.now()): DeadlineSchedulePlan {
    const ownTasks: DeadlineSubtask[] = tasks.filter((task: DeadlineSubtask) => task.deadlineId === deadline.id);
    const plan: DeadlineSchedulePlan = DeadlineScheduleService.buildPlan(deadline, ownTasks, now);
    if (plan.days.length === 0 || plan.totalRemainingHours <= 0) {
      return plan;
    }
    const agenda: ScheduleAgendaDay[] = DeadlineScheduleService.buildAgenda(deadlines, tasks, plan.days.length, now);
    let allocated: number = 0;
    let activeDays: number = 0;
    for (let index: number = 0; index < plan.days.length; index++) {
      const item: ScheduleAgendaItem | undefined = agenda[index].items.find((candidate: ScheduleAgendaItem) =>
        candidate.deadlineId === deadline.id && candidate.dayType === 'work');
      const hours: number = item?.estimatedHours ?? 0;
      plan.days[index].estimatedHours = hours;
      plan.days[index].dayType = hours > 0 ? 'work' : 'flex';
      plan.days[index].summary = hours > 0 ? (item?.summary ?? '') :
        LocalizationService.text('schedule_flex_summary');
      plan.days[index].taskIds = [];
      plan.days[index].taskTitles = [];
      plan.days[index].targetProgress = -1;
      if (hours > 0) {
        allocated += hours;
        activeDays++;
      }
    }
    plan.activeWorkDays = activeDays;
    plan.dailyAverageHours = activeDays > 0 ? DeadlineScheduleService.roundHours(allocated / activeDays) : 0;
    const portfolioInsight: DeadlineInsight = DeadlineInsightService.analyzePortfolio(deadline, deadlines, now);
    plan.isFeasible = portfolioInsight.riskLevel !== 'high' && portfolioInsight.riskLevel !== 'unknown';
    plan.bufferDays = 0;
    if (deadline.deadlineAt >= now) {
      plan.bufferMessage = LocalizationService.text('schedule_shared_capacity_note', '');
    }
    return plan;
  }
}
