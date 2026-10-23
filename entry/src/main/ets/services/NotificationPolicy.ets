import { Deadline, DeadlineSubtask, DeadlineReminderState } from '../models/Deadline';
import { DeadlineInsightService } from './DeadlineInsightService';
import { NotificationRuntimeState, NotificationSettings } from './NotificationSettingsService';
import { DeadlineTime } from './DeadlineTime';

// Local notification policy only. No business projection or cloud fields.
export class NotificationRiskMark {
  id: string;
  signal: string;
  constructor(id: string, signal: string) { this.id = id; this.signal = signal; }
}

export class NotificationPolicy {
  static keepReceipt(state: DeadlineReminderState, deadline: Deadline | undefined, now: number): boolean {
    return (state.scheduledAt <= now || state.signature.endsWith('|due_seen') || state.reminderId < 0) &&
      deadline !== undefined && !deadline.completed &&
      deadline.reminderOffsetMinutes > 0 && deadline.deadlineAt > now &&
      (DeadlineTime.reminderAt(deadline.deadlineAt, deadline.reminderOffsetMinutes) <= now ||
        NotificationPolicy.sameCutoff(state, deadline));
  }

  static sameCutoff(state: DeadlineReminderState, deadline: Deadline): boolean {
    const identity = `|cutoff=${deadline.deadlineAt}:${deadline.reminderOffsetMinutes}`;
    return state.signature.endsWith(identity) || state.signature.endsWith(identity + '|due_seen');
  }

  static calendarDay(value: number, offset: number): number {
    return DeadlineTime.calendarDay(value, offset);
  }

  static inQuiet(value: number, settings: NotificationSettings): boolean {
    if (!settings.quietEnabled || settings.quietStartMinutes === settings.quietEndMinutes) { return false; }
    const date = new Date(value);
    const minute = date.getHours() * 60 + date.getMinutes();
    return settings.quietStartMinutes < settings.quietEndMinutes ?
      minute >= settings.quietStartMinutes && minute < settings.quietEndMinutes :
      minute >= settings.quietStartMinutes || minute < settings.quietEndMinutes;
  }

  static afterQuiet(value: number, settings: NotificationSettings): number {
    if (!NotificationPolicy.inQuiet(value, settings)) { return value; }
    const date = new Date(value);
    const offset = settings.quietStartMinutes > settings.quietEndMinutes &&
      date.getHours() * 60 + date.getMinutes() >= settings.quietStartMinutes ? 1 : 0;
    let end = DeadlineTime.atMinute(value, settings.quietEndMinutes, offset);
    // During a repeated hour the first occurrence may already be past.
    if (end < value && DeadlineTime.isAmbiguous(end)) {
      end += (new Date(DeadlineTime.atMinute(end, settings.quietEndMinutes, 1)).getTimezoneOffset() -
        new Date(end).getTimezoneOffset()) * 60000;
    }
    return Math.max(value, end);
  }

  static basicTime(value: number, due: number, settings: NotificationSettings, now: number): number {
    if (!NotificationPolicy.inQuiet(value, settings)) { return value; }
    const date = new Date(value);
    const offset = settings.quietStartMinutes > settings.quietEndMinutes &&
      date.getHours() * 60 + date.getMinutes() < settings.quietEndMinutes ? -1 : 0;
    const before = DeadlineTime.atMinute(value, settings.quietStartMinutes, offset) - 60000;
    if (before > now && before < due) { return before; }
    const after = NotificationPolicy.afterQuiet(value, settings);
    // Do not lose a time-sensitive cutoff if no quiet-free window remains.
    return after > now && after < due ? after : value;
  }

  static finishedToday(runtime: NotificationRuntimeState, dateKey: string,
    deadlines: Deadline[], tasks: DeadlineSubtask[]): boolean {
    return runtime.lastPlanDate === dateKey && runtime.lastPlanTaskIds.length > 0 &&
      runtime.lastPlanTaskIds.every((id: string) => {
        const task = tasks.find((item: DeadlineSubtask) => item.id === id);
        const deadline = task === undefined ? undefined : deadlines.find((item: Deadline) => item.id === task.deadlineId);
        return task === undefined || task.completed || deadline === undefined || deadline.completed;
      });
  }

  static riskSignal(deadline: Deadline, deadlines: Deadline[], now: number): string {
    if (deadline.completed || deadline.deadlineAt <= now) { return 'none'; }
    const insight = DeadlineInsightService.analyzePortfolio(deadline, deadlines, now);
    if (insight.riskLevel === 'high' || insight.riskLevel === 'medium') { return insight.riskLevel; }
    return deadline.remainingHours > 0 && !DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence) ?
      'confirm' : 'none';
  }

  static worsened(signal: string, previous: string): boolean {
    if (signal === 'none' || signal === previous) { return false; }
    if (signal === 'medium' && previous === 'high') { return false; }
    return true;
  }

  static readRiskMarks(value: string): NotificationRiskMark[] {
    try {
      const parsed: NotificationRiskMark[] = JSON.parse(value) as NotificationRiskMark[];
      if (!Array.isArray(parsed)) { return []; }
      return parsed.filter((mark: NotificationRiskMark) => mark !== null && typeof mark.id === 'string' &&
        ['none', 'medium', 'high', 'confirm'].includes(mark.signal));
    } catch (_) { return []; }
  }
}
