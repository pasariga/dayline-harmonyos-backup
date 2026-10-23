export class DeadlineCloudCompatibility {
  static remainingState(hours: number, state: string, confirmedAt: number): string {
    if (!Number.isFinite(hours) || hours < 0 || !Number.isFinite(confirmedAt) || confirmedAt <= 0) {
      return 'unknown';
    }
    return state === 'initial' || state === 'confirmed' || state === 'unknown' ? state : 'unknown';
  }
}
