import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { AppSettings, AppSettingsService } from '../services/AppSettingsService';
import { CloudAccountService, CloudAccountSession } from '../services/CloudAccountService';
import { DeadlineReminderService } from '../services/DeadlineReminderService';
import { NotificationSettings as DaylineNotificationSettings, NotificationSettingsService } from
  '../services/NotificationSettingsService';
import { LocalizationService } from '../services/LocalizationService';
import { ReleaseScope } from '../services/ReleaseScope';

@Entry
@Component
struct Settings {
  @State accountSummary: string = '';
  @State notificationSummary: string = '';
  @State appearanceSummary: string = '';
  @State planningSummary: string = '';
  @State isLoading: boolean = true;
  @State loadError: string = '';

  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;

  onPageShow(): void {
    this.pageVisible = true;
    this.isNavigating = false;
    this.loadSettings(++this.loadVersion);
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.loadVersion++;
  }

  private getContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private getThemeLabel(mode: string): string {
    if (mode === 'light') {
      return LocalizationService.text('settings_theme_light');
    }
    if (mode === 'dark') {
      return LocalizationService.text('settings_theme_dark');
    }
    return LocalizationService.text('settings_theme_system');
  }

  private getLanguageLabel(mode: string): string {
    switch (mode) {
      case 'zh-Hans': return '简体中文';
      case 'zh-Hant': return '繁體中文';
      case 'en': return 'English';
      case 'ja': return '日本語';
      case 'ko': return '한국어';
      case 'de': return 'Deutsch';
      case 'es': return 'Español';
      case 'fr': return 'Français';
      default: return LocalizationService.text('settings_language_system');
    }
  }

  private getProgressLabel(mode: string): string {
    return mode === 'automatic' ? LocalizationService.text('core_automatic_progress') :
      LocalizationService.text('core_manual_progress');
  }

  private getNotificationIntensityLabel(intensity: string): string {
    if (intensity === 'concise') {
      return LocalizationService.text('settings_intensity_concise');
    }
    if (intensity === 'active') {
      return LocalizationService.text('settings_intensity_active');
    }
    if (intensity === 'custom') {
      return LocalizationService.text('settings_intensity_custom');
    }
    return LocalizationService.text('settings_intensity_standard');
  }

  private async loadSettings(version: number): Promise<void> {
    this.isLoading = true;
    try {
      const appSettings: AppSettings = await AppSettingsService.getSettings(this.getContext());
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      this.appearanceSummary = LocalizationService.text(
        'settings_summary_pair', this.getThemeLabel(appSettings.themeMode),
        this.getLanguageLabel(appSettings.languageMode)
      );
      this.planningSummary = LocalizationService.text(
        'settings_summary_pair', this.getProgressLabel(appSettings.defaultProgressMode),
        LocalizationService.text('settings_hours_day', appSettings.dailyAvailableHours)
      );
      this.loadError = '';
      await Promise.all([
        ReleaseScope.CLOUD_SYNC_AVAILABLE ? this.loadAccountSummary(version) : Promise.resolve(),
        this.loadNotificationSummary(version)
      ]);
    } catch (error) {
      console.error(`Failed to load settings directory: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('settings_load_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoading = false;
      }
    }
  }

  private async loadAccountSummary(version: number): Promise<void> {
    try {
      const session: CloudAccountSession = await CloudAccountService.getSession(this.getContext());
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      this.accountSummary = session.syncEnabled && session.openId.length > 0 ?
        (session.lastSyncAt === 0 ? LocalizationService.text('settings_sync_waiting') :
          (session.lastSyncCode === 0 ? LocalizationService.text('settings_sync_ok') :
            LocalizationService.text('settings_sync_failed'))) :
        LocalizationService.text('settings_signed_out');
    } catch (error) {
      console.error(`Failed to load account summary: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.accountSummary = LocalizationService.text('common_status_unavailable');
      }
    }
  }

