import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { CloudAccountService, CloudAccountSession } from './CloudAccountService';
import { DeadlineDatabaseService } from './DeadlineDatabaseService';
import { DeadlineReminderService } from './DeadlineReminderService';
import { AppLogger } from './AppLogger';
import { LocalizationService } from './LocalizationService';
import { CloudSyncLifecycle } from './CloudSyncLifecycle';
import { ReleaseScope } from './ReleaseScope';

const MIN_SYNC_INTERVAL: number = 5 * 60 * 1000;
// Fail closed until the journal schema and historical cloud import have been verified.
// Do not enable by merely creating the new cloud record type.
const EVENT_PROTOCOL_VALIDATED: boolean = false;

export class CloudSyncResult {
  code: number;
  message: string;

  constructor(code: number, message: string) {
    this.code = code;
    this.message = message;
  }

  isSuccess(): boolean {
    return this.code === relationalStore.ProgressCode.SUCCESS;
  }
}

export class CloudSyncService {
  private static syncInFlight: Promise<CloudSyncResult> | undefined = undefined;
  private static disableInFlight: Promise<void> | undefined = undefined;
  private static readonly ACCOUNT_UNAVAILABLE: number = -2;
  private static readonly ACCOUNT_MISMATCH: number = -3;
  private static readonly STATUS_UNAVAILABLE: number = -4;
  private static readonly STOP_FAILED: number = -5;
  private static readonly DATA_HELD: number = -6;
  private static readonly PROTOCOL_NOT_READY: number = -7;
  private static readonly listeners: Set<() => void> = new Set<() => void>();

  static onDataChanged(listener: () => void): void {
    CloudSyncService.listeners.add(listener);
  }

  static offDataChanged(listener: () => void): void {
    CloudSyncService.listeners.delete(listener);
  }

  static async requestDataSyncPermission(context: common.UIAbilityContext): Promise<boolean> {
    if (!ReleaseScope.CLOUD_SYNC_AVAILABLE) { return false; }
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await manager.requestPermissionsFromUser(
        context,
        ['ohos.permission.DISTRIBUTED_DATASYNC']
      );
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (error) {
      AppLogger.cloudError('CloudSync', 'Failed to request data sync permission', error as Object);
      return false;
    }
  }

  private static getMessage(code: number): string {
    if (code === CloudSyncService.PROTOCOL_NOT_READY) {
      return LocalizationService.text('cloud_protocol_pending');
    }
    if (code === CloudSyncService.DATA_HELD) {
      return LocalizationService.text('cloud_data_held');
    }
    if (code === CloudSyncService.ACCOUNT_UNAVAILABLE) {
      return LocalizationService.text('cloud_account_verify_failed');
    }
    if (code === CloudSyncService.ACCOUNT_MISMATCH) {
      return LocalizationService.text('cloud_account_mismatch');
    }
    if (code === CloudSyncService.STATUS_UNAVAILABLE) {
      return LocalizationService.text('cloud_status_save_failed');
    }
    if (code === CloudSyncService.STOP_FAILED) {
      return LocalizationService.text('cloud_stop_failed');
    }
    if (code === relationalStore.ProgressCode.SUCCESS) {
      return LocalizationService.text('cloud_result_synced');
    }
    if (code === relationalStore.ProgressCode.NETWORK_ERROR) {
      return LocalizationService.text('cloud_result_network');
    }
    if (code === relationalStore.ProgressCode.CLOUD_DISABLED) {
      return LocalizationService.text('cloud_result_enable_in_settings');
    }
    if (code === relationalStore.ProgressCode.RECORD_LIMIT_EXCEEDED) {
      return LocalizationService.text('cloud_result_data_limit');
    }
    if (code === relationalStore.ProgressCode.NO_SPACE_FOR_ASSET) {
      return LocalizationService.text('cloud_result_storage_full');
    }
    if (code === relationalStore.ProgressCode.BLOCKED_BY_NETWORK_STRATEGY) {
      return LocalizationService.text('cloud_result_network_policy');
    }
    return LocalizationService.text('cloud_result_failed');
  }

