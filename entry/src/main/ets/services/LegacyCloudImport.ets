import { Deadline, DeadlineSubtask } from '../models/Deadline';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate } from './DeadlineSyncProtocol';
import { DeadlineProgressService } from './DeadlineProgressService';
import { CloudProtocolPolicy } from './CloudProtocolPolicy';

export interface LegacyDeadlineRow {
  id: string; name: string; deadline_date: string; deadline_time: string; deadline_at: number;
  created_at: number; completed: number;
  type?: string | null; note?: string | null; estimated_hours?: number | null;
  progress?: number | null; progress_mode?: string | null; reminder_offset_minutes?: number | null;
  remaining_hours?: number | null; remaining_state?: string | null; remaining_updated_at?: number | null;
}
export interface LegacyTaskRow {
  id: string; deadline_id: string; title: string; completed: number; created_at: number;
  parent_id?: string | null; sort_order?: number | null;
}
export interface LegacyTaskManifest { deadlineId: string; taskIds: string[]; }
export interface LegacyCloudData {
  deadlines: LegacyDeadlineRow[]; tasks: LegacyTaskRow[]; manifests: LegacyTaskManifest[];
}
// These facts come from the authenticated, frozen reader, never from a cloud business row.
export class LegacyImportTrust {
  verifiedAccount: string; sourceAccount: string; sourceId: string; complete: boolean; writersStopped: boolean; journalComplete: boolean;
  constructor(verified: string, source: string, sourceId: string, complete: boolean, stopped: boolean, journalComplete: boolean = false) {
    this.verifiedAccount = verified; this.sourceAccount = source; this.sourceId = sourceId;
    this.complete = complete; this.writersStopped = stopped;
    this.journalComplete = journalComplete;
  }
}
export class LegacyImportItem {
  id: string; event: DeadlineSyncEvent | undefined; issue: string;
  constructor(id: string, event: DeadlineSyncEvent | undefined, issue: string = '') {
    this.id = id; this.event = event; this.issue = issue;
  }
}
export class LegacyImportPlan { items: LegacyImportItem[] = []; }

