// Epoch instants stay fixed. Calendar operations use the device's local date.
// UTC is only used to number calendar labels, never to measure local day lengths.
export class DeadlineTime {
  private static listeners: Array<() => void> = [];
  static onClockChanged(listener: () => void): void {
    if (!DeadlineTime.listeners.includes(listener)) { DeadlineTime.listeners.push(listener); }
  }
  static offClockChanged(listener: () => void): void {
    DeadlineTime.listeners = DeadlineTime.listeners.filter((value: () => void) => value !== listener);
  }
  static clockChanged(): void { DeadlineTime.listeners.slice().forEach((listener: () => void) => listener()); }
  static dayOrdinal(at: number): number {
    const d = new Date(at);
    return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000;
  }

  static daysBetween(first: number, second: number): number {
    return DeadlineTime.dayOrdinal(second) - DeadlineTime.dayOrdinal(first);
  }

  static calendarDay(at: number, offset: number = 0): number {
    const d = new Date(at);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset).getTime();
  }

  static dateKey(at: number): string {
    const d = new Date(at);
    return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')}`;
  }

  static timeKey(at: number): string {
    const d = new Date(at);
    return `${`${d.getHours()}`.padStart(2, '0')}:${`${d.getMinutes()}`.padStart(2, '0')}`;
  }

  static atMinute(at: number, minute: number, dayOffset: number = 0): number {
    const d = new Date(at);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + dayOffset,
      Math.floor(minute / 60), minute % 60).getTime();
  }

  static reminderAt(due: number, offsetMinutes: number): number {
    if (offsetMinutes === 1440 || offsetMinutes === 4320) {
      const d = new Date(due);
      return new Date(d.getFullYear(), d.getMonth(), d.getDate() - offsetMinutes / 1440,
        d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds()).getTime();
    }
    return due - offsetMinutes * 60000;
  }

  static fromLocal(date: string, time: string): number {
    const dp = date.split('-').map((v: string) => Number(v));
    const tp = time.split(':').map((v: string) => Number(v));
    if (dp.length !== 3 || tp.length !== 2) { return NaN; }
    const at = new Date(dp[0], dp[1] - 1, dp[2], tp[0], tp[1]).getTime();
    // Do not silently normalize a nonexistent spring-transition clock time.
    return DeadlineTime.dateKey(at) === date && DeadlineTime.timeKey(at) === time ? at : NaN;
  }

  static isAmbiguous(at: number): boolean {
    const nextDay = DeadlineTime.atMinute(at, new Date(at).getHours() * 60 + new Date(at).getMinutes(), 1);
    const foldMinutes = new Date(nextDay).getTimezoneOffset() - new Date(at).getTimezoneOffset();
    if (foldMinutes <= 0) { return false; }
    const second = at + foldMinutes * 60000;
    return DeadlineTime.dateKey(at) === DeadlineTime.dateKey(second) &&
      DeadlineTime.timeKey(at) === DeadlineTime.timeKey(second);
  }

  static calendarCanRepresent(at: number): boolean {
    const d = new Date(at);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes(),
      d.getSeconds(), d.getMilliseconds()).getTime() === at;
  }

  static inputError(date: string, time: string, editing: boolean, now: number): string {
    const at = DeadlineTime.fromLocal(date, time);
    if (!Number.isFinite(at)) { return 'validation_time_missing'; }
    if (DeadlineTime.isAmbiguous(at)) { return 'validation_time_ambiguous'; }
    return !editing && at <= now ? 'validation_time_past' : '';
  }

  static refreshDelay(now: number, due: number[]): number {
    let delay = Math.min(60000, DeadlineTime.calendarDay(now, 1) - now + 1);
    due.forEach((at: number) => { if (at >= now) { delay = Math.min(delay, at - now + 1); } });
    return Math.max(100, delay);
  }
}
