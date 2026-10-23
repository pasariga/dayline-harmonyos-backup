import { describe, beforeAll, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, bundleManager } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CloudDiagnostic } from '../../../main/ets/services/CloudDiagnostic';

// Diagnostic only: no session binding, persisted identity, database or cloud
// receiver. SDK response objects, identifiers and errors never enter logs.
export default function accountAccessNativeTest() {
  describe('accountAccess', () => {
    let context: common.UIAbilityContext;
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      context = (await delegator.getCurrentTopAbility()).context;
    });
    it('device capability and installed public signing metadata', 0, async () => {
      hilog.info(0x0D11, 'DDLAccountProbe', 'AUTH_SYSCAP=%{public}s RDB_SYSCAP=%{public}s',
        String(canIUse('SystemCapability.AuthenticationServices.HuaweiID.Auth')),
        String(canIUse('SystemCapability.DistributedDataManager.RelationalStore.Core')));
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO);
      const fingerprint: string = info.signatureInfo?.fingerprint ?? '';
      hilog.info(0x0D11, 'DDLAccountProbe', 'INSTALLED_CERT_SHA256=%{public}s APP_IDENTIFIER_PRESENT=%{public}s',
        /^[0-9a-fA-F]{64}$/.test(fingerprint) ? fingerprint.toUpperCase() : 'unavailable',
        String((info.signatureInfo?.appIdentifier ?? '').length > 0));
      expect(info.name).assertEqual('com.gary.ddl');
    });
    it('direct silent Account Kit request retains failure stage and numeric code only', 0, async () => {
      let stage: string = 'provider';
      let outcome: string = 'unknown';
      try {
        const provider = new authentication.HuaweiIDProvider();
        stage = 'request';
        const request = provider.createLoginWithHuaweiIDRequest();
        request.forceLogin = false;
        stage = 'controller';
        const controller = new authentication.AuthenticationController(context);
        stage = 'execute';
        const response = await new Promise<authentication.AuthenticationResponse>((resolve, reject) => {
          const timer: number = setTimeout(() => reject(new Error('Account probe timeout.')), 10000);
          controller.executeRequest(request).then((value) => { clearTimeout(timer); resolve(value); },
            (error: Object) => { clearTimeout(timer); reject(error); });
        }) as authentication.LoginWithHuaweiIDResponse;
        stage = 'response';
        outcome = typeof response.data?.openID === 'string' && response.data.openID.length > 0 ?
          'identity_present' : 'identity_missing';
        hilog.info(0x0D11, 'DDLAccountProbe', 'SILENT_STAGE=%{public}s OUTCOME=%{public}s', stage, outcome);
      } catch (error) {
        outcome = 'request_failed';
        hilog.info(0x0D11, 'DDLAccountProbe', 'SILENT_STAGE=%{public}s OUTCOME=%{public}s %{public}s',
          stage, outcome, CloudDiagnostic.code(error as Object));
      }
      // Completion of a diagnostic is not a successful login/cloud acceptance.
      expect(['identity_present', 'identity_missing', 'request_failed'].includes(outcome)).assertTrue();
    });
  });
}