export class LegacyCloudImport {
  static authorized(owner: string, trust: LegacyImportTrust): boolean {
    return CloudProtocolPolicy.canImport(owner, trust.verifiedAccount, trust.sourceAccount,
      trust.complete, trust.writersStopped) && trust.journalComplete && trust.sourceId.length > 0;
  }
  private static present(value: string | number | null | undefined): boolean {
    return value !== undefined && value !== null;
  }
  private static numeric(value: number | null | undefined, min: number, max: number = Number.MAX_SAFE_INTEGER): number {
    if (!LegacyCloudImport.present(value)) { return 0; }
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
      throw new Error('Invalid old numeric value');
    }
    return value;
  }
  private static text(value: string | null | undefined, fallback: string): string {
    if (!LegacyCloudImport.present(value)) { return fallback; }
    if (typeof value !== 'string') { throw new Error('Invalid old text value'); }
    return value;
  }
  private static unknownKeys(value: Object, allowed: string[]): void {
    if (Object.keys(value).some((key: string) => !allowed.includes(key))) { throw new Error('Unsupported old fields'); }
  }
  static candidate(row: LegacyDeadlineRow, rows: LegacyTaskRow[], manifest: LegacyTaskManifest): DeadlineSyncEvent {
    LegacyCloudImport.unknownKeys(row, ['id','name','type','deadline_date','deadline_time','deadline_at','created_at',
      'completed','note','estimated_hours','progress','progress_mode','reminder_offset_minutes','remaining_hours',
      'remaining_state','remaining_updated_at']);
    if (typeof row.id !== 'string' || row.id.length === 0 || typeof row.name !== 'string' || row.name.trim().length === 0 ||
      typeof row.deadline_date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(row.deadline_date) ||
      typeof row.deadline_time !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(row.deadline_time) ||
      typeof row.created_at !== 'number' || row.created_at <= 0 || typeof row.deadline_at !== 'number' || row.deadline_at <= 0 ||
      (row.completed !== 0 && row.completed !== 1)) { throw new Error('Missing old identity or date'); }
    const date: Date = new Date(`${row.deadline_date}T12:00:00`);
    if (!Number.isFinite(date.getTime()) || date.getFullYear() !== Number(row.deadline_date.slice(0,4)) ||
      date.getMonth() + 1 !== Number(row.deadline_date.slice(5,7)) || date.getDate() !== Number(row.deadline_date.slice(8,10))) {
      throw new Error('Invalid old date');
    }
    const mode: string = LegacyCloudImport.text(row.progress_mode, 'manual');
    const type: string = LegacyCloudImport.text(row.type, '其他');
    if (!['manual','automatic'].includes(mode) || !['作业','考试','竞赛','项目','生活','其他','exam','homework','project','other'].includes(type)) {
      throw new Error('Unsupported old type or progress mode');
    }
    const reminder: number = LegacyCloudImport.numeric(row.reminder_offset_minutes, 0);
    if (![0,60,1440,4320].includes(reminder)) { throw new Error('Unsupported old reminder'); }
    const tasks: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
    rows.forEach((r: LegacyTaskRow) => {
      LegacyCloudImport.unknownKeys(r, ['id','deadline_id','title','completed','created_at','parent_id','sort_order']);
      if (typeof r.id !== 'string' || r.id.length === 0 || r.deadline_id !== row.id || typeof r.title !== 'string' ||
        (r.completed !== 0 && r.completed !== 1) || typeof r.created_at !== 'number' || r.created_at <= 0) {
        throw new Error('Invalid old task');
      }
      const task: DeadlineSubtask = new DeadlineSubtask(r.id, r.deadline_id, r.title, r.completed === 1,
        LegacyCloudImport.numeric(r.created_at, 1), LegacyCloudImport.text(r.parent_id, ''),
        LegacyCloudImport.numeric(r.sort_order, 0));
      if (!Number.isInteger(task.sortOrder)) { throw new Error('Invalid task position'); }
      const previous: DeadlineSubtask | undefined = tasks.get(task.id);
      if (previous !== undefined && JSON.stringify(previous) !== JSON.stringify(task)) { throw new Error('Different old task versions'); }
      tasks.set(task.id, task);
    });
    if (manifest === undefined || manifest.deadlineId !== row.id || !Array.isArray(manifest.taskIds) ||
      manifest.taskIds.some((id: string) => typeof id !== 'string' || id.length === 0) ||
      new Set<string>(manifest.taskIds).size !== manifest.taskIds.length ||
      manifest.taskIds.length !== tasks.size || manifest.taskIds.some((id: string) => !tasks.has(id))) {
      throw new Error('Incomplete old task list');
    }
    const hasRemaining: boolean = LegacyCloudImport.present(row.remaining_hours) &&
      LegacyCloudImport.present(row.remaining_state) && LegacyCloudImport.present(row.remaining_updated_at);
    const hours: number = LegacyCloudImport.numeric(row.remaining_hours, 0);
    const confirmed: number = LegacyCloudImport.numeric(row.remaining_updated_at, 0);
    const state: string = LegacyCloudImport.text(row.remaining_state, 'unknown');
    const validRemaining: boolean = hasRemaining && ['initial','confirmed','unknown'].includes(state) &&
      (state === 'unknown' || confirmed > 0);
    const deadline: Deadline = new Deadline(row.id, row.name, type, row.deadline_date, row.deadline_time,
      LegacyCloudImport.text(row.note, ''), LegacyCloudImport.numeric(row.created_at, 1),
      LegacyCloudImport.numeric(row.deadline_at, 1), row.completed === 1,
      LegacyCloudImport.numeric(row.estimated_hours, 0), LegacyCloudImport.numeric(row.progress, 0, 100), mode, 0,
      reminder, validRemaining ? hours : 0, validRemaining ? state : 'unknown', validRemaining ? confirmed : 0);
    let list: DeadlineSubtask[] = Array.from(tasks.values());
    const aggregate: SyncAggregate = DeadlineSyncProtocol.normalize(new SyncAggregate(deadline, list));
    if (mode === 'automatic') {
      list = DeadlineProgressService.deriveParentStates(aggregate.tasks);
      aggregate.tasks = list; aggregate.deadline.progress = DeadlineProgressService.calculateDeadlineProgress(list);
    }
    const evidence: string[] = ['name','due','created','completed'];
    const optionalColumns: string[] = ['type','note','estimated_hours','progress_mode','progress','reminder_offset_minutes'];
    const optionalValues: (string | number | null | undefined)[] = [row.type,row.note,row.estimated_hours,
      row.progress_mode,row.progress,row.reminder_offset_minutes];
    const keys: string[] = ['type','note','total','mode','progress','reminder'];
    optionalColumns.forEach((column: string, index: number) => {
      if (LegacyCloudImport.present(optionalValues[index])) { evidence.push(keys[index]); }
    });
    if (validRemaining) { evidence.push('remaining'); }
    aggregate.tasks.forEach((task: DeadlineSubtask) => evidence.push(`task:${task.id}`));
    const event: DeadlineSyncEvent = new DeadlineSyncEvent(`legacy-v2:${encodeURIComponent(row.id)}`, row.id,
      [], undefined, aggregate, [], true);
    event.importFields = evidence.sort();
    return DeadlineSyncProtocol.decode(JSON.stringify(event));
  }
  static plan(payload: string): LegacyImportPlan {
    const result: LegacyImportPlan = new LegacyImportPlan();
    try {
      const data: LegacyCloudData = JSON.parse(payload) as LegacyCloudData;
      if (data === null || !Array.isArray(data.deadlines) || !Array.isArray(data.tasks) || !Array.isArray(data.manifests)) {
        throw new Error('Invalid frozen export');
      }
      LegacyCloudImport.unknownKeys(data, ['deadlines','tasks','manifests']);
      const ids: Set<string> = new Set<string>();
      data.deadlines.forEach((row: LegacyDeadlineRow, index: number) => {
        const id: string = row !== null && typeof row.id === 'string' && row.id.length > 0 ? row.id : `invalid-row-${index}`;
        try {
          if (ids.has(id)) { throw new Error('Duplicate old Deadline'); }
          ids.add(id);
          const manifests: LegacyTaskManifest[] = data.manifests.filter((m: LegacyTaskManifest) => m !== null && m.deadlineId === id);
          if (manifests.length !== 1) { throw new Error('Missing unique old task manifest'); }
          result.items.push(new LegacyImportItem(id, LegacyCloudImport.candidate(row,
            data.tasks.filter((t: LegacyTaskRow) => t !== null && t.deadline_id === id), manifests[0])));
        } catch (error) {
          result.items = result.items.filter((item: LegacyImportItem) => item.id !== id);
          result.items.push(new LegacyImportItem(id, undefined, 'invalid_or_incomplete'));
        }
      });
      data.tasks.forEach((row: LegacyTaskRow, index: number) => {
        if (row === null || typeof row.deadline_id !== 'string' || !ids.has(row.deadline_id)) {
          result.items.push(new LegacyImportItem(`orphan-row-${index}`, undefined, 'missing_deadline'));
        }
      });
    } catch (error) { result.items = [new LegacyImportItem('', undefined, 'invalid_export')]; }
    return result;
  }
}
