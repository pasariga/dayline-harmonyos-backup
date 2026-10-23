import { describe, expect, it } from '@ohos/hypium';
import { Deadline, DeadlineSubtask } from '../main/ets/models/Deadline';
import { DeadlineSyncProtocol, DeadlineSyncEvent, SyncAggregate } from '../main/ets/services/DeadlineSyncProtocol';
import { ConflictReview, DeadlineConflictRecovery, RecoverySelection } from '../main/ets/services/DeadlineConflictRecovery';

function base(): SyncAggregate {
  return new SyncAggregate(new Deadline('review-d', 'Original', 'exam', '2026-11-01', '18:00', '',
    100, 100000, false, 10, 0, 'automatic', 0, 30, 10, 'initial', 100),
    [new DeadlineSubtask('review-p', 'review-d', 'Parent', false, 100),
      new DeadlineSubtask('review-t', 'review-d', 'Task', false, 101, 'review-p')]);
}
function copy(a: SyncAggregate): SyncAggregate { return DeadlineSyncProtocol.normalize(a); }
function history(a: SyncAggregate, b: SyncAggregate): DeadlineSyncEvent[] {
  return [new DeadlineSyncEvent('review-r', 'review-d', [], undefined, base()),
    new DeadlineSyncEvent('review-a', 'review-d', ['review-r'], base(), a),
    new DeadlineSyncEvent('review-b', 'review-d', ['review-r'], base(), b)];
}
function select(review: ConflictReview, value: number = 0): RecoverySelection[] {
  return review.fields.map((f) => new RecoverySelection(f.key, f.values[value]));
}
function rejects(review: ConflictReview, choices: RecoverySelection[], events: DeadlineSyncEvent[], current: SyncAggregate): boolean {
  try { DeadlineConflictRecovery.resolve(review, choices, events, current, 'review-result'); return false; }
  catch (error) { return true; }
}

