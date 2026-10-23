import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { AppSettings, AppSettingsService } from '../services/AppSettingsService';
import { LocalizationService } from '../services/LocalizationService';

class AppearanceSelectItem {
  value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Entry
@Component
struct AppearanceLanguageSettings {
  @State themeMode: string = 'system';
  @State languageMode: string = 'system';
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State loadError: string = '';

  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;
  private saveInFlight: boolean = false;
  private readonly languageModes: string[] = [
    'system', 'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'de', 'es', 'fr'
  ];
  private readonly languageLabels: string[] = [
    '', '简体中文', '繁體中文', 'English', '日本語', '한국어', 'Deutsch', 'Español', 'Français'
  ];

  onPageShow(): void {
    this.pageVisible = true;
    this.isNavigating = false;
    this.isSaving = this.saveInFlight;
    if (!this.saveInFlight) {
      this.loadSettings(++this.loadVersion);
    }
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.loadVersion++;
  }

  private getContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadSettings(version: number): Promise<void> {
    this.isLoading = true;
    try {
      const settings: AppSettings = await AppSettingsService.getSettings(this.getContext());
      if (!this.pageVisible || version !== this.loadVersion) {
        return;
      }
      this.themeMode = settings.themeMode;
      this.languageMode = settings.languageMode;
      this.loadError = '';
    } catch (error) {
      console.error(`Failed to load appearance settings: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('settings_load_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoading = false;
      }
    }
  }

  private buildSettings(): AppSettings {
    return new AppSettings(this.themeMode, 'manual', 3, true, '23:59', 5, this.languageMode);
  }

  private async saveSettings(previous: AppSettings, applyTheme: boolean = false): Promise<void> {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.isLoading = true;
    this.saveInFlight = true;
    try {
      const current: AppSettings = await AppSettingsService.getSettings(this.getContext());
      const next: AppSettings = new AppSettings(
        this.themeMode,
        current.defaultProgressMode,
        current.dailyAvailableHours,
        current.showHomeSchedule,
        current.defaultDeadlineTime,
        current.weekendAvailableHours,
        this.languageMode
      );
      const saved: AppSettings = await AppSettingsService.saveSettings(this.getContext(), next);
      if (applyTheme) {
        AppSettingsService.applyTheme(this.getContext(), saved.themeMode);
        if (this.pageVisible) {
          await this.loadSettings(++this.loadVersion);
        }
      }
    } catch (error) {
      console.error(`Failed to save appearance settings: ${CloudDiagnostic.code(error as Object)}`);
      this.themeMode = previous.themeMode;
      this.languageMode = previous.languageMode;
      if (applyTheme) {
        try {
          AppSettingsService.applyTheme(this.getContext(), previous.themeMode);
        } catch (themeError) {
          console.error(`Failed to restore app theme: ${CloudDiagnostic.code(themeError as Object)}`);
        }
      }
      if (this.pageVisible) {
        this.showMessage(LocalizationService.text('settings_save_failed'));
      }
    } finally {
      this.saveInFlight = false;
      if (this.pageVisible) {
        this.isSaving = false;
        this.isLoading = false;
      }
    }
  }

  private getThemeIndex(): number {
    return this.themeMode === 'light' ? 1 : (this.themeMode === 'dark' ? 2 : 0);
  }

  private getThemeLabel(): string {
    if (this.themeMode === 'light') {
      return LocalizationService.text('settings_theme_light');
    }
    if (this.themeMode === 'dark') {
      return LocalizationService.text('settings_theme_dark');
    }
    return LocalizationService.text('settings_theme_system');
  }

  private getLanguageIndex(): number {
    const index: number = this.languageModes.indexOf(this.languageMode);
    return index >= 0 ? index : 0;
  }

  private getLanguageLabel(): string {
    const index: number = this.getLanguageIndex();
    return index === 0 ? LocalizationService.text('settings_language_system') : this.languageLabels[index];
  }

  private changeTheme(index: number): void {
    const nextMode: string = index === 1 ? 'light' : (index === 2 ? 'dark' : 'system');
    if (this.isSaving || nextMode === this.themeMode) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.themeMode = nextMode;
    this.saveSettings(previous, true);
  }

  private async changeLanguage(index: number): Promise<void> {
    if (this.isSaving || index < 0 || index >= this.languageModes.length) {
      return;
    }
    const nextMode: string = this.languageModes[index];
    if (nextMode === this.languageMode) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.languageMode = nextMode;
    this.isSaving = true;
    this.isLoading = true;
    this.saveInFlight = true;
    try {
      const current: AppSettings = await AppSettingsService.getSettings(this.getContext());
      const saved: AppSettings = await AppSettingsService.saveSettings(this.getContext(), new AppSettings(
        current.themeMode,
        current.defaultProgressMode,
        current.dailyAvailableHours,
        current.showHomeSchedule,
        current.defaultDeadlineTime,
        current.weekendAvailableHours,
        this.languageMode
      ));
      AppSettingsService.applyLanguage(saved.languageMode);
      if (saved.languageMode === 'system') {
        // The platform applies default language on a cold start; a warm restart
        // can retain the previous resources. Make that delayed result explicit.
        if (this.pageVisible) {
          await this.loadSettings(++this.loadVersion);
          this.showMessage(LocalizationService.text('settings_language_system_saved'));
        }
        return;
      }
      const context: common.UIAbilityContext = this.getContext();
      await context.restartApp({
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      });
    } catch (error) {
      console.error(`Failed to change app language: ${CloudDiagnostic.code(error as Object)}`);
      this.themeMode = previous.themeMode;
      this.languageMode = previous.languageMode;
      try {
        const current: AppSettings = await AppSettingsService.getSettings(this.getContext());
        await AppSettingsService.saveSettings(this.getContext(), new AppSettings(
          current.themeMode,
          current.defaultProgressMode,
          current.dailyAvailableHours,
          current.showHomeSchedule,
          current.defaultDeadlineTime,
          current.weekendAvailableHours,
          previous.languageMode
        ));
        AppSettingsService.applyLanguage(previous.languageMode);
      } catch (restoreError) {
        console.error(`Failed to restore app language: ${CloudDiagnostic.code(restoreError as Object)}`);
      }
      if (this.pageVisible) {
        this.showMessage(LocalizationService.text('settings_language_save_failed'));
      }
    } finally {
      this.saveInFlight = false;
      if (this.pageVisible) {
        this.isSaving = false;
        this.isLoading = false;
      }
    }
  }

  private navigateBack(): void {
    if (this.isNavigating || this.isSaving) {
      return;
    }
    this.isNavigating = true;
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      this.isNavigating = false;
      console.error(`Failed to leave appearance settings: ${CloudDiagnostic.code(error as Object)}`);
      this.showMessage(LocalizationService.text('common_error_retry'));
    }
  }

  onBackPress(): boolean {
    if (this.isSaving) {
      this.showMessage(LocalizationService.text('message_save_in_progress'));
      return true;
    }
    this.navigateBack();
    return true;
  }

  private showMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error(`Failed to show appearance settings message: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  @Builder
  SelectRow(title: ResourceStr, options: Array<AppearanceSelectItem>, selected: number, value: string,
    onSelect: (index: number) => void) {
    Row({ space: 12 }) {
      Text(title)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_strong'))
        .maxLines(2)
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_body'))
        .maxLines(2)
      Select(options)
        .selected(selected)
        .value(' ')
        .font({ size: 14 })
        .enabled(!this.isSaving)
        .onSelect((index: number) => { onSelect(index); })
    }
    .width('100%')
    .constraintSize({ minHeight: 68 })
    .padding({ left: 16, right: 12 })
    .alignItems(VerticalAlign.Center)
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
            .enabled(!this.isNavigating && !this.isSaving)
            .onClick(() => { this.navigateBack(); })
          Text($r('app.string.settings_appearance_language'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        if (this.isLoading) {
          Text($r('app.string.settings_loading'))
            .width('100%').fontSize(14).fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center).margin({ top: 80 })
        } else if (this.loadError.length > 0) {
          Column({ space: 12 }) {
            Text(this.loadError)
              .width('100%').fontSize(14).fontColor($r('app.color.danger'))
            Button($r('app.string.common_retry'))
              .type(ButtonType.Normal)
              .height(38)
              .onClick(() => { this.loadSettings(++this.loadVersion); })
          }
          .width('100%').margin({ top: 48 })
        } else {
          Column({ space: 0 }) {
            this.SelectRow($r('app.string.settings_appearance'), [
              new AppearanceSelectItem(LocalizationService.text('settings_theme_system')),
              new AppearanceSelectItem(LocalizationService.text('settings_theme_light')),
              new AppearanceSelectItem(LocalizationService.text('settings_theme_dark'))
            ], this.getThemeIndex(), this.getThemeLabel(), (index: number) => { this.changeTheme(index); })
            Divider().color($r('app.color.divider')).margin({ left: 16 })
            this.SelectRow($r('app.string.settings_app_language'), [
              new AppearanceSelectItem(LocalizationService.text('settings_language_system')),
              new AppearanceSelectItem('简体中文'), new AppearanceSelectItem('繁體中文'),
              new AppearanceSelectItem('English'), new AppearanceSelectItem('日本語'),
              new AppearanceSelectItem('한국어'), new AppearanceSelectItem('Deutsch'),
              new AppearanceSelectItem('Español'), new AppearanceSelectItem('Français')
            ], this.getLanguageIndex(), this.getLanguageLabel(), (index: number) => { this.changeLanguage(index); })
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          .margin({ top: 22, bottom: 28 })
        }
      }
      .width('100%').constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 18 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
