// A successful request submission is not a successful synchronization.
// Kept independent of native APIs so delayed/failed progress can be tested.
export interface CloudSyncProgress {
  finished: boolean;
  code: number;
  failedRecords: number;
}

export class CloudSyncLifecycle {
  static run(start: (report: (progress: CloudSyncProgress) => void) => Promise<void>,
    unknownCode: number, timeoutMs: number = 30000): Promise<number> {
    return new Promise<number>((resolve) => {
      let settled: boolean = false;
      let submitted: boolean = false;
      let terminalCode: number | undefined = undefined;
      const finish = (code: number): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(code);
      };
      const timer: number = setTimeout(() => finish(unknownCode), timeoutMs);
      const report = (progress: CloudSyncProgress): void => {
        if (settled || terminalCode !== undefined || !progress.finished) {
          return;
        }
        terminalCode = !Number.isFinite(progress.code) || !Number.isFinite(progress.failedRecords) ||
          progress.failedRecords < 0 || (progress.code === 0 && progress.failedRecords > 0) ?
          unknownCode : progress.code;
        if (submitted) {
          finish(terminalCode);
        }
      };
      try {
        start(report).then(() => {
          submitted = true;
          if (terminalCode !== undefined) {
            finish(terminalCode);
          }
        }).catch(() => finish(unknownCode));
      } catch (error) {
        finish(unknownCode);
      }
    });
  }

  static canUseAccount(owner: string, candidate: string): boolean {
    return candidate.length > 0 && (owner.length === 0 || owner === candidate);
  }

  static async refreshAfterAttempt(reconcile: () => Promise<void>, notify: () => void,
    onFailure: (error: Object) => void): Promise<void> {
    // Downloaded data remains committed even if local reminder refresh fails.
    try {
      await reconcile();
    } catch (error) {
      onFailure(error as Object);
    } finally {
      notify();
    }
  }

  static async stop(disableStore: () => Promise<void>, disableSession: () => Promise<void>): Promise<void> {
    // Do not announce sign-out or clear the session if the native store is still enabled.
    await disableStore();
    await disableSession();
  }
}
