import { AppLogger } from '../services/AppLogger';
import { DeadlineDatabaseService } from '../services/DeadlineDatabaseService';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { CloudAccountService, CloudAccountSession } from '../services/CloudAccountService';
import { CloudSyncResult, CloudSyncService } from '../services/CloudSyncService';
import { LocalizationService } from '../services/LocalizationService';
import { ReleaseScope } from '../services/ReleaseScope';

@Entry
@Component
struct CloudAccount {
  @State syncEnabled: boolean = false;
  @State accountText: string = '';
  @State syncStatusText: string = '';
  @State lastSyncText: string = '';
  @State isProcessing: boolean = false;
  @State sessionLoadFailed: boolean = false;

  private loginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  private pageVisible: boolean = false;
  private sessionVersion: number = 0;
  private callbackRegistered: boolean = false;
  private isNavigating: boolean = false;
  private processingInFlight: boolean = false;
  private loginInFlight: boolean = false;
  private disableDialogVisible: boolean = false;

  aboutToAppear(): void {
    if (ReleaseScope.CLOUD_SYNC_AVAILABLE) { this.registerLoginCallback(); }
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.isNavigating = false;
    this.disableDialogVisible = false;
    this.isProcessing = this.processingInFlight;
    if (ReleaseScope.CLOUD_SYNC_AVAILABLE) { this.loadSession(++this.sessionVersion); }
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.sessionVersion++;
  }

  private getContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private registerLoginCallback(): void {
    if (this.callbackRegistered) {
      return;
    }
    this.callbackRegistered = true;
    this.loginController.onClickLoginWithHuaweiIDButton(
      (error: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
        if (!this.pageVisible) {
          return;
        }
        if (error) {
          this.handleLoginError(error);
          return;
        }
        try {
          if (credential === undefined || typeof credential.openID !== 'string' || credential.openID.length === 0) {
            this.showMessage(LocalizationService.text('cloud_login_retry'));
            return;
          }
          this.handleLoginSuccess(credential.openID);
        } catch (credentialError) {
          AppLogger.cloudError('CloudAccount', 'Failed to read Huawei account credential', credentialError as Object);
          this.showMessage(LocalizationService.text('cloud_login_retry'));
        }
      }
    );
  }

  private async loadSession(version: number = this.sessionVersion): Promise<void> {
    try {
      const session: CloudAccountSession = await CloudAccountService.getSession(this.getContext());
      const heldIds: string[] = await DeadlineDatabaseService.getSyncProblemIds(this.getContext());
      const oldDataPending: boolean = await DeadlineDatabaseService.getLegacyImportPending(this.getContext());
      if (!this.pageVisible || version !== this.sessionVersion) {
        return;
      }
      this.syncEnabled = session.syncEnabled && session.openId.length > 0;
      this.accountText = this.maskOpenId(session.openId);
      this.lastSyncText = this.formatSyncTime(session.lastSyncAt);
      this.sessionLoadFailed = false;
      if (heldIds.length > 0) {
        this.syncStatusText = LocalizationService.text('cloud_data_held');
      } else if (oldDataPending) {
        this.syncStatusText = LocalizationService.text('cloud_legacy_pending');
      } else if (!this.syncEnabled) {
        this.syncStatusText = LocalizationService.text('cloud_status_local_only');
      } else if (session.lastSyncAt === 0) {
        this.syncStatusText = LocalizationService.text('cloud_status_waiting_first_sync');
      } else if (session.lastSyncCode === -7) {
        this.syncStatusText = LocalizationService.text('cloud_protocol_pending');
      } else if (session.lastSyncCode === 0) {
        this.syncStatusText = LocalizationService.text('cloud_status_synced');
      } else {
        this.syncStatusText = LocalizationService.text('cloud_status_sync_incomplete');
      }
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Failed to load cloud account session', error as Object);
      if (this.pageVisible && version === this.sessionVersion) {
        this.syncStatusText = LocalizationService.text('cloud_status_unavailable');
        this.sessionLoadFailed = true;
      }
    }
  }

