import { AbilityConstant, Configuration, ConfigurationConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { AppLogger } from '../services/AppLogger';
import { DeadlineReminderService } from '../services/DeadlineReminderService';
import { AppSettingsRuntime, AppSettingsService } from '../services/AppSettingsService';
import { LocalizationService } from '../services/LocalizationService';
import { commonEventManager } from '@kit.BasicServicesKit';
import { DeadlineTime } from '../services/DeadlineTime';

export default class EntryAbility extends UIAbility {
  private errorObserverId: number = -1;
  private timeSubscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  private currentLanguage: string = '';
  private settingsInitialized: boolean = false;
  private mainWindowStage: window.WindowStage | undefined = undefined;
  private readonly errorObserver: errorManager.ErrorObserver = {
    onUnhandledException: (errMsg: string): void => {
      AppLogger.error('Runtime', 'Unhandled ArkTS exception', new Error(errMsg));
    },
    onException: (error: Error): void => {
      AppLogger.error('Runtime', 'ArkTS exception object', error);
    }
  };
  private readonly loopObserver: errorManager.LoopObserver = {
    onLoopTimeOut: (timeout: number): void => {
      AppLogger.warn('Performance', `Main thread loop blocked for ${timeout} ms`);
    }
  };

  private async reconcileDeadlineReminders(): Promise<void> {
    if (!this.settingsInitialized) { return; }
    try {
      AppStorage.setOrCreate('daylineNotificationEnabled',
        await DeadlineReminderService.isNotificationPermissionEnabled());
      await DeadlineReminderService.reconcileAll(this.context);
    } catch (error) {
      AppLogger.error('EntryAbility', 'Unable to reconcile deadline reminders', error);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.observeClockChanges();
    try {
      this.errorObserverId = errorManager.on('error', this.errorObserver);
      errorManager.on('unhandledRejection', (reason: Error): void => {
        AppLogger.error('Runtime', 'Unhandled promise rejection', reason);
      });
      errorManager.on('loopObserver', 500, this.loopObserver);
    } catch (error) {
      AppLogger.error('EntryAbility', 'Failed to register runtime observers', error);
    }
  }

  onDestroy(): void {
    if (this.timeSubscriber !== undefined) {
      commonEventManager.unsubscribe(this.timeSubscriber);
      this.timeSubscriber = undefined;
    }
    try {
      if (this.errorObserverId >= 0) {
        errorManager.off('error', this.errorObserverId);
      }
      errorManager.off('unhandledRejection');
      errorManager.off('loopObserver', this.loopObserver);
    } catch (error) {
      AppLogger.error('EntryAbility', 'Failed to unregister runtime observers', error);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindowStage = windowStage;
    try {
      windowStage.on('windowStageEvent', (event: window.WindowStageEventType) => {
        if (event === window.WindowStageEventType.ACTIVE) {
          DeadlineTime.clockChanged();
          this.reconcileDeadlineReminders();
        }
      });
    } catch (_) { AppLogger.warn('DeadlineReminder', 'Window activation observer unavailable.'); }
    this.initializeWindow(windowStage);
  }

  private async initializeWindow(windowStage: window.WindowStage): Promise<void> {
    LocalizationService.initialize(this.context);
    try {
      await AppSettingsService.initialize(this.context);
      this.currentLanguage = LocalizationService.getEffectiveLocale();
    } catch (error) {
      AppLogger.error('EntryAbility', 'Unable to initialize app settings', error);
      try {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } catch (themeError) {
        AppLogger.error('EntryAbility', 'Unable to apply fallback color mode', themeError);
      }
    } finally {
      // Applying the persisted language itself can emit a configuration callback.
      // Only react to later system changes, otherwise a cold start may request an
      // unnecessary second restart before HarmonyOS' restart cooldown has elapsed.
      this.currentLanguage = LocalizationService.getEffectiveLocale();
      this.settingsInitialized = true;
    }
    this.reconcileDeadlineReminders();
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        AppLogger.error('EntryAbility', 'Unable to load the main page', new Error(JSON.stringify(err)));
        return;
      }
      try {
        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (_) { AppLogger.warn('UI', 'Keyboard resize mode unavailable.'); }
      AppLogger.info('EntryAbility', 'Main page loaded');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const nextLanguage: string = newConfig.language ?? '';
    if (!this.settingsInitialized || AppSettingsRuntime.getLanguageMode() !== 'system' ||
      nextLanguage.length === 0 || this.isSameSupportedLanguage(nextLanguage, this.currentLanguage)) {
      return;
    }
    this.currentLanguage = nextLanguage;
    this.restartAfterSystemLanguageChange();
  }

  private isSameSupportedLanguage(left: string, right: string): boolean {
    return this.normalizeSupportedLanguage(left) === this.normalizeSupportedLanguage(right);
  }

  private normalizeSupportedLanguage(value: string): string {
    const normalized: string = value.replace('_', '-').toLowerCase();
    if (normalized.startsWith('zh')) {
      if (normalized.indexOf('hant') >= 0 || normalized.indexOf('-tw') >= 0 ||
        normalized.indexOf('-hk') >= 0 || normalized.indexOf('-mo') >= 0) {
        return 'zh-hant';
      }
      return 'zh-hans';
    }
    const separatorIndex: number = normalized.indexOf('-');
    return separatorIndex < 0 ? normalized : normalized.substring(0, separatorIndex);
  }

  private async restartAfterSystemLanguageChange(): Promise<void> {
    try {
      await this.context.restartApp({
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: this.context.abilityInfo.name
      });
    } catch (error) {
      AppLogger.error('EntryAbility', 'Unable to refresh after system language change', error);
    }
  }

  onWindowStageDestroy(): void {
    try { this.mainWindowStage?.off('windowStageEvent'); }
    catch (_) { AppLogger.warn('DeadlineReminder', 'Window activation observer could not be removed.'); }
    this.mainWindowStage = undefined;
  }

  onForeground(): void {
    // Returning from system settings may change permission in less than a minute.
    DeadlineTime.clockChanged();
    this.reconcileDeadlineReminders();
  }

  private async observeClockChanges(): Promise<void> {
    try {
      this.timeSubscriber = await commonEventManager.createSubscriber({ events: [
        commonEventManager.Support.COMMON_EVENT_TIME_CHANGED,
        commonEventManager.Support.COMMON_EVENT_DATE_CHANGED,
        commonEventManager.Support.COMMON_EVENT_TIMEZONE_CHANGED
      ] });
      commonEventManager.subscribe(this.timeSubscriber, (error, data) => {
        if (!error) { DeadlineTime.clockChanged(); this.reconcileDeadlineReminders(); }
      });
    } catch (error) { AppLogger.warn('DeadlineReminder', 'Clock change subscription unavailable; foreground reconciliation remains active.'); }
  }

  onBackground(): void {
  }
}
