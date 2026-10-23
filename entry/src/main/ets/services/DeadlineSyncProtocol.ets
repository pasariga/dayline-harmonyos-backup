import { Deadline, DeadlineSubtask } from '../models/Deadline';
import { DeadlineCloudCompatibility } from './DeadlineCloudCompatibility';

export class SyncAggregate {
  deadline: Deadline;
  tasks: DeadlineSubtask[];
  constructor(deadline: Deadline, tasks: DeadlineSubtask[]) { this.deadline = deadline; this.tasks = tasks; }
}

// Each row has a fresh UUID. Rows are never updated or physically deleted.
export class DeadlineSyncEvent {
  version: number = 2;
  id: string;
  deadlineId: string;
  parents: string[];
  base: SyncAggregate | undefined;
  snapshot: SyncAggregate | undefined;
  removedTasks: string[];
  deleted: boolean;
  legacy: boolean;
  resolvedFields: string[] | undefined = undefined;
  importFields: string[] | undefined = undefined;
  constructor(id: string, deadlineId: string, parents: string[], base: SyncAggregate | undefined,
    snapshot: SyncAggregate | undefined, removedTasks: string[] = [], legacy: boolean = false,
    resolvedFields: string[] = []) {
    this.id = id; this.deadlineId = deadlineId; this.parents = parents;
    this.base = base; this.snapshot = snapshot; this.removedTasks = removedTasks;
    this.deleted = snapshot === undefined; this.legacy = legacy;
    this.resolvedFields = resolvedFields.length === 0 ? undefined : Array.from(new Set<string>(resolvedFields)).sort();
  }
}

export class SyncMergeResult {
  aggregate: SyncAggregate | undefined = undefined;
  deleted: boolean = false;
  conflicts: string[] = [];
  pending: boolean = false;
  removedTasks: string[] = [];
  // Canonical frontier values, used only by the explicit user review flow.
  fields: SyncFieldValues[] = [];
}

export class SyncFieldValues {
  key: string;
  values: string[];
  constructor(key: string, values: string[]) { this.key = key; this.values = values; }
}

class FieldWrite {
  eventId: string;
  value: string;
  constructor(eventId: string, value: string) { this.eventId = eventId; this.value = value; }
}

export class DeadlineSyncProtocol {
  static normalize(source: SyncAggregate): SyncAggregate {
    const d: Deadline = source.deadline;
    if (d === undefined || typeof d.id !== 'string' || d.id.length === 0 ||
      typeof d.name !== 'string' || typeof d.type !== 'string' || typeof d.note !== 'string' ||
      typeof d.deadlineDate !== 'string' || typeof d.deadlineTime !== 'string' ||
      !Number.isFinite(d.deadlineAt) || !Number.isFinite(d.createdAt) ||
      typeof d.completed !== 'boolean' || !Number.isFinite(d.estimatedHours) || d.estimatedHours < 0 ||
      !Number.isFinite(d.progress) || d.progress < 0 || d.progress > 100 ||
      (d.progressMode !== 'manual' && d.progressMode !== 'automatic') ||
      !Number.isFinite(d.reminderOffsetMinutes) || !Array.isArray(source.tasks)) {
      throw new Error('Invalid complete Deadline snapshot');
    }
    const state: string = DeadlineCloudCompatibility.remainingState(d.remainingHours, d.remainingState,
      d.remainingUpdatedAt);
    const hours: number = Number.isFinite(d.remainingHours) && d.remainingHours >= 0 ? d.remainingHours : 0;
    const confirmedAt: number = Number.isFinite(d.remainingUpdatedAt) && d.remainingUpdatedAt > 0 ?
      d.remainingUpdatedAt : 0;
    const deadline: Deadline = new Deadline(d.id, d.name, d.type, d.deadlineDate, d.deadlineTime, d.note,
      d.createdAt, d.deadlineAt, d.completed, d.estimatedHours, d.progress, d.progressMode, 0,
      d.reminderOffsetMinutes, hours, state, confirmedAt);
    const tasks: DeadlineSubtask[] = source.tasks.map((t: DeadlineSubtask) => {
      if (t === undefined || typeof t.id !== 'string' || t.id.length === 0 || t.deadlineId !== d.id ||
        typeof t.title !== 'string' || typeof t.completed !== 'boolean' || typeof t.parentId !== 'string' ||
        !Number.isFinite(t.createdAt) || !Number.isFinite(t.sortOrder)) {
        throw new Error('Invalid task in complete snapshot');
      }
      return new DeadlineSubtask(t.id, t.deadlineId, t.title, t.completed, t.createdAt, t.parentId, t.sortOrder);
    }).sort((a: DeadlineSubtask, b: DeadlineSubtask) => a.id.localeCompare(b.id));
    const byId: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
    tasks.forEach((t: DeadlineSubtask) => { if (byId.has(t.id)) { throw new Error('Duplicate task'); } byId.set(t.id, t); });
    tasks.forEach((t: DeadlineSubtask) => {
      const visited: Set<string> = new Set<string>([t.id]);
      let parent: string = t.parentId;
      while (parent.length > 0) {
        const node: DeadlineSubtask | undefined = byId.get(parent);
        if (node === undefined || visited.has(parent)) { throw new Error('Incomplete or cyclic task tree'); }
        visited.add(parent); parent = node.parentId;
      }
    });
    return new SyncAggregate(deadline, tasks);
  }

