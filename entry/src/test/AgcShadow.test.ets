import { describe, expect, it } from '@ohos/hypium';
import { AgcInspectionMetadata, AgcInspectionPage, AgcInspectionSource, AgcObservation,
  AgcShadowInspection, AgcShadowLocal } from '../main/ets/services/AgcShadowInspection';
import { LegacyReadControl } from '../main/ets/services/LegacySnapshotReader';
import { LegacyCloudData, LegacyCloudImport } from '../main/ets/services/LegacyCloudImport';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate } from '../main/ets/services/DeadlineSyncProtocol';
import { CloudDiagnostic } from '../main/ets/services/CloudDiagnostic';
import { CloudProtocolPolicy } from '../main/ets/services/CloudProtocolPolicy';
interface DiagnosticFixture { code: number; message: string; token: string; }

// Deliberately synthetic attestation. This fixture cannot serve as an AGC proof.
export class ShadowSource implements AgcInspectionSource {
  metadata: AgcInspectionMetadata = { account: 'synthetic-A', source: 'synthetic-export', revision: 'r1',
    accountAttested: true, writersStopped: true, deletionCoverage: true, treeAttested: true };
  data: LegacyCloudData = { deadlines: [{ id: 'shadow-d', name: 'Synthetic exam', deadline_date: '2026-11-01',
    deadline_time: '18:00', deadline_at: 1793527200000, created_at: 1791000000000, completed: 0,
    estimated_hours: 10, progress_mode: 'automatic' }], tasks: [
    { id: 'shadow-p', deadline_id: 'shadow-d', title: 'Parent', completed: 0, created_at: 1 },
    { id: 'shadow-t', deadline_id: 'shadow-d', title: 'Small task', completed: 1, created_at: 2, parent_id: 'shadow-p' }
  ], manifests: [{ deadlineId: 'shadow-d', taskIds: ['shadow-p','shadow-t'] }] };
  events: DeadlineSyncEvent[] = [];
  mutate: (page: AgcInspectionPage) => void = () => {};
  onPage: () => void = () => {};
  fail: boolean = false;
  hang: boolean = false;
  changeEnd: boolean = false;
  async begin(): Promise<AgcInspectionMetadata> { return this.metadata; }
  async page(section: string, cursor: string): Promise<AgcInspectionPage> {
    this.onPage();
    if (this.fail) { throw new Error('synthetic token=secret user content'); }
    if (this.hang) { return await new Promise<AgcInspectionPage>(() => {}); }
    const all: string[] = section === 'journal' ? this.events.map((e) => JSON.stringify(
      { id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) })) : section === 'deadlines' ?
      this.data.deadlines.map((r) => JSON.stringify(r)) : this.data.tasks.map((r) => JSON.stringify(r));
    const offset: number = cursor === '' ? 0 : Number(cursor); const finished: boolean = offset + 1 >= all.length;
    const page: AgcInspectionPage = { account: this.metadata.account, source: this.metadata.source, section: section,
      cursor: cursor, nextCursor: finished ? '' : String(offset + 1), finished: finished, rows: all.slice(offset, offset + 1) };
    this.mutate(page); return page;
  }
  async end(): Promise<AgcInspectionMetadata> {
    if (this.changeEnd) { this.metadata.revision = 'r2'; }
    return this.metadata;
  }
  observation(): AgcObservation {
    return { metadata: this.metadata, deadlines: this.data.deadlines.map((r) => JSON.stringify(r)),
      tasks: this.data.tasks.map((r) => JSON.stringify(r)), journal: this.events.map((e) => JSON.stringify(
        { id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) })) };
  }
  aggregate(): SyncAggregate { return LegacyCloudImport.plan(JSON.stringify(this.data)).items[0].event?.snapshot as SyncAggregate; }
}
function empty(): AgcShadowLocal { return { owner: '', aggregates: [], events: [] }; }
function local(s: ShadowSource): AgcShadowLocal {
  const a = s.aggregate(); return { owner: s.metadata.account, aggregates: [a],
    events: [new DeadlineSyncEvent('shadow-root', a.deadline.id, [], undefined, a)] };
}
function classify(s: ShadowSource, l: AgcShadowLocal = empty()): string {
  return AgcShadowInspection.analyze(s.observation(), l, s.metadata.account).items[0].classification;
}
async function reject(s: ShadowSource, verify: () => Promise<string> = async () => 'synthetic-A',
  control: LegacyReadControl = new LegacyReadControl()): Promise<string> {
  try { await AgcShadowInspection.collect(s, verify, control); return ''; }
  catch (error) { return (error as Error).message; }
}
export default function agcShadowTest() {
  describe('agcShadow', () => {
    it('raw SQL columns normalize without completion-count hours or null zero evidence', 0, () => {
      const s = new ShadowSource(); s.data.deadlines[0].remaining_hours = null;
      const a = s.aggregate(); expect(a.deadline.estimatedHours).assertEqual(10);
      expect(a.deadline.remainingState).assertEqual('unknown'); expect(a.deadline.progress).assertEqual(100);
      const r = AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A');
      expect(r.statistics.nullFields).assertEqual(1); expect(r.statistics.missingFields).assertEqual(2);
      expect(r.summary().importAllowed).assertFalse();
    });
    it('a fully attested synthetic fresh row is only a simulated baseline', 0, () => {
      expect(classify(new ShadowSource())).assertEqual('baseline_candidate');
    });
    it('missing V6 estimate fields agree with local known six without clearing them', 0, () => {
      const s = new ShadowSource(); const l = local(s); l.aggregates[0].deadline.remainingHours = 6;
      l.aggregates[0].deadline.remainingState = 'confirmed'; l.aggregates[0].deadline.remainingUpdatedAt = 1791000000001;
      expect(classify(s, l)).assertEqual('local_equal'); expect(l.aggregates[0].deadline.remainingHours).assertEqual(6);
    });
    it('unsequenced old different name requires confirmation never a timestamp winner', 0, () => {
      const s = new ShadowSource(); const l = local(s); s.data.deadlines[0].name = 'Other name';
      s.data.deadlines[0].created_at = 9999999999999;
      expect(classify(s, l)).assertEqual('conflict_confirmation');
    });
    it('six versus nine is a complete estimate conflict', 0, () => {
      const s = new ShadowSource(); const row = s.data.deadlines[0];
      row.remaining_hours = 6; row.remaining_state = 'confirmed'; row.remaining_updated_at = 1791000000001;
      const l = local(s); row.remaining_hours = 9;
      expect(classify(s, l)).assertEqual('conflict_confirmation'); expect(l.aggregates[0].deadline.remainingHours).assertEqual(6);
    });
    it('local causal successor is newer despite a smaller clock', 0, () => {
      const s = new ShadowSource(); const l = local(s); const root = l.events[0]; s.events = [root]; s.data.deadlines = [];
      const a = DeadlineSyncProtocol.normalize(l.aggregates[0]); a.deadline.name = 'New local'; a.deadline.createdAt = 1;
      l.events.push(new DeadlineSyncEvent('local-child', root.deadlineId, [root.id], root.snapshot, a)); l.aggregates = [a];
      expect(classify(s, l)).assertEqual('local_newer');
    });
    it('cloud causal successor is newer without relying on remaining confirmation time', 0, () => {
      const s = new ShadowSource(); const l = local(s); const root = l.events[0]; const a = DeadlineSyncProtocol.normalize(l.aggregates[0]);
      a.deadline.name = 'New cloud'; s.events = [root, new DeadlineSyncEvent('cloud-child', root.deadlineId, [root.id], root.snapshot, a)];
      s.data.deadlines = []; expect(classify(s, l)).assertEqual('cloud_newer');
    });
    it('newer event history cannot hide a disagreeing old business snapshot from the same scan', 0, () => {
      const s = new ShadowSource(); const l = local(s); const root = l.events[0];
      const a = DeadlineSyncProtocol.normalize(l.aggregates[0]); a.deadline.name = 'Causal cloud name';
      s.events = [root, new DeadlineSyncEvent('cloud-child', root.deadlineId, [root.id], root.snapshot, a)];
      s.data.deadlines[0].name = 'Different old business name';
      expect(classify(s, l)).assertEqual('conflict_confirmation');
    });
    it('a changed already-imported baseline is held rather than silently accepted as a new source', 0, () => {
      const s = new ShadowSource(); const old = LegacyCloudImport.plan(JSON.stringify(s.data)).items[0].event as DeadlineSyncEvent;
      const l: AgcShadowLocal = { owner: 'synthetic-A', aggregates: [s.aggregate()], events: [old] };
      s.data.deadlines[0].name = 'Mutable old source'; expect(classify(s, l)).assertEqual('cannot_decide');
    });
    it('different fields can simulate safe merge while same-field branches cannot', 0, () => {
      const s = new ShadowSource(); const l = local(s); const root = l.events[0]; const a = DeadlineSyncProtocol.normalize(l.aggregates[0]);
      const b = DeadlineSyncProtocol.normalize(a); a.deadline.name = 'Local name'; b.deadline.note = 'Cloud note';
      l.events.push(new DeadlineSyncEvent('la', root.deadlineId, [root.id], root.snapshot, a)); l.aggregates = [a];
      s.events = [root, new DeadlineSyncEvent('cb', root.deadlineId, [root.id], root.snapshot, b)]; s.data.deadlines = [];
      expect(classify(s, l)).assertEqual('safe_merge'); b.deadline.name = 'Cloud name';
      expect(classify(s, l)).assertEqual('conflict_confirmation');
    });
    it('local permanent deletion suppresses old live rows without requiring a cloud absence', 0, () => {
      const s = new ShadowSource(); const l = local(s);
      l.events.push(new DeadlineSyncEvent('tomb', 'shadow-d', ['shadow-root'], undefined, undefined)); l.aggregates = [];
      expect(classify(s, l)).assertEqual('local_tombstone');
    });
    it('unread cloud rows never delete an existing local project', 0, () => {
      const s = new ShadowSource(); const l = local(s); const before = JSON.stringify(l);
      s.data.deadlines = []; s.data.tasks = []; expect(classify(s, l)).assertEqual('cannot_decide');
      expect(JSON.stringify(l)).assertEqual(before);
    });
    it('empty history is not proof that old deleted records may be restored', 0, () => {
      const s = new ShadowSource(); s.metadata.deletionCoverage = false;
      expect(classify(s)).assertEqual('history_insufficient');
    });
    it('a successful download without freeze or independent manifest cannot be an import proof', 0, () => {
      const s = new ShadowSource(); s.metadata.writersStopped = false; s.metadata.revision = ''; s.metadata.treeAttested = false;
      const r = AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A');
      expect(r.items[0].classification).assertEqual('cannot_decide'); expect(r.blockers.includes('source_not_frozen')).assertTrue();
      expect(r.summary().importAllowed).assertFalse();
    });
    it('same current account does not attest the native SDK row account', 0, () => {
      const s = new ShadowSource(); s.metadata.accountAttested = false;
      const r = AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A');
      expect(r.blockers.includes('source_account_unattested')).assertTrue(); expect(r.summary().importAllowed).assertFalse();
    });
    it('A observation cannot enter B analysis and another database owner cannot be rebound', 0, () => {
      const s = new ShadowSource();
      expect(AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-B').items[0].classification).assertEqual('account_mismatch');
      const l = empty(); l.owner = 'synthetic-B'; expect(classify(s, l)).assertEqual('account_mismatch'); expect(l.owner).assertEqual('synthetic-B');
    });
    it('malformed JSON and changed duplicate identities are rejected without choosing a last row', 0, () => {
      const s = new ShadowSource(); const o = s.observation(); o.deadlines.push('{bad');
      expect(AgcShadowInspection.analyze(o, empty(), 'synthetic-A').items[0].classification).assertEqual('malformed_cloud');
      o.deadlines.pop(); const d = s.data.deadlines[0]; d.name = 'Changed'; o.deadlines.push(JSON.stringify(d));
      expect(AgcShadowInspection.analyze(o, empty(), 'synthetic-A').items[0].classification).assertEqual('malformed_cloud');
    });
    it('identical duplicate pages collapse deterministically', 0, () => {
      const s = new ShadowSource(); const o = s.observation(); o.tasks.push(o.tasks[0]);
      const r = AgcShadowInspection.analyze(o, empty(), 'synthetic-A');
      expect(r.statistics.duplicateRows).assertEqual(1); expect(r.items[0].classification).assertEqual('baseline_candidate');
      const a = s.aggregate(); s.events = [new DeadlineSyncEvent('duplicate-root', 'shadow-d', [], undefined, a)];
      const journal = s.observation(); journal.journal.push(journal.journal[0]);
      const once = AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A');
      const twice = AgcShadowInspection.analyze(journal, empty(), 'synthetic-A');
      expect(twice.statistics.duplicateRows).assertEqual(1);
      expect(twice.items[0].classification).assertEqual(once.items[0].classification);
    });
    it('missing parent and orphan task stay incomplete', 0, () => {
      const s = new ShadowSource(); s.data.tasks.shift(); expect(classify(s)).assertEqual('incomplete_cloud');
      s.data.tasks[0].deadline_id = 'absent';
      expect(AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A').statistics.orphanTasks).assertEqual(1);
    });
    it('missing causal ancestors cannot be hidden by completed paging', 0, () => {
      const s = new ShadowSource(); const a = s.aggregate(); s.events = [new DeadlineSyncEvent('child', 'shadow-d', ['missing'], a, a)];
      expect(classify(s)).assertEqual('history_insufficient');
    });
    it('bare protocol one history is not promoted to trusted protocol two', 0, () => {
      const s = new ShadowSource(); const e = new DeadlineSyncEvent('old', 'shadow-d', [], undefined, s.aggregate());
      e.version = 1; s.events = [e]; expect(classify(s)).assertEqual('malformed_cloud');
      const o = s.observation(); o.journal = [JSON.stringify({ id: CloudProtocolPolicy.historicalId(e.id),
        deadline_id: e.deadlineId, payload: CloudProtocolPolicy.wrapHistorical(e) })];
      expect(AgcShadowInspection.analyze(o, empty(), 'synthetic-A').items[0].classification).assertEqual('baseline_candidate');
    });
    it('paging collects all sections before an observation is released', 0, async () => {
      const s = new ShadowSource(); const o = await AgcShadowInspection.collect(s, async () => 'synthetic-A');
      expect(o.tasks.length).assertEqual(2); expect(o.deadlines.length).assertEqual(1);
    });
    it('repeated cursor and wrong page source are rejected', 0, async () => {
      const s = new ShadowSource(); s.mutate = (p) => { if (p.section === 'tasks') { p.finished = false; p.nextCursor = '1'; } };
      expect((await reject(s)).length > 0).assertTrue();
      s.mutate = (p) => { p.source = 'different'; }; expect((await reject(s)).length > 0).assertTrue();
    });
    it('account switch or lost authentication during a page releases no A observation', 0, async () => {
      const s = new ShadowSource(); let account: string = 'synthetic-A'; s.onPage = () => { account = 'synthetic-B'; };
      expect((await reject(s, async () => account)).length > 0).assertTrue();
      expect((await reject(new ShadowSource(), async () => '')).length > 0).assertTrue();
    });
    it('changed source freeze at final seal rejects the scan', 0, async () => {
      const s = new ShadowSource(); s.changeEnd = true; expect((await reject(s)).length > 0).assertTrue();
    });
    it('interrupted read and retry leave inputs untouched with no token in errors', 0, async () => {
      const s = new ShadowSource(); s.fail = true; const text = await reject(s);
      expect(text.includes('secret')).assertFalse(); expect(text.length > 0).assertTrue(); s.fail = false;
      const a = await AgcShadowInspection.collect(s, async () => 'synthetic-A');
      const b = await AgcShadowInspection.collect(s, async () => 'synthetic-A'); expect(JSON.stringify(a)).assertEqual(JSON.stringify(b));
    });
    it('timeout and cancellation discard partial scan', 0, async () => {
      const s = new ShadowSource(); s.hang = true; expect((await reject(s, async () => 'synthetic-A', new LegacyReadControl(5))).length > 0).assertTrue();
      const other = new ShadowSource(); const c = new LegacyReadControl(); other.onPage = () => { c.cancelled = true; };
      expect((await reject(other, async () => 'synthetic-A', c)).length > 0).assertTrue();
    });
    it('twenty scans and a reconstructed reader produce stable summaries and no mutation', 0, () => {
      const s = new ShadowSource(); const l = local(s); const before = JSON.stringify(l); const raw = JSON.stringify(s.observation());
      const expected = JSON.stringify(AgcShadowInspection.analyze(s.observation(), l, 'synthetic-A').summary());
      for (let i: number = 0; i < 20; i++) {
        expect(JSON.stringify(AgcShadowInspection.analyze(JSON.parse(raw) as AgcObservation,
          JSON.parse(before) as AgcShadowLocal, 'synthetic-A').summary())).assertEqual(expected);
      }
      expect(JSON.stringify(l)).assertEqual(before); expect(JSON.stringify(s.observation())).assertEqual(raw);
    });
    it('anonymous report and cloud diagnostics exclude accounts user content token and stack', 0, () => {
      const s = new ShadowSource(); const output = JSON.stringify(AgcShadowInspection.analyze(s.observation(), empty(), 'synthetic-A').summary());
      ['synthetic-A','Synthetic exam','shadow-d','Small task'].forEach((text: string) => expect(output.includes(text)).assertFalse());
      const failure = new Error('access token SECRET and user text');
      expect(CloudDiagnostic.code(failure)).assertEqual('code=unavailable');
      const fixture: DiagnosticFixture = { code: 1001502003, message: 'SECRET', token: 'SECRET' };
      expect(CloudDiagnostic.code(fixture)).assertEqual('code=1001502003');
    });
  });
}
