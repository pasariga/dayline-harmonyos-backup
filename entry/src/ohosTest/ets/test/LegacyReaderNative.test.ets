import { describe, beforeAll, afterAll, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Source } from '../../../test/LegacySnapshotReader.test';
import { FrozenLegacyRead, LegacyJournalRow, LegacyReadControl, LegacySnapshotReader } from '../../../main/ets/services/LegacySnapshotReader';
import { LegacyCloudData, LegacyCloudImport, LegacyDeadlineRow, LegacyImportTrust } from '../../../main/ets/services/LegacyCloudImport';
import { DeadlineDatabaseService } from '../../../main/ets/services/DeadlineDatabaseService';
import { DeadlineSyncEvent, SyncAggregate } from '../../../main/ets/services/DeadlineSyncProtocol';

// Device-only, synthetic account/source. No Account Kit or AGC calls are made.
export default function legacyReaderNativeTest() {
  describe('legacyReaderNative', () => {
    let context: common.UIAbilityContext;
    let store: relationalStore.RdbStore;
    const account: string = 'fixture-reader-account';
    const prefix: string = 'native-reader-' + util.generateRandomUUID(true);
    const sources: Source[] = [];
    const source = (suffix: string): Source => {
      const s = new Source(); const id: string = prefix + '-' + suffix;
      s.data.deadlines[0].id = id;
      s.data.tasks.forEach((t, index: number) => { t.id = id + '-' + index; t.deadline_id = id; t.parent_id = index === 0 ? '' : id + '-0'; });
      s.data.manifests[0].deadlineId = id; s.data.manifests[0].taskIds = s.data.tasks.map((t) => t.id);
      s.d.accountId = account; s.d.sourceId = id; s.d.deadlines.ids = [id]; s.d.tasks.ids = s.data.manifests[0].taskIds;
      s.mutate = (p) => { p.accountId = account; };
      sources.push(s); return s;
    };
    const counts = async (): Promise<string> => {
      const rows = await store.querySql('SELECT (SELECT count(*) FROM deadlines), (SELECT count(*) FROM deadline_subtasks), ' +
        '(SELECT count(*) FROM ddl_sync_events), (SELECT count(*) FROM ddl_sync_archive), (SELECT count(*) FROM ddl_legacy_imports), ' +
        '(SELECT count(*) FROM ddl_sync_owner)');
      try { rows.goToNextRow(); return [0,1,2,3,4,5].map((i: number) => rows.getLong(i)).join(','); } finally { rows.close(); }
    };
    const stage = async (r: FrozenLegacyRead): Promise<string> => {
      return await DeadlineDatabaseService.stageLegacyCloudImport(context,
        new LegacyImportTrust(account, r.accountId, r.sourceId, r.complete, r.oldWritesStopped, r.journalComplete), r.payload, r.journal);
    };
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      context = (await delegator.getCurrentTopAbility()).context;
      await DeadlineDatabaseService.getAllDeadlines(context);
      expect(await DeadlineDatabaseService.getSyncOwner(context)).assertEqual('');
      store = await relationalStore.getRdbStore(context, { name: 'ddl.db', securityLevel: relationalStore.SecurityLevel.S1 });
    });
    afterAll(async () => {
      if (store === undefined) { return; }
      await store.execute('DROP TRIGGER IF EXISTS native_reader_abort');
      const items = await DeadlineDatabaseService.getAllDeadlines(context);
      for (const d of items.filter((d) => d.id.startsWith(prefix))) { await DeadlineDatabaseService.deleteDeadline(context, d); }
      // Only this synthetic test session's staging and ownership are removed.
      await store.execute('DELETE FROM ddl_legacy_imports WHERE account_id = ?', [account]);
      await store.execute("DELETE FROM ddl_sync_owner WHERE id = 'owner' AND account_id = ?", [account]);
    });
    it('native interrupted pages leave every persistent table unchanged', 0, async () => {
      const before = await counts(); const s = source('interrupted'); s.fail = true;
      let failed: boolean = false;
      try { await stage(await LegacySnapshotReader.collect(s, async () => account)); } catch (error) { failed = true; }
      expect(failed).assertTrue(); expect(await counts()).assertEqual(before);
    });
    it('native complete history is durable before importing old live rows', 0, async () => {
      const s = source('complete'); const row: LegacyDeadlineRow = JSON.parse(JSON.stringify(s.data.deadlines[0])) as LegacyDeadlineRow;
      row.id = prefix + '-deleted';
      const rootData: LegacyCloudData = { deadlines: [row], tasks: [], manifests: [{ deadlineId: row.id, taskIds: [] }] };
      const a: SyncAggregate = LegacyCloudImport.plan(JSON.stringify(rootData)).items[0].event?.snapshot as SyncAggregate;
      const root = new DeadlineSyncEvent(prefix + '-root', row.id, [], undefined, a);
      const deleted = new DeadlineSyncEvent(prefix + '-tomb', row.id, [root.id], undefined, undefined);
      s.history = [root, deleted].map((e: DeadlineSyncEvent): LegacyJournalRow =>
        ({ id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) }));
      s.d.journal.ids = s.history.map((r) => r.id);
      s.data.deadlines.push(row); s.d.deadlines.ids.push(row.id); s.d.manifests.push({ deadlineId: row.id, taskIds: [] });
      const r = await LegacySnapshotReader.collect(s, async () => account);
      expect(await stage(r)).assertEqual('done');
      const items = await DeadlineDatabaseService.getAllDeadlines(context);
      expect(items.some((d) => d.id === row.id)).assertFalse();
      const current = items.find((d) => d.id === s.data.deadlines[0].id);
      expect(current?.estimatedHours).assertEqual(10); expect(current?.remainingState).assertEqual('unknown');
      expect(current?.progress).assertEqual(100);
      expect((await DeadlineDatabaseService.getSubtasks(context, s.data.deadlines[0].id)).length).assertEqual(2);
      const stable = await counts();
      for (let i: number = 0; i < 10; i++) { expect(await stage(r)).assertEqual('done'); }
      expect(await counts()).assertEqual(stable);
    });
    it('native staging ABORT rolls back transport archive owner and batch together', 0, async () => {
      const s = source('abort'); const a = LegacyCloudImport.plan(JSON.stringify(s.data)).items[0].event?.snapshot as SyncAggregate;
      const e = new DeadlineSyncEvent(prefix + '-abort-root', a.deadline.id, [], undefined, a);
      s.history = [{ id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) }]; s.d.journal.ids = [e.id];
      const r = await LegacySnapshotReader.collect(s, async () => account); const before = await counts();
      await store.execute("CREATE TRIGGER native_reader_abort BEFORE INSERT ON ddl_legacy_imports WHEN NEW.kind='batch' " +
        "BEGIN SELECT RAISE(ABORT, 'native reader staging failure'); END");
      let failed: boolean = false;
      try { await stage(r); } catch (error) { failed = true; }
      finally { await store.execute('DROP TRIGGER IF EXISTS native_reader_abort'); }
      expect(failed).assertTrue(); expect(await counts()).assertEqual(before);
      expect(await stage(r)).assertEqual('done');
      const stable = await counts(); expect(await stage(r)).assertEqual('done'); expect(await counts()).assertEqual(stable);
    });
    it('native immutable archive mismatch never overwrites previously saved content', 0, async () => {
      const s = sources.find((s) => s.d.sourceId.endsWith('-abort')) as Source;
      const r = await LegacySnapshotReader.collect(s, async () => account);
      const altered = JSON.parse(r.journal[0].payload) as DeadlineSyncEvent;
      if (altered.snapshot !== undefined) { altered.snapshot.deadline.name = 'Unsafe replacement'; }
      r.journal[0].payload = JSON.stringify(altered);
      const before = await counts(); let failed: boolean = false;
      try { await stage(r); } catch (error) { failed = true; }
      expect(failed).assertTrue(); expect(await counts()).assertEqual(before);
      const current = (await DeadlineDatabaseService.getAllDeadlines(context)).find((d) => d.id === altered.deadlineId);
      expect(current?.name).assertEqual('Exam');
    });
    it('native cancellation and source-account mismatch do not create a batch', 0, async () => {
      const s = source('cancel'); const c = new LegacyReadControl(); const before = await counts();
      s.onSeal = () => { c.cancelled = true; }; let failed: boolean = false;
      try { await stage(await LegacySnapshotReader.collect(s, async () => account, c)); } catch (error) { failed = true; }
      expect(failed).assertTrue(); expect(await counts()).assertEqual(before);
      const other = source('other-account'); const r = await LegacySnapshotReader.collect(other, async () => account);
      r.accountId = 'B'; failed = false;
      try { await stage(r); } catch (error) { failed = true; }
      expect(failed).assertTrue(); expect(await counts()).assertEqual(before);
    });
  });
}
