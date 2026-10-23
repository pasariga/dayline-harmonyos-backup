import { describe, it, expect } from '@ohos/hypium';
import { CloudSyncLifecycle, CloudSyncProgress } from '../main/ets/services/CloudSyncLifecycle';
import { DeadlineCloudCompatibility } from '../main/ets/services/DeadlineCloudCompatibility';

export default function cloudReliabilityTest() {
  describe('cloudReliability', () => {
    it('request acceptance alone is not sync success', 0, async () => {
      expect(await CloudSyncLifecycle.run(async () => {}, -1, 10)).assertEqual(-1);
    });
    it('waits for delayed terminal success', 0, async () => {
      let delivered: boolean = false;
      const code: number = await CloudSyncLifecycle.run(async (report) => {
        report({ finished: false, code: 0, failedRecords: 0 });
        setTimeout(() => {
          delivered = true;
          report({ finished: true, code: 0, failedRecords: 0 });
        }, 5);
      }, -1, 1000);
      expect(delivered).assertTrue();
      expect(code).assertEqual(0);
    });
    it('does not replace terminal failure with a later success', 0, async () => {
      expect(await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 7, failedRecords: 1 });
        report({ finished: true, code: 0, failedRecords: 0 });
      }, -1)).assertEqual(7);
    });
    it('does not call partial upload download a success', 0, async () => {
      expect(await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 0, failedRecords: 2 });
      }, -1)).assertEqual(-1);
    });
    it('request rejection wins over premature progress success', 0, async () => {
      expect(await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 0, failedRecords: 0 });
        throw new Error('Network request failed');
      }, -1)).assertEqual(-1);
    });
    it('ignores late completion after a timeout', 0, async () => {
      let lateReport: (progress: CloudSyncProgress) => void = () => {};
      const code: number = await CloudSyncLifecycle.run(async (report) => { lateReport = report; }, -1, 10);
      lateReport({ finished: true, code: 0, failedRecords: 0 });
      expect(code).assertEqual(-1);
    });
    it('accepts a completed empty-cloud attempt', 0, async () => {
      expect(await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 0, failedRecords: 0 });
      }, -1)).assertEqual(0);
    });
    it('allows first account and same owner but rejects another account', 0, () => {
      expect(CloudSyncLifecycle.canUseAccount('', 'A')).assertTrue();
      expect(CloudSyncLifecycle.canUseAccount('A', 'A')).assertTrue();
      expect(CloudSyncLifecycle.canUseAccount('A', 'B')).assertFalse();
      expect(CloudSyncLifecycle.canUseAccount('A', '')).assertFalse();
    });
    it('native stop failure keeps the session', 0, async () => {
      let sessionCleared: boolean = false;
      let failed: boolean = false;
      try {
        await CloudSyncLifecycle.stop(async () => { throw new Error('Native stop failed'); },
          async () => { sessionCleared = true; });
      } catch (error) { failed = true; }
      expect(failed).assertTrue();
      expect(sessionCleared).assertFalse();
    });
    it('clears session only after native stop and reports preference failure', 0, async () => {
      let stopped: boolean = false;
      let failed: boolean = false;
      try {
        await CloudSyncLifecycle.stop(async () => { stopped = true; }, async () => {
          expect(stopped).assertTrue();
          throw new Error('Preference flush failed');
        });
      } catch (error) { failed = true; }
      expect(failed).assertTrue();
      expect(stopped).assertTrue();
    });
    it('preserves V6 estimate states and degrades old or malformed records', 0, () => {
      expect(DeadlineCloudCompatibility.remainingState(6, 'confirmed', 100)).assertEqual('confirmed');
      expect(DeadlineCloudCompatibility.remainingState(10, 'initial', 100)).assertEqual('initial');
      expect(DeadlineCloudCompatibility.remainingState(9, 'unknown', 100)).assertEqual('unknown');
      expect(DeadlineCloudCompatibility.remainingState(0, 'unknown', 0)).assertEqual('unknown');
      expect(DeadlineCloudCompatibility.remainingState(6, 'confirmed', 0)).assertEqual('unknown');
      expect(DeadlineCloudCompatibility.remainingState(-1, 'confirmed', 100)).assertEqual('unknown');
      expect(DeadlineCloudCompatibility.remainingState(9, 'invalid', 100)).assertEqual('unknown');
    });
    it('can retry successfully after a failed request', 0, async () => {
      expect(await CloudSyncLifecycle.run(async () => { throw new Error('Offline'); }, -1)).assertEqual(-1);
      expect(await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 0, failedRecords: 0 });
      }, -1)).assertEqual(0);
    });
    it('refresh failure still notifies pages and preserves sync result', 0, async () => {
      const code: number = await CloudSyncLifecycle.run(async (report) => {
        report({ finished: true, code: 0, failedRecords: 0 });
      }, -1);
      let notified: boolean = false;
      let failureRecorded: boolean = false;
      await CloudSyncLifecycle.refreshAfterAttempt(async () => { throw new Error('Reminder read failed'); },
        () => { notified = true; }, () => { failureRecorded = true; });
      expect(code).assertEqual(0);
      expect(failureRecorded).assertTrue();
      expect(notified).assertTrue();
    });
    it('successful refresh finishes before pages are notified', 0, async () => {
      let reconciled: boolean = false;
      let notified: boolean = false;
      let failed: boolean = false;
      await CloudSyncLifecycle.refreshAfterAttempt(async () => { reconciled = true; }, () => {
        expect(reconciled).assertTrue();
        notified = true;
      }, () => { failed = true; });
      expect(notified).assertTrue();
      expect(failed).assertFalse();
    });
  });
}
