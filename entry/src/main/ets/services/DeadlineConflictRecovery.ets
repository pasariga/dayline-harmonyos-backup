import { DeadlineSubtask } from '../models/Deadline';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate, SyncMergeResult } from './DeadlineSyncProtocol';

export class RecoveryField {
  key: string;
  values: string[];
  currentValue: string;
  constructor(key: string, values: string[], currentValue: string) {
    this.key = key; this.values = values; this.currentValue = currentValue;
  }
}

export class RecoverySelection {
  key: string;
  value: string;
  constructor(key: string, value: string) { this.key = key; this.value = value; }
}

export class ConflictReview {
  deadlineId: string = '';
  name: string = '';
  fingerprint: string = '';
  fields: RecoveryField[] = [];
  safeValues: RecoverySelection[] = [];
  heads: string[] = [];
  removedTasks: string[] = [];
  blocked: boolean = false;
  requiresUpgrade: boolean = false;
  deleted: boolean = false;
}

export class DeletionNotice {
  deadlineId: string;
  name: string;
  deleted: boolean;
  titles: string[];
  token: string;
  constructor(id: string, name: string, deleted: boolean, titles: string[], token: string) {
    this.deadlineId = id; this.name = name; this.deleted = deleted; this.titles = titles; this.token = token;
  }
}

// No device clocks, weighting, or guesses. Every conflicting value needs an explicit choice.
export class DeadlineConflictRecovery {
  static fingerprint(events: DeadlineSyncEvent[], current: SyncAggregate | undefined): string {
    const payloads: string[] = Array.from(new Set<string>(events.map((e: DeadlineSyncEvent) =>
      JSON.stringify(DeadlineSyncProtocol.decode(JSON.stringify(e)))))).sort();
    return JSON.stringify([payloads, current === undefined ? null : DeadlineSyncProtocol.normalize(current)]);
  }

  static review(events: DeadlineSyncEvent[], id: string, current: SyncAggregate | undefined): ConflictReview {
    const review: ConflictReview = new ConflictReview();
    review.deadlineId = id;
    review.name = current?.deadline.name ?? events.find((e: DeadlineSyncEvent) =>
      e.snapshot !== undefined)?.snapshot?.deadline.name ?? '';
    const merged: SyncMergeResult = DeadlineSyncProtocol.merge(events, id);
    review.deleted = merged.deleted;
    review.removedTasks = merged.removedTasks;
    review.blocked = merged.pending || merged.conflicts.some((key: string) =>
      key === 'invalid' || key === 'causal');
    if (review.blocked) { return review; }
    try { review.fingerprint = DeadlineConflictRecovery.fingerprint(events, current); }
    catch (error) { review.blocked = true; return review; }
    if (review.deleted || merged.conflicts.length === 0) { return review; }
    const parentIds: Set<string> = new Set<string>();
    events.forEach((e: DeadlineSyncEvent) => e.parents.forEach((p: string) => parentIds.add(p)));
    review.heads = Array.from(new Set<string>(events.filter((e: DeadlineSyncEvent) => !parentIds.has(e.id))
      .map((e: DeadlineSyncEvent) => e.id))).sort();
    const local: Map<string, string> = current === undefined ? new Map<string, string>() :
      DeadlineSyncProtocol.fields(current);
    merged.fields.forEach((field) => {
      if (field.values.length === 1) { review.safeValues.push(new RecoverySelection(field.key, field.values[0])); }
      else if (field.values.length > 1) {
        const currentValue: string = local.get(field.key) ?? '';
        const values: string[] = field.values.slice();
        if (currentValue.length > 0 && !values.includes(currentValue)) { values.push(currentValue); }
        values.sort((a: string, b: string) => a === currentValue ? -1 : b === currentValue ? 1 : a.localeCompare(b));
        review.fields.push(new RecoveryField(field.key, values, currentValue));
      }
    });
    // A synthetic cyclic tree has no sensible per-record merge UI. Choose one complete tree.
    if (merged.conflicts.includes('tree')) {
      const trees: string[] = [];
      const sources: SyncAggregate[] = events.filter((e: DeadlineSyncEvent) => review.heads.includes(e.id) &&
        e.snapshot !== undefined).map((e: DeadlineSyncEvent) => e.snapshot as SyncAggregate);
      if (current !== undefined) { sources.unshift(current); }
      sources.forEach((source: SyncAggregate) => {
        const fields: Map<string, string> = DeadlineSyncProtocol.fields(source);
        try {
          const clean: SyncAggregate = DeadlineSyncProtocol.fromFields(fields, id, review.removedTasks);
          const value: string = JSON.stringify(clean.tasks);
          if (!trees.includes(value)) { trees.push(value); }
        } catch (error) { /* Never offer an incomplete task tree. */ }
      });
      review.fields = review.fields.filter((f: RecoveryField) => !f.key.startsWith('task:'));
      review.fields.push(new RecoveryField('tasks', trees, current === undefined ? '' :
        JSON.stringify(DeadlineSyncProtocol.fromFields(local, id, review.removedTasks).tasks)));
      review.safeValues = review.safeValues.filter((f: RecoverySelection) => !f.key.startsWith('task:'));
      if (trees.length === 0) { review.blocked = true; }
    }
    const order: string[] = ['name', 'due', 'remaining', 'tasks'];
    review.fields.sort((a: RecoveryField, b: RecoveryField) => {
      const ai: number = order.includes(a.key) ? order.indexOf(a.key) : 4;
      const bi: number = order.includes(b.key) ? order.indexOf(b.key) : 4;
      return ai - bi || a.key.localeCompare(b.key);
    });
    return review;
  }

