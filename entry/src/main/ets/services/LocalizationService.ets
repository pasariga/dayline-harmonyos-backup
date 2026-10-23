import { CloudDiagnostic } from './CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';

export class LocalizationService {
  private static context: common.UIAbilityContext | undefined = undefined;

  static initialize(context: common.UIAbilityContext): void {
    LocalizationService.context = context;
  }

  static text(name: string, ...args: Array<string | number>): string {
    if (LocalizationService.context === undefined) {
      return name;
    }
    try {
      let value: string = LocalizationService.context.resourceManager.getStringByNameSync(name);
      args.forEach((argument: string | number, index: number) => {
        const localizedArgument: string = typeof argument === 'number' ?
          LocalizationService.formatNumber(argument) : argument;
        value = value.replace(new RegExp(`\\{${index}\\}`, 'g'), localizedArgument);
        value = value.replace('%s', localizedArgument);
      });
      return value;
    } catch (error) {
      console.error(`Missing localized string ${name}: ${CloudDiagnostic.code(error as Object)}`);
      return name;
    }
  }

  static count(name: string, count: number, ...args: Array<string | number>): string {
    const suffix: string = count === 1 ? 'one' : 'other';
    return LocalizationService.text(`${name}_${suffix}`, count, ...args);
  }

  static getEffectiveLocale(): string {
    try {
      const preferredLanguage: string = i18n.System.getAppPreferredLanguage();
      return preferredLanguage === 'default' ? i18n.System.getSystemLocaleInstance().toString() : preferredLanguage;
    } catch (error) {
      console.error(`Unable to read effective locale: ${CloudDiagnostic.code(error as Object)}`);
      return 'en';
    }
  }

  static formatDate(value: Date, style: 'medium' | 'full' | 'long' | 'short' = 'medium'): string {
    try {
      const formatter: Intl.DateTimeFormat = new Intl.DateTimeFormat(
        LocalizationService.getEffectiveLocale(),
        { dateStyle: style, timeZone: i18n.getTimeZone().getID() }
      );
      return formatter.format(value);
    } catch (error) {
      console.error(`Unable to format localized date: ${CloudDiagnostic.code(error as Object)}`);
      return `${value.getFullYear()}-${LocalizationService.pad(value.getMonth() + 1)}-${LocalizationService.pad(value.getDate())}`;
    }
  }

  static formatDateTime(value: Date): string {
    try {
      const formatter: Intl.DateTimeFormat = new Intl.DateTimeFormat(
        LocalizationService.getEffectiveLocale(),
        { dateStyle: 'medium', timeStyle: 'short', hour12: !LocalizationService.uses24HourClock(),
          timeZone: i18n.getTimeZone().getID() }
      );
      return formatter.format(value);
    } catch (error) {
      console.error(`Unable to format localized date and time: ${CloudDiagnostic.code(error as Object)}`);
      return `${LocalizationService.formatDate(value)} ${LocalizationService.pad(value.getHours())}:${LocalizationService.pad(value.getMinutes())}`;
    }
  }

  static formatTime(value: Date): string {
    try {
      const formatter: Intl.DateTimeFormat = new Intl.DateTimeFormat(
        LocalizationService.getEffectiveLocale(),
        { hour: 'numeric', minute: '2-digit', hour12: !LocalizationService.uses24HourClock(),
          timeZone: i18n.getTimeZone().getID() }
      );
      return formatter.format(value);
    } catch (error) {
      console.error(`Unable to format localized time: ${CloudDiagnostic.code(error as Object)}`);
      return `${LocalizationService.pad(value.getHours())}:${LocalizationService.pad(value.getMinutes())}`;
    }
  }

  // A form's clock selection is not an instant. Formatting it in UTC avoids
  // moving the draft when the device zone changes or normalizing a DST gap.
  static formatClockTime(value: string): string {
    const parts = value.split(':');
    try {
      return new Intl.DateTimeFormat(LocalizationService.getEffectiveLocale(), {
        hour: 'numeric', minute: '2-digit', hour12: !LocalizationService.uses24HourClock(), timeZone: 'UTC'
      }).format(new Date(Date.UTC(2000, 0, 1, Number(parts[0]), Number(parts[1]))));
    } catch (_) { return value; }
  }

  static uses24HourClock(): boolean {
    try {
      return i18n.System.is24HourClock();
    } catch (error) {
      console.error(`Unable to read system time format: ${CloudDiagnostic.code(error as Object)}`);
      return true;
    }
  }

  static formatNumber(value: number, maximumFractionDigits: number = 1): string {
    try {
      const formatter: Intl.NumberFormat = new Intl.NumberFormat(
        LocalizationService.getEffectiveLocale(),
        { maximumFractionDigits: maximumFractionDigits }
      );
      return formatter.format(value);
    } catch (error) {
      console.error(`Unable to format localized number: ${CloudDiagnostic.code(error as Object)}`);
      return `${value}`;
    }
  }

  static deadlineType(value: string): string {
    switch (value) {
      case '作业':
        return LocalizationService.text('type_assignment');
      case '考试':
        return LocalizationService.text('type_exam');
      case '竞赛':
        return LocalizationService.text('type_competition');
      case '项目':
        return LocalizationService.text('type_project');
      case '生活':
        return LocalizationService.text('type_life');
      default:
        return LocalizationService.text('type_other');
    }
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
