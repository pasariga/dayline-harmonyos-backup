import { hilog } from '@kit.PerformanceAnalysisKit';
import { CloudDiagnostic } from './CloudDiagnostic';

const LOG_DOMAIN: number = 0x0D11;
const LOG_TAG: string = 'DDL';

export class AppLogger {
  static cloudError(scope: string, message: string, error: Object): void {
    const code: string = CloudDiagnostic.code(error);
    try { hilog.error(LOG_DOMAIN, LOG_TAG, '[%{public}s] %{public}s (%{public}s)', scope, message, code); }
    catch (failure) { console.error(`[DDL][${scope}] ${message} (${code})`); }
  }
  private static safeErrorText(error: Object): string {
    // Public runtime errors may embed account responses or SQL/user content.
    return CloudDiagnostic.code(error);
  }

  static info(scope: string, message: string): void {
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[%{public}s] %{public}s', scope, message);
    } catch (error) {
      console.info(`[DDL][${scope}] ${message}`);
    }
  }

  static warn(scope: string, message: string): void {
    try {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[%{public}s] %{public}s', scope, message);
    } catch (error) {
      console.warn(`[DDL][${scope}] ${message}`);
    }
  }

  static error(scope: string, message: string, error: Object): void {
    const errorText: string = AppLogger.safeErrorText(error);
    try {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[%{public}s] %{public}s: %{public}s', scope, message, errorText);
    } catch (logError) {
      console.error(`[DDL][${scope}] ${message}: ${errorText}`);
    }
  }
}