export default function conflictRecoveryTest() {
  describe('conflictRecovery', () => {
    it('choose current title explicitly dominates old conflicting writes', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review), events, a, 'chosen');
      expect(DeadlineSyncProtocol.merge(events.concat([event]), 'review-d').aggregate?.deadline.name).assertEqual('A');
      expect(event.parents.join()).assertEqual('review-a,review-b');
      expect(event.resolvedFields?.join()).assertEqual('name');
    });
    it('last complete value may be chosen without secretly selecting newer variant', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review), events, base(), 'chosen');
      expect(DeadlineSyncProtocol.merge(events.concat([event]), 'review-d').aggregate?.deadline.name).assertEqual('Original');
    });
    it('name choice keeps independently merged notes and task changes', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A'; a.deadline.note = 'Keep note';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B'; b.tasks[1].completed = true;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review), events, base(), 'chosen');
      expect(event.snapshot?.deadline.note).assertEqual('Keep note');
      expect(event.snapshot?.tasks.find((t: DeadlineSubtask) => t.id === 'review-t')?.completed).assertTrue();
    });
    it('due choice is the exact date time and timestamp tuple', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.deadlineDate = '2026-11-02'; a.deadline.deadlineAt = 200000;
      const b: SyncAggregate = copy(base()); b.deadline.deadlineTime = '10:00'; b.deadline.deadlineAt = 300000;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review, 1), events, a, 'chosen');
      expect(event.snapshot?.deadline.deadlineDate).assertEqual('2026-11-01');
      expect(event.snapshot?.deadline.deadlineTime).assertEqual('10:00');
      expect(event.snapshot?.deadline.deadlineAt).assertEqual(300000);
    });
    it('six versus nine hours is selected with original confirmation time no averaging', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.remainingHours = 6; a.deadline.remainingState = 'confirmed'; a.deadline.remainingUpdatedAt = 200;
      const b: SyncAggregate = copy(base()); b.deadline.remainingHours = 9; b.deadline.remainingState = 'confirmed'; b.deadline.remainingUpdatedAt = 300;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review, 1), events, a, 'chosen');
      expect(event.snapshot?.deadline.remainingHours).assertEqual(9);
      expect(event.snapshot?.deadline.remainingUpdatedAt).assertEqual(300);
      expect(event.snapshot?.deadline.estimatedHours).assertEqual(10);
    });
    it('task title versus completion chooses a whole task not a guessed hybrid', 0, () => {
      const a: SyncAggregate = copy(base()); a.tasks[1].title = 'A title';
      const b: SyncAggregate = copy(base()); b.tasks[1].completed = true;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review, 1), events, a, 'chosen');
      const task: DeadlineSubtask | undefined = event.snapshot?.tasks.find((t: DeadlineSubtask) => t.id === 'review-t');
      expect(task?.title).assertEqual('Task'); expect(task?.completed).assertTrue();
      expect(event.snapshot?.deadline.remainingHours).assertEqual(10);
    });
    it('task deletion wins and is explainable without a restore choice', 0, () => {
      const a: SyncAggregate = copy(base()); a.tasks = [a.tasks[0]];
      const b: SyncAggregate = copy(base()); b.tasks[1].title = 'Edited';
      const events: DeadlineSyncEvent[] = history(a, b); events[1].removedTasks = ['review-t'];
      expect(DeadlineConflictRecovery.review(events, 'review-d', base()).fields.length).assertEqual(0);
      expect(DeadlineSyncProtocol.merge(events, 'review-d').aggregate?.tasks.length).assertEqual(1);
      expect(DeadlineConflictRecovery.deletionNotice(events, 'review-d')?.titles.join()).assertEqual('Edited');
    });
    it('deadline deletion remains absorbing and has understandable notice', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'Edited';
      const events: DeadlineSyncEvent[] = [new DeadlineSyncEvent('review-r', 'review-d', [], undefined, base()),
        new DeadlineSyncEvent('delete', 'review-d', ['review-r'], base(), undefined),
        new DeadlineSyncEvent('edit', 'review-d', ['review-r'], base(), a)];
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      expect(review.deleted).assertTrue(); expect(rejects(review, [], events, base())).assertTrue();
      expect(DeadlineConflictRecovery.deletionNotice(events, 'review-d')?.deleted).assertTrue();
    });
    it('repeat conflict does not change the review fingerprint', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      expect(DeadlineConflictRecovery.fingerprint(events.concat(events), base())).assertEqual(DeadlineConflictRecovery.fingerprint(events, base()));
    });
    it('old events after resolution and serialization do not reopen conflict', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      const event: DeadlineSyncEvent = DeadlineSyncProtocol.decode(JSON.stringify(
        DeadlineConflictRecovery.resolve(review, select(review, 1), events, base(), 'chosen')));
      const historyAfter: DeadlineSyncEvent[] = events.concat([event], events).reverse();
      expect(DeadlineSyncProtocol.merge(historyAfter, 'review-d').conflicts.length).assertEqual(0);
      expect(DeadlineConflictRecovery.review(historyAfter, 'review-d', event.snapshot).fields.length).assertEqual(0);
    });
    it('cancel does not mutate history or previous complete state', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b); const original: string = JSON.stringify(events);
      DeadlineConflictRecovery.review(events, 'review-d', base());
      expect(JSON.stringify(events)).assertEqual(original); expect(base().deadline.name).assertEqual('Original');
    });
    it('new arrival or local change rejects a stale decision', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      const c: SyncAggregate = copy(base()); c.deadline.note = 'new';
      const extra: DeadlineSyncEvent = new DeadlineSyncEvent('extra', 'review-d', ['review-r'], base(), c);
      expect(rejects(review, select(review), events.concat([extra]), base())).assertTrue();
      expect(rejects(review, select(review), events, c)).assertTrue();
    });
    it('every field must be explicitly chosen and no invented values accepted', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A'; a.deadline.remainingHours = 6;
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B'; b.deadline.remainingHours = 9;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      expect(rejects(review, [], events, base())).assertTrue();
      expect(rejects(review, [new RecoverySelection('name', '"Invented"')], events, base())).assertTrue();
    });
    it('pending ancestors and corrupt events are not offered as selectable versions', 0, () => {
      const event: DeadlineSyncEvent = new DeadlineSyncEvent('missing', 'review-d', ['absent'], base(), copy(base()));
      expect(DeadlineConflictRecovery.review([event], 'review-d', base()).blocked).assertTrue();
      expect(DeadlineConflictRecovery.review([event], 'review-d', base()).name).assertEqual('Original');
      event.parents = ['missing'];
      expect(DeadlineConflictRecovery.review([event], 'review-d', base()).blocked).assertTrue();
    });
    it('a cyclic synthesized tree can be resolved to one valid full tree', 0, () => {
      const r: SyncAggregate = copy(base()); r.tasks[1].parentId = '';
      const a: SyncAggregate = copy(r); a.tasks[0].parentId = 'review-t';
      const b: SyncAggregate = copy(r); b.tasks[1].parentId = 'review-p';
      const events: DeadlineSyncEvent[] = [new DeadlineSyncEvent('review-r', 'review-d', [], undefined, r),
        new DeadlineSyncEvent('review-a', 'review-d', ['review-r'], r, a), new DeadlineSyncEvent('review-b', 'review-d', ['review-r'], r, b)];
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', r);
      expect(review.fields[0].key).assertEqual('tasks');
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review, 1), events, r, 'chosen');
      expect(DeadlineSyncProtocol.merge(events.concat([event]), 'review-d').conflicts.length).assertEqual(0);
      expect(event.snapshot?.tasks.length).assertEqual(2);
    });
    it('resolving another field never clears a permanent task tombstone', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A'; a.tasks = [a.tasks[0]];
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b); events[1].removedTasks = ['review-t'];
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review), events, a, 'chosen');
      const merged = DeadlineSyncProtocol.merge(events.concat([event], events), 'review-d');
      expect(merged.aggregate?.tasks.length).assertEqual(1); expect(merged.removedTasks.includes('review-t')).assertTrue();
    });
    it('safe different fields do not ask user to review', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.note = 'Note';
      expect(DeadlineConflictRecovery.review(history(a, b), 'review-d', base()).fields.length).assertEqual(0);
    });
    it('individual name and remaining choices can come from different saved versions', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A'; a.deadline.remainingHours = 6;
      a.deadline.remainingState = 'confirmed'; a.deadline.remainingUpdatedAt = 200;
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B'; b.deadline.remainingHours = 9;
      b.deadline.remainingState = 'confirmed'; b.deadline.remainingUpdatedAt = 300;
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', base());
      const selections: RecoverySelection[] = [new RecoverySelection('name', JSON.stringify('A')),
        new RecoverySelection('remaining', JSON.stringify([9, 'confirmed', 300]))];
      const event: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, selections, events, base(), 'chosen');
      expect(event.snapshot?.deadline.name).assertEqual('A');
      expect(event.snapshot?.deadline.remainingHours).assertEqual(9);
      expect(event.snapshot?.deadline.remainingUpdatedAt).assertEqual(300);
      expect(event.snapshot?.deadline.estimatedHours).assertEqual(10);
      expect(DeadlineSyncProtocol.merge(events.concat([event], events), 'review-d').conflicts.length).assertEqual(0);
    });
    it('causal task removal does not create a spurious concurrency notice', 0, () => {
      const a: SyncAggregate = copy(base()); a.tasks[1].title = 'Edited';
      const b: SyncAggregate = copy(a); b.tasks = [b.tasks[0]];
      const events: DeadlineSyncEvent[] = [new DeadlineSyncEvent('review-r', 'review-d', [], undefined, base()),
        new DeadlineSyncEvent('review-a', 'review-d', ['review-r'], base(), a),
        new DeadlineSyncEvent('remove', 'review-d', ['review-a'], a, b, ['review-t'])];
      expect(DeadlineConflictRecovery.deletionNotice(events, 'review-d') === undefined).assertTrue();
    });
    it('reviewing a title does not conflict with an independent unobserved note edit', 0, () => {
      const a: SyncAggregate = copy(base()); a.deadline.name = 'A';
      const b: SyncAggregate = copy(base()); b.deadline.name = 'B';
      const events: DeadlineSyncEvent[] = history(a, b);
      const review: ConflictReview = DeadlineConflictRecovery.review(events, 'review-d', a);
      const chosen: DeadlineSyncEvent = DeadlineConflictRecovery.resolve(review, select(review), events, a, 'chosen');
      const note: SyncAggregate = copy(a); note.deadline.note = 'Independent note';
      const concurrent: DeadlineSyncEvent = new DeadlineSyncEvent('concurrent', 'review-d', ['review-a', 'review-b'], a, note);
      const result = DeadlineSyncProtocol.merge(events.concat([chosen, concurrent]), 'review-d');
      expect(result.conflicts.length).assertEqual(0);
      expect(result.aggregate?.deadline.name).assertEqual('A');
      expect(result.aggregate?.deadline.note).assertEqual('Independent note');
    });
  });
}
