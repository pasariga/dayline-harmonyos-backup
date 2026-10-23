import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'ddl_notification_settings';
const KEY_INTENSITY: string = 'intensity';
const KEY_DAILY_SUMMARY: string = 'daily_summary';
const KEY_RISK_ALERTS: string = 'risk_alerts';
const KEY_REPLAN_ALERTS: string = 'replan_alerts';
const KEY_SUMMARY_HOUR: string = 'summary_hour';
const KEY_SUMMARY_MINUTE: string = 'summary_minute';
const KEY_QUIET_ENABLED: string = 'quiet_enabled';
const KEY_QUIET_START: string = 'quiet_start';
const KEY_QUIET_END: string = 'quiet_end';
const KEY_LAST_ACTIVITY_AT: string = 'last_activity_at';
const KEY_LAST_ACTIVITY_DEADLINE_ID: string = 'last_activity_deadline_id';
const KEY_LAST_PLAN_DATE: string = 'last_plan_date';
const KEY_LAST_PLAN_TASK_IDS: string = 'last_plan_task_ids';
const KEY_PERMISSION_GUIDE_HANDLED: string = 'permission_guide_handled';
const KEY_RISK_MARKS: string = 'risk_marks';
const KEY_LAST_RISK_AT: string = 'last_risk_at';

export class NotificationSettings {
  intensity: string;
  dailySummaryEnabled: boolean;
  riskAlertsEnabled: boolean;
  replanAlertsEnabled: boolean;
  summaryHour: number;
  summaryMinute: number;
  quietEnabled: boolean;
  quietStartMinutes: number;
  quietEndMinutes: number;

  constructor(intensity: string = 'standard', dailySummaryEnabled: boolean = true,
    riskAlertsEnabled: boolean = true, replanAlertsEnabled: boolean = true,
    summaryHour: number = 8, summaryMinute: number = 30, quietEnabled: boolean = true,
    quietStartMinutes: number = 22 * 60 + 30, quietEndMinutes: number = 8 * 60) {
    this.intensity = intensity;
    this.dailySummaryEnabled = dailySummaryEnabled;
    this.riskAlertsEnabled = riskAlertsEnabled;
    this.replanAlertsEnabled = replanAlertsEnabled;
    this.summaryHour = summaryHour;
    this.summaryMinute = summaryMinute;
    this.quietEnabled = quietEnabled;
    this.quietStartMinutes = quietStartMinutes;
    this.quietEndMinutes = quietEndMinutes;
  }
}

export class NotificationRuntimeState {
  lastActivityAt: number;
  lastActivityDeadlineId: string;
  lastPlanDate: string;
  lastPlanTaskIds: string[];
  riskMarks: string;
  lastRiskAt: number;

  constructor(lastActivityAt: number = 0, lastActivityDeadlineId: string = '', lastPlanDate: string = '',
    lastPlanTaskIds: string[] = [], riskMarks: string = '[]', lastRiskAt: number = 0) {
    this.lastActivityAt = lastActivityAt;
    this.lastActivityDeadlineId = lastActivityDeadlineId;
    this.lastPlanDate = lastPlanDate;
    this.lastPlanTaskIds = lastPlanTaskIds;
    this.riskMarks = riskMarks;
    this.lastRiskAt = lastRiskAt;
  }
}