  private handleLoginError(error: BusinessError): void {
    AppLogger.cloudError('CloudAccount', 'Huawei account login failed', error);
    if (error.code === 1001502012) {
      return;
    }
    if (error.code === 1001500001 || error.code === 1001502002) {
      this.showMessage(LocalizationService.text('cloud_login_unavailable'));
      return;
    }
    if (error.code === 1001502003) {
      this.showMessage(LocalizationService.text('cloud_login_update_required'));
      return;
    }
    if (error.code === 1001502001) {
      this.showMessage(LocalizationService.text('cloud_login_device_account'));
      return;
    }
    if (error.code === 1001502005) {
      this.showMessage(LocalizationService.text('cloud_network_unavailable'));
      return;
    }
    if (error.code === 1001502014) {
      this.showMessage(LocalizationService.text('cloud_authorization_incomplete'));
      return;
    }
    if (error.code === 1005300001) {
      this.showMessage(LocalizationService.text('cloud_privacy_required'));
      return;
    }
    this.showMessage(LocalizationService.text('cloud_login_incomplete'));
  }

  private async handleLoginSuccess(openId: string): Promise<void> {
    if (openId.length === 0 || this.isProcessing || this.loginInFlight) {
      return;
    }
    this.loginInFlight = true;
    try {
      const context: common.UIAbilityContext = this.getContext();
      const session: CloudAccountSession = await CloudAccountService.getSession(context);
      if (!this.pageVisible) {
        return;
      }
      if (session.lastAccountOpenId.length > 0 && session.lastAccountOpenId !== openId) {
        this.showMessage(LocalizationService.text('cloud_account_mismatch'));
        return;
      }
      await this.enableAndSync(openId);
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Failed to prepare cloud account', error as Object);
      this.showMessage(LocalizationService.text('cloud_enable_failed_safe'));
    } finally {
      this.loginInFlight = false;
    }
  }

