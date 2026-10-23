import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';
import { DeadlineTime } from './DeadlineTime';

const STORE_NAME: string = 'dayline_app_settings';
const KEY_THEME_MODE: string = 'theme_mode';
const KEY_DEFAULT_PROGRESS_MODE: string = 'default_progress_mode';
const KEY_DAILY_AVAILABLE_HOURS: string = 'daily_available_hours';
const KEY_WEEKEND_AVAILABLE_HOURS: string = 'weekend_available_hours';
const KEY_SHOW_HOME_SCHEDULE: string = 'show_home_schedule';
const KEY_DEFAULT_DEADLINE_TIME: string = 'default_deadline_time';
const KEY_LANGUAGE_MODE: string = 'language_mode';

export class AppSettings {
  themeMode: string;
  defaultProgressMode: string;
  dailyAvailableHours: number;
  weekendAvailableHours: number;
  showHomeSchedule: boolean;
  defaultDeadlineTime: string;
  languageMode: string;

  constructor(themeMode: string = 'system', defaultProgressMode: string = 'manual',
    dailyAvailableHours: number = 3, showHomeSchedule: boolean = true,
    defaultDeadlineTime: string = '23:59', weekendAvailableHours: number = 5,
    languageMode: string = 'system') {
    this.themeMode = themeMode;
    this.defaultProgressMode = defaultProgressMode;
    this.dailyAvailableHours = dailyAvailableHours;
    this.weekendAvailableHours = weekendAvailableHours;
    this.showHomeSchedule = showHomeSchedule;
    this.defaultDeadlineTime = defaultDeadlineTime;
    this.languageMode = languageMode;
  }
}

export class AppSettingsRuntime {
  private static current: AppSettings = new AppSettings();

  static apply(settings: AppSettings): void {
    AppSettingsRuntime.current = new AppSettings(
      settings.themeMode,
      settings.defaultProgressMode,
      settings.dailyAvailableHours,
      settings.showHomeSchedule,
      settings.defaultDeadlineTime,
      settings.weekendAvailableHours,
      settings.languageMode
    );
  }

  static getDailyAvailableHours(): number {
    return AppSettingsRuntime.getAvailableHoursForDate(Date.now());
  }

  static getWeekdayAvailableHours(): number {
    return AppSettingsRuntime.current.dailyAvailableHours;
  }

  static getWeekendAvailableHours(): number {
    return AppSettingsRuntime.current.weekendAvailableHours;
  }

  static getAvailableHoursForDate(dateAt: number): number {
    const day: number = new Date(dateAt).getDay();
    return day === 0 || day === 6 ? AppSettingsRuntime.current.weekendAvailableHours :
      AppSettingsRuntime.current.dailyAvailableHours;
  }

  static getAvailableHoursBetween(startAt: number, endAt: number): number {
    if (endAt <= startAt) {
      return 0;
    }
    let cursor: number = startAt;
    let totalHours: number = 0;
    let processedDays: number = 0;
    while (cursor < endAt && processedDays < 3660) {
      const cursorDate: Date = new Date(cursor);
      const nextDayAt: number = new Date(
        cursorDate.getFullYear(), cursorDate.getMonth(), cursorDate.getDate() + 1
      ).getTime();
      const segmentEnd: number = Math.min(endAt, nextDayAt);
      const dayDuration: number = Math.max(1, nextDayAt - new Date(
        cursorDate.getFullYear(), cursorDate.getMonth(), cursorDate.getDate()
      ).getTime());
      const segmentRatio: number = Math.max(0, segmentEnd - cursor) / dayDuration;
      totalHours += AppSettingsRuntime.getAvailableHoursForDate(cursor) * segmentRatio;
      cursor = segmentEnd;
      processedDays++;
    }
    if (cursor < endAt) {
      const averageDailyHours: number = (AppSettingsRuntime.current.dailyAvailableHours * 5 +
        AppSettingsRuntime.current.weekendAvailableHours * 2) / 7;
      const endDay = DeadlineTime.calendarDay(endAt);
      totalHours += DeadlineTime.daysBetween(cursor, endDay) * averageDailyHours;
      totalHours += (endAt - endDay) / Math.max(1, DeadlineTime.calendarDay(endAt, 1) - endDay) *
        AppSettingsRuntime.getAvailableHoursForDate(endAt);
    }
    return Math.round(totalHours * 10) / 10;
  }

  static getDefaultProgressMode(): string {
    return AppSettingsRuntime.current.defaultProgressMode;
  }

  static getDefaultDeadlineTime(): string {
    return AppSettingsRuntime.current.defaultDeadlineTime;
  }

  static shouldShowHomeSchedule(): boolean {
    return AppSettingsRuntime.current.showHomeSchedule;
  }

  static getLanguageMode(): string {
    return AppSettingsRuntime.current.languageMode;
  }
}