  private static async performSync(context: common.UIAbilityContext): Promise<CloudSyncResult> {
    const startedAt: number = Date.now();
    let latestCode: number = relationalStore.ProgressCode.UNKNOWN_ERROR;
    let attempted: boolean = false;
    try {
      // Remove any native automatic sync retained by an older app version first.
      await DeadlineDatabaseService.setCloudSyncEnabled(context, false);
      const session: CloudAccountSession = await CloudAccountService.getSession(context);
      if (!session.syncEnabled || session.openId.length === 0) {
        latestCode = CloudSyncService.ACCOUNT_UNAVAILABLE;
      } else {
        let currentOpenId: string = '';
        try {
          currentOpenId = await CloudAccountService.getCurrentOpenId(context);
        } catch (error) {
          latestCode = CloudSyncService.ACCOUNT_UNAVAILABLE;
        }
        if (currentOpenId.length === 0) {
          latestCode = CloudSyncService.ACCOUNT_UNAVAILABLE;
        } else if (currentOpenId !== session.openId ||
          !CloudSyncLifecycle.canUseAccount(session.lastAccountOpenId, currentOpenId)) {
          latestCode = CloudSyncService.ACCOUNT_MISMATCH;
        } else if (!EVENT_PROTOCOL_VALIDATED) {
          latestCode = CloudSyncService.PROTOCOL_NOT_READY;
        } else {
          await DeadlineDatabaseService.setCloudSyncEnabled(context, true);
          attempted = true;
          latestCode = await CloudSyncLifecycle.run((report) => DeadlineDatabaseService.syncCloud(context,
            (details: relationalStore.ProgressDetails) => {
              if (details.schedule !== relationalStore.Progress.SYNC_FINISH) {
                return;
              }
              let failedRecords: number = 0;
              const tables: string[] = details.details === undefined ? [] : Object.keys(details.details);
              for (let index: number = 0; index < tables.length; index++) {
                const table: relationalStore.TableDetails = details.details[tables[index]];
                if (table === undefined || table.upload === undefined || table.download === undefined) {
                  failedRecords = Number.NaN;
                  break;
                }
                failedRecords += table.upload.failed + table.download.failed;
              }
              report({ finished: details.schedule === relationalStore.Progress.SYNC_FINISH,
                code: details.code, failedRecords: failedRecords });
            }), relationalStore.ProgressCode.UNKNOWN_ERROR);
        }
      }
    } catch (error) {
      AppLogger.cloudError('CloudSync', 'Cloud sync failed', error as Object);
      latestCode = relationalStore.ProgressCode.UNKNOWN_ERROR;
    } finally {
      try {
        await DeadlineDatabaseService.setCloudSyncEnabled(context, false);
      } catch (error) {
        AppLogger.cloudError('CloudSync', 'Unable to stop native cloud synchronization', error as Object);
        latestCode = CloudSyncService.STOP_FAILED;
      }
    }
    if (attempted) {
      try {
        await DeadlineDatabaseService.reconcileSyncJournal(context);
        if ((await DeadlineDatabaseService.getSyncProblemIds(context)).length > 0) {
          latestCode = CloudSyncService.DATA_HELD;
        }
      } catch (error) {
        AppLogger.cloudError('CloudSync', 'Cloud data preserved; projection not committed', error as Object);
        latestCode = CloudSyncService.DATA_HELD;
      }
    }
    try {
      await CloudAccountService.recordSyncResult(context, latestCode);
    } catch (error) {
      AppLogger.cloudError('CloudSync', 'Unable to persist synchronization status', error as Object);
      latestCode = CloudSyncService.STATUS_UNAVAILABLE;
    }
    // A failed/partial sync may already have downloaded rows. Reconcile those too.
    if (attempted) {
      await CloudSyncLifecycle.refreshAfterAttempt(() => DeadlineReminderService.reconcileAll(context), () => {
        CloudSyncService.listeners.forEach((listener: () => void) => {
          try {
            listener();
          } catch (error) {
            AppLogger.cloudError('CloudSync', 'Unable to refresh a synchronized page', error as Object);
          }
        });
      }, (error: Object) => AppLogger.cloudError('CloudSync', 'Unable to refresh local reminders after sync', error));
    }
    const duration: number = Date.now() - startedAt;
    const performanceMessage: string = `Cloud sync finished in ${duration} ms with code ${latestCode}`;
    if (duration >= 1000) {
      AppLogger.warn('CloudSync', performanceMessage);
    } else {
      AppLogger.info('CloudSync', performanceMessage);
    }
    return new CloudSyncResult(latestCode, CloudSyncService.getMessage(latestCode));
  }

  static async syncNow(context: common.UIAbilityContext): Promise<CloudSyncResult> {
    if (!ReleaseScope.CLOUD_SYNC_AVAILABLE) {
      return new CloudSyncResult(CloudSyncService.PROTOCOL_NOT_READY,
        LocalizationService.text('cloud_release_unavailable'));
    }
    if (CloudSyncService.disableInFlight !== undefined) {
      return new CloudSyncResult(CloudSyncService.ACCOUNT_UNAVAILABLE,
        CloudSyncService.getMessage(CloudSyncService.ACCOUNT_UNAVAILABLE));
    }
    if (CloudSyncService.syncInFlight !== undefined) {
      return await CloudSyncService.syncInFlight;
    }
    const syncPromise: Promise<CloudSyncResult> = CloudSyncService.performSync(context);
    CloudSyncService.syncInFlight = syncPromise;
    try {
      return await syncPromise;
    } finally {
      if (CloudSyncService.syncInFlight === syncPromise) {
        CloudSyncService.syncInFlight = undefined;
      }
    }
  }

  static async syncIfDue(context: common.UIAbilityContext): Promise<CloudSyncResult | undefined> {
    if (!ReleaseScope.CLOUD_SYNC_AVAILABLE) { return undefined; }
    const session: CloudAccountSession = await CloudAccountService.getSession(context);
    if (!session.syncEnabled || session.openId.length === 0) {
      return undefined;
    }
    if (Date.now() - session.lastSyncAt < MIN_SYNC_INTERVAL) {
      return undefined;
    }
    return await CloudSyncService.syncNow(context);
  }

  static async disable(context: common.UIAbilityContext): Promise<void> {
    if (CloudSyncService.disableInFlight !== undefined) {
      return await CloudSyncService.disableInFlight;
    }
    const operation: Promise<void> = CloudSyncService.performDisable(context);
    CloudSyncService.disableInFlight = operation;
    try {
      await operation;
    } finally {
      CloudSyncService.disableInFlight = undefined;
    }
  }

  private static async performDisable(context: common.UIAbilityContext): Promise<void> {
    const activeSync: Promise<CloudSyncResult> | undefined = CloudSyncService.syncInFlight;
    if (activeSync !== undefined) {
      try {
        await activeSync;
      } catch (error) {
        AppLogger.cloudError('CloudSync', 'The preceding sync did not finish normally', error as Object);
      }
    }
    await CloudSyncLifecycle.stop(() => DeadlineDatabaseService.setCloudSyncEnabled(context, false),
      () => CloudAccountService.disable(context));
  }
}
