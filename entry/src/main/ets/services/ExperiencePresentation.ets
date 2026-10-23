import { ScheduleAgendaDay, ScheduleAgendaItem } from './DeadlineScheduleService';
import { DeadlineTime } from './DeadlineTime';
import { DeadlineRouteParams } from '../models/Deadline';
import { TodayAction } from './TodayActionService';

export class ExperienceRouteParams extends DeadlineRouteParams {
  workspace: number;
  constructor(id: string, workspace: number = 0) { super(id); this.workspace = workspace; }
}

// Presentation only: scheduled hours are never presented as total demand.
export class TodayContext {
  scheduledHours: number;
  hasUnknownWork: boolean;
  hasSchedule: boolean;
  constructor(hours: number, unknown: boolean, available: boolean) {
    this.scheduledHours = hours;
    this.hasUnknownWork = unknown;
    this.hasSchedule = available;
  }
}

export class CreationReceipt {
  deadlineId: string;
  name: string;
  constructor(id: string, name: string) { this.deadlineId = id; this.name = name; }
}

export class ExperiencePresentation {
  private static receipt: CreationReceipt | undefined = undefined;

  static actionKey(action: TodayAction): string {
    return JSON.stringify([action.deadlineId, action.taskId, action.deadlineName, action.deadlineAt,
      action.title, action.riskLevel, action.riskLabel, action.kind, action.canComplete]);
  }

  static todayContext(agenda: ScheduleAgendaDay[], now: number): TodayContext {
    const day: ScheduleAgendaDay | undefined = agenda.find((item: ScheduleAgendaDay) =>
      DeadlineTime.dateKey(item.dateAt) === DeadlineTime.dateKey(now));
    if (day === undefined) { return new TodayContext(0, false, false); }
    return new TodayContext(Number.isFinite(day.estimatedHours) ? Math.max(0, day.estimatedHours) : 0,
      day.items.some((item: ScheduleAgendaItem) => item.dayType === 'unknown'), true);
  }

  // A transient UI receipt, not a persisted activity or business state.
  static recordCreated(id: string, name: string): void {
    ExperiencePresentation.receipt = new CreationReceipt(id, name);
  }
  static consumeCreated(): CreationReceipt | undefined {
    const result: CreationReceipt | undefined = ExperiencePresentation.receipt;
    ExperiencePresentation.receipt = undefined;
    return result;
  }
}
