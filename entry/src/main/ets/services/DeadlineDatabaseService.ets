import { CloudDiagnostic } from './CloudDiagnostic';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { Deadline, DeadlineReminderState, DeadlineSubtask } from '../models/Deadline';
import { DeadlineCloudCompatibility } from './DeadlineCloudCompatibility';
import { util } from '@kit.ArkTS';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate, SyncMergeResult } from './DeadlineSyncProtocol';
import { DeadlineProgressService } from './DeadlineProgressService';
import { ConflictReview, DeadlineConflictRecovery, DeletionNotice, RecoverySelection } from './DeadlineConflictRecovery';
import { LegacyCloudImport, LegacyImportTrust, LegacyImportPlan, LegacyImportItem } from './LegacyCloudImport';
import { CloudProtocolPolicy } from './CloudProtocolPolicy';
import { LegacyJournalRow, LegacySnapshotReader } from './LegacySnapshotReader';

export class SyncRecoveryEntry {
  id: string;
  name: string;
  kind: string;
  constructor(id: string, name: string, kind: string) { this.id = id; this.name = name; this.kind = kind; }
}

const DATABASE_NAME: string = 'ddl.db';
const DATABASE_VERSION: number = 8;
const LEGACY_IMPORTS: string = 'ddl_legacy_imports';
const SYNC_TABLE: string = 'ddl_sync_events';
const SYNC_ARCHIVE: string = 'ddl_sync_archive';
const SYNC_ISSUES: string = 'ddl_sync_issues';
const SYNC_OWNER: string = 'ddl_sync_owner';
const TABLE_NAME: string = 'deadlines';
const SUBTASK_TABLE_NAME: string = 'deadline_subtasks';
const REMINDER_STATE_TABLE_NAME: string = 'deadline_reminder_states';

const COLUMN_ID: string = 'id';
const COLUMN_NAME: string = 'name';
const COLUMN_TYPE: string = 'type';
const COLUMN_DEADLINE_DATE: string = 'deadline_date';
const COLUMN_DEADLINE_TIME: string = 'deadline_time';
const COLUMN_NOTE: string = 'note';
const COLUMN_CREATED_AT: string = 'created_at';
const COLUMN_DEADLINE_AT: string = 'deadline_at';
const COLUMN_COMPLETED: string = 'completed';
const COLUMN_ESTIMATED_HOURS: string = 'estimated_hours';
const COLUMN_REMAINING_HOURS: string = 'remaining_hours';
const COLUMN_REMAINING_STATE: string = 'remaining_state';
const COLUMN_REMAINING_UPDATED_AT: string = 'remaining_updated_at';
const COLUMN_PROGRESS: string = 'progress';
const COLUMN_PROGRESS_MODE: string = 'progress_mode';
const COLUMN_REMINDER_OFFSET_MINUTES: string = 'reminder_offset_minutes';

const ALL_COLUMNS: string[] = [
  COLUMN_ID,
  COLUMN_NAME,
  COLUMN_TYPE,
  COLUMN_DEADLINE_DATE,
  COLUMN_DEADLINE_TIME,
  COLUMN_NOTE,
  COLUMN_CREATED_AT,
  COLUMN_DEADLINE_AT,
  COLUMN_COMPLETED,
  COLUMN_ESTIMATED_HOURS,
  COLUMN_REMAINING_HOURS,
  COLUMN_REMAINING_STATE,
  COLUMN_REMAINING_UPDATED_AT,
  COLUMN_PROGRESS,
  COLUMN_PROGRESS_MODE,
  COLUMN_REMINDER_OFFSET_MINUTES
];

const VERSION_4_DEADLINE_COLUMNS: string[] = [
  COLUMN_ID,
  COLUMN_NAME,
  COLUMN_TYPE,
  COLUMN_DEADLINE_DATE,
  COLUMN_DEADLINE_TIME,
  COLUMN_NOTE,
  COLUMN_CREATED_AT,
  COLUMN_DEADLINE_AT,
  COLUMN_COMPLETED,
  COLUMN_ESTIMATED_HOURS,
  COLUMN_PROGRESS,
  COLUMN_PROGRESS_MODE
];

const CREATE_TABLE_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (` +
  `${COLUMN_ID} TEXT PRIMARY KEY, ` +
  `${COLUMN_NAME} TEXT, ` +
  `${COLUMN_TYPE} TEXT, ` +
  `${COLUMN_DEADLINE_DATE} TEXT, ` +
  `${COLUMN_DEADLINE_TIME} TEXT, ` +
  `${COLUMN_NOTE} TEXT DEFAULT '', ` +
  `${COLUMN_CREATED_AT} INTEGER, ` +
  `${COLUMN_DEADLINE_AT} INTEGER, ` +
  `${COLUMN_COMPLETED} INTEGER DEFAULT 0, ` +
  `${COLUMN_ESTIMATED_HOURS} REAL DEFAULT 0, ` +
  `${COLUMN_PROGRESS} INTEGER DEFAULT 0, ` +
  `${COLUMN_PROGRESS_MODE} TEXT DEFAULT 'manual', ` +
  `${COLUMN_REMINDER_OFFSET_MINUTES} INTEGER DEFAULT 0, ` +
  `${COLUMN_REMAINING_HOURS} REAL NOT NULL DEFAULT 0, ` +
  `${COLUMN_REMAINING_STATE} TEXT NOT NULL DEFAULT 'unknown', ` +
  `${COLUMN_REMAINING_UPDATED_AT} INTEGER NOT NULL DEFAULT 0)`;

const CREATE_SUBTASK_TABLE_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${SUBTASK_TABLE_NAME} (` +
  `id TEXT PRIMARY KEY, ` +
  `deadline_id TEXT, ` +
  `title TEXT, ` +
  `completed INTEGER DEFAULT 0, ` +
  `created_at INTEGER, ` +
  `parent_id TEXT DEFAULT '', ` +
  `sort_order INTEGER DEFAULT 0)`;

const SUBTASK_COLUMNS: string[] = [
  'id', 'deadline_id', 'title', 'completed', 'created_at', 'parent_id', 'sort_order'
];

