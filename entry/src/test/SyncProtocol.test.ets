import { describe, it, expect } from '@ohos/hypium';
import { Deadline, DeadlineSubtask } from '../main/ets/models/Deadline';
import { DeadlineSyncProtocol, DeadlineSyncEvent, SyncAggregate, SyncMergeResult } from
  '../main/ets/services/DeadlineSyncProtocol';

function snapshot(): SyncAggregate {
  return new SyncAggregate(new Deadline('d', 'Exam', 'exam', '2026-11-01', '18:00', '', 100,
    100000, false, 10, 0, 'automatic', 0, 30, 10, 'initial', 100),
    [new DeadlineSubtask('p', 'd', 'Parent', false, 100),
      new DeadlineSubtask('t', 'd', 'Small task', false, 101, 'p')]);
}
function copy(source: SyncAggregate): SyncAggregate {
  return DeadlineSyncProtocol.normalize(JSON.parse(JSON.stringify(source)) as SyncAggregate);
}
function root(): DeadlineSyncEvent { return new DeadlineSyncEvent('r', 'd', [], undefined, snapshot()); }
function update(id: string, next: SyncAggregate): DeadlineSyncEvent {
  return new DeadlineSyncEvent(id, 'd', ['r'], snapshot(), next);
}
function ordered(events: DeadlineSyncEvent[]): SyncMergeResult {
  const a: SyncMergeResult = DeadlineSyncProtocol.merge(events, 'd');
  const b: SyncMergeResult = DeadlineSyncProtocol.merge(events.slice().reverse(), 'd');
  expect(JSON.stringify(a)).assertEqual(JSON.stringify(b));
  return a;
}
function rejects(source: SyncAggregate): boolean {
  try { DeadlineSyncProtocol.normalize(source); return false; } catch (error) { return true; }
}

