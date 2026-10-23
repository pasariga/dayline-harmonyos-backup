import { describe, beforeAll, afterAll, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { AgcShadowReadAdapter } from '../../../main/ets/services/AgcShadowReadAdapter';
import { AgcShadowInspection, AgcShadowLocal } from '../../../main/ets/services/AgcShadowInspection';
import { ShadowSource } from '../../../test/AgcShadow.test';
import { CloudAccountService } from '../../../main/ets/services/CloudAccountService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LegacyReadControl } from '../../../main/ets/services/LegacySnapshotReader';

// Real local ResultSets and private receiver; Account Kit availability probe
// only, no AGC call. SQL fixtures are not reported as real cloud samples.
export default function agcShadowNativeTest() {
  describe('agcShadowNative', () => {
    let context: common.UIAbilityContext;
    let store: relationalStore.RdbStore;
    const view: AgcShadowLocal = { owner: '', aggregates: [], events: [] };
    const counts = async (): Promise<string> => {
      const rows = await store.querySql('SELECT count(*) FROM deadlines');
      try { rows.goToNextRow(); return String(rows.getLong(0)); } finally { rows.close(); }
    };
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      context = (await delegator.getCurrentTopAbility()).context;
      store = await relationalStore.getRdbStore(context, { name: 'shadow-native.db', securityLevel: relationalStore.SecurityLevel.S1 });
      await store.execute('CREATE TABLE IF NOT EXISTS deadlines (id TEXT PRIMARY KEY,name TEXT,deadline_date TEXT,deadline_time TEXT,' +
        'deadline_at INTEGER,created_at INTEGER,completed INTEGER,estimated_hours REAL,progress_mode TEXT,remaining_hours REAL)');
      await store.execute('DELETE FROM deadlines');
      await store.insert('deadlines', { id: 'native-shadow-d', name: 'Synthetic exam', deadline_date: '2026-11-01',
        deadline_time: '18:00', deadline_at: 1793527200000, created_at: 1791000000000,
        completed: 0, estimated_hours: 10, progress_mode: 'automatic', remaining_hours: null });
      await store.execute('CREATE TABLE IF NOT EXISTS shadow_control (id TEXT PRIMARY KEY, armed INTEGER)');
    });
    afterAll(async () => {
      if (store === undefined) { return; }
      const rows = await store.querySql("SELECT armed FROM shadow_control WHERE id = 'pause'");
      let armed: boolean = false;
      try { armed = rows.goToNextRow() && rows.getLong(0) === 1; } finally { rows.close(); }
      if (armed) {
        const source = new ShadowSource(); let calls: number = 0;
        source.onPage = () => {
          calls++;
          if (calls === 3) {
            source.hang = true;
            hilog.info(0x0D11, 'DDLShadow', 'SHADOW_PAUSE_READY');
          }
        };
        // Host arms only this independent test DB, waits for the marker, kills
        // the App, and verifies original DB hashes. Never registered in main UI.
        await AgcShadowInspection.collect(source, async () => 'synthetic-A', new LegacyReadControl(120000));
      }
      await store.close();
    });
    it('native encrypted same-name receiver is physically isolated and does not enable download', 0, async () => {
      const receiver = await AgcShadowReadAdapter.openReceiver(context); let held: boolean = false;
      try { await receiver.begin(); } catch (error) { held = true; } finally { await receiver.close(); }
      expect(held).assertTrue(); expect(await counts()).assertEqual('1');
    });
    it('native nullable ResultSet maps total ten and unknown remaining without touching the source', 0, async () => {
      const s = new ShadowSource(); const o = s.observation(); o.deadlines = await AgcShadowReadAdapter.readRows(store, 'deadlines'); o.tasks = [];
      const before = JSON.stringify(o); const r = AgcShadowInspection.analyze(o, view, 'synthetic-A');
      expect(r.items[0].classification).assertEqual('baseline_candidate'); expect(r.statistics.nullFields).assertEqual(1);
      expect(r.summary().importAllowed).assertFalse(); expect(JSON.stringify(o)).assertEqual(before); expect(await counts()).assertEqual('1');
    });
    it('native read failure leaves every source row intact and a retry yields the same summary', 0, async () => {
      const s = new ShadowSource(); s.fail = true; let failed: boolean = false;
      const before = (await AgcShadowReadAdapter.readRows(store, 'deadlines')).join();
      try { await AgcShadowInspection.collect(s, async () => 'synthetic-A'); } catch (error) { failed = true; }
      expect(failed).assertTrue(); s.fail = false;
      const a = await AgcShadowInspection.collect(s, async () => 'synthetic-A');
      const b = await AgcShadowInspection.collect(s, async () => 'synthetic-A'); expect(JSON.stringify(a)).assertEqual(JSON.stringify(b));
      expect((await AgcShadowReadAdapter.readRows(store, 'deadlines')).join()).assertEqual(before);
    });
    it('native twenty shadow scans and reopening source do not change its rows', 0, async () => {
      const s = new ShadowSource(); const o = s.observation(); const before = (await AgcShadowReadAdapter.readRows(store, 'deadlines')).join();
      const summary = JSON.stringify(AgcShadowInspection.analyze(o, view, 'synthetic-A').summary());
      for (let i: number = 0; i < 20; i++) { expect(JSON.stringify(AgcShadowInspection.analyze(o, view, 'synthetic-A').summary())).assertEqual(summary); }
      await store.close(); store = await relationalStore.getRdbStore(context, { name: 'shadow-native.db', securityLevel: relationalStore.SecurityLevel.S1 });
      expect((await AgcShadowReadAdapter.readRows(store, 'deadlines')).join()).assertEqual(before);
    });
    it('native real read gate blocks before authentication network or cloud registration', 0, async () => {
      let held: boolean = false;
      try { await AgcShadowReadAdapter.read(context); } catch (error) { held = true; }
      expect(held).assertTrue(); expect(await counts()).assertEqual('1');
    });
    it('native current Account Kit identity probe records availability only without binding the database', 0, async () => {
      const availability: string = await new Promise<string>((resolve) => {
        const timer: number = setTimeout(() => resolve('timeout'), 10000);
        CloudAccountService.getCurrentOpenId(context).then((identity: string) => {
          clearTimeout(timer); resolve(identity.length > 0 ? 'verified' : 'unavailable');
        }, () => { clearTimeout(timer); resolve('unavailable'); });
      });
      hilog.info(0x0D11, 'DDLShadow', 'ACCOUNT_PROBE=%{public}s', availability);
      expect(['verified','unavailable','timeout'].includes(availability)).assertTrue(); expect(await counts()).assertEqual('1');
    });
  });
}