  static decode(payload: string): DeadlineSyncEvent {
    const source: DeadlineSyncEvent = JSON.parse(payload) as DeadlineSyncEvent;
    if (source !== null && source.version === 2 && Object.keys(source).some((key: string) =>
      !['version','id','deadlineId','parents','base','snapshot','removedTasks','deleted','legacy','resolvedFields','importFields'].includes(key))) {
      throw new Error('Unsupported protocol-two fields');
    }
    if (source === null || (source.version !== 1 && source.version !== 2) || typeof source.id !== 'string' || source.id.length === 0 ||
      typeof source.deadlineId !== 'string' || source.deadlineId.length === 0 ||
      !Array.isArray(source.parents) || !Array.isArray(source.removedTasks) ||
      typeof source.deleted !== 'boolean' || typeof source.legacy !== 'boolean' ||
      source.parents.some((id: string) => typeof id !== 'string' || id.length === 0 || id === source.id) ||
      source.removedTasks.some((id: string) => typeof id !== 'string' || id.length === 0) ||
      (source.deleted && source.snapshot !== undefined) || (!source.deleted && source.snapshot === undefined)) {
      throw new Error('Invalid synchronization envelope');
    }
    const snapshot: SyncAggregate | undefined = source.snapshot === undefined ? undefined :
      DeadlineSyncProtocol.normalize(source.snapshot);
    const base: SyncAggregate | undefined = source.base === undefined ? undefined :
      DeadlineSyncProtocol.normalize(source.base);
    const resolved: string[] = source.resolvedFields ?? [];
    if (!Array.isArray(resolved) || resolved.some((key: string) => typeof key !== 'string') ||
      (resolved.length > 0 && (source.deleted || source.legacy || source.parents.length === 0 ||
        base === undefined || snapshot === undefined || resolved.some((key: string) =>
          key !== 'tasks' && !DeadlineSyncProtocol.fields(snapshot as SyncAggregate).has(key))))) {
      throw new Error('Invalid explicit field decision');
    }
    if (source.importFields !== undefined && (!Array.isArray(source.importFields) || source.version !== 2 ||
      !source.legacy || source.deleted || snapshot === undefined ||
      source.importFields.some((key: string) => typeof key !== 'string' ||
        !DeadlineSyncProtocol.fields(snapshot as SyncAggregate).has(key)) ||
      !source.importFields.includes('name') || !source.importFields.includes('due') ||
      snapshot.tasks.some((task: DeadlineSubtask) => !source.importFields?.includes(`task:${task.id}`)))) {
      throw new Error('Invalid legacy field evidence');
    }
    if ((snapshot !== undefined && snapshot.deadline.id !== source.deadlineId) ||
      (base !== undefined && base.deadline.id !== source.deadlineId) ||
      (source.legacy && (source.parents.length > 0 || base !== undefined || source.deleted))) {
      throw new Error('Snapshot belongs to another aggregate');
    }
    const event: DeadlineSyncEvent = new DeadlineSyncEvent(source.id, source.deadlineId, Array.from(new Set<string>(source.parents)).sort(),
      base, snapshot, Array.from(new Set<string>(source.removedTasks)).sort(), source.legacy, resolved);
    event.version = source.version;
    event.importFields = source.importFields === undefined ? undefined : Array.from(new Set<string>(source.importFields)).sort();
    return event;
  }

  static fields(aggregate: SyncAggregate): Map<string, string> {
    const d: Deadline = aggregate.deadline;
    const fields: Map<string, string> = new Map<string, string>();
    fields.set('name', JSON.stringify(d.name)); fields.set('type', JSON.stringify(d.type));
    fields.set('due', JSON.stringify([d.deadlineDate, d.deadlineTime, d.deadlineAt]));
    fields.set('note', JSON.stringify(d.note)); fields.set('created', JSON.stringify(d.createdAt));
    fields.set('completed', JSON.stringify(d.completed)); fields.set('total', JSON.stringify(d.estimatedHours));
    // Remaining estimate is one indivisible value; never merge its state/time separately.
    fields.set('remaining', JSON.stringify([d.remainingHours, d.remainingState, d.remainingUpdatedAt]));
    fields.set('mode', JSON.stringify(d.progressMode));
    fields.set('progress', JSON.stringify(d.progressMode === 'automatic' ? 0 : d.progress));
    fields.set('reminder', JSON.stringify(d.reminderOffsetMinutes));
    aggregate.tasks.forEach((t: DeadlineSubtask) => fields.set(`task:${t.id}`, JSON.stringify(t)));
    return fields;
  }