export default function syncProtocolTest() {
  describe('syncProtocol', () => {
    it('idempotent repeated event', 0, () => {
      const r: DeadlineSyncEvent = root();
      expect(JSON.stringify(ordered([r, r]).aggregate)).assertEqual(JSON.stringify(snapshot()));
    });
    it('new causal title survives old replay in both orders', 0, () => {
      const next: SyncAggregate = copy(snapshot()); next.deadline.name = 'New';
      expect(ordered([root(), update('a', next)]).aggregate?.deadline.name).assertEqual('New');
    });
    it('older descendant date cannot win using wall clock', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'First'; a.deadline.createdAt = 9999999;
      const b: SyncAggregate = copy(a); b.deadline.name = 'Latest causal'; b.deadline.createdAt = 1;
      const event: DeadlineSyncEvent = new DeadlineSyncEvent('b', 'd', ['a'], a, b);
      expect(ordered([root(), update('a', a), event]).aggregate?.deadline.name).assertEqual('Latest causal');
    });
    it('concurrent due and remaining tuple merge', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.deadlineDate = '2026-11-02';
      a.deadline.deadlineTime = '20:00'; a.deadline.deadlineAt = 200000;
      const b: SyncAggregate = copy(snapshot()); b.deadline.remainingHours = 6;
      b.deadline.remainingState = 'confirmed'; b.deadline.remainingUpdatedAt = 200;
      const result: SyncAggregate | undefined = ordered([root(), update('a', a), update('b', b)]).aggregate;
      expect(result?.deadline.deadlineDate).assertEqual('2026-11-02');
      expect(result?.deadline.deadlineAt).assertEqual(200000);
      expect(result?.deadline.remainingHours).assertEqual(6);
      expect(result?.deadline.remainingState).assertEqual('confirmed');
      expect(result?.deadline.remainingUpdatedAt).assertEqual(200);
      expect(result?.deadline.estimatedHours).assertEqual(10);
    });
    it('concurrent title and task completion coexist', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'Renamed';
      const b: SyncAggregate = copy(snapshot()); b.tasks[1].completed = true; b.deadline.progress = 100;
      const result: SyncAggregate | undefined = ordered([root(), update('a', a), update('b', b)]).aggregate;
      expect(result?.deadline.name).assertEqual('Renamed'); expect(result?.tasks[1].completed).assertTrue();
      expect(result?.deadline.remainingHours).assertEqual(10);
    });
    it('concurrent same field retains explicit conflict', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(snapshot()); b.deadline.name = 'B';
      const result: SyncMergeResult = ordered([root(), update('a', a), update('b', b)]);
      expect(result.aggregate === undefined).assertTrue(); expect(result.conflicts.join()).assertEqual('name');
    });
    it('concurrent equal writes coalesce', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'Same';
      expect(ordered([root(), update('a', a), update('b', a)]).aggregate?.deadline.name).assertEqual('Same');
    });
    it('remaining hours state and time cannot hybrid merge', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.remainingHours = 6;
      a.deadline.remainingState = 'confirmed'; a.deadline.remainingUpdatedAt = 200;
      const b: SyncAggregate = copy(snapshot()); b.deadline.remainingState = 'unknown'; b.deadline.remainingUpdatedAt = 300;
      expect(ordered([root(), update('a', a), update('b', b)]).conflicts.join()).assertEqual('remaining');
    });
    it('concurrent due tuple cannot hybrid merge', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.deadlineDate = '2026-11-02';
      const b: SyncAggregate = copy(snapshot()); b.deadline.deadlineTime = '12:00';
      expect(ordered([root(), update('a', a), update('b', b)]).conflicts.join()).assertEqual('due');
    });
    it('same task conflicting edits require review', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks[1].title = 'Changed';
      const b: SyncAggregate = copy(snapshot()); b.tasks[1].completed = true;
      expect(ordered([root(), update('a', a), update('b', b)]).conflicts.join()).assertEqual('task:t');
    });
    it('different tasks safely merge', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks[0].title = 'New parent';
      const b: SyncAggregate = copy(snapshot()); b.tasks[1].completed = true;
      const result: SyncAggregate | undefined = ordered([root(), update('a', a), update('b', b)]).aggregate;
      expect(result?.tasks[0].title).assertEqual('New parent'); expect(result?.tasks[1].completed).assertTrue();
    });
    it('unrelated later edit does not implicitly resolve conflict', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(snapshot()); b.deadline.name = 'B';
      const c: SyncAggregate = copy(a); c.deadline.note = 'Another edit';
      const e: DeadlineSyncEvent = new DeadlineSyncEvent('c', 'd', ['a', 'b'], a, c);
      expect(ordered([root(), update('a', a), update('b', b), e]).conflicts.join()).assertEqual('name');
    });
    it('explicit changed field after all heads resolves that field', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(snapshot()); b.deadline.name = 'B';
      const c: SyncAggregate = copy(a); c.deadline.name = 'Reviewed';
      const e: DeadlineSyncEvent = new DeadlineSyncEvent('c', 'd', ['a', 'b'], a, c);
      expect(ordered([root(), update('a', a), update('b', b), e]).aggregate?.deadline.name).assertEqual('Reviewed');
    });
    it('deadline delete wins concurrent stale edit both orders', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'Offline';
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('delete', 'd', ['r'], snapshot(), undefined);
      expect(ordered([root(), update('a', a), del]).deleted).assertTrue();
    });
    it('delete stays absorbing after a late descendant edit', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks[1].completed = true;
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('delete', 'd', ['r'], snapshot(), undefined);
      const stale: DeadlineSyncEvent = new DeadlineSyncEvent('stale', 'd', ['a'], a, copy(snapshot()));
      expect(ordered([root(), update('a', a), del, stale, del]).deleted).assertTrue();
    });
    it('delete applies before its ancestors arrive', 0, () => {
      expect(ordered([new DeadlineSyncEvent('delete', 'd', ['missing'], snapshot(), undefined)]).deleted).assertTrue();
    });
    it('valid delete cannot be blocked by malformed unrelated event', 0, () => {
      const bad: DeadlineSyncEvent = update('bad', snapshot()); bad.parents = ['bad'];
      expect(ordered([bad, new DeadlineSyncEvent('delete', 'd', [], snapshot(), undefined)]).deleted).assertTrue();
    });
    it('task delete wins stale completed task', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks = a.tasks.filter((t: DeadlineSubtask) => t.id !== 't');
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('delete', 'd', ['r'], snapshot(), a, ['t']);
      const b: SyncAggregate = copy(snapshot()); b.tasks[1].completed = true;
      expect(ordered([root(), del, update('b', b)]).aggregate?.tasks.length).assertEqual(1);
    });
    it('parent task delete removes a late new child', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks = [];
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('delete', 'd', ['r'], snapshot(), a, ['p', 't']);
      const b: SyncAggregate = copy(snapshot()); b.tasks.push(new DeadlineSubtask('late', 'd', 'Late', false, 200, 'p'));
      const result: SyncMergeResult = ordered([root(), del, update('b', b)]);
      expect(result.aggregate?.tasks.length).assertEqual(0); expect(result.removedTasks.includes('late')).assertTrue();
    });
    it('task tombstone preserved during unrelated title conflict', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A'; a.tasks = [a.tasks[0]];
      const b: SyncAggregate = copy(snapshot()); b.deadline.name = 'B';
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('delete', 'd', ['r'], snapshot(), a, ['t']);
      const result: SyncMergeResult = ordered([root(), del, update('b', b)]);
      expect(result.conflicts.join()).assertEqual('name'); expect(result.removedTasks.includes('t')).assertTrue();
    });
    it('missing ancestor holds complete projection then converges', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(a); b.deadline.note = 'B';
      const e: DeadlineSyncEvent = new DeadlineSyncEvent('b', 'd', ['a'], a, b);
      expect(ordered([root(), e]).pending).assertTrue();
      expect(ordered([root(), e, update('a', a)]).aggregate?.deadline.note).assertEqual('B');
    });
    it('causal cycle quarantined', 0, () => {
      const a: DeadlineSyncEvent = update('a', snapshot()); a.parents = ['b'];
      const b: DeadlineSyncEvent = update('b', snapshot()); b.parents = ['a'];
      expect(ordered([a, b]).conflicts.join()).assertEqual('causal');
    });
    it('immutable event content collision quarantined', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(snapshot()); b.deadline.name = 'B';
      expect(ordered([root(), update('same', a), update('same', b)]).conflicts.join()).assertEqual('invalid');
    });
    it('incomplete tree rejected', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks = [a.tasks[1]]; expect(rejects(a)).assertTrue();
    });
    it('cyclic task tree rejected', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks[0].parentId = 't'; expect(rejects(a)).assertTrue();
    });
    it('task ownership and duplicate ids rejected', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.tasks[1].deadlineId = 'other'; expect(rejects(a)).assertTrue();
      const b: SyncAggregate = copy(snapshot()); b.tasks.push(b.tasks[1]); expect(rejects(b)).assertTrue();
    });
    it('cross deadline event cannot join causal graph', 0, () => {
      const a: DeadlineSyncEvent = root(); a.deadlineId = 'other';
      expect(ordered([a]).conflicts.join()).assertEqual('invalid');
    });
    it('legacy missing remaining fields is unknown not zero known', 0, () => {
      const json: string = JSON.stringify(snapshot()).replace('"remainingHours":10,', '')
        .replace('"remainingState":"initial",', '').replace('"remainingUpdatedAt":100,', '');
      const old: SyncAggregate = DeadlineSyncProtocol.normalize(JSON.parse(json) as SyncAggregate);
      expect(old.deadline.remainingState).assertEqual('unknown'); expect(old.deadline.remainingUpdatedAt).assertEqual(0);
      expect(old.deadline.estimatedHours).assertEqual(10);
    });
    it('legacy missing fields cannot replace confirmed local estimate', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.remainingHours = 6;
      a.deadline.remainingState = 'confirmed'; a.deadline.remainingUpdatedAt = 200;
      const old: SyncAggregate = copy(snapshot()); old.deadline.remainingHours = 0;
      old.deadline.remainingState = 'unknown'; old.deadline.remainingUpdatedAt = 0;
      const legacy: DeadlineSyncEvent = new DeadlineSyncEvent('old', 'd', [], undefined, old, [], true);
      expect(ordered([root(), update('a', a), legacy]).aggregate?.deadline.remainingHours).assertEqual(6);
    });
    it('legacy automatic partial progress never infers remaining hours', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.progress = 50;
      a.deadline.remainingState = 'unknown'; a.deadline.remainingUpdatedAt = 0;
      const old: DeadlineSyncEvent = new DeadlineSyncEvent('old', 'd', [], undefined, a, [], true);
      const result: SyncAggregate | undefined = ordered([old]).aggregate;
      expect(result?.deadline.remainingState).assertEqual('unknown'); expect(result?.deadline.remainingHours).assertEqual(10);
    });
    it('invalid remaining tuple degrades without manufacturing knowledge', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.remainingHours = -1; a.deadline.remainingState = 'confirmed';
      expect(DeadlineSyncProtocol.normalize(a).deadline.remainingState).assertEqual('unknown');
    });
    it('valid tombstone remains absorbing during immutable id collision', 0, () => {
      const live: DeadlineSyncEvent = update('collision', snapshot());
      const del: DeadlineSyncEvent = new DeadlineSyncEvent('collision', 'd', ['r'], snapshot(), undefined);
      expect(ordered([root(), live, del]).deleted).assertTrue();
    });
    it('legacy unknown reference survives later unrelated local edit', 0, () => {
      const a: SyncAggregate = copy(snapshot()); a.deadline.remainingState = 'unknown'; a.deadline.remainingUpdatedAt = 0;
      const old: DeadlineSyncEvent = new DeadlineSyncEvent('old', 'd', [], undefined, a, [], true);
      const b: SyncAggregate = copy(a); b.deadline.name = 'Renamed';
      const edit: DeadlineSyncEvent = new DeadlineSyncEvent('edit', 'd', ['old'], a, b);
      const result: SyncAggregate | undefined = ordered([old, edit]).aggregate;
      expect(result?.deadline.remainingState).assertEqual('unknown'); expect(result?.deadline.remainingHours).assertEqual(10);
    });
    it('concurrent task moves producing cycle hold whole aggregate', 0, () => {
      const base: SyncAggregate = copy(snapshot()); base.tasks[1].parentId = '';
      const r: DeadlineSyncEvent = new DeadlineSyncEvent('r', 'd', [], undefined, base);
      const a: SyncAggregate = copy(base); a.tasks[0].parentId = 't';
      const b: SyncAggregate = copy(base); b.tasks[1].parentId = 'p';
      const result: SyncMergeResult = ordered([r, new DeadlineSyncEvent('a', 'd', ['r'], base, a),
        new DeadlineSyncEvent('b', 'd', ['r'], base, b)]);
      expect(result.aggregate === undefined).assertTrue(); expect(result.conflicts.join()).assertEqual('tree');
    });
  });
}
