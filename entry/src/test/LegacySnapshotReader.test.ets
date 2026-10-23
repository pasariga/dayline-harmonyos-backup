import { describe, expect, it } from '@ohos/hypium';
import { FrozenLegacyRead, LegacyJournalRow, LegacyReadControl, LegacySnapshotDescriptor,
  LegacySnapshotPage, LegacySnapshotReader, LegacySnapshotSource } from '../main/ets/services/LegacySnapshotReader';
import { LegacyCloudData, LegacyCloudImport } from '../main/ets/services/LegacyCloudImport';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate } from '../main/ets/services/DeadlineSyncProtocol';
import { CloudProtocolPolicy } from '../main/ets/services/CloudProtocolPolicy';

export class Source implements LegacySnapshotSource {
  data: LegacyCloudData = { deadlines: [{ id: 'reader-x', name: 'Exam', deadline_date: '2026-11-01',
    deadline_time: '18:00', deadline_at: 1793527200000, created_at: 1791000000000, completed: 0,
    estimated_hours: 10, progress_mode: 'automatic' }], tasks: [
    { id: 'reader-p', deadline_id: 'reader-x', title: 'Preparation', created_at: 1, completed: 0 },
    { id: 'reader-t', deadline_id: 'reader-x', title: 'Review', created_at: 2, completed: 1, parent_id: 'reader-p' }
  ], manifests: [{ deadlineId: 'reader-x', taskIds: ['reader-p', 'reader-t'] }] };
  history: LegacyJournalRow[] = [];
  d: LegacySnapshotDescriptor = { accountId: 'A', sourceId: 'frozen-reader-1', revision: 'r1',
    boundaryId: 'server-rejects-old-writes', historySeal: 'complete-deletion-export', minimumProtocol: 2,
    oldWritesStopped: true, journal: { ids: [], pages: 1 }, deadlines: { ids: ['reader-x'], pages: 1 },
    tasks: { ids: ['reader-p', 'reader-t'], pages: 2 }, manifests: this.data.manifests };
  calls: string[] = [];
  mutate: (p: LegacySnapshotPage) => void = () => {};
  onPage: () => void = () => {};
  onSeal: () => void = () => {};
  fail: boolean = false;
  hang: boolean = false;
  async begin(accountId: string): Promise<LegacySnapshotDescriptor> { this.calls.push('begin'); return this.d; }
  async page(d: LegacySnapshotDescriptor, section: string, cursor: string): Promise<LegacySnapshotPage> {
    this.calls.push(section + ':' + cursor); this.onPage();
    if (this.fail && section === 'tasks') { throw new Error('Disconnected'); }
    if (this.hang) { return await new Promise<LegacySnapshotPage>(() => {}); }
    const index: number = cursor === '' ? 0 : Number(cursor);
    const all: string[] = section === 'journal' ? this.history.map((row: LegacyJournalRow) => JSON.stringify(row)) :
      section === 'deadlines' ? this.data.deadlines.map((row) => JSON.stringify(row)) : this.data.tasks.map((row) => JSON.stringify(row));
    const last: boolean = section !== 'tasks' || index === 1;
    const p: LegacySnapshotPage = { accountId: 'A', sourceId: this.d.sourceId, revision: this.d.revision, section: section,
      cursor: cursor, nextCursor: last ? '' : '1', finished: last, rows: section === 'tasks' ? [all[index]] : all };
    this.mutate(p); return p;
  }
  async seal(d: LegacySnapshotDescriptor): Promise<LegacySnapshotDescriptor> { this.calls.push('seal'); this.onSeal(); return this.d; }
}
async function rejected(s: Source, guard: () => Promise<string> = async () => 'A',
  c: LegacyReadControl = new LegacyReadControl()): Promise<boolean> {
  try { await LegacySnapshotReader.collect(s, guard, c); return false; } catch (error) { return true; }
}
function aggregate(s: Source): SyncAggregate {
  return LegacyCloudImport.plan(JSON.stringify(s.data)).items[0].event?.snapshot as SyncAggregate;
}
function addHistory(s: Source, e: DeadlineSyncEvent): void {
  const row: LegacyJournalRow = { id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) };
  s.history.push(row); s.d.journal.ids.push(row.id);
}