  private async enableAndSync(openId: string): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.processingInFlight = true;
    this.syncStatusText = LocalizationService.text('cloud_status_merging');
    try {
      const context: common.UIAbilityContext = this.getContext();
      const permissionGranted: boolean = await CloudSyncService.requestDataSyncPermission(context);
      if (!permissionGranted) {
        if (this.pageVisible) {
          this.syncStatusText = LocalizationService.text('cloud_status_permission_local');
        }
        return;
      }
      await CloudAccountService.enableForAccount(context, openId);
      if (this.pageVisible) {
        this.syncEnabled = true;
        this.accountText = this.maskOpenId(openId);
      }
      const result: CloudSyncResult = await CloudSyncService.syncNow(context);
      if (this.pageVisible) {
        await this.loadSession(this.sessionVersion);
        this.syncStatusText = result.message;
      }
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Failed to enable cloud sync', error as Object);
      if (this.pageVisible) {
        this.syncStatusText = LocalizationService.text(this.syncEnabled ? 'cloud_status_sync_incomplete' :
          'cloud_status_local_only');
        this.showMessage(LocalizationService.text(this.syncEnabled ? 'cloud_result_failed' :
          'cloud_enable_failed_safe'));
      }
    } finally {
      this.processingInFlight = false;
      if (this.pageVisible) {
        this.isProcessing = false;
      }
    }
  }

  private async syncNow(): Promise<void> {
    if (!this.syncEnabled || this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.processingInFlight = true;
    this.syncStatusText = LocalizationService.text('cloud_syncing');
    try {
      const context: common.UIAbilityContext = this.getContext();
      const permissionGranted: boolean = await CloudSyncService.requestDataSyncPermission(context);
      if (!permissionGranted) {
        if (this.pageVisible) {
          this.syncStatusText = LocalizationService.text('cloud_status_permission_local');
        }
        return;
      }
      const result: CloudSyncResult = await CloudSyncService.syncNow(context);
      if (this.pageVisible) {
        await this.loadSession(this.sessionVersion);
        this.syncStatusText = result.message;
      }
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Manual cloud sync failed', error as Object);
      if (this.pageVisible) {
        this.syncStatusText = LocalizationService.text('cloud_status_sync_incomplete');
      }
    } finally {
      this.processingInFlight = false;
      if (this.pageVisible) {
        this.isProcessing = false;
      }
    }
  }

  private confirmDisableSync(): void {
    if (this.disableDialogVisible || this.isProcessing) {
      return;
    }
    this.disableDialogVisible = true;
    try {
      this.getUIContext().showAlertDialog({
        title: LocalizationService.text('cloud_sign_out_title'),
        message: LocalizationService.text('cloud_sign_out_body'),
        cancel: () => { this.disableDialogVisible = false; },
        primaryButton: {
          value: LocalizationService.text('common_cancel'),
          action: () => {
            this.disableDialogVisible = false;
          }
        },
        secondaryButton: {
          value: LocalizationService.text('cloud_sign_out'),
          fontColor: $r('app.color.danger'),
          action: () => {
            this.disableDialogVisible = false;
            this.disableSync();
          }
        }
      });
    } catch (error) {
      this.disableDialogVisible = false;
      AppLogger.cloudError('CloudAccount', 'Failed to show cloud sync exit confirmation', error as Object);
      this.showMessage(LocalizationService.text('cloud_sign_out_confirm_failed'));
    }
  }

  private async disableSync(): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.processingInFlight = true;
    try {
      const context: common.UIAbilityContext = this.getContext();
      await CloudSyncService.disable(context);
      if (this.pageVisible) {
        await this.loadSession(this.sessionVersion);
        this.showMessage(LocalizationService.text('cloud_signed_out'));
      }
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Failed to disable cloud sync', error as Object);
      this.showMessage(LocalizationService.text('cloud_sign_out_failed'));
    } finally {
      this.processingInFlight = false;
      if (this.pageVisible) {
        this.isProcessing = false;
      }
    }
  }

  onBackPress(): boolean {
    if (this.isProcessing) {
      this.showMessage(LocalizationService.text('message_processing'));
      return true;
    }
    return false;
  }

  private navigateBack(): void {
    if (this.isProcessing || this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      AppLogger.cloudError('CloudAccount', 'Failed to leave cloud account page', error as Object);
      this.showMessage(LocalizationService.text('message_go_back_failed'));
    }
  }

  private maskOpenId(openId: string): string {
    if (openId.length <= 10) {
      return openId;
    }
    return `${openId.substring(0, 5)}…${openId.substring(openId.length - 4)}`;
  }

  private formatSyncTime(timestamp: number): string {
    if (timestamp <= 0) {
      return LocalizationService.text('cloud_never_synced');
    }
    return LocalizationService.formatDateTime(new Date(timestamp));
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      AppLogger.cloudError('CloudAccount', 'Failed to show message', error as Object);
    }
  }

  @Builder
  InfoRow(label: ResourceStr, value: string) {
    Row({ space: 16 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))

      Blank()

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_strong'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 13, bottom: 13 })
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row({ space: 14 }) {
          Button($r('app.string.common_back'))
            .type(ButtonType.Normal)
            .height(38)
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(18)
            .enabled(!this.isProcessing && !this.isNavigating)
            .onClick(() => {
              this.navigateBack();
            })

          Text($r('app.string.cloud_title'))
            .layoutWeight(1)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!ReleaseScope.CLOUD_SYNC_AVAILABLE) {
          Text($r('app.string.cloud_release_unavailable'))
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .margin({ top: 20, bottom: 28 })
        } else {
        Column({ space: 14 }) {
          Text(this.syncEnabled ? $r('app.string.cloud_enabled') : $r('app.string.cloud_not_signed_in'))
            .width('100%')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))

          Text(this.syncStatusText)
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .maxLines(3)

          Text(this.syncEnabled ? $r('app.string.cloud_offline_footer') : $r('app.string.cloud_optional_footer'))
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)

          if (this.sessionLoadFailed) {
            Button($r('app.string.common_retry'))
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor($r('app.color.brand_accent'))
              .backgroundColor($r('app.color.surface_muted'))
              .onClick(() => { this.loadSession(++this.sessionVersion); })
          } else if (this.syncEnabled) {
            Divider().color($r('app.color.divider'))
            this.InfoRow($r('app.string.cloud_current_account'), this.accountText)
            this.InfoRow($r('app.string.cloud_last_sync'), this.lastSyncText)

            Button(this.isProcessing ? $r('app.string.cloud_syncing') : $r('app.string.cloud_sync_now'))
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.brand'))
              .borderRadius(14)
              .enabled(!this.isProcessing)
              .onClick(() => {
                this.syncNow();
              })

            Button($r('app.string.cloud_sign_out'))
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor($r('app.color.text_body'))
              .backgroundColor(Color.Transparent)
              .enabled(!this.isProcessing)
              .onClick(() => {
                this.confirmDisableSync();
              })
          } else {
            LoginWithHuaweiIDButton({
              params: {
                style: loginComponentManager.Style.BUTTON_BLACK,
                borderRadius: 14,
                loginType: loginComponentManager.LoginType.ID,
                textAndIconStyle: false,
                supportDarkMode: false
              },
              controller: this.loginController
            })
              .width('100%')
              .height(48)
          }
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .margin({ top: 20, bottom: 28 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
