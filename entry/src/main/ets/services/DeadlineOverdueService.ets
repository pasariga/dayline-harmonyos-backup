import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Deadline } from '../models/Deadline';
import { LocalizationService } from './LocalizationService';

export interface OverdueDecision {
  id: string;
  deadlineAt: number;
  mode: string;
}

// Device-local intent only. No business-field encoding, protocol changes or
// cloud exchange. A changed due date invalidates the decision naturally.
export class DeadlineOverdueRuntime {
  private static decisions: OverdueDecision[] = [];

  static restore(value: string): void {
    const parsed: OverdueDecision[] = JSON.parse(value) as OverdueDecision[];
    if (!Array.isArray(parsed) || parsed.some((item: OverdueDecision) => !item ||
      typeof item.id !== 'string' || !Number.isFinite(item.deadlineAt) ||
      (item.mode !== 'continue' && item.mode !== 'stopped'))) {
      throw new Error('Overdue decisions unavailable.');
    }
    DeadlineOverdueRuntime.decisions = parsed.map((item: OverdueDecision): OverdueDecision => {
      const copy: OverdueDecision = { id: item.id, deadlineAt: item.deadlineAt, mode: item.mode };
      return copy;
    });
  }

  static serialize(): string { return JSON.stringify(DeadlineOverdueRuntime.decisions); }

  static isOverdue(deadline: Deadline, now: number = Date.now()): boolean {
    return !deadline.completed && deadline.deadlineAt < now;
  }

  static state(deadline: Deadline, now: number = Date.now()): string {
    if (!DeadlineOverdueRuntime.isOverdue(deadline, now)) { return 'normal'; }
    return DeadlineOverdueRuntime.decisions.find((item: OverdueDecision) =>
      item.id === deadline.id && item.deadlineAt === deadline.deadlineAt)?.mode ?? 'pending';
  }

  static next(deadline: Deadline, mode: string): string {
    if (!['pending', 'continue', 'stopped'].includes(mode)) { throw new Error('Invalid overdue choice.'); }
    const next: OverdueDecision[] = DeadlineOverdueRuntime.decisions.filter((item: OverdueDecision) =>
      item.id !== deadline.id);
    if (mode !== 'pending') { next.push({ id: deadline.id, deadlineAt: deadline.deadlineAt, mode: mode }); }
    return JSON.stringify(next);
  }

  static statusText(deadline: Deadline, now: number = Date.now()): string {
    return LocalizationService.text('overdue_' + DeadlineOverdueRuntime.state(deadline, now));
  }

  static elapsedText(deadline: Deadline, now: number = Date.now()): string {
    const elapsed: number = Math.max(0, now - deadline.deadlineAt);
    if (elapsed < 3600000) { return LocalizationService.text('overdue_less_hour'); }
    if (elapsed < 86400000) { return LocalizationService.count('overdue_hours', Math.floor(elapsed / 3600000)); }
    return LocalizationService.count('overdue_days', Math.floor(elapsed / 86400000));
  }
}

export class DeadlineOverdueService {
  private static queue: Promise<void> = Promise.resolve();
  private static enqueue(operation: () => Promise<void>): Promise<void> {
    const result = DeadlineOverdueService.queue.then(operation);
    DeadlineOverdueService.queue = result.catch(() => {});
    return result;
  }

  static load(context: common.UIAbilityContext): Promise<void> {
    return DeadlineOverdueService.enqueue(async () => {
      const store = await preferences.getPreferences(context, { name: 'dayline_overdue_choices' });
      const value = await store.get('choices', '[]');
      if (typeof value !== 'string') { throw new Error('Overdue decisions unavailable.'); }
      DeadlineOverdueRuntime.restore(value);
    });
  }

  static choose(context: common.UIAbilityContext, deadline: Deadline, mode: string): Promise<void> {
    return DeadlineOverdueService.enqueue(async () => {
      const store = await preferences.getPreferences(context, { name: 'dayline_overdue_choices' });
      const previous: string = DeadlineOverdueRuntime.serialize();
      const next: string = DeadlineOverdueRuntime.next(deadline, mode);
      try {
        await store.put('choices', next);
        await store.flush();
      } catch (error) {
        // A failed flush must not look like a saved choice on re-entry.
        try { await store.put('choices', previous); await store.flush(); } catch (restoreError) {}
        throw new Error('Overdue choice not saved.');
      }
      DeadlineOverdueRuntime.restore(next);
    });
  }
}
