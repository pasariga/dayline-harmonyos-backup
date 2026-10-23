import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CloudAccountService } from './CloudAccountService';
import { LegacyReadControl } from './LegacySnapshotReader';
import { AgcInspectionMetadata, AgcInspectionPage, AgcInspectionSource, AgcObservation,
  AgcShadowInspection } from './AgcShadowInspection';

// Native cloud registration uses the store name. Physical separation alone has
// not proved that a second ddl.db has an independent cloud registration. Keep
// the network branch closed until that AND actual container/account mapping are
// verified. This is separate from, and does not relax, the normal sync gate.
const AGC_READ_ISOLATION_VERIFIED: boolean = false;
const TABLES: string[] = ['ddl_sync_events', 'deadlines', 'deadline_subtasks'];
const COLUMNS: string[][] = [
  ['id TEXT PRIMARY KEY','deadline_id TEXT','payload TEXT'],
  ['id TEXT PRIMARY KEY','name TEXT','type TEXT','deadline_date TEXT','deadline_time TEXT',
    'deadline_at INTEGER','created_at INTEGER','completed INTEGER','note TEXT','estimated_hours REAL',
    'progress INTEGER','progress_mode TEXT','reminder_offset_minutes INTEGER','remaining_hours REAL',
    'remaining_state TEXT','remaining_updated_at INTEGER'],
  ['id TEXT PRIMARY KEY','deadline_id TEXT','title TEXT','completed INTEGER','created_at INTEGER','parent_id TEXT','sort_order INTEGER']
];