export class AppSettingsService {
  private static async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (error) {
      throw new Error(`Unable to open app settings preferences: ${JSON.stringify(error)}`);
    }
  }

  private static normalizeThemeMode(value: preferences.ValueType): string {
    return value === 'light' || value === 'dark' ? value : 'system';
  }

  private static normalizeProgressMode(value: preferences.ValueType): string {
    return value === 'automatic' ? 'automatic' : 'manual';
  }

  private static normalizeDailyHours(value: preferences.ValueType): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 3;
    }
    return Math.max(1, Math.min(12, Math.round(value * 2) / 2));
  }

  private static normalizeDeadlineTime(value: preferences.ValueType): string {
    if (typeof value !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) {
      return '23:59';
    }
    return value;
  }

  private static normalizeLanguageMode(value: preferences.ValueType): string {
    const supportedLanguages: string[] = ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'de', 'es', 'fr'];
    return typeof value === 'string' && supportedLanguages.indexOf(value) >= 0 ? value : 'system';
  }

  static async getSettings(context: common.UIAbilityContext): Promise<AppSettings> {
    try {
      const store: preferences.Preferences = await AppSettingsService.getStore(context);
      const hasSavedDailyHours: boolean = await store.has(KEY_DAILY_AVAILABLE_HOURS);
      const dailyHoursValue: preferences.ValueType = await store.get(KEY_DAILY_AVAILABLE_HOURS, 3);
      const legacyCompatibleWeekendDefault: number = hasSavedDailyHours ?
        AppSettingsService.normalizeDailyHours(dailyHoursValue) : 5;
      const values: preferences.ValueType[] = await Promise.all([
        store.get(KEY_THEME_MODE, 'system'),
        store.get(KEY_DEFAULT_PROGRESS_MODE, 'manual'),
        store.get(KEY_SHOW_HOME_SCHEDULE, true),
        store.get(KEY_DEFAULT_DEADLINE_TIME, '23:59'),
        store.get(KEY_WEEKEND_AVAILABLE_HOURS, legacyCompatibleWeekendDefault),
        store.get(KEY_LANGUAGE_MODE, 'system')
      ]);
      return new AppSettings(
        AppSettingsService.normalizeThemeMode(values[0]),
        AppSettingsService.normalizeProgressMode(values[1]),
        AppSettingsService.normalizeDailyHours(dailyHoursValue),
        values[2] !== false,
        AppSettingsService.normalizeDeadlineTime(values[3]),
        AppSettingsService.normalizeDailyHours(values[4]),
        AppSettingsService.normalizeLanguageMode(values[5])
      );
    } catch (error) {
      throw new Error(`Unable to read app settings: ${JSON.stringify(error)}`);
    }
  }

  static async saveSettings(context: common.UIAbilityContext, settings: AppSettings): Promise<AppSettings> {
    const normalized: AppSettings = new AppSettings(
      AppSettingsService.normalizeThemeMode(settings.themeMode),
      AppSettingsService.normalizeProgressMode(settings.defaultProgressMode),
      AppSettingsService.normalizeDailyHours(settings.dailyAvailableHours),
      settings.showHomeSchedule,
      AppSettingsService.normalizeDeadlineTime(settings.defaultDeadlineTime),
      AppSettingsService.normalizeDailyHours(settings.weekendAvailableHours),
      AppSettingsService.normalizeLanguageMode(settings.languageMode)
    );
    try {
      const store: preferences.Preferences = await AppSettingsService.getStore(context);
      await store.put(KEY_THEME_MODE, normalized.themeMode);
      await store.put(KEY_DEFAULT_PROGRESS_MODE, normalized.defaultProgressMode);
      await store.put(KEY_DAILY_AVAILABLE_HOURS, normalized.dailyAvailableHours);
      await store.put(KEY_WEEKEND_AVAILABLE_HOURS, normalized.weekendAvailableHours);
      await store.put(KEY_SHOW_HOME_SCHEDULE, normalized.showHomeSchedule);
      await store.put(KEY_DEFAULT_DEADLINE_TIME, normalized.defaultDeadlineTime);
      await store.put(KEY_LANGUAGE_MODE, normalized.languageMode);
      await store.flush();
      AppSettingsRuntime.apply(normalized);
      return normalized;
    } catch (error) {
      throw new Error(`Unable to save app settings: ${JSON.stringify(error)}`);
    }
  }

  static applyTheme(context: common.UIAbilityContext, themeMode: string): void {
    let colorMode: ConfigurationConstant.ColorMode =
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (themeMode === 'light') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (themeMode === 'dark') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      context.getApplicationContext().setColorMode(colorMode);
    } catch (error) {
      throw new Error(`Unable to apply app theme: ${JSON.stringify(error)}`);
    }
  }

  static applyLanguage(languageMode: string): void {
    const normalizedLanguage: string = AppSettingsService.normalizeLanguageMode(languageMode);
    try {
      i18n.System.setAppPreferredLanguage(normalizedLanguage === 'system' ? 'default' : normalizedLanguage);
    } catch (error) {
      throw new Error(`Unable to apply app language: ${JSON.stringify(error)}`);
    }
  }

  static async initialize(context: common.UIAbilityContext): Promise<AppSettings> {
    const settings: AppSettings = await AppSettingsService.getSettings(context);
    AppSettingsRuntime.apply(settings);
    AppSettingsService.applyLanguage(settings.languageMode);
    AppSettingsService.applyTheme(context, settings.themeMode);
    return settings;
  }
}