  static resolve(review: ConflictReview, selections: RecoverySelection[], events: DeadlineSyncEvent[],
    current: SyncAggregate | undefined, newId: string): DeadlineSyncEvent {
    if (review.blocked || review.deleted || review.fields.length === 0 ||
      review.fingerprint !== DeadlineConflictRecovery.fingerprint(events, current) ||
      selections.length !== review.fields.length || new Set<string>(selections.map((s: RecoverySelection) => s.key)).size !== selections.length) {
      throw new Error('Review changed or incomplete');
    }
    const selected: Map<string, string> = new Map<string, string>();
    review.safeValues.forEach((s: RecoverySelection) => selected.set(s.key, s.value));
    review.fields.forEach((field: RecoveryField) => {
      const selection: RecoverySelection | undefined = selections.find((s: RecoverySelection) => s.key === field.key);
      if (selection === undefined || !field.values.includes(selection.value)) { throw new Error('Unreviewed choice'); }
      if (field.key === 'tasks') {
        const tasks: DeadlineSubtask[] = JSON.parse(selection.value) as DeadlineSubtask[];
        tasks.forEach((task: DeadlineSubtask) => selected.set(`task:${task.id}`, JSON.stringify(task)));
      } else { selected.set(field.key, selection.value); }
    });
    const snapshot: SyncAggregate = DeadlineSyncProtocol.fromFields(selected, review.deadlineId, review.removedTasks);
    const kept: Set<string> = new Set<string>(snapshot.tasks.map((t: DeadlineSubtask) => t.id));
    const removed: Set<string> = new Set<string>(review.removedTasks);
    if (review.fields.some((f: RecoveryField) => f.key === 'tasks')) {
      events.forEach((e: DeadlineSyncEvent) => (e.snapshot?.tasks ?? []).forEach((t: DeadlineSubtask) => {
        if (!kept.has(t.id)) { removed.add(t.id); }
      }));
    }
    // Explicitly assert only the reviewed fields, including a value equal to the previous
    // version. Safe fields retain their original causal writers, so unrelated concurrent edits
    // do not become artificial conflicts. The complete snapshot still travels atomically.
    const resolvedFields: string[] = review.fields.filter((field: RecoveryField) => field.key !== 'tasks')
      .map((field: RecoveryField) => field.key);
    if (review.fields.some((field: RecoveryField) => field.key === 'tasks')) {
      resolvedFields.push('tasks');
      snapshot.tasks.forEach((task: DeadlineSubtask) => resolvedFields.push(`task:${task.id}`));
    }
    const event: DeadlineSyncEvent = new DeadlineSyncEvent(newId, review.deadlineId, review.heads,
      snapshot, snapshot, Array.from(removed).sort(), false, resolvedFields);
    const check: SyncMergeResult = DeadlineSyncProtocol.merge(events.concat([event]), review.deadlineId);
    if (check.deleted || check.pending || check.conflicts.length > 0 || check.aggregate === undefined) {
      throw new Error('Choice does not produce a complete result');
    }
    return event;
  }

  static deletionNotice(events: DeadlineSyncEvent[], id: string): DeletionNotice | undefined {
    const byId: Map<string, DeadlineSyncEvent> = new Map<string, DeadlineSyncEvent>();
    events.forEach((e: DeadlineSyncEvent) => byId.set(e.id, e));
    const sees = (event: DeadlineSyncEvent, other: string): boolean => {
      const visited: Set<string> = new Set<string>();
      const pending: string[] = event.parents.slice();
      while (pending.length > 0) {
        const key: string = pending.pop() as string;
        if (key === other) { return true; }
        if (!visited.has(key)) { visited.add(key); pending.push(...(byId.get(key)?.parents ?? [])); }
      }
      return false;
    };
    const evidence: Set<string> = new Set<string>();
    const titles: Set<string> = new Set<string>();
    let deleted: boolean = false;
    let name: string = '';
    events.forEach((remove: DeadlineSyncEvent) => {
      if (!remove.deleted && remove.removedTasks.length === 0) { return; }
      const branch: Set<string> = new Set<string>(remove.removedTasks);
      const historicalTasks: DeadlineSubtask[] = [];
      events.forEach((e: DeadlineSyncEvent) => historicalTasks.push(...(e.snapshot?.tasks ?? []), ...(e.base?.tasks ?? [])));
      let changed: boolean = true;
      while (changed) {
        changed = false;
        historicalTasks.forEach((t: DeadlineSubtask) => {
          if (branch.has(t.parentId) && !branch.has(t.id)) { branch.add(t.id); changed = true; }
        });
      }
      events.forEach((edit: DeadlineSyncEvent) => {
        if (edit.id === remove.id || edit.snapshot === undefined || edit.legacy ||
          sees(edit, remove.id) || sees(remove, edit.id)) { return; }
        const before: Map<string, string> = edit.base === undefined ? new Map<string, string>() : DeadlineSyncProtocol.fields(edit.base);
        const after: Map<string, string> = DeadlineSyncProtocol.fields(edit.snapshot);
        const modified: string[] = Array.from(after.keys()).filter((key: string) => before.get(key) !== after.get(key));
        const affected: DeadlineSubtask[] = edit.snapshot.tasks.filter((t: DeadlineSubtask) =>
          branch.has(t.id) && modified.includes(`task:${t.id}`));
        if ((remove.deleted && modified.length > 0) || affected.length > 0) {
          evidence.add(remove.id); evidence.add(edit.id);
          name = remove.base?.deadline.name ?? edit.snapshot.deadline.name;
          deleted = deleted || remove.deleted;
          affected.forEach((t: DeadlineSubtask) => titles.add(t.title));
        }
      });
    });
    return evidence.size === 0 ? undefined : new DeletionNotice(id, name, deleted,
      Array.from(titles).sort(), JSON.stringify(Array.from(evidence).sort()));
  }
}