// A real ArkData receiver, NOT Cloud Foundation DatabaseZone.query(). It never
// obtains the application's business RdbStore or calls the migration service.
export class AgcShadowReadAdapter implements AgcInspectionSource {
  private store: relationalStore.RdbStore;
  private metadata: AgcInspectionMetadata;
  private pages: string[][] = [[], [], []];
  private started: boolean = false;
  private constructor(store: relationalStore.RdbStore, source: string) {
    this.store = store;
    this.metadata = { account: '', source: source, revision: '', accountAttested: false,
      writersStopped: false, deletionCoverage: false, treeAttested: false };
  }
  // Also used by device tests to prove physical isolation without making any
  // cloud call. Encryption protects raw inspection data in the private sandbox.
  static async openReceiver(context: common.Context): Promise<AgcShadowReadAdapter> {
    const directory: string = 'agc-inspection/' + util.generateRandomUUID(true);
    let store: relationalStore.RdbStore;
    try {
      store = await relationalStore.getRdbStore(context,
        { name: 'ddl.db', customDir: directory, securityLevel: relationalStore.SecurityLevel.S1,
          encrypt: true, allowRebuild: false, autoCleanDirtyData: false });
    } catch (error) { throw new Error('Inspection receiver unavailable.'); }
    try {
      const paths = await store.querySql('PRAGMA database_list');
      let isolated: boolean = false;
      try {
        while (paths.goToNextRow()) {
          if (paths.getString(1) === 'main') { isolated = paths.getString(2).endsWith('/' + directory + '/ddl.db'); }
        }
      } finally { paths.close(); }
      if (!isolated) { throw new Error('Inspection receiver is not isolated.'); }
      for (let i: number = 0; i < TABLES.length; i++) {
        await store.execute('CREATE TABLE ' + TABLES[i] + ' (' + COLUMNS[i].join(',') + ')');
      }
      return new AgcShadowReadAdapter(store, 'arkdata-cloud-first');
    } catch (error) {
      try { await store.close(); } catch (closeError) { throw new Error('Inspection receiver unavailable.'); }
      throw new Error('Inspection receiver unavailable.');
    }
  }
  static async read(context: common.UIAbilityContext, control: LegacyReadControl = new LegacyReadControl()): Promise<AgcObservation> {
    // Never substitute a saved ID for current Account Kit authentication.
    if (!AGC_READ_ISOLATION_VERIFIED) { throw new Error('AGC read isolation and source mapping require verification.'); }
    const verify = (): Promise<string> => CloudAccountService.getCurrentOpenId(context);
    const account: string = await verify();
    if (account.length === 0 || control.cancelled) { throw new Error('Inspection identity unavailable.'); }
    const source = await AgcShadowReadAdapter.openReceiver(context);
    source.metadata.account = account;
    try { return await AgcShadowInspection.collect(source, verify, control); }
    finally { await source.close(); }
  }
  async begin(): Promise<AgcInspectionMetadata> {
    try {
    if (!AGC_READ_ISOLATION_VERIFIED || this.started) { throw new Error('Inspection download is not enabled.'); }
    this.started = true;
    await this.store.setDistributedTables(TABLES, relationalStore.DistributedType.DISTRIBUTED_CLOUD,
      { autoSync: false, enableCloud: true });
    // CLOUD_FIRST is the documented cloud-to-device direction. Never use
    // TIME_FIRST, NATIVE_FIRST or the device-to-device PULL enum here.
    await new Promise<void>((resolve, reject) => {
      let requestDone: boolean = false; let finished: boolean = false; let settled: boolean = false;
      const timer: number = setTimeout(() => fail(), 30000);
      const fail = (): void => {
        if (!settled) { settled = true; clearTimeout(timer); reject(new Error('Inspection download incomplete.')); }
      };
      const finish = (): void => {
        if (requestDone && finished && !settled) { settled = true; clearTimeout(timer); resolve(); }
      };
      try {
        this.store.cloudSync(relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST, TABLES, (progress) => {
        if (progress.schedule !== relationalStore.Progress.SYNC_FINISH || settled) { return; }
        if (progress.code !== relationalStore.ProgressCode.SUCCESS || progress.details === undefined ||
          TABLES.some((table: string) => progress.details[table] === undefined ||
            progress.details[table].download === undefined || progress.details[table].upload === undefined ||
            progress.details[table].download.failed !== 0 || progress.details[table].upload.total !== 0)) { fail(); return; }
        finished = true; finish();
        }).then(() => { requestDone = true; finish(); }, () => fail());
      } catch (error) { fail(); }
    });
    await this.store.setDistributedTables(TABLES, relationalStore.DistributedType.DISTRIBUTED_CLOUD,
      { autoSync: false, enableCloud: false });
    for (let i: number = 0; i < TABLES.length; i++) { this.pages[i] = await AgcShadowReadAdapter.readRows(this.store, TABLES[i]); }
    // Native progress has no authenticated row owner, freeze revision, complete
    // deletion export or independent task manifest. Do not fabricate any of them.
    return this.metadata;
    } catch (error) { throw new Error('Inspection download unavailable; local data preserved.'); }
  }
  static async readRows(store: relationalStore.RdbStore, table: string): Promise<string[]> {
    if (!TABLES.includes(table)) { throw new Error('Unsupported inspection table.'); }
    const all: string[] = [];
    let rows: relationalStore.ResultSet;
    try { rows = await store.querySql('SELECT * FROM ' + table + ' ORDER BY id'); }
    catch (error) { throw new Error('Inspection table could not be read.'); }
    try {
      while (rows.goToNextRow()) {
        if (all.length >= 100000) { throw new Error('Inspection size limit.'); }
        const values = rows.getRow();
        // Preserve SQL NULL and column absence. Never coerce null to zero or
        // dates/progress to hours. Unknown fields go to the strict mapper.
        all.push(JSON.stringify(values));
      }
    } catch (error) { throw new Error('Inspection rows could not be read.'); }
    finally {
      try { rows.close(); } catch (error) { throw new Error('Inspection result could not be closed.'); }
    }
    return all;
  }
  async page(section: string, cursor: string): Promise<AgcInspectionPage> {
    if (!this.started) { throw new Error('Inspection has not started.'); }
    const index: number = ['journal','deadlines','tasks'].indexOf(section);
    const offset: number = cursor === '' ? 0 : Number(cursor);
    if (index < 0 || !Number.isSafeInteger(offset) || offset < 0 ||
      (cursor !== '' && (String(offset) !== cursor || offset % 200 !== 0))) { throw new Error('Invalid inspection cursor.'); }
    const all = this.pages[index]; const finished: boolean = offset + 200 >= all.length;
    return { account: this.metadata.account, source: this.metadata.source, section: section, cursor: cursor,
      nextCursor: finished ? '' : String(offset + 200), finished: finished, rows: all.slice(offset, offset + 200) };
  }
  async end(): Promise<AgcInspectionMetadata> { return this.metadata; }
  async close(): Promise<void> {
    // Even timed out operations can complete late, but only this private receiver
    // is in their closure. Nothing can call the main projection/import path.
    try {
      if (this.started) {
        await this.store.setDistributedTables(TABLES, relationalStore.DistributedType.DISTRIBUTED_CLOUD,
          { autoSync: false, enableCloud: false });
      }
    } catch (error) { throw new Error('Inspection cloud registration could not be stopped.'); }
    finally {
      this.pages = [[],[],[]];
      try { await this.store.close(); } catch (error) { throw new Error('Inspection receiver could not be closed.'); }
    }
  }
}