  static merge(input: DeadlineSyncEvent[], deadlineId: string): SyncMergeResult {
    const result: SyncMergeResult = new SyncMergeResult();
    const events: Map<string, DeadlineSyncEvent> = new Map<string, DeadlineSyncEvent>();
    const validHistory: DeadlineSyncEvent[] = [];
    let invalid: boolean = false;
    input.forEach((raw: DeadlineSyncEvent) => {
      try {
        const event: DeadlineSyncEvent = DeadlineSyncProtocol.decode(JSON.stringify(raw));
        if (event.deadlineId !== deadlineId) { throw new Error('Cross-Deadline causal link'); }
        validHistory.push(event);
        const existing: DeadlineSyncEvent | undefined = events.get(event.id);
        if (existing !== undefined && JSON.stringify(existing) !== JSON.stringify(event)) {
          throw new Error('Immutable event changed');
        }
        events.set(event.id, event);
      } catch (error) { invalid = true; }
    });
    // A valid deletion is absorbing, including when its ancestors arrive later.
    if (validHistory.some((event: DeadlineSyncEvent) => event.deleted)) {
      result.deleted = true; return result;
    }
    const removed: Set<string> = new Set<string>();
    const taskHistory: DeadlineSubtask[] = [];
    validHistory.forEach((event: DeadlineSyncEvent) => {
      event.removedTasks.forEach((id: string) => removed.add(id));
      taskHistory.push(...(event.snapshot?.tasks ?? []), ...(event.base?.tasks ?? []));
    });
    let changed: boolean = true;
    while (changed) {
      changed = false;
      taskHistory.forEach((t: DeadlineSubtask) => {
        if (removed.has(t.parentId) && !removed.has(t.id)) { removed.add(t.id); changed = true; }
      });
    }
    result.removedTasks = Array.from(removed).sort();
    if (invalid) { result.conflicts = ['invalid']; return result; }
    const ancestors: Map<string, Set<string>> = new Map<string, Set<string>>();
    const visiting: Set<string> = new Set<string>();
    const visit = (id: string): Set<string> => {
      const known: Set<string> | undefined = ancestors.get(id);
      if (known !== undefined) { return known; }
      const event: DeadlineSyncEvent | undefined = events.get(id);
      if (event === undefined) { result.pending = true; return new Set<string>(); }
      if (visiting.has(id)) { throw new Error('Causal cycle'); }
      visiting.add(id);
      const all: Set<string> = new Set<string>();
      event.parents.forEach((parent: string) => { all.add(parent); visit(parent).forEach((a: string) => all.add(a)); });
      visiting.delete(id); ancestors.set(id, all); return all;
    };
    try { events.forEach((event: DeadlineSyncEvent) => visit(event.id)); }
    catch (error) { result.conflicts = ['causal']; return result; }
    if (result.pending || events.size === 0) { return result; }
    const writes: Map<string, FieldWrite[]> = new Map<string, FieldWrite[]>();
    const authoritativeRemaining: boolean = Array.from(events.values()).some((event: DeadlineSyncEvent) =>
      event.snapshot !== undefined && (!event.legacy || event.snapshot.deadline.remainingUpdatedAt > 0) &&
      ((event.resolvedFields ?? []).includes('remaining') || event.base === undefined || DeadlineSyncProtocol.fields(event.base).get('remaining') !==
        DeadlineSyncProtocol.fields(event.snapshot).get('remaining')));
    events.forEach((event: DeadlineSyncEvent) => {
      if (event.snapshot === undefined) { return; }
      const before: Map<string, string> = event.base === undefined ? new Map<string, string>() :
        DeadlineSyncProtocol.fields(event.base);
      DeadlineSyncProtocol.fields(event.snapshot).forEach((value: string, key: string) => {
        if (event.importFields !== undefined && !event.importFields.includes(key)) { return; }
        if (key === 'remaining' && authoritativeRemaining && event.legacy && event.snapshot !== undefined &&
          event.snapshot.deadline.remainingState === 'unknown' && event.snapshot.deadline.remainingUpdatedAt === 0) { return; }
        if (before.get(key) !== value || (event.resolvedFields ?? []).includes(key)) {
          const candidates: FieldWrite[] = writes.get(key) ?? [];
          candidates.push(new FieldWrite(event.id, value)); writes.set(key, candidates);
        }
      });
    });
    const selected: Map<string, string> = new Map<string, string>();
    writes.forEach((candidates: FieldWrite[], key: string) => {
      if (key.startsWith('task:') && removed.has(key.substring(5))) { return; }
      const frontier: FieldWrite[] = candidates.filter((c: FieldWrite) =>
        !candidates.some((other: FieldWrite) => other.eventId !== c.eventId &&
          (ancestors.get(other.eventId)?.has(c.eventId) ?? false)));
      const values: Set<string> = new Set<string>(frontier.map((c: FieldWrite) => c.value));
      result.fields.push(new SyncFieldValues(key, Array.from(values).sort()));
      if (values.size > 1) { result.conflicts.push(key); }
      else if (frontier.length > 0) { selected.set(key, frontier[0].value); }
    });
    result.conflicts.sort();
    result.fields.sort((a: SyncFieldValues, b: SyncFieldValues) => a.key.localeCompare(b.key));
    // Absence in an old complete task list is not a task tombstone. Never silently
    // union it with a different local tree: the missing task might have been deleted.
    const imports: DeadlineSyncEvent[] = Array.from(events.values()).filter((e: DeadlineSyncEvent) => e.importFields !== undefined);
    imports.forEach((imported: DeadlineSyncEvent) => {
      events.forEach((other: DeadlineSyncEvent) => {
        if (other.id === imported.id || other.snapshot === undefined || imported.snapshot === undefined ||
          ancestors.get(other.id)?.has(imported.id) || ancestors.get(imported.id)?.has(other.id)) { return; }
        if (other.base !== undefined && JSON.stringify(other.base.tasks) === JSON.stringify(other.snapshot.tasks)) { return; }
        const reviewed: boolean = Array.from(events.values()).some((e: DeadlineSyncEvent) =>
          (e.resolvedFields ?? []).includes('tasks') && ancestors.get(e.id)?.has(imported.id) &&
          ancestors.get(e.id)?.has(other.id));
        if (reviewed) { return; }
        const tree = (a: SyncAggregate): string => JSON.stringify(DeadlineSyncProtocol.fromFields(
          DeadlineSyncProtocol.fields(a), deadlineId, result.removedTasks).tasks);
        if (tree(imported.snapshot) !== tree(other.snapshot) && !result.conflicts.includes('tree')) {
          result.conflicts.push('tree');
        }
      });
    });
    result.conflicts.sort();
    if (result.conflicts.length > 0) { return result; }
    try {
      result.aggregate = DeadlineSyncProtocol.fromFields(selected, deadlineId, result.removedTasks);
    } catch (error) { result.conflicts = ['tree']; }
    return result;
  }

