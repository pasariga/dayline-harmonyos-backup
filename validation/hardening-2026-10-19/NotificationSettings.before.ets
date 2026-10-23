import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { DeadlineReminderService } from '../services/DeadlineReminderService';
import { NotificationSettings as DDLNotificationSettings, NotificationSettingsService } from
  '../services/NotificationSettingsService';
import { LocalizationService } from '../services/LocalizationService';

@Entry
@Component
struct NotificationSettings {
  @State intensity: string = 'standard';
  @State dailySummaryEnabled: boolean = true;
  @State riskAlertsEnabled: boolean = true;
  @State replanAlertsEnabled: boolean = true;
  @State summaryTimeIndex: number = 1;
  @State quietIndex: number = 0;
  @StorageLink('daylineNotificationEnabled') notificationEnabled: boolean = false;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State loadError: string = '';
  @State showAdvanced: boolean = false;
  @State savedSettingsKey: string = '';
  @State reminderRefreshFailed: boolean = false;

  private readonly summaryTimeLabels: string[] = ['08:00', '08:30', '09:00', '12:00', '18:00'];
  private readonly summaryTimeMinutes: number[] = [8 * 60, 8 * 60 + 30, 9 * 60, 12 * 60, 18 * 60];
  private readonly quietLabels: string[] = ['22:30–08:00', '23:00–08:00', '23:00–07:30'];
  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;
  private saveInFlight: boolean = false;
  private discardDialogVisible: boolean = false;
  private allowLeave: boolean = false;
  private permissionCheckTimer: number = -1;
  private permissionCheckVersion: number = 0;

  onPageShow(): void {
    this.pageVisible = true;
    this.isNavigating = false;
    this.isSaving = this.saveInFlight;
    if (this.saveInFlight) {
      return;
    }
    if (this.hasUnsavedChanges()) {
      this.refreshPermission(++this.loadVersion);
      return;
    }
    this.loadSettings(++this.loadVersion);
  }

  onPageHide(): void {
    this.stopPermissionCheck();
    this.pageVisible = false;
    this.loadVersion++;
  }

  private getContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private getSummaryTimeIndex(hour: number, minute: number): number {
    const minuteOfDay: number = hour * 60 + minute;
    const index: number = this.summaryTimeMinutes.indexOf(minuteOfDay);
    return index >= 0 ? index : 1;
  }

  private getQuietIndex(settings: DDLNotificationSettings): number {
    if (!settings.quietEnabled) {
      return 3;
    }
    if (settings.quietStartMinutes === 23 * 60 && settings.quietEndMinutes === 8 * 60) {
      return 1;
    }
    if (settings.quietStartMinutes === 23 * 60 && settings.quietEndMinutes === 7 * 60 + 30) {
      return 2;
    }
    return 0;
  }

  private applySettings(settings: DDLNotificationSettings): void {
    this.intensity = settings.intensity;
    this.dailySummaryEnabled = settings.dailySummaryEnabled;
    this.riskAlertsEnabled = settings.riskAlertsEnabled;
    this.replanAlertsEnabled = settings.replanAlertsEnabled;
    this.summaryTimeIndex = this.getSummaryTimeIndex(settings.summaryHour, settings.summaryMinute);
    this.quietIndex = this.getQuietIndex(settings);
  }