export default function legacySnapshotReaderTest() {
  describe('legacySnapshotReader', () => {
    it('reads every page before producing a complete tree with honest unknown hours', 0, async () => {
      const s = new Source(); const r = await LegacySnapshotReader.collect(s, async () => 'A');
      expect(s.calls.join(',')).assertEqual('begin,journal:,deadlines:,tasks:,tasks:1,seal');
      const plan = LegacyCloudImport.plan(r.payload);
      expect(plan.items[0].event?.snapshot?.tasks.length).assertEqual(2);
      expect(plan.items[0].event?.snapshot?.deadline.estimatedHours).assertEqual(10);
      expect(plan.items[0].event?.snapshot?.deadline.remainingState).assertEqual('unknown');
    });
    it('a disconnected second task page produces no usable import and can retry unchanged', 0, async () => {
      const s = new Source(); s.fail = true; expect(await rejected(s)).assertTrue();
      s.fail = false; const a = await LegacySnapshotReader.collect(s, async () => 'A');
      const b = await LegacySnapshotReader.collect(s, async () => 'A'); expect(a.payload).assertEqual(b.payload);
    });
    it('an early finished page cannot pretend the remaining task page is empty', 0, async () => {
      const s = new Source(); s.mutate = (p) => { if (p.section === 'tasks') { p.finished = true; p.nextCursor = ''; } };
      expect(await rejected(s)).assertTrue();
    });
    it('a missing declared task is detected even when every page says finished', 0, async () => {
      const s = new Source(); s.mutate = (p) => { if (p.cursor === '1') { p.rows = []; } };
      expect(await rejected(s)).assertTrue();
    });
    it('cursor loops and mismatched echoed cursors cannot create a complete export', 0, async () => {
      const s = new Source(); s.d.tasks.pages = 3;
      s.mutate = (p) => { if (p.section === 'tasks') { p.finished = false; p.nextCursor = '1'; } };
      expect(await rejected(s)).assertTrue();
      const other = new Source(); other.mutate = (p) => { p.cursor = 'wrong'; }; expect(await rejected(other)).assertTrue();
    });
    it('source revision changes between tables are rejected', 0, async () => {
      const s = new Source(); s.mutate = (p) => { if (p.section === 'tasks') { p.revision = 'r2'; } };
      expect(await rejected(s)).assertTrue();
    });
    it('a changed final freeze or history seal is rejected before saving', 0, async () => {
      const s = new Source(); s.onSeal = () => { s.d.historySeal = 'changed'; }; expect(await rejected(s)).assertTrue();
      const other = new Source(); other.onSeal = () => { other.d.oldWritesStopped = false; }; expect(await rejected(other)).assertTrue();
    });
    it('a stale server boundary and unsupported minimum protocol cannot begin a restore', 0, async () => {
      const s = new Source(); s.d.boundaryId = ''; expect(await rejected(s)).assertTrue();
      s.d.boundaryId = 'proof'; s.d.minimumProtocol = 1; expect(await rejected(s)).assertTrue();
    });
    it('empty history without deletion coverage is not a proof of no deletions', 0, async () => {
      const s = new Source(); s.d.historySeal = ''; expect(await rejected(s)).assertTrue();
      expect(s.calls.includes('deadlines:')).assertFalse();
    });
    it('account switch during a page rejects A rather than associating it with B', 0, async () => {
      const s = new Source(); let account: string = 'A'; s.onPage = () => { account = 'B'; };
      expect(await rejected(s, async () => account)).assertTrue(); expect(s.calls.includes('seal')).assertFalse();
    });
    it('a page from another account is rejected even when the session stays the same', 0, async () => {
      const s = new Source(); s.mutate = (p) => { p.accountId = 'B'; }; expect(await rejected(s)).assertTrue();
    });
    it('cancel during reading and at the final seal produces no candidate', 0, async () => {
      const s = new Source(); const c = new LegacyReadControl(); s.onPage = () => { c.cancelled = true; };
      expect(await rejected(s, async () => 'A', c)).assertTrue();
      const other = new Source(); const last = new LegacyReadControl(); other.onSeal = () => { last.cancelled = true; };
      expect(await rejected(other, async () => 'A', last)).assertTrue();
    });
    it('a stalled reader times out instead of marking partial pages complete', 0, async () => {
      const s = new Source(); s.hang = true; expect(await rejected(s, async () => 'A', new LegacyReadControl(10))).assertTrue();
    });
    it('a forged task owner and incomplete server task manifest are rejected', 0, async () => {
      const s = new Source(); s.data.tasks[1].deadline_id = 'other'; expect(await rejected(s)).assertTrue();
      const other = new Source(); other.d.manifests[0].taskIds = ['reader-p']; expect(await rejected(other)).assertTrue();
    });
    it('unknown declared records and duplicate manifest identities cannot be guessed', 0, async () => {
      const s = new Source(); s.mutate = (p) => { if (p.section === 'deadlines') { p.rows = ['{"id":"other"}']; } };
      expect(await rejected(s)).assertTrue(); const other = new Source(); other.d.tasks.ids.push('reader-p');
      expect(await rejected(other)).assertTrue();
    });
    it('independent bad business values remain visible to per-project quarantine', 0, async () => {
      const s = new Source(); s.data.deadlines.push({ id: 'bad', name: 'Bad', deadline_date: '2026-11-01',
        deadline_time: '18:00', deadline_at: 1, created_at: -1, completed: 0 });
      s.d.deadlines.ids.push('bad'); s.d.manifests.push({ deadlineId: 'bad', taskIds: [] });
      const r = await LegacySnapshotReader.collect(s, async () => 'A'); const p = LegacyCloudImport.plan(r.payload);
      expect(p.items.find((item) => item.id === 'bad')?.event === undefined).assertTrue();
      expect(p.items.find((item) => item.id === 'reader-x')?.event !== undefined).assertTrue();
    });
    it('complete history deletion wins over the old live business row', 0, async () => {
      const s = new Source(); const a = aggregate(s); addHistory(s, new DeadlineSyncEvent('reader-root', 'reader-x', [], undefined, a));
      addHistory(s, new DeadlineSyncEvent('reader-deleted', 'reader-x', ['reader-root'], undefined, undefined));
      const r = await LegacySnapshotReader.collect(s, async () => 'A'); const events = LegacySnapshotReader.validateJournal(r.journal);
      const old = LegacyCloudImport.plan(r.payload).items[0].event as DeadlineSyncEvent; events.push(old);
      expect(DeadlineSyncProtocol.merge(events, 'reader-x').deleted).assertTrue();
    });
    it('missing causal parents are rejected before old business pages are requested', 0, async () => {
      const s = new Source(); addHistory(s, new DeadlineSyncEvent('child', 'reader-x', ['missing'], aggregate(s), aggregate(s)));
      expect(await rejected(s)).assertTrue(); expect(s.calls.includes('deadlines:')).assertFalse();
    });
    it('a conflicting immutable row is rejected while identical repeats do not add history', 0, async () => {
      const s = new Source(); const a = aggregate(s); addHistory(s, new DeadlineSyncEvent('root', 'reader-x', [], undefined, a));
      s.history.push(s.history[0]); const r = await LegacySnapshotReader.collect(s, async () => 'A');
      expect(LegacySnapshotReader.validateJournal(r.journal).length).assertEqual(1);
      const b = DeadlineSyncProtocol.normalize(a); b.deadline.name = 'Changed';
      s.history[1] = { id: 'root', deadline_id: 'reader-x', payload: JSON.stringify(new DeadlineSyncEvent('root', 'reader-x', [], undefined, b)) };
      expect(await rejected(s)).assertTrue();
    });
    it('trusted historical carriers preserve parent identities but bare old writes are rejected', 0, async () => {
      const s = new Source(); const e = new DeadlineSyncEvent('old-root', 'reader-x', [], undefined, aggregate(s)); e.version = 1;
      s.history = [{ id: CloudProtocolPolicy.historicalId(e.id), deadline_id: e.deadlineId, payload: CloudProtocolPolicy.wrapHistorical(e) }];
      s.d.journal.ids = [s.history[0].id]; const r = await LegacySnapshotReader.collect(s, async () => 'A');
      expect(LegacySnapshotReader.validateJournal(r.journal)[0].id).assertEqual('old-root');
      s.history = [{ id: e.id, deadline_id: e.deadlineId, payload: JSON.stringify(e) }]; s.d.journal.ids = [e.id];
      expect(await rejected(s)).assertTrue();
    });
    it('independent project histories are validated separately', 0, async () => {
      const s = new Source(); addHistory(s, new DeadlineSyncEvent('root-x', 'reader-x', [], undefined, aggregate(s)));
      const other = DeadlineSyncProtocol.normalize(aggregate(s)); other.deadline.id = 'reader-y'; other.tasks = [];
      addHistory(s, new DeadlineSyncEvent('root-y', 'reader-y', [], undefined, other));
      const r = await LegacySnapshotReader.collect(s, async () => 'A');
      expect(LegacySnapshotReader.validateJournal(r.journal).length).assertEqual(2);
    });
    it('even deletion history cannot claim a complete export when its ancestry cycles', 0, async () => {
      const s = new Source(); addHistory(s, new DeadlineSyncEvent('a', 'reader-x', ['b'], aggregate(s), aggregate(s)));
      addHistory(s, new DeadlineSyncEvent('b', 'reader-x', ['a'], undefined, undefined));
      expect(await rejected(s)).assertTrue();
    });
  });
}