  static fromFields(selected: Map<string, string>, deadlineId: string, removedIds: string[]): SyncAggregate {
    const removed: Set<string> = new Set<string>(removedIds);
    const due: (string | number)[] = JSON.parse(selected.get('due') ?? '[]') as (string | number)[];
    const remaining: (string | number)[] = JSON.parse(selected.get('remaining') ?? '[0,"unknown",0]') as (string | number)[];
    const d: Deadline = new Deadline(deadlineId, JSON.parse(selected.get('name') ?? 'null') as string,
      JSON.parse(selected.get('type') ?? '"其他"') as string, due[0] as string, due[1] as string,
      JSON.parse(selected.get('note') ?? '""') as string, JSON.parse(selected.get('created') ?? '0') as number,
      due[2] as number, JSON.parse(selected.get('completed') ?? 'null') as boolean,
      JSON.parse(selected.get('total') ?? '0') as number, JSON.parse(selected.get('progress') ?? '0') as number,
      JSON.parse(selected.get('mode') ?? '"manual"') as string, 0, JSON.parse(selected.get('reminder') ?? '0') as number,
      remaining[0] as number, remaining[1] as string, remaining[2] as number);
    let tasks: DeadlineSubtask[] = [];
    selected.forEach((value: string, key: string) => { if (key.startsWith('task:')) { tasks.push(JSON.parse(value) as DeadlineSubtask); } });
    // A child arriving after a removed ancestor also stays removed.
    let changed: boolean = true;
    while (changed) {
      changed = false;
      tasks.forEach((t: DeadlineSubtask) => {
        if (removed.has(t.parentId) && !removed.has(t.id)) { removed.add(t.id); changed = true; }
      });
    }
    tasks = tasks.filter((t: DeadlineSubtask) => !removed.has(t.id));
    return DeadlineSyncProtocol.normalize(new SyncAggregate(d, tasks));
  }

}