  private async loadSettings(version: number): Promise<void> {
    this.isLoading = true;
    try {
      const values = await Promise.all([
        NotificationSettingsService.getSettings(this.getContext()),
        DeadlineReminderService.isNotificationPermissionEnabled()
      ]);
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      this.applySettings(values[0] as DDLNotificationSettings);
      this.savedSettingsKey = JSON.stringify(this.buildSettings());
      this.allowLeave = false;
      this.notificationEnabled = values[1] as boolean;
      this.loadError = '';
    } catch (error) {
      console.error(`Failed to load notification settings: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('notification_load_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoading = false;
      }
    }
  }

  private async refreshPermission(version: number): Promise<void> {
    try {
      const enabled: boolean = await DeadlineReminderService.isNotificationPermissionEnabled();
      if (this.pageVisible && version === this.loadVersion) {
        this.notificationEnabled = enabled;
      }
    } catch (error) {
      console.error(`Failed to refresh notification permission: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private hasUnsavedChanges(): boolean {
    return this.savedSettingsKey.length > 0 && this.savedSettingsKey !== JSON.stringify(this.buildSettings());
  }

  private applyPreset(intensity: string): void {
    const current: DDLNotificationSettings = this.buildSettings();
    const preset: DDLNotificationSettings = NotificationSettingsService.createPreset(intensity, current);
    this.applySettings(preset);
    if (intensity === 'custom') {
      this.showAdvanced = true;
    }
  }

  private markCustom(): void {
    if (this.intensity !== 'custom') {
      this.intensity = 'custom';
    }
  }

  private buildSettings(): DDLNotificationSettings {
    const summaryMinuteOfDay: number = this.summaryTimeMinutes[this.summaryTimeIndex];
    let quietEnabled: boolean = true;
    let quietStart: number = 22 * 60 + 30;
    let quietEnd: number = 8 * 60;
    if (this.quietIndex === 1) {
      quietStart = 23 * 60;
    } else if (this.quietIndex === 2) {
      quietStart = 23 * 60;
      quietEnd = 7 * 60 + 30;
    } else if (this.quietIndex === 3) {
      quietEnabled = false;
    }
    return new DDLNotificationSettings(
      this.intensity,
      this.dailySummaryEnabled,
      this.riskAlertsEnabled,
      this.replanAlertsEnabled,
      Math.floor(summaryMinuteOfDay / 60),
      summaryMinuteOfDay % 60,
      quietEnabled,
      quietStart,
      quietEnd
    );
  }

  private async saveSettings(): Promise<void> {
    if (this.isSaving || this.isLoading) {
      return;
    }
    this.isSaving = true;
    this.saveInFlight = true;
    let settingsSaved: boolean = false;
    try {
      const context: common.UIAbilityContext = this.getContext();
      await NotificationSettingsService.saveSettings(context, this.buildSettings());
      settingsSaved = true;
      this.savedSettingsKey = JSON.stringify(this.buildSettings());
      await DeadlineReminderService.reconcileAll(context);
      this.reminderRefreshFailed = false;
      if (this.pageVisible) {
        this.notificationEnabled = await DeadlineReminderService.isNotificationPermissionEnabled();
        this.showMessage(LocalizationService.text('notification_saved') + (this.notificationEnabled ? '' :
          ` ${LocalizationService.text('reminder_result_permission_disabled')}`));
      }
    } catch (error) {
      console.error(`Failed to save notification settings: ${CloudDiagnostic.code(error as Object)}`);
      this.reminderRefreshFailed = settingsSaved;
      if (this.pageVisible) {
        this.showMessage(LocalizationService.text(settingsSaved ? 'notification_refresh_failed' :
          'notification_save_failed'));
      }
    } finally {
      this.saveInFlight = false;
      if (this.pageVisible) {
        this.isSaving = false;
      }
    }
  }

  private async enableSystemNotification(): Promise<void> {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.saveInFlight = true;
    try {
      await NotificationSettingsService.markPermissionGuideHandled(this.getContext());
      // A denied permission prompt may never appear again. This explicit entry
      // always lets the user change the actual system setting without looping.
      await DeadlineReminderService.openNotificationSettings(this.getContext());
      this.notificationEnabled = await DeadlineReminderService.isNotificationPermissionEnabled();
      AppStorage.setOrCreate('daylineNotificationEnabled', this.notificationEnabled);
      // This SDK resolves when the sheet opens and does not reliably emit a
      // page/focus callback when it closes. Check only after this explicit user
      // action, for at most one minute; never keep a global/background poll.
      this.stopPermissionCheck();
      this.checkOpenedPermission(this.permissionCheckVersion, 30);
    } catch (error) {
      console.error(`Failed to enable system notification: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible) {
        this.showMessage(LocalizationService.text(this.notificationEnabled ? 'notification_refresh_failed' :
          'notification_open_system_failed'));
      }
    } finally {
      this.saveInFlight = false;
      if (this.pageVisible) {
        this.isSaving = false;
      }
    }
  }

  private stopPermissionCheck(): void {
    this.permissionCheckVersion++;
    if (this.permissionCheckTimer >= 0) { clearTimeout(this.permissionCheckTimer); }
    this.permissionCheckTimer = -1;
  }

  private checkOpenedPermission(version: number, remaining: number): void {
    if (!this.pageVisible || version !== this.permissionCheckVersion || remaining <= 0) { return; }
    this.permissionCheckTimer = setTimeout(async () => {
      this.permissionCheckTimer = -1;
      const enabled = await DeadlineReminderService.isNotificationPermissionEnabled();
      if (!this.pageVisible || version !== this.permissionCheckVersion) { return; }
      if (enabled !== this.notificationEnabled) {
        this.notificationEnabled = enabled;
        AppStorage.setOrCreate('daylineNotificationEnabled', enabled);
        this.stopPermissionCheck();
        try { await DeadlineReminderService.reconcileAll(this.getContext()); }
        catch (_) {
          this.reminderRefreshFailed = true;
          if (this.pageVisible) { this.showMessage(LocalizationService.text('notification_refresh_failed')); }
        }
      } else { this.checkOpenedPermission(version, remaining - 1); }
    }, 2000);
  }

  private getIntensityDescription(): string {
    if (this.intensity === 'concise') {
      return LocalizationService.text('notification_intensity_concise_desc');
    }
    if (this.intensity === 'active') {
      return LocalizationService.text('notification_intensity_active_desc');
    }
    if (this.intensity === 'custom') {
      return LocalizationService.text('notification_intensity_custom_desc');
    }
    return LocalizationService.text('notification_intensity_standard_desc');
  }

  private getIntensityLabel(value: string): string {
    if (value === 'concise') {
      return LocalizationService.text('notification_intensity_concise');
    }
    if (value === 'active') {
      return LocalizationService.text('notification_intensity_active');
    }
    if (value === 'custom') {
      return LocalizationService.text('notification_intensity_custom');
    }
    return LocalizationService.text('notification_intensity_standard');
  }

  private getQuietLabel(index: number): string {
    return index < this.quietLabels.length ? this.quietLabels[index] :
      LocalizationService.text('notification_quiet_off');
  }

  private navigateBack(): void {
    if (this.isSaving || this.isNavigating) {
      return;
    }
    if (!this.allowLeave && this.hasUnsavedChanges()) {
      if (this.discardDialogVisible) {
        return;
      }
      this.discardDialogVisible = true;
      try {
        this.getUIContext().showAlertDialog({
          title: LocalizationService.text('editor_discard_title'),
          message: LocalizationService.text('editor_discard_body'),
          cancel: () => { this.discardDialogVisible = false; },
          primaryButton: {
            value: LocalizationService.text('common_cancel'),
            action: () => { this.discardDialogVisible = false; }
          },
          secondaryButton: {
            value: LocalizationService.text('editor_discard_action'),
            fontColor: $r('app.color.danger'),
            action: () => {
              this.discardDialogVisible = false;
              this.allowLeave = true;
              this.navigateBack();
            }
          }
        });
      } catch (error) {
        this.discardDialogVisible = false;
        this.showMessage(LocalizationService.text('message_go_back_failed'));
      }
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to leave notification settings: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('message_go_back_failed'));
    }
  }

  onBackPress(): boolean {
    if (this.isSaving) {
      this.showMessage(LocalizationService.text('notification_save_in_progress'));
      return true;
    }
    this.navigateBack();
    return true;
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show notification settings message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  @Builder
  SettingSwitch(title: ResourceStr, value: boolean,
    onChanged: (nextValue: boolean) => void) {
    Row({ space: 14 }) {
      Text(title)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_strong'))
        .maxLines(2)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .enabled(!this.isSaving)
        .onChange((nextValue: boolean) => {
          onChanged(nextValue);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 15, bottom: 15 })
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
            .enabled(!this.isSaving && !this.isNavigating)
            .onClick(() => {
              this.navigateBack();
            })

          Text($r('app.string.notification_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(2)
        }
        .width('100%')

        if (this.isLoading) {
          Text($r('app.string.notification_loading'))
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 80 })
        } else if (this.loadError.length > 0) {
          Column({ space: 12 }) {
            Text(this.loadError)
              .width('100%').fontSize(14).fontColor($r('app.color.danger'))
            Button($r('app.string.common_retry'))
              .type(ButtonType.Normal).height(38)
              .onClick(() => { this.loadSettings(++this.loadVersion); })
          }
          .width('100%').margin({ top: 48 })
        } else {
          Text($r('app.string.notification_delivery_notice'))
            .width('100%').fontSize(13).fontColor($r('app.color.text_secondary'))
            .margin({ top: 18 })
          Column({ space: 10 }) {
            Row({ space: 12 }) {
              Text($r('app.string.notification_permission'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_body'))

              Blank()

              Text(this.notificationEnabled ? $r('app.string.common_enabled') : $r('app.string.common_disabled'))
                .fontSize(13)
                .fontColor(this.notificationEnabled ? $r('app.color.success') : $r('app.color.text_secondary'))

            }
            .width('100%')
            if (!this.notificationEnabled) {
              Text($r('app.string.notification_permission_off_hint'))
                .width('100%').fontSize(13).fontColor($r('app.color.text_secondary'))
              Button($r('app.string.notification_enable'))
                .type(ButtonType.Normal)
                .height(38)
                .fontSize(13)
                .fontColor($r('app.color.text_body'))
                .backgroundColor($r('app.color.surface_muted'))
                .enabled(!this.isSaving)
                .onClick(() => { this.enableSystemNotification(); })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 14, top: 12, bottom: 12 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ top: 18 })

          Column({ space: 12 }) {
            Text($r('app.string.notification_intensity'))
              .width('100%')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))

            Select([
              { value: LocalizationService.text('notification_intensity_concise') },
              { value: LocalizationService.text('notification_intensity_standard') },
              { value: LocalizationService.text('notification_intensity_active') },
              { value: LocalizationService.text('notification_intensity_custom') }
            ])
              .selected(['concise', 'standard', 'active', 'custom'].indexOf(this.intensity))
              .value(this.getIntensityLabel(this.intensity))
              .width('100%')
              .font({ size: 14 })
              .enabled(!this.isSaving)
              .onSelect((index: number) => {
                this.applyPreset(['concise', 'standard', 'active', 'custom'][index]);
              })

            Text(this.getIntensityDescription())
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(20)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ top: 12 })

          Row() {
            Text(this.showAdvanced ? $r('app.string.notification_less_settings') :
              $r('app.string.notification_more_settings'))
              .layoutWeight(1)
              .fontSize(15)
              .fontColor($r('app.color.text_body'))
            Text(this.showAdvanced ? '−' : '+')
              .fontSize(20)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ left: 2, right: 2, top: 18, bottom: 10 })
          .onClick(() => { this.showAdvanced = !this.showAdvanced; })

          if (this.showAdvanced) {
          Column({ space: 0 }) {
            Text($r('app.string.notification_content'))
              .width('100%')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .margin({ bottom: 4 })

            this.SettingSwitch($r('app.string.notification_daily'),
              this.dailySummaryEnabled, (nextValue: boolean) => {
                if (nextValue !== this.dailySummaryEnabled) {
                  this.dailySummaryEnabled = nextValue;
                  this.markCustom();
                }
              })
            Divider().color($r('app.color.divider'))
            this.SettingSwitch($r('app.string.notification_risk'),
              this.riskAlertsEnabled, (nextValue: boolean) => {
                if (nextValue !== this.riskAlertsEnabled) {
                  this.riskAlertsEnabled = nextValue;
                  this.markCustom();
                }
              })
            Divider().color($r('app.color.divider'))
            this.SettingSwitch($r('app.string.notification_replan'),
              this.replanAlertsEnabled, (nextValue: boolean) => {
                if (nextValue !== this.replanAlertsEnabled) {
                  this.replanAlertsEnabled = nextValue;
                  this.markCustom();
                }
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ top: 8 })

          Column({ space: 14 }) {
            Text($r('app.string.notification_time'))
              .width('100%')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))

            Row({ space: 12 }) {
              Text($r('app.string.notification_summary_time'))
                .fontSize(14)
                .fontColor($r('app.color.text_body'))
                .layoutWeight(1)
              Select([
                { value: '08:00' },
                { value: '08:30' },
                { value: '09:00' },
                { value: '12:00' },
                { value: '18:00' }
              ])
                .selected(this.summaryTimeIndex)
                .value(this.summaryTimeLabels[this.summaryTimeIndex])
                .font({ size: 13 })
                .enabled(!this.isSaving)
                .onSelect((index: number) => {
                  this.summaryTimeIndex = index;
                  this.markCustom();
                })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text($r('app.string.notification_quiet'))
                .fontSize(14)
                .fontColor($r('app.color.text_body'))
                .layoutWeight(1)
              Select([
                { value: '22:30–08:00' },
                { value: '23:00–08:00' },
                { value: '23:00–07:30' },
                { value: LocalizationService.text('notification_quiet_off') }
              ])
                .selected(this.quietIndex)
                .value(this.getQuietLabel(this.quietIndex))
                .font({ size: 13 })
                .enabled(!this.isSaving)
                .onSelect((index: number) => {
                  this.quietIndex = index;
                  this.markCustom();
                })
            }
            .width('100%')

            Text($r('app.string.notification_quiet_desc'))
              .width('100%')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(18)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ top: 8 })
          }

          Button(this.isSaving ? $r('app.string.common_saving') : $r('app.string.notification_save'))
            .type(ButtonType.Capsule)
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.brand'))
            .enabled(!this.isSaving && (this.hasUnsavedChanges() || this.reminderRefreshFailed))
            .margin({ top: 20, bottom: 28 })
            .onClick(() => {
              this.saveSettings();
            })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
