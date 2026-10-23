import { CloudDiagnostic } from '../services/CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { AppSettings, AppSettingsService } from '../services/AppSettingsService';
import { LocalizationService } from '../services/LocalizationService';
import { DeadlineReminderService } from '../services/DeadlineReminderService';

class PlanningSelectItem {
  value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Entry
@Component
struct PlanningSettings {
  @State defaultProgressMode: string = 'manual';
  @State dailyAvailableHours: number = 3;
  @State weekendAvailableHours: number = 5;
  @State showHomeSchedule: boolean = true;
  @State defaultDeadlineTime: string = '23:59';
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State loadError: string = '';

  private pageVisible: boolean = false;
  private loadVersion: number = 0;
  private isNavigating: boolean = false;
  private saveInFlight: boolean = false;
  private readonly availableHoursOptions: number[] = [1, 2, 3, 4, 5, 6, 8];

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
      this.defaultProgressMode = settings.defaultProgressMode;
      this.dailyAvailableHours = settings.dailyAvailableHours;
      this.weekendAvailableHours = settings.weekendAvailableHours;
      this.showHomeSchedule = settings.showHomeSchedule;
      this.defaultDeadlineTime = settings.defaultDeadlineTime;
      this.loadError = '';
    } catch (error) {
      console.error(`Failed to load planning settings: ${CloudDiagnostic.code(error as Object)}`);
      if (this.pageVisible && version === this.loadVersion) {
        this.loadError = LocalizationService.text('settings_load_failed');
      }
    } finally {
      if (this.pageVisible && version === this.loadVersion) {
        this.isLoading = false;
      }
    }
  }

  private async saveSettings(previous: AppSettings): Promise<void> {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.isLoading = true;
    this.saveInFlight = true;
    try {
      const current: AppSettings = await AppSettingsService.getSettings(this.getContext());
      await AppSettingsService.saveSettings(this.getContext(), new AppSettings(
        current.themeMode,
        this.defaultProgressMode,
        this.dailyAvailableHours,
        this.showHomeSchedule,
        this.defaultDeadlineTime,
        this.weekendAvailableHours,
        current.languageMode
      ));
      if (previous.dailyAvailableHours !== this.dailyAvailableHours ||
        previous.weekendAvailableHours !== this.weekendAvailableHours) {
        try { await DeadlineReminderService.reconcileAll(this.getContext()); }
        catch (_) {
          if (this.pageVisible) { this.showMessage(LocalizationService.text('reminder_result_failed')); }
        }
      }
      if (this.pageVisible) {
        await this.loadSettings(++this.loadVersion);
      }
    } catch (error) {
      console.error(`Failed to save planning settings: ${CloudDiagnostic.code(error as Object)}`);
      this.defaultProgressMode = previous.defaultProgressMode;
      this.dailyAvailableHours = previous.dailyAvailableHours;
      this.weekendAvailableHours = previous.weekendAvailableHours;
      this.showHomeSchedule = previous.showHomeSchedule;
      this.defaultDeadlineTime = previous.defaultDeadlineTime;
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

  private buildSettings(): AppSettings {
    return new AppSettings(
      'system', this.defaultProgressMode, this.dailyAvailableHours, this.showHomeSchedule,
      this.defaultDeadlineTime, this.weekendAvailableHours, 'system'
    );
  }

  private changeProgressMode(index: number): void {
    const nextMode: string = index === 0 ? 'automatic' : 'manual';
    if (this.isSaving || nextMode === this.defaultProgressMode) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.defaultProgressMode = nextMode;
    this.saveSettings(previous);
  }

  private changeDailyHours(index: number): void {
    const nextHours: number = this.availableHoursOptions[index];
    if (this.isSaving || nextHours === this.dailyAvailableHours) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.dailyAvailableHours = nextHours;
    this.saveSettings(previous);
  }

  private changeWeekendHours(index: number): void {
    const nextHours: number = this.availableHoursOptions[index];
    if (this.isSaving || nextHours === this.weekendAvailableHours) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.weekendAvailableHours = nextHours;
    this.saveSettings(previous);
  }

  private changeHomeSchedule(value: boolean): void {
    if (this.isSaving || value === this.showHomeSchedule) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.showHomeSchedule = value;
    this.saveSettings(previous);
  }

  private changeDefaultDeadlineTime(index: number, value: string): void {
    if (this.isSaving || value === this.defaultDeadlineTime) {
      return;
    }
    const previous: AppSettings = this.buildSettings();
    this.defaultDeadlineTime = value;
    this.saveSettings(previous);
  }

  private getHoursIndex(hours: number): number {
    const index: number = this.availableHoursOptions.indexOf(hours);
    return index >= 0 ? index : 2;
  }

  private hourOptions(): Array<PlanningSelectItem> {
    return this.availableHoursOptions.map((hours: number) => {
      return new PlanningSelectItem(LocalizationService.text('common_hours_value', hours));
    });
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
      console.error(`Failed to leave planning settings: ${CloudDiagnostic.code(error as Object)}`);
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
      console.error(`Failed to show planning settings message: ${CloudDiagnostic.code(error as Object)}`);
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
  SelectRow(title: ResourceStr, options: Array<PlanningSelectItem>, selected: number, value: string,
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
            .constraintSize({ minHeight: 44 })
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(18)
            .enabled(!this.isNavigating && !this.isSaving)
            .onClick(() => { this.navigateBack(); })
          Text($r('app.string.settings_tasks_plans'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
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
              .constraintSize({ minHeight: 44 })
              .onClick(() => { this.loadSettings(++this.loadVersion); })
          }
          .width('100%').margin({ top: 48 })
        } else {
          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_planning_defaults'))
            Column() {
              this.SelectRow($r('app.string.settings_default_progress'), [
                new PlanningSelectItem(LocalizationService.text('core_automatic_progress')),
                new PlanningSelectItem(LocalizationService.text('core_manual_progress'))
              ], this.defaultProgressMode === 'automatic' ? 0 : 1,
              this.defaultProgressMode === 'automatic' ? LocalizationService.text('core_automatic_progress') :
                LocalizationService.text('core_manual_progress'),
              (index: number) => { this.changeProgressMode(index); })
              Divider().color($r('app.color.divider')).margin({ left: 16 })
              this.SelectRow($r('app.string.settings_default_deadline_time'), [
                new PlanningSelectItem('12:00'), new PlanningSelectItem('18:00'),
                new PlanningSelectItem('23:59')
              ], this.defaultDeadlineTime === '12:00' ? 0 : (this.defaultDeadlineTime === '18:00' ? 1 : 2),
              this.defaultDeadlineTime, (index: number) => {
                this.changeDefaultDeadlineTime(index, index === 0 ? '12:00' : (index === 1 ? '18:00' : '23:59'));
              })
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          .width('100%').margin({ top: 18 })

          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_planning_time'))
            Column() {
              this.SelectRow($r('app.string.settings_weekday'), this.hourOptions(),
                this.getHoursIndex(this.dailyAvailableHours),
                LocalizationService.text('common_hours_value', this.dailyAvailableHours),
                (index: number) => { this.changeDailyHours(index); })
              Divider().color($r('app.color.divider')).margin({ left: 16 })
              this.SelectRow($r('app.string.settings_weekend'), this.hourOptions(),
                this.getHoursIndex(this.weekendAvailableHours),
                LocalizationService.text('common_hours_value', this.weekendAvailableHours),
                (index: number) => { this.changeWeekendHours(index); })
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          .width('100%').margin({ top: 16 })

          Column({ space: 0 }) {
            this.GroupTitle($r('app.string.settings_planning_home'))
            Row({ space: 12 }) {
              Text($r('app.string.settings_home_schedule'))
                .layoutWeight(1)
                .fontSize(16)
                .fontColor($r('app.color.text_strong'))
              Toggle({ type: ToggleType.Switch, isOn: this.showHomeSchedule })
                .enabled(!this.isSaving)
                .onChange((value: boolean) => { this.changeHomeSchedule(value); })
            }
            .width('100%').constraintSize({ minHeight: 68 }).padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.surface')).borderRadius(12)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%').margin({ top: 16, bottom: 28 })
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