const CREATE_REMINDER_STATE_TABLE_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${REMINDER_STATE_TABLE_NAME} (` +
  `deadline_id TEXT PRIMARY KEY, reminder_id INTEGER, scheduled_at INTEGER, signature TEXT DEFAULT '')`;

export class DeadlineDataSnapshot {
  deadlines: Deadline[];
  subtasks: DeadlineSubtask[];

  constructor(deadlines: Deadline[], subtasks: DeadlineSubtask[]) {
    this.deadlines = deadlines;
    this.subtasks = subtasks;
  }
}

export class DeadlineDataConflictError extends Error {
  constructor() {
    super('The deadline changed after it was opened.');
  }
}

export class DeadlineSyncHeldError extends DeadlineDataConflictError {
  constructor() { super(); }
}

export class DeadlineDatabaseService {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static storePromise: Promise<relationalStore.RdbStore> | undefined = undefined;

  private static closeResultSet(resultSet: relationalStore.ResultSet | undefined): void {
    if (resultSet === undefined) {
      return;
    }
    try {
      resultSet.close();
    } catch (error) {
      console.error(`Failed to close database result set: ${CloudDiagnostic.code(error as Object)}`);
    }
  }

  private static async hasColumn(store: relationalStore.RdbStore, tableName: string,
    columnName: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(`PRAGMA table_info(${tableName})`);
      const nameIndex: number = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameIndex) === columnName) {
          return true;
        }
      }
      return false;
    } catch (error) {
      throw new Error(`Unable to inspect ${tableName}.${columnName}: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  private static async hasDeadlineTable(store: relationalStore.RdbStore): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(
        `SELECT name FROM sqlite_master WHERE type = 'table' AND name = '${TABLE_NAME}'`
      );
      return resultSet.goToNextRow();
    } catch (error) {
      throw new Error(`Unable to inspect deadline table: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  private static async upgradeToVersion2(store: relationalStore.RdbStore): Promise<void> {
    try {
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_ESTIMATED_HOURS)) {
        await store.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_ESTIMATED_HOURS} REAL NOT NULL DEFAULT 0`);
      }
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_PROGRESS)) {
        await store.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_PROGRESS} INTEGER NOT NULL DEFAULT 0`);
      }
      await store.execute(CREATE_SUBTASK_TABLE_SQL);
      store.version = 2;
    } catch (error) {
      throw new Error(`Database upgrade to version 2 failed: ${JSON.stringify(error)}`);
    }
  }

  private static async upgradeToVersion3(store: relationalStore.RdbStore): Promise<void> {
    try {
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_PROGRESS_MODE)) {
        await store.execute(
          `ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_PROGRESS_MODE} TEXT NOT NULL DEFAULT 'manual'`
        );
      }
      if (!await DeadlineDatabaseService.hasColumn(store, SUBTASK_TABLE_NAME, 'parent_id')) {
        await store.execute(
          `ALTER TABLE ${SUBTASK_TABLE_NAME} ADD COLUMN parent_id TEXT NOT NULL DEFAULT ''`
        );
      }
      if (!await DeadlineDatabaseService.hasColumn(store, SUBTASK_TABLE_NAME, 'sort_order')) {
        await store.execute(
          `ALTER TABLE ${SUBTASK_TABLE_NAME} ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0`
        );
      }
      store.version = 3;
    } catch (error) {
      throw new Error(`Database upgrade to version 3 failed: ${JSON.stringify(error)}`);
    }
  }

  private static async upgradeToVersion4(store: relationalStore.RdbStore): Promise<void> {
    const deadlineTempTable: string = 'deadlines_cloud_v4';
    const subtaskTempTable: string = 'deadline_subtasks_cloud_v4';
    let transaction: relationalStore.Transaction | undefined = undefined;
    try {
      transaction = await store.createTransaction();
      await transaction.execute(`DROP TABLE IF EXISTS ${deadlineTempTable}`);
      await transaction.execute(`DROP TABLE IF EXISTS ${subtaskTempTable}`);
      await transaction.execute(
        `CREATE TABLE ${deadlineTempTable} (` +
        `id TEXT PRIMARY KEY, name TEXT, type TEXT, deadline_date TEXT, deadline_time TEXT, ` +
        `note TEXT DEFAULT '', created_at INTEGER, deadline_at INTEGER, completed INTEGER DEFAULT 0, ` +
        `estimated_hours REAL DEFAULT 0, progress INTEGER DEFAULT 0, progress_mode TEXT DEFAULT 'manual')`
      );
      await transaction.execute(
        `INSERT INTO ${deadlineTempTable} (${VERSION_4_DEADLINE_COLUMNS.join(', ')}) ` +
        `SELECT ${VERSION_4_DEADLINE_COLUMNS.join(', ')} FROM ${TABLE_NAME}`
      );
      await transaction.execute(
        `CREATE TABLE ${subtaskTempTable} (` +
        `id TEXT PRIMARY KEY, deadline_id TEXT, title TEXT, completed INTEGER DEFAULT 0, ` +
        `created_at INTEGER, parent_id TEXT DEFAULT '', sort_order INTEGER DEFAULT 0)`
      );
      await transaction.execute(
        `INSERT INTO ${subtaskTempTable} (${SUBTASK_COLUMNS.join(', ')}) ` +
        `SELECT ${SUBTASK_COLUMNS.join(', ')} FROM ${SUBTASK_TABLE_NAME}`
      );
      await transaction.execute(`DROP TABLE ${SUBTASK_TABLE_NAME}`);
      await transaction.execute(`DROP TABLE ${TABLE_NAME}`);
      await transaction.execute(`ALTER TABLE ${deadlineTempTable} RENAME TO ${TABLE_NAME}`);
      await transaction.execute(`ALTER TABLE ${subtaskTempTable} RENAME TO ${SUBTASK_TABLE_NAME}`);
      await transaction.commit();
      store.version = 4;
    } catch (error) {
      if (transaction !== undefined) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back database version 4 upgrade: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
      }
      throw new Error(`Cloud-compatible database migration failed: ${JSON.stringify(error)}`);
    }
  }

  private static async upgradeToVersion5(store: relationalStore.RdbStore): Promise<void> {
    try {
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_REMINDER_OFFSET_MINUTES)) {
        await store.execute(
          `ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_REMINDER_OFFSET_MINUTES} INTEGER NOT NULL DEFAULT 0`
        );
      }
      await store.execute(CREATE_REMINDER_STATE_TABLE_SQL);
      store.version = 5;
    } catch (error) {
      throw new Error(`Database upgrade to version 5 failed: ${JSON.stringify(error)}`);
    }
  }

  private static async upgradeToVersion6(store: relationalStore.RdbStore): Promise<void> {
    try {
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_REMAINING_HOURS)) {
        await store.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_REMAINING_HOURS} REAL NOT NULL DEFAULT 0`);
      }
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_REMAINING_STATE)) {
        await store.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_REMAINING_STATE} TEXT NOT NULL DEFAULT 'unknown'`);
      }
      if (!await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_REMAINING_UPDATED_AT)) {
        await store.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${COLUMN_REMAINING_UPDATED_AT} INTEGER NOT NULL DEFAULT 0`);
      }
      // Preserve the old total as a reference, without treating started work as known remaining work.
      await store.execute(`UPDATE ${TABLE_NAME} SET ${COLUMN_REMAINING_HOURS} = ${COLUMN_ESTIMATED_HOURS} ` +
        `WHERE ${COLUMN_REMAINING_STATE} = 'unknown' AND ${COLUMN_REMAINING_UPDATED_AT} = 0 ` +
        `AND ${COLUMN_ESTIMATED_HOURS} > 0`);
      // Only untouched, unfinished estimates can safely become initial remaining work.
      await store.execute(`UPDATE ${TABLE_NAME} SET ${COLUMN_REMAINING_STATE} = 'initial', ` +
        `${COLUMN_REMAINING_UPDATED_AT} = ${COLUMN_CREATED_AT} ` +
        `WHERE ${COLUMN_REMAINING_STATE} = 'unknown' AND ${COLUMN_REMAINING_UPDATED_AT} = 0 ` +
        `AND ${COLUMN_COMPLETED} = 0 AND ${COLUMN_PROGRESS} = 0 AND ${COLUMN_ESTIMATED_HOURS} > 0`);
      store.version = 6;
    } catch (error) {
      throw new Error(`Database upgrade to version 6 failed: ${JSON.stringify(error)}`);
    }
  }

  private static async initializeStore(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
      // An earlier version may have persisted automatic cloud sync. Pause it before
      // any local migration/write, without making cloud availability a prerequisite.
      const distributedTables = await store.querySql(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'naturalbase_rdb_aux_%' LIMIT 1");
      let wasDistributed: boolean = false;
      try {
        wasDistributed = distributedTables.goToNextRow();
      } finally {
        distributedTables.close();
      }
      if (wasDistributed) {
        try {
          await store.setDistributedTables([TABLE_NAME, SUBTASK_TABLE_NAME],
            relationalStore.DistributedType.DISTRIBUTED_CLOUD, { autoSync: false, enableCloud: false });
        } catch (error) {
          console.error(`Unable to pause previously enabled cloud sync: ${CloudDiagnostic.code(error as Object)}`);
        }
      }
      const hasExistingDeadlines: boolean = await DeadlineDatabaseService.hasDeadlineTable(store);
      await store.execute(CREATE_TABLE_SQL);
      if (!hasExistingDeadlines || (store.version === 0 &&
        await DeadlineDatabaseService.hasColumn(store, TABLE_NAME, COLUMN_REMAINING_UPDATED_AT))) {
        await store.execute(CREATE_SUBTASK_TABLE_SQL);
        await store.execute(CREATE_REMINDER_STATE_TABLE_SQL);
        await DeadlineDatabaseService.initializeJournal(store);
        return store;
      }
      if (store.version < 2) {
        await DeadlineDatabaseService.upgradeToVersion2(store);
      }
      await store.execute(CREATE_SUBTASK_TABLE_SQL);
      if (store.version < 3) {
        await DeadlineDatabaseService.upgradeToVersion3(store);
      }
      if (store.version < 4) {
        await DeadlineDatabaseService.upgradeToVersion4(store);
      }
      if (store.version < 5) {
        await DeadlineDatabaseService.upgradeToVersion5(store);
      }
      if (store.version < 6) {
        await DeadlineDatabaseService.upgradeToVersion6(store);
      }
      await store.execute(CREATE_REMINDER_STATE_TABLE_SQL);
      await DeadlineDatabaseService.initializeJournal(store);
      return store;
    } catch (error) {
      console.error(`Failed to initialize deadline database: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to initialize deadline database: ${JSON.stringify(error)}`);
    }
  }

  private static async getStore(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (DeadlineDatabaseService.store !== undefined) {
      return DeadlineDatabaseService.store;
    }
    if (DeadlineDatabaseService.storePromise === undefined) {
      DeadlineDatabaseService.storePromise = DeadlineDatabaseService.initializeStore(context);
    }
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.storePromise;
      DeadlineDatabaseService.store = store;
      return store;
    } finally {
      DeadlineDatabaseService.storePromise = undefined;
    }
  }

  private static async initializeJournal(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.execute(`CREATE TABLE IF NOT EXISTS ${SYNC_TABLE} (id TEXT PRIMARY KEY, deadline_id TEXT, payload TEXT)`);
      await store.execute(`CREATE TABLE IF NOT EXISTS ${SYNC_ARCHIVE} (id TEXT PRIMARY KEY, deadline_id TEXT, payload TEXT)`);
      await store.execute(`CREATE TABLE IF NOT EXISTS ${SYNC_ISSUES} (id TEXT PRIMARY KEY, detail TEXT)`);
      await store.execute(`CREATE TABLE IF NOT EXISTS ${SYNC_OWNER} (id TEXT PRIMARY KEY, account_id TEXT NOT NULL)`);
      // Additive local staging/receipts. Never register this table for cloud synchronization.
      await store.execute(`CREATE TABLE IF NOT EXISTS ${LEGACY_IMPORTS} (` +
        'id TEXT PRIMARY KEY, kind TEXT NOT NULL, account_id TEXT NOT NULL, source_id TEXT NOT NULL, ' +
        'payload TEXT NOT NULL, complete INTEGER NOT NULL DEFAULT 0, writers_stopped INTEGER NOT NULL DEFAULT 0, ' +
        'journal_complete INTEGER NOT NULL DEFAULT 0, ' +
        "status TEXT NOT NULL DEFAULT 'staged', detail TEXT NOT NULL DEFAULT '', event_id TEXT NOT NULL DEFAULT '')");
      const registered: relationalStore.ResultSet = await store.querySql(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'naturalbase_rdb_aux_ddl_sync_events_%' LIMIT 1");
      let journalWasDistributed: boolean = false;
      try { journalWasDistributed = registered.goToNextRow(); } finally { registered.close(); }
      if (journalWasDistributed) {
        await store.setDistributedTables([SYNC_TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD,
          { autoSync: false, enableCloud: false });
      }
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const deadlines: Deadline[] = await DeadlineDatabaseService.queryDeadlines(transaction);
        for (let index: number = 0; index < deadlines.length; index++) {
          const events: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, deadlines[index].id);
          if (events.length === 0) {
            const aggregate: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, deadlines[index].id);
            if (aggregate !== undefined) {
              // Seed once per existing ID. Repeating the upgrade does not duplicate data.
              const event: DeadlineSyncEvent = new DeadlineSyncEvent(util.generateRandomUUID(true), deadlines[index].id,
                [], undefined, aggregate, [], true);
              try {
                DeadlineSyncProtocol.normalize(aggregate);
              } catch (error) {
                await transaction.insert(SYNC_ISSUES, { id: deadlines[index].id, detail: '["legacy_tree"]' },
                  relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
                continue;
              }
              await DeadlineDatabaseService.persistEvent(transaction, event);
            }
          }
        }
        await transaction.commit();
        store.version = DATABASE_VERSION;
        try {
          await DeadlineDatabaseService.materializeJournal(store);
          await DeadlineDatabaseService.applyStagedLegacyImports(store);
          await DeadlineDatabaseService.prepareHistoricalTransport(store);
        } catch (projectionError) {
          const marker: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
          marker.equalTo('id', '__projection__');
          const guard: relationalStore.ResultSet = await store.query(marker, ['id']);
          let protectedProjection: boolean = false;
          try { protectedProjection = guard.goToNextRow(); } finally { guard.close(); }
          if (!protectedProjection) { throw new Error('Unable to protect the previous sync projection.'); }
          console.error(`Sync projection deferred; local rows preserved: ${CloudDiagnostic.code(projectionError as Object)}`);
        }
      } catch (error) {
        try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back sync upgrade'); }
        throw new Error(`Unable to upgrade sync journal: ${(error as Error).message ?? JSON.stringify(error)}`);
      }
    } catch (error) {
      throw new Error(`Sync storage operation failed: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  private static async captureAggregate(transaction: relationalStore.Transaction, id: string): Promise<SyncAggregate | undefined> {
    const deadline: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(transaction, id);
    return deadline === undefined ? undefined : new SyncAggregate(deadline,
      await DeadlineDatabaseService.queryTransactionSubtasks(transaction, id));
  }

  private static async readSyncEvents(transaction: relationalStore.Transaction, id: string): Promise<DeadlineSyncEvent[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ARCHIVE);
      predicates.equalTo('deadline_id', id);
      const rows: relationalStore.ResultSet = await transaction.query(predicates, ['payload']);
      const events: DeadlineSyncEvent[] = [];
      try { while (rows.goToNextRow()) { events.push(DeadlineSyncProtocol.decode(rows.getString(0))); } }
      finally { rows.close(); }
      return events;
    } catch (error) {
      throw new Error(`Sync storage operation failed: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  private static async persistEvent(transaction: relationalStore.Transaction, event: DeadlineSyncEvent): Promise<void> {
    try {
      const payload: string = JSON.stringify(DeadlineSyncProtocol.decode(JSON.stringify(event)));
      const values: relationalStore.ValuesBucket = { id: event.id, deadline_id: event.deadlineId, payload: payload };
      await transaction.insert(SYNC_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
      await transaction.insert(SYNC_ARCHIVE, values, relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
    } catch (error) {
      throw new Error(`Sync storage operation failed: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  private static async appendSyncEvent(transaction: relationalStore.Transaction, id: string,
    before: SyncAggregate | undefined): Promise<void> {
    try {
      const after: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, id);
      const events: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, id);
      if (after !== undefined && events.some((event: DeadlineSyncEvent) => event.deleted)) {
        throw new DeadlineDataConflictError();
      }
      const issues: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
      issues.equalTo('id', id).or().equalTo('id', '__projection__');
      const issueRows: relationalStore.ResultSet = await transaction.query(issues, ['id']);
      let held: boolean = false;
      try { held = issueRows.goToNextRow(); } finally { issueRows.close(); }
      const merged: SyncMergeResult = DeadlineSyncProtocol.merge(events, id);
      if (after !== undefined && (held || merged.pending || merged.conflicts.length > 0 ||
        after.tasks.some((t: DeadlineSubtask) => merged.removedTasks.includes(t.id)))) {
        throw new DeadlineSyncHeldError();
      }
      const nextIds: Set<string> = new Set<string>((after?.tasks ?? []).map((task: DeadlineSubtask) => task.id));
      const removed: string[] = (before?.tasks ?? []).filter((task: DeadlineSubtask) => !nextIds.has(task.id))
        .map((task: DeadlineSubtask) => task.id);
      const parentIds: Set<string> = new Set<string>();
      events.forEach((event: DeadlineSyncEvent) => event.parents.forEach((parent: string) => parentIds.add(parent)));
      const heads: string[] = events.filter((event: DeadlineSyncEvent) => !parentIds.has(event.id)).map((event: DeadlineSyncEvent) => event.id).sort();
      const event: DeadlineSyncEvent = new DeadlineSyncEvent(util.generateRandomUUID(true), id, heads, after === undefined ? undefined : before, after, removed);
      await DeadlineDatabaseService.persistEvent(transaction, event);
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Unable to persist aggregate version: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  private static async materializeJournal(store: relationalStore.RdbStore): Promise<void> {
    try {
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const rows: relationalStore.ResultSet = await transaction.query(new relationalStore.RdbPredicates(SYNC_TABLE),
          ['id', 'deadline_id', 'payload']);
        const invalid: Set<string> = new Set<string>();
        const incompatible: Set<string> = new Set<string>();
        const repairs: DeadlineSyncEvent[] = [];
        try {
          while (rows.goToNextRow()) {
            const id: string = rows.getString(0);
            const deadlineId: string = rows.getString(1);
            const payload: string = rows.getString(2);
            try {
              const event: DeadlineSyncEvent = CloudProtocolPolicy.readTransport(id, deadlineId, payload);
              const known: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ARCHIVE);
              known.equalTo('id', event.id);
              const archive: relationalStore.ResultSet = await transaction.query(known, ['payload']);
              try {
                const archived: boolean = archive.goToNextRow();
                if (!archived && !CloudProtocolPolicy.canExchange(CloudProtocolPolicy.transportVersion(payload))) {
                  const witnessPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_TABLE);
                  witnessPredicate.equalTo('id', CloudProtocolPolicy.historicalId(event.id));
                  const witness: relationalStore.ResultSet = await transaction.query(witnessPredicate, ['payload']);
                  let certified: boolean = false;
                  try { if (witness.goToNextRow()) {
                    certified = JSON.stringify(CloudProtocolPolicy.readTransport(CloudProtocolPolicy.historicalId(event.id),
                      deadlineId, witness.getString(0))) === JSON.stringify(event);
                  } } finally { witness.close(); }
                  if (!certified) { incompatible.add(deadlineId); continue; }
                }
                if (archived && archive.getString(0) !== JSON.stringify(event)) {
                  // Preserve both payloads if a supposedly immutable native row changes.
                  // A valid tombstone must remain durable even if that row changes back.
                  const previous: DeadlineSyncEvent = DeadlineSyncProtocol.decode(archive.getString(0));
                  invalid.add(previous.deadlineId);
                  invalid.add(deadlineId);
                  const duplicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ARCHIVE);
                  duplicate.equalTo('deadline_id', deadlineId);
                  duplicate.equalTo('payload', JSON.stringify(event));
                  const variants: relationalStore.ResultSet = await transaction.query(duplicate, ['id']);
                  let preserved: boolean = false;
                  try { preserved = variants.goToNextRow(); } finally { variants.close(); }
                  if (!preserved) {
                    await transaction.insert(SYNC_ARCHIVE, {
                      id: `quarantine:${util.generateRandomUUID(true)}`,
                      deadline_id: deadlineId,
                      payload: JSON.stringify(event)
                    }, relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
                    if (event.deleted || event.removedTasks.length > 0) {
                      // Republish the observed deletion under a fresh immutable ID.
                      // Reinstall must not depend solely on this device's quarantine copy.
                      repairs.push(new DeadlineSyncEvent(
                        util.generateRandomUUID(true), event.deadlineId, event.parents, event.base,
                        event.snapshot, event.removedTasks, event.legacy));
                    }
                  }
                  continue;
                }
              } finally { archive.close(); }
              await transaction.insert(SYNC_ARCHIVE, { id: event.id, deadline_id: deadlineId, payload: JSON.stringify(event) },
                relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
            } catch (error) { invalid.add(deadlineId); }
          }
        } finally { rows.close(); }
        for (let repairIndex: number = 0; repairIndex < repairs.length; repairIndex++) {
          await DeadlineDatabaseService.persistEvent(transaction, repairs[repairIndex]);
        }
        const ids: relationalStore.ResultSet = await transaction.querySql(`SELECT DISTINCT deadline_id FROM ${SYNC_ARCHIVE}`);
        const deadlineIds: string[] = [];
        try { while (ids.goToNextRow()) { deadlineIds.push(ids.getString(0)); } } finally { ids.close(); }
        invalid.forEach((id: string) => { if (!deadlineIds.includes(id)) { deadlineIds.push(id); } });
        incompatible.forEach((id: string) => { if (!deadlineIds.includes(id)) { deadlineIds.push(id); } });
        const taskOwners: Map<string, string> = new Map<string, string>();
        const collisions: Set<string> = new Set<string>();
        for (let index: number = 0; index < deadlineIds.length; index++) {
          const id: string = deadlineIds[index];
          const history: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, id);
          history.forEach((event: DeadlineSyncEvent) => {
            (event.snapshot?.tasks ?? []).forEach((task: DeadlineSubtask) => {
              const owner: string | undefined = taskOwners.get(task.id);
              if (owner !== undefined && owner !== id) { collisions.add(owner); collisions.add(id); }
              taskOwners.set(task.id, id);
            });
          });
        }
        collisions.forEach((id: string) => invalid.add(id));
        for (let index: number = 0; index < deadlineIds.length; index++) {
          const id: string = deadlineIds[index];
          const result: SyncMergeResult = DeadlineSyncProtocol.merge(await DeadlineDatabaseService.readSyncEvents(transaction, id), id);
          const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
          predicate.equalTo('id', id);
          const taskPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
          taskPredicate.equalTo('deadline_id', id);
          const issuePredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
          issuePredicate.equalTo('id', id);
          if (result.deleted) {
            await transaction.delete(taskPredicate); await transaction.delete(predicate); await transaction.delete(issuePredicate);
          } else if (incompatible.has(id) || invalid.has(id) || result.pending || result.conflicts.length > 0) {
            // A valid task tombstone applies even if an unrelated field remains conflicted.
            const local: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, id);
            if (local !== undefined && result.removedTasks.length > 0) {
              const removed: Set<string> = new Set<string>(result.removedTasks);
              let changed: boolean = true;
              while (changed) {
                changed = false;
                local.tasks.forEach((t: DeadlineSubtask) => {
                  if (removed.has(t.parentId) && !removed.has(t.id)) { removed.add(t.id); changed = true; }
                });
              }
              for (let taskIndex: number = 0; taskIndex < local.tasks.length; taskIndex++) {
                if (removed.has(local.tasks[taskIndex].id)) {
                  const removedPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
                  removedPredicate.equalTo('id', local.tasks[taskIndex].id);
                  await transaction.delete(removedPredicate);
                }
              }
              local.tasks = DeadlineProgressService.deriveParentStates(local.tasks.filter((t: DeadlineSubtask) => !removed.has(t.id)));
              for (let taskIndex: number = 0; taskIndex < local.tasks.length; taskIndex++) {
                const kept: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
                kept.equalTo('id', local.tasks[taskIndex].id);
                await transaction.update(DeadlineDatabaseService.toSubtaskValues(local.tasks[taskIndex]), kept);
              }
              if (local.deadline.progressMode === 'automatic') {
                await transaction.update({ progress: DeadlineProgressService.calculateDeadlineProgress(local.tasks) }, predicate);
              }
            }
            // Preserve the remaining complete local projection. Never expose half a tree.
            await transaction.insert(SYNC_ISSUES, { id: id, detail: JSON.stringify(incompatible.has(id) ? ['upgrade'] : invalid.has(id) ? ['invalid'] : result.pending ? ['pending'] : result.conflicts) },
              relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
          } else if (result.aggregate !== undefined) {
            const aggregate: SyncAggregate = result.aggregate;
            if (aggregate.deadline.progressMode === 'automatic') {
              aggregate.tasks = DeadlineProgressService.deriveParentStates(aggregate.tasks);
              aggregate.deadline.progress = DeadlineProgressService.calculateDeadlineProgress(aggregate.tasks);
            }
            await transaction.insert(TABLE_NAME, DeadlineDatabaseService.toValuesBucket(aggregate.deadline),
              relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
            await transaction.delete(taskPredicate);
            for (let taskIndex: number = 0; taskIndex < aggregate.tasks.length; taskIndex++) {
              await transaction.insert(SUBTASK_TABLE_NAME, DeadlineDatabaseService.toSubtaskValues(aggregate.tasks[taskIndex]),
                relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
            }
            await transaction.delete(issuePredicate);
          }
        }
        const cleared: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
        cleared.equalTo('id', '__projection__');
        await transaction.delete(cleared);
        await transaction.commit();
      } catch (error) {
        try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back cloud projection'); }
        await store.insert(SYNC_ISSUES, { id: '__projection__', detail: '["projection_failed"]' },
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        throw new Error(`Unable to reconcile synchronization journal: ${(error as Error).message ?? JSON.stringify(error)}`);
      }
    } catch (error) {
      throw new Error(`Sync storage operation failed: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  static async reconcileSyncJournal(context: common.UIAbilityContext): Promise<void> {
    const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
    await DeadlineDatabaseService.materializeJournal(store);
    await DeadlineDatabaseService.prepareHistoricalTransport(store);
  }

  private static async prepareHistoricalTransport(store: relationalStore.RdbStore): Promise<void> {
    try {
    const transaction: relationalStore.Transaction = await store.createTransaction();
    try {
      const rows: relationalStore.ResultSet = await transaction.query(new relationalStore.RdbPredicates(SYNC_ARCHIVE), ['id','payload']);
      const events: DeadlineSyncEvent[] = [];
      try { while (rows.goToNextRow()) {
        const payload: string = rows.getString(1);
        if (CloudProtocolPolicy.canCarryHistorical(rows.getString(0), payload)) {
          events.push(DeadlineSyncProtocol.decode(payload));
        }
      } } finally { rows.close(); }
      for (const event of events) {
        const id: string = CloudProtocolPolicy.historicalId(event.id);
        const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_TABLE);predicate.equalTo('id',id);
        const existing: relationalStore.ResultSet = await transaction.query(predicate,['payload']);
        const payload: string = CloudProtocolPolicy.wrapHistorical(event);
        let exists: boolean = false;let same: boolean = false;
        try { exists = existing.goToNextRow();if(exists) { same=existing.getString(0)===payload; } } finally { existing.close(); }
        if (exists && !same) { continue; } // Preserve an abnormal carrier for the normal quarantine path.
        if (!exists) { await transaction.insert(SYNC_TABLE,{id:id,deadline_id:event.deadlineId,payload:payload}); }
      }
      await transaction.commit();
    } catch(error) {
      try { await transaction.rollback(); } catch(rollbackError) { console.error('Unable to roll back history transport'); }
      // Original history and business rows are complete; do not make startup depend on publishing carriers.
      console.error('Historical transport deferred; local data preserved');
    }
    } catch (storageError) { console.error('Historical transport deferred; local data preserved'); }
  }

  // This is an authenticated staging boundary, not a legacy cloudSync call. The
  // future isolated reader must supply proven barriers; business JSON cannot set them.
  static async stageLegacyCloudImport(context: common.UIAbilityContext, trust: LegacyImportTrust,
    payload: string, journal: LegacyJournalRow[] = []): Promise<string> {
    try {
    let stagedBatchId: string = '';
    const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
    const transaction: relationalStore.Transaction = await store.createTransaction();
    try {
      const ownerRows: relationalStore.ResultSet = await transaction.querySql(
        `SELECT account_id FROM ${SYNC_OWNER} WHERE id='owner'`);
      let owner: string = '';
      try { if (ownerRows.goToNextRow()) { owner = ownerRows.getString(0); } } finally { ownerRows.close(); }
      if (trust.verifiedAccount.length === 0 || trust.verifiedAccount !== trust.sourceAccount ||
        (owner.length > 0 && owner !== trust.verifiedAccount) || trust.sourceId.length === 0) {
        throw new Error('The old data source account could not be verified.');
      }
      if (owner.length === 0) {
        await transaction.insert(SYNC_OWNER, { id: 'owner', account_id: trust.verifiedAccount });
      }
      if (journal.length > 0) {
        if (!LegacyCloudImport.authorized(owner, trust)) { throw new Error('The history source is not verified.'); }
        // A complete export is validated before any row is written. Both physical
        // transport and unwrapped history are immutable, including deleted rows.
        const events: DeadlineSyncEvent[] = LegacySnapshotReader.validateJournal(journal);
        for (const row of journal) {
          const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_TABLE);
          p.equalTo('id', row.id);
          const known: relationalStore.ResultSet = await transaction.query(p, ['deadline_id', 'payload']);
          let exists: boolean = false;
          try {
            exists = known.goToNextRow();
            if (exists && (known.getString(0) !== row.deadline_id || known.getString(1) !== row.payload)) {
              throw new Error('An immutable history transport already has different content.');
            }
          } finally { known.close(); }
          if (!exists) { await transaction.insert(SYNC_TABLE, { id: row.id, deadline_id: row.deadline_id, payload: row.payload }); }
        }
        for (const event of events) {
          const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ARCHIVE);
          p.equalTo('id', event.id);
          const known: relationalStore.ResultSet = await transaction.query(p, ['deadline_id', 'payload']);
          let exists: boolean = false;
          try {
            exists = known.goToNextRow();
            if (exists && (known.getString(0) !== event.deadlineId || known.getString(1) !== JSON.stringify(event))) {
              throw new Error('An immutable history archive already has different content.');
            }
          } finally { known.close(); }
          if (!exists) { await transaction.insert(SYNC_ARCHIVE,
            { id: event.id, deadline_id: event.deadlineId, payload: JSON.stringify(event) }); }
        }
      }
      const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LEGACY_IMPORTS);
      predicate.equalTo('kind', 'batch').equalTo('account_id', trust.sourceAccount)
        .equalTo('source_id', trust.sourceId).equalTo('payload', payload);
      const existing: relationalStore.ResultSet = await transaction.query(predicate, ['id']);
      let batchId: string = '';
      try { if (existing.goToNextRow()) { batchId = existing.getString(0); } } finally { existing.close(); }
      const values: relationalStore.ValuesBucket = {
        complete: trust.complete ? 1 : 0, writers_stopped: trust.writersStopped ? 1 : 0,
        journal_complete: trust.journalComplete ? 1 : 0,
        status: LegacyCloudImport.authorized(owner, trust) ? 'staged' : 'waiting'
      };
      if (batchId.length > 0) {
        stagedBatchId = batchId;
        const found: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LEGACY_IMPORTS);
        found.equalTo('id', batchId);
        await transaction.update(values, found);
      } else {
        stagedBatchId = util.generateRandomUUID(true);
        values.id = stagedBatchId; values.kind = 'batch'; values.account_id = trust.sourceAccount;
        values.source_id = trust.sourceId; values.payload = payload;
        await transaction.insert(LEGACY_IMPORTS, values);
      }
      await transaction.commit();
    } catch (error) {
      try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back old data staging'); }
      throw new Error('The old data was not staged; local data remains unchanged.');
    }
    if (journal.length > 0) { await DeadlineDatabaseService.materializeJournal(store); }
    await DeadlineDatabaseService.applyStagedLegacyImports(store);
    const statePredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LEGACY_IMPORTS);
    statePredicate.equalTo('id', stagedBatchId);
    const state: relationalStore.ResultSet = await store.query(statePredicate, ['status']);
    try { return state.goToNextRow() ? state.getString(0) : 'waiting'; } finally { state.close(); }
    } catch (storageError) { throw new Error('Unable to confirm the import status; complete local data is preserved.'); }
  }

  private static async applyStagedLegacyImports(store: relationalStore.RdbStore): Promise<void> {
    try {
    const batches: relationalStore.ResultSet = await store.querySql(
      `SELECT id FROM ${LEGACY_IMPORTS} WHERE kind='batch' AND status IN ('staged','retry','waiting')`);
    const ids: string[] = [];
    try { while (batches.goToNextRow()) { ids.push(batches.getString(0)); } } finally { batches.close(); }
    for (const batchId of ids) {
      const transaction: relationalStore.Transaction = await store.createTransaction();
      const batchPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LEGACY_IMPORTS);
      batchPredicate.equalTo('id', batchId);
      try {
        const batch: relationalStore.ResultSet = await transaction.query(batchPredicate,
          ['account_id','source_id','payload','complete','writers_stopped','journal_complete']);
        let account: string = ''; let payload: string = ''; let trust: LegacyImportTrust | undefined = undefined;
        try {
          if (batch.goToNextRow()) {
            account = batch.getString(0); payload = batch.getString(2);
            trust = new LegacyImportTrust(account, account, batch.getString(1), batch.getLong(3) === 1,
              batch.getLong(4) === 1, batch.getLong(5) === 1);
          }
        } finally { batch.close(); }
        const ownerRows: relationalStore.ResultSet = await transaction.querySql(
          `SELECT account_id FROM ${SYNC_OWNER} WHERE id='owner'`);
        let owner: string = '';
        try { if (ownerRows.goToNextRow()) { owner = ownerRows.getString(0); } } finally { ownerRows.close(); }
        if (trust === undefined || owner !== account || !LegacyCloudImport.authorized(owner, trust)) {
          await transaction.update({ status: 'waiting', detail: 'source_not_verified' }, batchPredicate);
          await transaction.commit(); continue;
        }
        const plan: LegacyImportPlan = LegacyCloudImport.plan(payload);
        const problems: string[] = [];
        for (const item of plan.items) {
          if (item.event === undefined) { problems.push(`${item.id}:${item.issue}`); continue; }
          const event: DeadlineSyncEvent = item.event;
          const canonical: string = JSON.stringify(event);
          const receiptId: string = `item:${encodeURIComponent(item.id)}`;
          const receiptPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(LEGACY_IMPORTS);
          receiptPredicate.equalTo('id', receiptId);
          const receipt: relationalStore.ResultSet = await transaction.query(receiptPredicate, ['account_id','payload']);
          let received: boolean = false; let same: boolean = false;
          try {
            received = receipt.goToNextRow();
            if (received) { same = receipt.getString(0) === account && receipt.getString(1) === canonical; }
          } finally { receipt.close(); }
          if (received) { if (!same) { problems.push(`${item.id}:old_source_changed`); } continue; }
          const history: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, item.id);
          const removed: boolean = history.some((e: DeadlineSyncEvent) => e.deleted);
          if (!removed) {
            const problemPredicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
            problemPredicate.equalTo('id', item.id).or().equalTo('id','__projection__');
            const guard: relationalStore.ResultSet = await transaction.query(problemPredicate, ['detail']);
            let unsafe: boolean = false;
            try { while (guard.goToNextRow()) {
              const reasons: string[] = JSON.parse(guard.getString(0)) as string[];
              unsafe = unsafe || reasons.some((s: string) => ['invalid','pending','causal','legacy_tree','projection_failed','upgrade'].includes(s));
            } } finally { guard.close(); }
            // Task IDs cannot be borrowed from another project's live or deleted history.
            const others: relationalStore.ResultSet = await transaction.querySql(
              `SELECT payload FROM ${SYNC_ARCHIVE} WHERE deadline_id <> ?`, [item.id]);
            const taskIds: Set<string> = new Set<string>((event.snapshot?.tasks ?? []).map((t: DeadlineSubtask) => t.id));
            try { while (others.goToNextRow()) {
              const other: DeadlineSyncEvent = DeadlineSyncProtocol.decode(others.getString(0));
              unsafe = unsafe || (other.snapshot?.tasks ?? []).concat(other.base?.tasks ?? [])
                .some((task: DeadlineSubtask) => taskIds.has(task.id));
            } } finally { others.close(); }
            if (unsafe) { problems.push(`${item.id}:local_state_not_safe`); continue; }
            const existing: DeadlineSyncEvent | undefined = history.find((e: DeadlineSyncEvent) => e.id === event.id);
            if (existing !== undefined && JSON.stringify(existing) !== canonical) {
              problems.push(`${item.id}:old_source_changed`); continue;
            }
            if (existing === undefined) { await DeadlineDatabaseService.persistEvent(transaction, event); history.push(event); }
            const result: SyncMergeResult = DeadlineSyncProtocol.merge(history, item.id);
            const issue: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES); issue.equalTo('id',item.id);
            if (result.pending || result.conflicts.length > 0 || result.aggregate === undefined) {
              await transaction.insert(SYNC_ISSUES, { id: item.id, detail: JSON.stringify(result.pending ? ['pending'] : result.conflicts) },
                relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
            } else {
              const aggregate: SyncAggregate = result.aggregate;
              if (aggregate.deadline.progressMode === 'automatic') {
                aggregate.tasks = DeadlineProgressService.deriveParentStates(aggregate.tasks);
                aggregate.deadline.progress = DeadlineProgressService.calculateDeadlineProgress(aggregate.tasks);
              }
              await transaction.insert(TABLE_NAME, DeadlineDatabaseService.toValuesBucket(aggregate.deadline),
                relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
              const tasks: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
              tasks.equalTo('deadline_id',item.id); await transaction.delete(tasks);
              for (const task of aggregate.tasks) { await transaction.insert(SUBTASK_TABLE_NAME, DeadlineDatabaseService.toSubtaskValues(task)); }
              await transaction.delete(issue);
            }
          }
          await transaction.insert(LEGACY_IMPORTS, { id: receiptId, kind: 'item', account_id: account,
            source_id: trust.sourceId, payload: canonical, status: removed ? 'deleted' : 'received', event_id: removed ? '' : event.id });
        }
        await transaction.update({ status: problems.length > 0 ? 'quarantined' : 'done', detail: JSON.stringify(problems) }, batchPredicate);
        await transaction.commit();
      } catch (error) {
        try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back old data import'); }
        await store.update({ status: 'retry', detail: 'import_not_committed' }, batchPredicate);
        console.error('Old data import deferred; complete local data preserved');
      }
    }
    } catch (storageError) { console.error('Old import deferred; local startup remains available'); }
  }

  static async getLegacyImportPending(context: common.UIAbilityContext): Promise<boolean> {
    try {
    const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
    const rows: relationalStore.ResultSet = await store.querySql(
      `SELECT id FROM ${LEGACY_IMPORTS} WHERE kind='batch' AND status <> 'done' LIMIT 1`);
    try { return rows.goToNextRow(); } finally { rows.close(); }
    } catch (storageError) { throw new Error('Unable to read the old data import status.'); }
  }

  static async getSyncProblemIds(context: common.UIAbilityContext): Promise<string[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const rows: relationalStore.ResultSet = await store.query(new relationalStore.RdbPredicates(SYNC_ISSUES), ['id']);
      const ids: string[] = [];
      try { while (rows.goToNextRow()) { ids.push(rows.getString(0)); } } finally { rows.close(); }
      return ids.filter((id: string) => !id.startsWith('ack:')).sort();
    } catch (error) {
      throw new Error(`Sync storage operation failed: ${(error as Error).message ?? JSON.stringify(error)}`);
    }
  }

  private static async recoveryReview(transaction: relationalStore.Transaction, id: string): Promise<ConflictReview> {
    try {
      const history: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, id);
      const current: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, id);
      const review: ConflictReview = DeadlineConflictRecovery.review(history, id, current);
      const issues: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
      issues.equalTo('id', id).or().equalTo('id', '__projection__');
      const rows: relationalStore.ResultSet = await transaction.query(issues, ['detail']);
      try {
        while (rows.goToNextRow()) {
          const reasons: string[] = JSON.parse(rows.getString(0)) as string[];
          if (reasons.includes('upgrade')) { review.requiresUpgrade = true; }
          if (reasons.some((reason: string) => ['invalid', 'pending', 'causal', 'legacy_tree', 'projection_failed', 'upgrade'].includes(reason))) {
            review.blocked = true;
          }
        }
      } finally { rows.close(); }
      return review;
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async getConflictReview(context: common.UIAbilityContext, id: string): Promise<ConflictReview> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const review: ConflictReview = await DeadlineDatabaseService.recoveryReview(transaction, id);
        await transaction.commit(); return review;
      } catch (error) { try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back review'); }
        if (error instanceof DeadlineDataConflictError) { throw error; }
        throw new Error(`Review storage failed: ${(error as Error).message}`); }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async getSyncDeletionNotice(context: common.UIAbilityContext, id: string): Promise<DeletionNotice | undefined> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const notice: DeletionNotice | undefined = DeadlineConflictRecovery.deletionNotice(
          await DeadlineDatabaseService.readSyncEvents(transaction, id), id);
        await transaction.commit(); return notice;
      } catch (error) { try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back review'); }
        if (error instanceof DeadlineDataConflictError) { throw error; }
        throw new Error(`Review storage failed: ${(error as Error).message}`); }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async getSyncRecoveryEntries(context: common.UIAbilityContext): Promise<SyncRecoveryEntry[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const rows: relationalStore.ResultSet = await transaction.query(new relationalStore.RdbPredicates(SYNC_ISSUES), ['id', 'detail']);
        const problems: Set<string> = new Set<string>();
        const acknowledged: Map<string, string> = new Map<string, string>();
        try {
          while (rows.goToNextRow()) {
            const id: string = rows.getString(0);
            if (id.startsWith('ack:')) { acknowledged.set(id.substring(4), rows.getString(1)); }
            else { problems.add(id); }
          }
        } finally { rows.close(); }
        const archived: relationalStore.ResultSet = await transaction.querySql(`SELECT DISTINCT deadline_id FROM ${SYNC_ARCHIVE}`);
        const ids: Set<string> = new Set<string>(problems);
        try { while (archived.goToNextRow()) { ids.add(archived.getString(0)); } } finally { archived.close(); }
        const entries: SyncRecoveryEntry[] = [];
        for (const id of Array.from(ids).sort()) {
          if (problems.has(id)) {
            const review: ConflictReview = await DeadlineDatabaseService.recoveryReview(transaction, id);
            entries.push(new SyncRecoveryEntry(id, review.name, review.blocked ? 'waiting' : 'review'));
          } else {
            const notice: DeletionNotice | undefined = DeadlineConflictRecovery.deletionNotice(
              await DeadlineDatabaseService.readSyncEvents(transaction, id), id);
            if (notice !== undefined && acknowledged.get(id) !== notice.token) {
              entries.push(new SyncRecoveryEntry(id, notice.name, notice.deleted ? 'deleted' : 'task_deleted'));
            }
          }
        }
        await transaction.commit(); return entries;
      } catch (error) { try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back review'); }
        if (error instanceof DeadlineDataConflictError) { throw error; }
        throw new Error(`Review storage failed: ${(error as Error).message}`); }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async acknowledgeSyncDeletion(context: common.UIAbilityContext, expected: DeletionNotice): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const notice: DeletionNotice | undefined = DeadlineConflictRecovery.deletionNotice(
          await DeadlineDatabaseService.readSyncEvents(transaction, expected.deadlineId), expected.deadlineId);
        if (notice === undefined || notice.token !== expected.token) { throw new DeadlineDataConflictError(); }
        // A local informational receipt, not a conflict and never a deletion reset.
        await transaction.insert(SYNC_ISSUES, { id: `ack:${notice.deadlineId}`, detail: notice.token },
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        await transaction.commit();
      } catch (error) { try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back review'); }
        if (error instanceof DeadlineDataConflictError) { throw error; }
        throw new Error(`Review storage failed: ${(error as Error).message}`); }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async resolveSyncConflict(context: common.UIAbilityContext, expected: ConflictReview,
    selections: RecoverySelection[]): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const id: string = expected.deadlineId;
        // A new native row may have arrived while this screen was open. Do not absorb an unseen
        // candidate into the user's choice. Reconcile and reload before any new decision.
        const raw: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_TABLE);
        raw.equalTo('deadline_id', id);
        const incoming: relationalStore.ResultSet = await transaction.query(raw, ['id', 'payload']);
        const received: DeadlineSyncEvent[] = [];
        try {
          while (incoming.goToNextRow()) {
            const event: DeadlineSyncEvent = CloudProtocolPolicy.readTransport(incoming.getString(0), id, incoming.getString(1));
            received.push(event);
          }
        } finally { incoming.close(); }
        const history: DeadlineSyncEvent[] = await DeadlineDatabaseService.readSyncEvents(transaction, id);
        if (received.some((e: DeadlineSyncEvent) => !history.some((known: DeadlineSyncEvent) =>
          e.id === known.id && JSON.stringify(e) === JSON.stringify(known)))) { throw new DeadlineDataConflictError(); }
        const current: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, id);
        const review: ConflictReview = await DeadlineDatabaseService.recoveryReview(transaction, id);
        if (review.blocked || review.fingerprint !== expected.fingerprint) { throw new DeadlineDataConflictError(); }
        const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, selections, history, current,
          util.generateRandomUUID(true));
        const aggregate: SyncAggregate = event.snapshot as SyncAggregate;
        if (aggregate.deadline.progressMode === 'automatic') {
          aggregate.tasks = DeadlineProgressService.deriveParentStates(aggregate.tasks);
          aggregate.deadline.progress = DeadlineProgressService.calculateDeadlineProgress(aggregate.tasks);
        }
        await DeadlineDatabaseService.persistEvent(transaction, event);
        await transaction.insert(TABLE_NAME, DeadlineDatabaseService.toValuesBucket(aggregate.deadline),
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        const tasks: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
        tasks.equalTo('deadline_id', id);
        await transaction.delete(tasks);
        for (let index: number = 0; index < aggregate.tasks.length; index++) {
          await transaction.insert(SUBTASK_TABLE_NAME, DeadlineDatabaseService.toSubtaskValues(aggregate.tasks[index]),
            relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
        }
        const issues: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
        issues.equalTo('id', id);
        await transaction.delete(issues);
        await transaction.commit();
      } catch (error) {
        try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back review'); }
        if (error instanceof DeadlineDataConflictError) { throw error; }
        throw new Error(`Unable to save reviewed data: ${(error as Error).message}`);
      }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) { throw error; }
      throw new Error(`Review storage failed: ${(error as Error).message}`);
    }
  }

  static async getSyncOwner(context: common.UIAbilityContext): Promise<string> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_OWNER);
      predicate.equalTo('id', 'owner');
      const rows: relationalStore.ResultSet = await store.query(predicate, ['account_id']);
      try { return rows.goToNextRow() ? rows.getString(0) : ''; } finally { rows.close(); }
    } catch (error) { throw new Error('Unable to verify database account association.'); }
  }

  static async bindSyncOwner(context: common.UIAbilityContext, accountId: string): Promise<void> {
    let transaction: relationalStore.Transaction | undefined = undefined;
    try {
      if (accountId.length === 0) { throw new Error('Missing account identity.'); }
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      transaction = await store.createTransaction();
      const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_OWNER);
      predicate.equalTo('id', 'owner');
      const rows: relationalStore.ResultSet = await transaction.query(predicate, ['account_id']);
      let owner: string = '';
      try { if (rows.goToNextRow()) { owner = rows.getString(0); } } finally { rows.close(); }
      if (owner.length > 0 && owner !== accountId) { throw new Error('Account mismatch.'); }
      if (owner.length === 0) {
        await transaction.insert(SYNC_OWNER, { id: 'owner', account_id: accountId },
          relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
      }
      await transaction.commit();
    } catch (error) {
      if (transaction !== undefined) {
        try { await transaction.rollback(); } catch (rollbackError) { console.error('Unable to roll back account association'); }
      }
      throw new Error('Unable to associate this database with the selected account.');
    }
  }

  static async setCloudSyncEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const config: relationalStore.DistributedConfig = {
        // All sync attempts must pass the app's current-account check and completion tracking.
        autoSync: false,
        enableCloud: enabled
      };
      await store.setDistributedTables(
        [SYNC_TABLE],
        relationalStore.DistributedType.DISTRIBUTED_CLOUD,
        config
      );
    } catch (error) {
      throw new Error(`Unable to configure cloud tables: ${JSON.stringify(error)}`);
    }
  }

  static async syncCloud(context: common.UIAbilityContext,
    progress: (details: relationalStore.ProgressDetails) => void): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      await store.cloudSync(
        relationalStore.SyncMode.SYNC_MODE_TIME_FIRST,
        [SYNC_TABLE],
        progress
      );
    } catch (error) {
      throw new Error(`Unable to synchronize cloud tables: ${JSON.stringify(error)}`);
    }
  }

  private static toValuesBucket(deadline: Deadline): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      id: deadline.id,
      name: deadline.name,
      type: deadline.type,
      deadline_date: deadline.deadlineDate,
      deadline_time: deadline.deadlineTime,
      note: deadline.note,
      created_at: deadline.createdAt,
      deadline_at: deadline.deadlineAt,
      completed: deadline.completed ? 1 : 0,
      estimated_hours: DeadlineDatabaseService.normalizeHours(deadline.estimatedHours),
      remaining_hours: DeadlineDatabaseService.normalizeHours(deadline.remainingHours),
      remaining_state: deadline.remainingState,
      remaining_updated_at: deadline.remainingUpdatedAt,
      progress: DeadlineDatabaseService.normalizeProgress(deadline.progress),
      progress_mode: deadline.progressMode === 'automatic' ? 'automatic' : 'manual',
      reminder_offset_minutes: DeadlineDatabaseService.normalizeReminderOffset(deadline.reminderOffsetMinutes)
    };
    return values;
  }

  private static fromResultSet(resultSet: relationalStore.ResultSet): Deadline {
    try {
      const hoursIndex: number = resultSet.getColumnIndex(COLUMN_REMAINING_HOURS);
      const stateIndex: number = resultSet.getColumnIndex(COLUMN_REMAINING_STATE);
      const timeIndex: number = resultSet.getColumnIndex(COLUMN_REMAINING_UPDATED_AT);
      const hours: number = hoursIndex < 0 || resultSet.isColumnNull(hoursIndex) ? 0 : resultSet.getDouble(hoursIndex);
      const state: string = stateIndex < 0 || resultSet.isColumnNull(stateIndex) ? 'unknown' : resultSet.getString(stateIndex);
      const confirmedAt: number = timeIndex < 0 || resultSet.isColumnNull(timeIndex) ? 0 : resultSet.getLong(timeIndex);
      return new Deadline(
        resultSet.getString(resultSet.getColumnIndex(COLUMN_ID)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_NAME)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_TYPE)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_DEADLINE_DATE)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_DEADLINE_TIME)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_NOTE)),
        resultSet.getLong(resultSet.getColumnIndex(COLUMN_CREATED_AT)),
        resultSet.getLong(resultSet.getColumnIndex(COLUMN_DEADLINE_AT)),
        resultSet.getLong(resultSet.getColumnIndex(COLUMN_COMPLETED)) === 1,
        resultSet.getDouble(resultSet.getColumnIndex(COLUMN_ESTIMATED_HOURS)),
        resultSet.getLong(resultSet.getColumnIndex(COLUMN_PROGRESS)),
        resultSet.getString(resultSet.getColumnIndex(COLUMN_PROGRESS_MODE)),
        0,
        resultSet.getLong(resultSet.getColumnIndex(COLUMN_REMINDER_OFFSET_MINUTES)),
        DeadlineDatabaseService.normalizeHours(hours),
        DeadlineCloudCompatibility.remainingState(hours, state, confirmedAt),
        confirmedAt
      );
    } catch (error) {
      throw new Error(`Unable to map deadline row: ${JSON.stringify(error)}`);
    }
  }

  private static normalizeProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(progress)));
  }

  private static normalizeHours(hours: number): number {
    if (!Number.isFinite(hours) || hours < 0) {
      return 0;
    }
    return Math.round(hours * 10) / 10;
  }

  private static normalizeReminderOffset(offsetMinutes: number): number {
    if (offsetMinutes === 60 || offsetMinutes === 1440 || offsetMinutes === 4320) {
      return offsetMinutes;
    }
    return 0;
  }

  private static fromSubtaskResultSet(resultSet: relationalStore.ResultSet): DeadlineSubtask {
    try {
      return new DeadlineSubtask(
        resultSet.getString(resultSet.getColumnIndex('id')),
        resultSet.getString(resultSet.getColumnIndex('deadline_id')),
        resultSet.getString(resultSet.getColumnIndex('title')),
        resultSet.getLong(resultSet.getColumnIndex('completed')) === 1,
        resultSet.getLong(resultSet.getColumnIndex('created_at')),
        resultSet.getString(resultSet.getColumnIndex('parent_id')),
        resultSet.getLong(resultSet.getColumnIndex('sort_order'))
      );
    } catch (error) {
      throw new Error(`Unable to map subtask row: ${JSON.stringify(error)}`);
    }
  }

  private static toSubtaskValues(subtask: DeadlineSubtask): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      id: subtask.id,
      deadline_id: subtask.deadlineId,
      title: subtask.title,
      completed: subtask.completed ? 1 : 0,
      created_at: subtask.createdAt,
      parent_id: subtask.parentId,
      sort_order: subtask.sortOrder
    };
    return values;
  }

  private static sameDeadline(first: Deadline, second: Deadline): boolean {
    return first.id === second.id && first.name === second.name && first.type === second.type &&
      first.deadlineDate === second.deadlineDate && first.deadlineTime === second.deadlineTime &&
      first.note === second.note && first.createdAt === second.createdAt &&
      first.deadlineAt === second.deadlineAt && first.completed === second.completed &&
      first.estimatedHours === second.estimatedHours && first.progress === second.progress &&
      first.progressMode === second.progressMode &&
      first.reminderOffsetMinutes === second.reminderOffsetMinutes &&
      first.remainingHours === second.remainingHours && first.remainingState === second.remainingState &&
      first.remainingUpdatedAt === second.remainingUpdatedAt;
  }

  private static sameSubtasks(first: DeadlineSubtask[], second: DeadlineSubtask[]): boolean {
    if (first.length !== second.length) {
      return false;
    }
    const expected: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
    for (let index: number = 0; index < second.length; index++) {
      expected.set(second[index].id, second[index]);
    }
    if (expected.size !== second.length) {
      return false;
    }
    for (let index: number = 0; index < first.length; index++) {
      const current: DeadlineSubtask = first[index];
      const old: DeadlineSubtask | undefined = expected.get(current.id);
      if (old === undefined || current.deadlineId !== old.deadlineId || current.title !== old.title ||
        current.completed !== old.completed || current.createdAt !== old.createdAt ||
        current.parentId !== old.parentId || current.sortOrder !== old.sortOrder) {
        return false;
      }
    }
    return true;
  }

  private static async queryTransactionDeadline(transaction: relationalStore.Transaction,
    deadlineId: string): Promise<Deadline | undefined> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo(COLUMN_ID, deadlineId);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await transaction.query(predicates, ALL_COLUMNS);
      return resultSet.goToNextRow() ? DeadlineDatabaseService.fromResultSet(resultSet) : undefined;
    } catch (error) {
      throw new Error(`Unable to check current deadline: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  private static async queryTransactionSubtasks(transaction: relationalStore.Transaction,
    deadlineId: string): Promise<DeadlineSubtask[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
    predicates.equalTo('deadline_id', deadlineId);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const tasks: DeadlineSubtask[] = [];
    try {
      resultSet = await transaction.query(predicates, SUBTASK_COLUMNS);
      while (resultSet.goToNextRow()) {
        tasks.push(DeadlineDatabaseService.fromSubtaskResultSet(resultSet));
      }
      return tasks;
    } catch (error) {
      throw new Error(`Unable to check current tasks: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  private static async countSubtasks(store: relationalStore.RdbStore, deadlineId: string): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
    predicates.equalTo('deadline_id', deadlineId);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    let count: number = 0;
    try {
      resultSet = await store.query(predicates, ['id']);
      while (resultSet.goToNextRow()) {
        count++;
      }
    } catch (error) {
      throw new Error(`Unable to count tasks for ${deadlineId}: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
    return count;
  }

  private static async queryDeadlines(store: relationalStore.RdbStore | relationalStore.Transaction): Promise<Deadline[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.orderByAsc(COLUMN_DEADLINE_AT);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const deadlines: Deadline[] = [];
    try {
      resultSet = await store.query(predicates, ALL_COLUMNS);
      while (resultSet.goToNextRow()) {
        deadlines.push(DeadlineDatabaseService.fromResultSet(resultSet));
      }
    } catch (error) {
      throw new Error(`Unable to query deadline rows: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
    return deadlines;
  }

  private static async queryAllSubtasks(store: relationalStore.RdbStore | relationalStore.Transaction): Promise<DeadlineSubtask[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
    predicates.orderByAsc('created_at');
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const subtasks: DeadlineSubtask[] = [];
    try {
      resultSet = await store.query(predicates, SUBTASK_COLUMNS);
      while (resultSet.goToNextRow()) {
        subtasks.push(DeadlineDatabaseService.fromSubtaskResultSet(resultSet));
      }
    } catch (error) {
      throw new Error(`Unable to query subtask rows: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
    return subtasks;
  }

  private static async holdUnresolvedEstimates(store: relationalStore.RdbStore | relationalStore.Transaction,
    deadlines: Deadline[]): Promise<void> {
    try {
      const rows: relationalStore.ResultSet = await store.query(new relationalStore.RdbPredicates(SYNC_ISSUES), ['id']);
      const held: Set<string> = new Set<string>();
      try { while (rows.goToNextRow()) { held.add(rows.getString(0)); } } finally { rows.close(); }
      deadlines.forEach((d: Deadline) => {
        if (held.has('__projection__') || held.has(d.id)) { d.remainingState = 'unknown'; }
      });
    } catch (error) { throw new Error(`Unable to check unresolved sync data: ${JSON.stringify(error)}`); }
  }

  static async getDeadlineDataSnapshot(context: common.UIAbilityContext): Promise<DeadlineDataSnapshot> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      let deadlines: Deadline[] = [];
      let subtasks: DeadlineSubtask[] = [];
      try {
        deadlines = await DeadlineDatabaseService.queryDeadlines(transaction);
        subtasks = await DeadlineDatabaseService.queryAllSubtasks(transaction);
        const invalidTrees: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SYNC_ISSUES);
        invalidTrees.equalTo('detail', '["legacy_tree"]');
        const badRows: relationalStore.ResultSet = await transaction.query(invalidTrees, ['id']);
        const badIds: Set<string> = new Set<string>();
        try { while (badRows.goToNextRow()) { badIds.add(badRows.getString(0)); } } finally { badRows.close(); }
        subtasks = subtasks.filter((t: DeadlineSubtask) => !badIds.has(t.deadlineId));
        await DeadlineDatabaseService.holdUnresolvedEstimates(transaction, deadlines);
        await transaction.commit();
      } catch (error) {
        await transaction.rollback();
        throw new Error(`Unable to read a consistent snapshot: ${JSON.stringify(error)}`);
      }
      const taskCounts: Map<string, number> = new Map<string, number>();
      for (let index: number = 0; index < subtasks.length; index++) {
        const deadlineId: string = subtasks[index].deadlineId;
        taskCounts.set(deadlineId, (taskCounts.get(deadlineId) ?? 0) + 1);
      }
      for (let index: number = 0; index < deadlines.length; index++) {
        deadlines[index].taskCount = taskCounts.get(deadlines[index].id) ?? 0;
      }
      return new DeadlineDataSnapshot(deadlines, subtasks);
    } catch (error) {
      console.error(`Failed to query deadline data snapshot: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to query deadline data: ${JSON.stringify(error)}`);
    }
  }

  static async insertDeadline(context: common.UIAbilityContext, deadline: Deadline): Promise<void> {
    try {
      await DeadlineDatabaseService.saveDeadlineWithSubtasks(context, deadline, [], false);
    } catch (error) {
      console.error(`Failed to insert deadline: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to insert deadline: ${JSON.stringify(error)}`);
    }
  }

  static async saveDeadlineWithSubtasks(context: common.UIAbilityContext, deadline: Deadline,
    subtasks: DeadlineSubtask[], isEditMode: boolean, expectedDeadline?: Deadline,
    expectedSubtasks?: DeadlineSubtask[]): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const syncBefore: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, deadline.id);
        if (isEditMode) {
          const currentDeadline: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(
            transaction, deadline.id
          );
          const currentSubtasks: DeadlineSubtask[] = await DeadlineDatabaseService.queryTransactionSubtasks(
            transaction, deadline.id
          );
          if (expectedDeadline === undefined || expectedSubtasks === undefined ||
            currentDeadline === undefined || !DeadlineDatabaseService.sameDeadline(currentDeadline, expectedDeadline) ||
            !DeadlineDatabaseService.sameSubtasks(currentSubtasks, expectedSubtasks)) {
            throw new DeadlineDataConflictError();
          }
          const deadlinePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
          deadlinePredicates.equalTo(COLUMN_ID, deadline.id);
          const updatedRows: number = await transaction.update(
            DeadlineDatabaseService.toValuesBucket(deadline),
            deadlinePredicates
          );
          if (updatedRows === 0) {
            throw new Error('No deadline was updated.');
          }
          // Preserve unchanged task rows and their cloud identities. A name/date edit
          // must not generate a delete/reinsert for every task.
          const nextIds: Set<string> = new Set<string>();
          for (let index: number = 0; index < subtasks.length; index++) {
            const task: DeadlineSubtask = subtasks[index];
            if (task.deadlineId !== deadline.id || nextIds.has(task.id)) {
              throw new Error('Invalid task draft.');
            }
            nextIds.add(task.id);
          }
          for (let index: number = 0; index < currentSubtasks.length; index++) {
            if (!nextIds.has(currentSubtasks[index].id)) {
              const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
              predicates.equalTo('id', currentSubtasks[index].id);
              await transaction.delete(predicates);
            }
          }
          for (let index: number = 0; index < subtasks.length; index++) {
            const task: DeadlineSubtask = subtasks[index];
            const previous: DeadlineSubtask | undefined = currentSubtasks.find((item: DeadlineSubtask) => item.id === task.id);
            if (previous === undefined) {
              await transaction.insert(SUBTASK_TABLE_NAME, DeadlineDatabaseService.toSubtaskValues(task),
                relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
            } else if (!DeadlineDatabaseService.sameSubtasks([previous], [task])) {
              const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
              predicates.equalTo('id', task.id);
              await transaction.update(DeadlineDatabaseService.toSubtaskValues(task), predicates);
            }
          }
        } else {
          const rowId: number = await transaction.insert(
            TABLE_NAME,
            DeadlineDatabaseService.toValuesBucket(deadline),
            relationalStore.ConflictResolution.ON_CONFLICT_ABORT
          );
          if (rowId === -1) {
            throw new Error('The database did not insert the deadline.');
          }
        }

        for (let index: number = 0; !isEditMode && index < subtasks.length; index++) {
          await transaction.insert(
            SUBTASK_TABLE_NAME,
            DeadlineDatabaseService.toSubtaskValues(subtasks[index]),
            relationalStore.ConflictResolution.ON_CONFLICT_ABORT
          );
        }
        await DeadlineDatabaseService.appendSyncEvent(transaction, deadline.id, syncBefore);
        await transaction.commit();
      } catch (transactionError) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back deadline draft save: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
        if (transactionError instanceof DeadlineDataConflictError) {
          throw transactionError;
        }
        throw new Error(`Deadline draft transaction failed: ${JSON.stringify(transactionError)}`);
      }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      console.error(`Failed to save deadline with tasks: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to save deadline with tasks: ${JSON.stringify(error)}`);
    }
  }

  static async commitTaskChanges(context: common.UIAbilityContext, deadlineId: string,
    previousTasks: DeadlineSubtask[], nextTasks: DeadlineSubtask[], progress: number,
    expectedDeadline: Deadline): Promise<void> {
    const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
    let transaction: relationalStore.Transaction | undefined = undefined;
    try {
      transaction = await store.createTransaction();
      const currentDeadline: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(
        transaction, deadlineId);
      const currentTasks: DeadlineSubtask[] = await DeadlineDatabaseService.queryTransactionSubtasks(
        transaction, deadlineId
      );
      const syncBefore: SyncAggregate | undefined = currentDeadline === undefined ? undefined :
        new SyncAggregate(currentDeadline, currentTasks);
      if (currentDeadline === undefined ||
        !DeadlineDatabaseService.sameDeadline(currentDeadline, expectedDeadline) ||
        !DeadlineDatabaseService.sameSubtasks(currentTasks, previousTasks)) {
        throw new DeadlineDataConflictError();
      }
      const previousById: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
      const nextById: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
      for (let index: number = 0; index < previousTasks.length; index++) {
        previousById.set(previousTasks[index].id, previousTasks[index]);
      }
      for (let index: number = 0; index < nextTasks.length; index++) {
        const task: DeadlineSubtask = nextTasks[index];
        if (task.deadlineId !== deadlineId || nextById.has(task.id)) {
          throw new Error('Invalid task changes.');
        }
        nextById.set(task.id, task);
      }
      for (let index: number = 0; index < previousTasks.length; index++) {
        const task: DeadlineSubtask = previousTasks[index];
        if (!nextById.has(task.id)) {
          const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
          predicates.equalTo('id', task.id);
          if (await transaction.delete(predicates) !== 1) {
            throw new DeadlineDataConflictError();
          }
        }
      }
      for (let index: number = 0; index < nextTasks.length; index++) {
        const task: DeadlineSubtask = nextTasks[index];
        const previous: DeadlineSubtask | undefined = previousById.get(task.id);
        if (previous === undefined) {
          await transaction.insert(SUBTASK_TABLE_NAME, DeadlineDatabaseService.toSubtaskValues(task),
            relationalStore.ConflictResolution.ON_CONFLICT_ABORT);
        } else if (task.title !== previous.title || task.completed !== previous.completed ||
          task.parentId !== previous.parentId || task.sortOrder !== previous.sortOrder) {
          const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
          predicates.equalTo('id', task.id);
          if (await transaction.update(DeadlineDatabaseService.toSubtaskValues(task), predicates) !== 1) {
            throw new DeadlineDataConflictError();
          }
        }
      }
      const deadlinePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      deadlinePredicates.equalTo(COLUMN_ID, deadlineId);
      if (await transaction.update({ progress: DeadlineDatabaseService.normalizeProgress(progress) },
        deadlinePredicates) !== 1) {
        throw new DeadlineDataConflictError();
      }
      await DeadlineDatabaseService.appendSyncEvent(transaction, deadlineId, syncBefore);
      await transaction.commit();
    } catch (error) {
      if (transaction !== undefined) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back task change: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
      }
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      throw new Error(`Unable to commit task changes: ${JSON.stringify(error)}`);
    }
  }

  static async getAllDeadlines(context: common.UIAbilityContext): Promise<Deadline[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const deadlines: Deadline[] = await DeadlineDatabaseService.queryDeadlines(store);
      await DeadlineDatabaseService.holdUnresolvedEstimates(store, deadlines);
      for (let index: number = 0; index < deadlines.length; index++) {
        deadlines[index].taskCount = await DeadlineDatabaseService.countSubtasks(store, deadlines[index].id);
      }
      return deadlines;
    } catch (error) {
      console.error(`Failed to query deadlines: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to query deadlines: ${JSON.stringify(error)}`);
    }
  }

  static async getDeadlinesForReminderSync(context: common.UIAbilityContext): Promise<Deadline[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const deadlines: Deadline[] = await DeadlineDatabaseService.queryDeadlines(store);
      await DeadlineDatabaseService.holdUnresolvedEstimates(store, deadlines);
      return deadlines;
    } catch (error) {
      throw new Error(`Unable to query deadlines for reminder sync: ${JSON.stringify(error)}`);
    }
  }

  static async getDeadlineById(context: common.UIAbilityContext, id: string): Promise<Deadline | undefined> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo(COLUMN_ID, id);
      const resultSet: relationalStore.ResultSet = await store.query(predicates, ALL_COLUMNS);
      let deadline: Deadline | undefined = undefined;
      try {
        if (resultSet.goToNextRow()) {
          deadline = DeadlineDatabaseService.fromResultSet(resultSet);
        }
      } finally {
        resultSet.close();
      }
      if (deadline !== undefined) {
        deadline.taskCount = await DeadlineDatabaseService.countSubtasks(store, deadline.id);
        await DeadlineDatabaseService.holdUnresolvedEstimates(store, [deadline]);
      }
      return deadline;
    } catch (error) {
      console.error(`Failed to query deadline ${id}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to query deadline: ${JSON.stringify(error)}`);
    }
  }

  static async updateDeadline(context: common.UIAbilityContext, deadline: Deadline): Promise<number> {
    try {
      const current: Deadline | undefined = await DeadlineDatabaseService.getDeadlineById(context, deadline.id);
      if (current === undefined) { return 0; }
      const tasks: DeadlineSubtask[] = await DeadlineDatabaseService.getSubtasks(context, deadline.id);
      await DeadlineDatabaseService.saveDeadlineWithSubtasks(context, deadline, tasks, true, current, tasks);
      return 1;
    } catch (error) {
      console.error(`Failed to update deadline ${deadline.id}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to update deadline: ${JSON.stringify(error)}`);
    }
  }

  static async updateRemainingEstimate(context: common.UIAbilityContext, expected: Deadline,
    hours: number, state: string, updatedAt: number): Promise<void> {
    const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
    let transaction: relationalStore.Transaction | undefined = undefined;
    try {
      transaction = await store.createTransaction();
      const syncBefore: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, expected.id);
      const current: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(transaction, expected.id);
      if (current === undefined || !DeadlineDatabaseService.sameDeadline(current, expected)) {
        throw new DeadlineDataConflictError();
      }
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo(COLUMN_ID, expected.id);
      const values: relationalStore.ValuesBucket = {
        remaining_hours: DeadlineDatabaseService.normalizeHours(hours),
        remaining_state: state,
        remaining_updated_at: updatedAt
      };
      if (await transaction.update(values, predicates) !== 1) {
        throw new DeadlineDataConflictError();
      }
      await DeadlineDatabaseService.appendSyncEvent(transaction, expected.id, syncBefore);
      await transaction.commit();
    } catch (error) {
      if (transaction !== undefined) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back remaining estimate update: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
      }
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      throw new Error(`Unable to update remaining estimate: ${JSON.stringify(error)}`);
    }
  }

  private static async updateFieldsIfUnchanged(context: common.UIAbilityContext, expected: Deadline,
    values: relationalStore.ValuesBucket): Promise<number> {
    let transaction: relationalStore.Transaction | undefined = undefined;
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      transaction = await store.createTransaction();
      const syncBefore: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, expected.id);
      const current: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(transaction, expected.id);
      if (current === undefined || !DeadlineDatabaseService.sameDeadline(current, expected)) {
        throw new DeadlineDataConflictError();
      }
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo(COLUMN_ID, expected.id);
      const rows: number = await transaction.update(values, predicates);
      if (rows !== 1) {
        throw new DeadlineDataConflictError();
      }
      await DeadlineDatabaseService.appendSyncEvent(transaction, expected.id, syncBefore);
      await transaction.commit();
      return rows;
    } catch (error) {
      if (transaction !== undefined) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Unable to roll back deadline fields: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
      }
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      throw new Error(`Unable to update current deadline fields: ${JSON.stringify(error)}`);
    }
  }

  static async updateCompleted(context: common.UIAbilityContext, expected: Deadline, completed: boolean): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {
        completed: completed ? 1 : 0,
        remaining_state: 'unknown'
      };
      return await DeadlineDatabaseService.updateFieldsIfUnchanged(context, expected, values);
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      console.error(`Failed to update completed state for ${expected.id}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to update completed state: ${JSON.stringify(error)}`);
    }
  }

  static async updateProgress(context: common.UIAbilityContext, expected: Deadline, progress: number): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {
        progress: DeadlineDatabaseService.normalizeProgress(progress)
      };
      return await DeadlineDatabaseService.updateFieldsIfUnchanged(context, expected, values);
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      console.error(`Failed to update progress for ${expected.id}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to update progress: ${JSON.stringify(error)}`);
    }
  }

  static async getSubtasks(context: common.UIAbilityContext, deadlineId: string): Promise<DeadlineSubtask[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
      predicates.equalTo('deadline_id', deadlineId);
      predicates.orderByAsc('created_at');
      const resultSet: relationalStore.ResultSet = await store.query(predicates, SUBTASK_COLUMNS);
      const subtasks: DeadlineSubtask[] = [];
      try {
        while (resultSet.goToNextRow()) {
          subtasks.push(DeadlineDatabaseService.fromSubtaskResultSet(resultSet));
        }
      } finally {
        resultSet.close();
      }
      return subtasks;
    } catch (error) {
      console.error(`Failed to query subtasks for ${deadlineId}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to query subtasks: ${JSON.stringify(error)}`);
    }
  }

  static async getAllSubtasks(context: common.UIAbilityContext): Promise<DeadlineSubtask[]> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      return await DeadlineDatabaseService.queryAllSubtasks(store);
    } catch (error) {
      console.error(`Failed to query all subtasks: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to query all subtasks: ${JSON.stringify(error)}`);
    }
  }

  static async getReminderState(context: common.UIAbilityContext,
    deadlineId: string): Promise<DeadlineReminderState | undefined> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(REMINDER_STATE_TABLE_NAME);
      predicates.equalTo('deadline_id', deadlineId);
      resultSet = await store.query(predicates, ['deadline_id', 'reminder_id', 'scheduled_at', 'signature']);
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return new DeadlineReminderState(
        resultSet.getString(resultSet.getColumnIndex('deadline_id')),
        resultSet.getLong(resultSet.getColumnIndex('reminder_id')),
        resultSet.getLong(resultSet.getColumnIndex('scheduled_at')),
        resultSet.getString(resultSet.getColumnIndex('signature'))
      );
    } catch (error) {
      throw new Error(`Unable to query reminder state for ${deadlineId}: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  static async getAllReminderStates(context: common.UIAbilityContext): Promise<DeadlineReminderState[]> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const states: DeadlineReminderState[] = [];
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      resultSet = await store.query(
        new relationalStore.RdbPredicates(REMINDER_STATE_TABLE_NAME),
        ['deadline_id', 'reminder_id', 'scheduled_at', 'signature']
      );
      while (resultSet.goToNextRow()) {
        states.push(new DeadlineReminderState(
          resultSet.getString(resultSet.getColumnIndex('deadline_id')),
          resultSet.getLong(resultSet.getColumnIndex('reminder_id')),
          resultSet.getLong(resultSet.getColumnIndex('scheduled_at')),
          resultSet.getString(resultSet.getColumnIndex('signature'))
        ));
      }
      return states;
    } catch (error) {
      throw new Error(`Unable to query reminder states: ${JSON.stringify(error)}`);
    } finally {
      DeadlineDatabaseService.closeResultSet(resultSet);
    }
  }

  static async saveReminderState(context: common.UIAbilityContext, state: DeadlineReminderState): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const rowId: number = await store.insert(
        REMINDER_STATE_TABLE_NAME,
        {
          deadline_id: state.deadlineId,
          reminder_id: state.reminderId,
          scheduled_at: state.scheduledAt,
          signature: state.signature
        },
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      if (rowId === -1) {
        throw new Error('The database did not save the reminder state.');
      }
    } catch (error) {
      throw new Error(`Unable to save reminder state for ${state.deadlineId}: ${JSON.stringify(error)}`);
    }
  }

  static async deleteReminderState(context: common.UIAbilityContext, deadlineId: string): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(REMINDER_STATE_TABLE_NAME);
      predicates.equalTo('deadline_id', deadlineId);
      await store.delete(predicates);
    } catch (error) {
      throw new Error(`Unable to delete reminder state for ${deadlineId}: ${JSON.stringify(error)}`);
    }
  }

  static async deleteDeadline(context: common.UIAbilityContext, expected: Deadline): Promise<number> {
    const id: string = expected.id;
    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        const syncBefore: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, id);
        const current: Deadline | undefined = await DeadlineDatabaseService.queryTransactionDeadline(transaction, id);
        if (current === undefined || !DeadlineDatabaseService.sameDeadline(current, expected)) {
          throw new DeadlineDataConflictError();
        }
        const subtaskPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates(SUBTASK_TABLE_NAME);
        subtaskPredicates.equalTo('deadline_id', id);
        await transaction.delete(subtaskPredicates);
        const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo(COLUMN_ID, id);
        const deletedRows: number = await transaction.delete(predicates);
        await DeadlineDatabaseService.appendSyncEvent(transaction, id, syncBefore);
        await transaction.commit();
        return deletedRows;
      } catch (transactionError) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back deadline deletion: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
        if (transactionError instanceof DeadlineDataConflictError) {
          throw transactionError;
        }
        throw new Error(`Deadline deletion transaction failed: ${JSON.stringify(transactionError)}`);
      }
    } catch (error) {
      if (error instanceof DeadlineDataConflictError) {
        throw error;
      }
      console.error(`Failed to delete deadline ${id}: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to delete deadline: ${JSON.stringify(error)}`);
    }
  }

  static async importDeadlines(context: common.UIAbilityContext, deadlines: Deadline[]): Promise<void> {
    if (deadlines.length === 0) {
      return;
    }

    try {
      const store: relationalStore.RdbStore = await DeadlineDatabaseService.getStore(context);
      const transaction: relationalStore.Transaction = await store.createTransaction();
      try {
        for (let index: number = 0; index < deadlines.length; index++) {
          const syncBefore: SyncAggregate | undefined = await DeadlineDatabaseService.captureAggregate(transaction, deadlines[index].id);
          await transaction.insert(
            TABLE_NAME,
            DeadlineDatabaseService.toValuesBucket(deadlines[index]),
            relationalStore.ConflictResolution.ON_CONFLICT_IGNORE
          );
          if (syncBefore === undefined) {
            await DeadlineDatabaseService.appendSyncEvent(transaction, deadlines[index].id, undefined);
          }
        }
        await transaction.commit();
      } catch (transactionError) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error(`Failed to roll back deadline migration: ${CloudDiagnostic.code(rollbackError as Object)}`);
        }
        throw new Error(`Deadline migration transaction failed: ${JSON.stringify(transactionError)}`);
      }
    } catch (error) {
      console.error(`Failed to import legacy deadlines: ${CloudDiagnostic.code(error as Object)}`);
      throw new Error(`Unable to import legacy deadlines: ${JSON.stringify(error)}`);
    }
  }
}
