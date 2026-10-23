import { DeadlineDatabaseService } from './DeadlineDatabaseService';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { authentication } from '@kit.AccountKit';
import { CloudSyncLifecycle } from './CloudSyncLifecycle';

const STORE_NAME: string = 'ddl_cloud_account';
const KEY_SYNC_ENABLED: string = 'sync_enabled';
const KEY_OPEN_ID: string = 'open_id';
const KEY_LAST_ACCOUNT_OPEN_ID: string = 'last_account_open_id';
const KEY_LAST_SYNC_AT: string = 'last_sync_at';
const KEY_LAST_SYNC_CODE: string = 'last_sync_code';

export class CloudAccountSession {
  syncEnabled: boolean;
  openId: string;
  lastAccountOpenId: string;
  lastSyncAt: number;
  lastSyncCode: number;

  constructor(syncEnabled: boolean = false, openId: string = '', lastAccountOpenId: string = '',
    lastSyncAt: number = 0, lastSyncCode: number = -1) {
    this.syncEnabled = syncEnabled;
    this.openId = openId;
    this.lastAccountOpenId = lastAccountOpenId;
    this.lastSyncAt = lastSyncAt;
    this.lastSyncCode = lastSyncCode;
  }
}

export class CloudAccountService {
  static async getCurrentOpenId(context: common.UIAbilityContext): Promise<string> {
    try {
      const request: authentication.LoginWithHuaweiIDRequest =
        new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      request.forceLogin = false;
      const controller: authentication.AuthenticationController = new authentication.AuthenticationController(context);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const openId: string = response.data?.openID ?? '';
      if (openId.length === 0) {
        throw new Error('The current Huawei account could not be verified.');
      }
      return openId;
    } catch (error) {
      // Never reuse a persisted OpenID when current authentication is unavailable.
      throw new Error('Unable to verify the current Huawei account.');
    }
  }

  private static async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (error) {
      throw new Error('Unable to open cloud account preferences.');
    }
  }

  static async getSession(context: common.UIAbilityContext): Promise<CloudAccountSession> {
    try {
      const store: preferences.Preferences = await CloudAccountService.getStore(context);
      const syncEnabled: preferences.ValueType = await store.get(KEY_SYNC_ENABLED, false);
      const openId: preferences.ValueType = await store.get(KEY_OPEN_ID, '');
      const lastAccountOpenId: preferences.ValueType = await store.get(KEY_LAST_ACCOUNT_OPEN_ID, '');
      const lastSyncAt: preferences.ValueType = await store.get(KEY_LAST_SYNC_AT, 0);
      const lastSyncCode: preferences.ValueType = await store.get(KEY_LAST_SYNC_CODE, -1);
      // Keep ownership with the database as well as Preferences, so a V7 database
      // restored without account preferences cannot be silently adopted by another account.
      let owner: string = await DeadlineDatabaseService.getSyncOwner(context);
      const oldOwner: string = typeof lastAccountOpenId === 'string' && lastAccountOpenId.length > 0 ?
        lastAccountOpenId : typeof openId === 'string' ? openId : '';
      if (owner.length === 0 && oldOwner.length > 0) {
        await DeadlineDatabaseService.bindSyncOwner(context, oldOwner);
        owner = oldOwner;
      }
      return new CloudAccountSession(
        syncEnabled === true,
        typeof openId === 'string' ? openId : '',
        owner,
        typeof lastSyncAt === 'number' ? lastSyncAt : 0,
        typeof lastSyncCode === 'number' ? lastSyncCode : -1
      );
    } catch (error) {
      throw new Error('Unable to read cloud account session.');
    }
  }

  static async enableForAccount(context: common.UIAbilityContext, openId: string): Promise<void> {
    const session: CloudAccountSession = await CloudAccountService.getSession(context);
    if (!CloudSyncLifecycle.canUseAccount(session.lastAccountOpenId || session.openId, openId)) {
      throw new Error('This local database is already associated with another Huawei account.');
    }
    try {
      await DeadlineDatabaseService.bindSyncOwner(context, openId);
      const store: preferences.Preferences = await CloudAccountService.getStore(context);
      await store.put(KEY_SYNC_ENABLED, true);
      await store.put(KEY_OPEN_ID, openId);
      await store.put(KEY_LAST_ACCOUNT_OPEN_ID, openId);
      await store.flush();
    } catch (error) {
      throw new Error('Unable to enable cloud account session.');
    }
  }

  static async disable(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await CloudAccountService.getStore(context);
      await store.put(KEY_SYNC_ENABLED, false);
      await store.put(KEY_OPEN_ID, '');
      await store.flush();
    } catch (error) {
      throw new Error('Unable to disable cloud account session.');
    }
  }

  static async recordSyncResult(context: common.UIAbilityContext, code: number): Promise<void> {
    try {
      const store: preferences.Preferences = await CloudAccountService.getStore(context);
      await store.put(KEY_LAST_SYNC_AT, Date.now());
      await store.put(KEY_LAST_SYNC_CODE, code);
      await store.flush();
    } catch (error) {
      throw new Error('Unable to record cloud sync result.');
    }
  }
}