export class NotificationSettingsService {
  private static async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (error) {
      throw new Error(`Unable to open notification settings: ${JSON.stringify(error)}`);
    }
  }

  private static normalizeIntensity(value: string): string {
    if (value === 'concise' || value === 'active' || value === 'custom') {
      return value;
    }
    return 'standard';
  }

  private static normalizeMinuteOfDay(value: number, fallback: number): number {
    if (!Number.isFinite(value) || value < 0 || value >= 1440) {
      return fallback;
    }
    return Math.min(1439, Math.round(value));
  }

  static createPreset(intensity: string, current: NotificationSettings | undefined = undefined): NotificationSettings {
    const normalized: string = NotificationSettingsService.normalizeIntensity(intensity);
    if (normalized === 'concise') {
      return new NotificationSettings('concise', false, false, false, 8, 30, true, 22 * 60 + 30, 8 * 60);
    }
    if (normalized === 'active') {
      return new NotificationSettings('active', true, true, true, 8, 30, true, 23 * 60, 7 * 60 + 30);
    }
    if (normalized === 'custom' && current !== undefined) {
      return new NotificationSettings(
        'custom', current.dailySummaryEnabled, current.riskAlertsEnabled, current.replanAlertsEnabled,
        current.summaryHour, current.summaryMinute, current.quietEnabled,
        current.quietStartMinutes, current.quietEndMinutes
      );
    }
    return new NotificationSettings();
  }

  static async getSettings(context: common.UIAbilityContext): Promise<NotificationSettings> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      const intensityValue: preferences.ValueType = await store.get(KEY_INTENSITY, 'standard');
      const intensity: string = NotificationSettingsService.normalizeIntensity(
        typeof intensityValue === 'string' ? intensityValue : 'standard'
      );
      const preset: NotificationSettings = NotificationSettingsService.createPreset(intensity);
      const dailyValue: preferences.ValueType = await store.get(KEY_DAILY_SUMMARY, preset.dailySummaryEnabled);
      const riskValue: preferences.ValueType = await store.get(KEY_RISK_ALERTS, preset.riskAlertsEnabled);
      const replanValue: preferences.ValueType = await store.get(KEY_REPLAN_ALERTS, preset.replanAlertsEnabled);
      const hourValue: preferences.ValueType = await store.get(KEY_SUMMARY_HOUR, preset.summaryHour);
      const minuteValue: preferences.ValueType = await store.get(KEY_SUMMARY_MINUTE, preset.summaryMinute);
      const quietValue: preferences.ValueType = await store.get(KEY_QUIET_ENABLED, preset.quietEnabled);
      const quietStartValue: preferences.ValueType = await store.get(KEY_QUIET_START, preset.quietStartMinutes);
      const quietEndValue: preferences.ValueType = await store.get(KEY_QUIET_END, preset.quietEndMinutes);
      return new NotificationSettings(
        intensity,
        dailyValue === true,
        riskValue === true,
        replanValue === true,
        typeof hourValue === 'number' ? Math.max(0, Math.min(23, Math.round(hourValue))) : preset.summaryHour,
        typeof minuteValue === 'number' ? Math.max(0, Math.min(59, Math.round(minuteValue))) : preset.summaryMinute,
        quietValue === true,
        NotificationSettingsService.normalizeMinuteOfDay(
          typeof quietStartValue === 'number' ? quietStartValue : preset.quietStartMinutes,
          preset.quietStartMinutes
        ),
        NotificationSettingsService.normalizeMinuteOfDay(
          typeof quietEndValue === 'number' ? quietEndValue : preset.quietEndMinutes,
          preset.quietEndMinutes
        )
      );
    } catch (error) {
      throw new Error(`Unable to read notification settings: ${JSON.stringify(error)}`);
    }
  }

  static async saveSettings(context: common.UIAbilityContext, settings: NotificationSettings): Promise<void> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      await store.put(KEY_INTENSITY, NotificationSettingsService.normalizeIntensity(settings.intensity));
      await store.put(KEY_DAILY_SUMMARY, settings.dailySummaryEnabled);
      await store.put(KEY_RISK_ALERTS, settings.riskAlertsEnabled);
      await store.put(KEY_REPLAN_ALERTS, settings.replanAlertsEnabled);
      await store.put(KEY_SUMMARY_HOUR, Math.max(0, Math.min(23, Math.round(settings.summaryHour))));
      await store.put(KEY_SUMMARY_MINUTE, Math.max(0, Math.min(59, Math.round(settings.summaryMinute))));
      await store.put(KEY_QUIET_ENABLED, settings.quietEnabled);
      await store.put(KEY_QUIET_START,
        NotificationSettingsService.normalizeMinuteOfDay(settings.quietStartMinutes, 22 * 60 + 30));
      await store.put(KEY_QUIET_END,
        NotificationSettingsService.normalizeMinuteOfDay(settings.quietEndMinutes, 8 * 60));
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to save notification settings: ${JSON.stringify(error)}`);
    }
  }

  static async hasHandledPermissionGuide(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      const value: preferences.ValueType = await store.get(KEY_PERMISSION_GUIDE_HANDLED, false);
      return value === true;
    } catch (error) {
      throw new Error(`Unable to read notification permission guidance state: ${JSON.stringify(error)}`);
    }
  }

  static async markPermissionGuideHandled(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      await store.put(KEY_PERMISSION_GUIDE_HANDLED, true);
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to save notification permission guidance state: ${JSON.stringify(error)}`);
    }
  }

  static async getRuntimeState(context: common.UIAbilityContext): Promise<NotificationRuntimeState> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      const activityAtValue: preferences.ValueType = await store.get(KEY_LAST_ACTIVITY_AT, 0);
      const activityDeadlineValue: preferences.ValueType = await store.get(KEY_LAST_ACTIVITY_DEADLINE_ID, '');
      const planDateValue: preferences.ValueType = await store.get(KEY_LAST_PLAN_DATE, '');
      const planTasksValue: preferences.ValueType = await store.get(KEY_LAST_PLAN_TASK_IDS, '');
      const riskMarksValue: preferences.ValueType = await store.get(KEY_RISK_MARKS, '[]');
      const riskAtValue: preferences.ValueType = await store.get(KEY_LAST_RISK_AT, 0);
      const serializedTaskIds: string = typeof planTasksValue === 'string' ? planTasksValue : '';
      return new NotificationRuntimeState(
        typeof activityAtValue === 'number' ? activityAtValue : 0,
        typeof activityDeadlineValue === 'string' ? activityDeadlineValue : '',
        typeof planDateValue === 'string' ? planDateValue : '',
        serializedTaskIds.length > 0 ? serializedTaskIds.split('|').filter((value: string) => value.length > 0) : [],
        typeof riskMarksValue === 'string' ? riskMarksValue : '[]',
        typeof riskAtValue === 'number' ? riskAtValue : 0
      );
    } catch (error) {
      throw new Error(`Unable to read notification runtime state: ${JSON.stringify(error)}`);
    }
  }

  static async saveRiskHistory(context: common.UIAbilityContext, marks: string, lastRiskAt: number): Promise<void> {
    try {
      const store = await NotificationSettingsService.getStore(context);
      await store.put(KEY_RISK_MARKS, marks);
      await store.put(KEY_LAST_RISK_AT, lastRiskAt);
      await store.flush();
    } catch (_) { throw new Error('Local notification history could not be saved.'); }
  }

  static async recordUserActivity(context: common.UIAbilityContext, deadlineId: string): Promise<void> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      await store.put(KEY_LAST_ACTIVITY_AT, Date.now());
      await store.put(KEY_LAST_ACTIVITY_DEADLINE_ID, deadlineId);
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to record notification activity: ${JSON.stringify(error)}`);
    }
  }

  static async savePlanSnapshot(context: common.UIAbilityContext, dateKey: string,
    taskIds: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await NotificationSettingsService.getStore(context);
      await store.put(KEY_LAST_PLAN_DATE, dateKey);
      await store.put(KEY_LAST_PLAN_TASK_IDS, taskIds.join('|'));
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to save notification plan snapshot: ${JSON.stringify(error)}`);
    }
  }

  static getDailyHorizon(settings: NotificationSettings): number {
    if (!settings.dailySummaryEnabled || settings.intensity === 'concise') {
      return 0;
    }
    return settings.intensity === 'active' ? 5 : 3;
  }

  static getRiskReminderLimit(settings: NotificationSettings): number {
    if (!settings.riskAlertsEnabled || settings.intensity === 'concise') {
      return 0;
    }
    return settings.intensity === 'active' ? 2 : 1;
  }

  static getActivityCooldown(settings: NotificationSettings): number {
    if (settings.intensity === 'active') {
      return 90 * 60 * 1000;
    }
    if (settings.intensity === 'concise') {
      return 6 * 60 * 60 * 1000;
    }
    return 3 * 60 * 60 * 1000;
  }

  static getBasicReminderLimit(settings: NotificationSettings): number {
    if (settings.intensity === 'active') {
      return 20;
    }
    if (settings.intensity === 'concise') {
      return 26;
    }
    return 22;
  }
}
