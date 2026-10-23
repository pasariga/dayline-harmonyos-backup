import { describe, it, expect } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { CloudSyncService } from '../main/ets/services/CloudSyncService';

export default function releaseScopeTest() {
  describe('releaseScope', () => {
    // No functioning native context: these requests must stop before account,
    // preferences, permission UI, database or network access.
    const context = {} as common.UIAbilityContext;
    it('rejects manual cloud sync without trying to authenticate or save a result', 0, async () => {
      const result = await CloudSyncService.syncNow(context);
      expect(result.isSuccess()).assertFalse();
      expect(result.code).assertEqual(-7);
    });
    it('skips automatic sync without reading a persisted account session', 0, async () => {
      expect(await CloudSyncService.syncIfDue(context)).assertUndefined();
    });
    it('does not request a distributed permission for an unavailable feature', 0, async () => {
      expect(await CloudSyncService.requestDataSyncPermission(context)).assertFalse();
    });
  });
}