  private async loadNotificationSummary(version: number): Promise<void> {
    try {
      const values = await Promise.all([
        NotificationSettingsService.getSettings(this.getContext()),
        DeadlineReminderService.isNotificationPermissionEnabled()
      ]);
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      const notificationSettings: DaylineNotificationSettings = values[0] as DaylineNotificationSettings;
      const permissionEnabled: boolean = values[1] as boolean;
      this.notificationSummary = LocalizationService.text(
        'settings_summary_pair', this.getNotificationIntensityLabel(notificationSettings.intensity),
        permissionEnabled ? LocalizationService.text('settings_permission_on') :
          LocalizationService.text('settings_permission_off')
      );
    } catch (error) {
      console.error(`Failed to load notification summary: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.notificationSummary = LocalizationService.text('common_status_unavailable');
      }
    }
  }

  private openPage(url: string, failureMessage: string): void {
    if (this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().pushUrl({ url: url }, (error) => {
        if (error) {
          this.isNavigating = false;
          console.error(`Failed to open settings destination: ${CloudDiagnostic.code(error as Object)}`);
          this.showMessage(failureMessage);
        }
      });
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to navigate from settings: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(failureMessage);
    }
  }

  private navigateBack(): void {
    if (this.isNavigating) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to leave settings: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('common_error_retry'));
    }
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show settings message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private showDataInformation(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: LocalizationService.text('settings_privacy'),
        message: LocalizationService.text('settings_privacy_desc'),
        buttons: [{ text: LocalizationService.text('review_understood'), color: $r('app.color.brand_accent') }]
      });
    } catch (error) {
      this.showMessage(LocalizationService.text('common_error_retry'));
    }
  }

  @Builder
  GroupTitle(title: ResourceStr) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .margin({ left: 4, bottom: 8 })
  }

  @Builder
  NavigationRow(title: ResourceStr, summary: string, onTapped: () => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .width('100%')
          .fontSize(16)
          .fontColor($r('app.color.text_strong'))
          .maxLines(2)
        Text(summary)
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(24)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 14, top: 8, bottom: 8 })
    .onClick(() => { onTapped(); })
  }

  @Builder
  InfoRow(title: ResourceStr, summary: ResourceStr, onTapped: () => void) {
    Column({ space: 3 }) {
      Text(title)
        .width('100%')
        .fontSize(16)
        .fontColor($r('app.color.text_strong'))
      Text(summary)
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => { onTapped(); })
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row({ space: 14 }) {
          Button($r('app.string.common_back'))
            .type(ButtonType.Normal)
            .constraintSize({ minHeight: 44 })
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(18)
            .enabled(!this.isNavigating)
            .onClick(() => { this.navigateBack(); })
          Text($r('app.string.settings_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')

        if (this.isLoading) {
          Text($r('app.string.settings_loading'))
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 80 })
        } else if (this.loadError.length > 0) {
          Column({ space: 14 }) {
            Text(this.loadError).fontSize(14).fontColor($r('app.color.danger'))
            Button($r('app.string.common_retry'))
              .type(ButtonType.Capsule)
              .constraintSize({ minHeight: 44 })
              .fontColor($r('app.color.text_body'))
              .backgroundColor($r('app.color.surface_muted'))
              .onClick(() => { this.loadSettings(++this.loadVersion); })
          }
          .width('100%')
          .margin({ top: 70 })
        } else {
          if (ReleaseScope.CLOUD_SYNC_AVAILABLE) {
          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_account_title'))
            Column() {
              this.NavigationRow($r('app.string.settings_huawei_account'), this.accountSummary, () => {
                this.openPage('pages/CloudAccount', LocalizationService.text('settings_open_account_failed'));
              })
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          .width('100%').margin({ top: 18 })
          }

          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_preferences'))
            Column() {
              this.NavigationRow($r('app.string.settings_appearance_language'), this.appearanceSummary, () => {
                this.openPage('pages/AppearanceLanguageSettings',
                  LocalizationService.text('settings_open_appearance_failed'));
              })
              Divider().color($r('app.color.divider')).margin({ left: 16 })
              this.NavigationRow($r('app.string.core_notification_policy'), this.notificationSummary, () => {
                this.openPage('pages/NotificationSettings',
                  LocalizationService.text('settings_open_notifications_failed'));
              })
              Divider().color($r('app.color.divider')).margin({ left: 16 })
              this.NavigationRow($r('app.string.settings_tasks_plans'), this.planningSummary, () => {
                this.openPage('pages/PlanningSettings', LocalizationService.text('settings_open_planning_failed'));
              })
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          .width('100%').margin({ top: 18 })

          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_general'))
            Column() {
              this.InfoRow($r('app.string.settings_privacy'), $r('app.string.settings_privacy_summary'),
                () => { this.showDataInformation(); })
              Divider().color($r('app.color.divider')).margin({ left: 16 })
              this.InfoRow($r('app.string.settings_about'), $r('app.string.settings_version'), () => {})
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          .width('100%').margin({ top: 18, bottom: 28 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
