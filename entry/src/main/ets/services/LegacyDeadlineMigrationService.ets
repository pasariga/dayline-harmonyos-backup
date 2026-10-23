import { CloudDiagnostic } from './CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { Deadline } from '../models/Deadline';
import { DeadlineDatabaseService } from './DeadlineDatabaseService';
import { LocalizationService } from './LocalizationService';

const LEGACY_STORE_NAME: string = 'ddl_deadline_preferences';
const LEGACY_DEADLINES_KEY: string = 'deadlines';
const MIGRATION_COMPLETED_KEY: string = 'relational_store_migration_v1_completed';

export class LegacyDeadlineMigrationService {
  private static normalizeLegacyDeadline(legacy: Deadline): Deadline {
    const id: string = typeof legacy.id === 'string' && legacy.id.length > 0 ? legacy.id : util.generateRandomUUID();
    const name: string = typeof legacy.name === 'string' && legacy.name.length > 0 ? legacy.name :
      LocalizationService.text('deadline_untitled');
    const type: string = typeof legacy.type === 'string' && legacy.type.length > 0 ? legacy.type : '其他';
    const deadlineDate: string = typeof legacy.deadlineDate === 'string' ? legacy.deadlineDate : '';
    const deadlineTime: string = typeof legacy.deadlineTime === 'string' ? legacy.deadlineTime : '23:59';
    const note: string = typeof legacy.note === 'string' ? legacy.note : '';
    const createdAt: number = typeof legacy.createdAt === 'number' ? legacy.createdAt : Date.now();
    let deadlineAt: number = typeof legacy.deadlineAt === 'number' ? legacy.deadlineAt : 0;
    if (deadlineAt <= 0) {
      deadlineAt = new Date(`${deadlineDate}T${deadlineTime}:00`).getTime();
    }
    if (!Number.isFinite(deadlineAt)) {
      deadlineAt = createdAt;
    }
    const completed: boolean = typeof legacy.completed === 'boolean' ? legacy.completed : false;
    return new Deadline(
      id,
      name,
      type,
      deadlineDate,
      deadlineTime,
      note,
      createdAt,
      deadlineAt,
      completed
    );
  }

  static async migrateIfNeeded(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        { name: LEGACY_STORE_NAME }
      );
      const migrationCompleted: preferences.ValueType = await store.get(MIGRATION_COMPLETED_KEY, false);
      if (migrationCompleted === true) {
        return;
      }

      const storedValue: preferences.ValueType = await store.get(LEGACY_DEADLINES_KEY, '');
      const deadlinesToMigrate: Deadline[] = [];
      if (typeof storedValue === 'string' && storedValue.length > 0) {
        const legacyDeadlines: Deadline[] = JSON.parse(storedValue) as Deadline[];
        if (!Array.isArray(legacyDeadlines)) {
          throw new Error('Legacy deadline data is not an array.');
        }
        for (let index: number = 0; index < legacyDeadlines.length; index++) {
          deadlinesToMigrate.push(
            LegacyDeadlineMigrationService.normalizeLegacyDeadline(legacyDeadlines[index])
          );
        }
      }

      await DeadlineDatabaseService.importDeadlines(context, deadlinesToMigrate);
      await store.put(MIGRATION_COMPLETED_KEY, true);
      await store.flush();
    } catch (error) {
      console.error(`Failed to migrate legacy deadline data: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to migrate legacy deadline data: ${JSON.stringify(error)}`);
    }
  }
}
