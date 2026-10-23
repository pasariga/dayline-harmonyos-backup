import { LegacyCloudData, LegacyDeadlineRow, LegacyTaskRow, LegacyTaskManifest } from './LegacyCloudImport';
import { CloudProtocolPolicy } from './CloudProtocolPolicy';
import { DeadlineSyncEvent, DeadlineSyncProtocol } from './DeadlineSyncProtocol';

export interface LegacyJournalRow { id: string; deadline_id: string; payload: string; }
export interface LegacySnapshotSection { ids: string[]; pages: number; }
// These are authenticated export metadata, not claims made by old business rows.
// An actual server adapter is intentionally absent while cloud exchange is paused.
export interface LegacySnapshotDescriptor {
  accountId: string; sourceId: string; revision: string; boundaryId: string;
  historySeal: string; minimumProtocol: number; oldWritesStopped: boolean;
  journal: LegacySnapshotSection; deadlines: LegacySnapshotSection; tasks: LegacySnapshotSection;
  manifests: LegacyTaskManifest[];
}
export interface LegacySnapshotPage {
  accountId: string; sourceId: string; revision: string; section: string;
  cursor: string; nextCursor: string; finished: boolean; rows: string[];
}
export interface LegacySnapshotSource {
  begin(accountId: string): Promise<LegacySnapshotDescriptor>;
  page(snapshot: LegacySnapshotDescriptor, section: string, cursor: string): Promise<LegacySnapshotPage>;
  seal(snapshot: LegacySnapshotDescriptor): Promise<LegacySnapshotDescriptor>;
}
export interface FrozenLegacyRead {
  accountId: string; sourceId: string; payload: string; journal: LegacyJournalRow[];
  complete: boolean; oldWritesStopped: boolean; journalComplete: boolean;
}
export class LegacyReadControl {
  cancelled: boolean = false;
  timeoutMs: number;
  constructor(timeoutMs: number = 30000) { this.timeoutMs = timeoutMs; }
}

// Reads into memory first. No partially read page can reach the business database.
export class LegacySnapshotReader {
  private static ids(ids: string[]): string[] {
    if (!Array.isArray(ids) || ids.some((id: string) => typeof id !== 'string' || id.length === 0) ||
      new Set<string>(ids).size !== ids.length) { throw new Error('Incomplete snapshot identity list.'); }
    return ids.slice().sort();
  }
  private static descriptor(source: LegacySnapshotDescriptor, account: string): LegacySnapshotDescriptor {
    const d: LegacySnapshotDescriptor = JSON.parse(JSON.stringify(source)) as LegacySnapshotDescriptor;
    if (d === null || d.accountId !== account || typeof d.sourceId !== 'string' || d.sourceId.length === 0 ||
      typeof d.revision !== 'string' || d.revision.length === 0 || typeof d.boundaryId !== 'string' || d.boundaryId.length === 0 ||
      typeof d.historySeal !== 'string' || d.historySeal.length === 0 || d.oldWritesStopped !== true ||
      !CloudProtocolPolicy.canExchange(d.minimumProtocol) || !Array.isArray(d.manifests)) {
      throw new Error('The frozen source or deletion history cannot be verified.');
    }
    [d.journal, d.deadlines, d.tasks].forEach((section: LegacySnapshotSection) => {
      if (section === undefined || section === null || !Number.isSafeInteger(section.pages) || section.pages < 1) {
        throw new Error('Missing snapshot page manifest.');
      }
      section.ids = LegacySnapshotReader.ids(section.ids);
    });
    const roots: string[] = [];
    const taskIds: string[] = [];
    d.manifests.forEach((m: LegacyTaskManifest) => {
      if (m === null || typeof m.deadlineId !== 'string' || !d.deadlines.ids.includes(m.deadlineId)) {
        throw new Error('Invalid task manifest owner.');
      }
      roots.push(m.deadlineId); m.taskIds = LegacySnapshotReader.ids(m.taskIds);
      taskIds.push(...m.taskIds);
    });
    if (JSON.stringify(LegacySnapshotReader.ids(roots)) !== JSON.stringify(d.deadlines.ids) ||
      JSON.stringify(LegacySnapshotReader.ids(taskIds)) !== JSON.stringify(d.tasks.ids)) {
      throw new Error('The task manifest does not cover the frozen snapshot.');
    }
    d.manifests.sort((a: LegacyTaskManifest, b: LegacyTaskManifest) => a.deadlineId.localeCompare(b.deadlineId));
    return d;
  }
  static validateJournal(rows: LegacyJournalRow[]): DeadlineSyncEvent[] {
    const events: Map<string, DeadlineSyncEvent> = new Map<string, DeadlineSyncEvent>();
    const physical: Map<string, string> = new Map<string, string>();
    rows.forEach((row: LegacyJournalRow) => {
      if (row === null || typeof row.id !== 'string' || row.id.length === 0 || typeof row.deadline_id !== 'string' ||
        row.deadline_id.length === 0 || typeof row.payload !== 'string' ||
        Object.keys(row).some((key: string) => !['id', 'deadline_id', 'payload'].includes(key)) ||
        !CloudProtocolPolicy.canExchange(CloudProtocolPolicy.transportVersion(row.payload))) {
        throw new Error('Unsupported history row.');
      }
      const event: DeadlineSyncEvent = CloudProtocolPolicy.readTransport(row.id, row.deadline_id, row.payload);
      const canonical: string = JSON.stringify(event);
      if ((physical.has(row.id) && physical.get(row.id) !== row.payload) ||
        (events.has(event.id) && JSON.stringify(events.get(event.id)) !== canonical)) {
        throw new Error('The history contains different versions of one immutable row.');
      }
      physical.set(row.id, row.payload); events.set(event.id, event);
    });
    events.forEach((event: DeadlineSyncEvent) => {
      if (event.parents.some((id: string) => !events.has(id) || events.get(id)?.deadlineId !== event.deadlineId)) {
        throw new Error('The history export is missing an ancestor.');
      }
    });
    const visited: Set<string> = new Set<string>();
    const visiting: Set<string> = new Set<string>();
    const visit = (id: string): void => {
      if (visiting.has(id)) { throw new Error('The history export has a causal cycle.'); }
      if (visited.has(id)) { return; }
      visiting.add(id);
      events.get(id)?.parents.forEach((parent: string) => visit(parent));
      visiting.delete(id); visited.add(id);
    };
    events.forEach((event: DeadlineSyncEvent) => visit(event.id));
    const roots: Set<string> = new Set<string>();
    events.forEach((event: DeadlineSyncEvent) => roots.add(event.deadlineId));
    roots.forEach((id: string) => {
      const result = DeadlineSyncProtocol.merge(Array.from(events.values()).filter((e: DeadlineSyncEvent) => e.deadlineId === id), id);
      if (result.pending || result.conflicts.includes('invalid') || result.conflicts.includes('causal')) {
        throw new Error('The history export is not causally complete.');
      }
    });
    return Array.from(events.values());
  }
  private static async checked<T>(action: () => Promise<T>, account: string,
    verifyAccount: () => Promise<string>, control: LegacyReadControl): Promise<T> {
    if (control.cancelled || await verifyAccount() !== account) { throw new Error('The import account changed or reading was cancelled.'); }
    const result: T = await new Promise<T>((resolve, reject) => {
      const timer: number = setTimeout(() => reject(new Error('The snapshot read timed out; nothing was imported.')), control.timeoutMs);
      Promise.resolve().then(action).then((value: T) => { clearTimeout(timer); resolve(value); },
        () => { clearTimeout(timer); reject(new Error('The snapshot could not be read; nothing was imported.')); });
    });
    if (control.cancelled || await verifyAccount() !== account) { throw new Error('The import account changed or reading was cancelled.'); }
    return result;
  }
  private static async section(source: LegacySnapshotSource, d: LegacySnapshotDescriptor,
    name: string, manifest: LegacySnapshotSection, verifyAccount: () => Promise<string>, control: LegacyReadControl): Promise<string[]> {
    let cursor: string = '';
    const cursors: Set<string> = new Set<string>();
    const rows: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let index: number = 0; index < manifest.pages; index++) {
      if (cursors.has(cursor)) { throw new Error('A snapshot page cursor repeated.'); }
      cursors.add(cursor);
      const requested: string = cursor;
      const page: LegacySnapshotPage = await LegacySnapshotReader.checked(
        () => source.page(JSON.parse(JSON.stringify(d)) as LegacySnapshotDescriptor, name, requested), d.accountId, verifyAccount, control);
      const last: boolean = index === manifest.pages - 1;
      if (page === null || page.accountId !== d.accountId || page.sourceId !== d.sourceId || page.revision !== d.revision ||
        page.section !== name || page.cursor !== requested || page.finished !== last || typeof page.nextCursor !== 'string' ||
        (last ? page.nextCursor !== '' : page.nextCursor.length === 0) || !Array.isArray(page.rows)) {
        throw new Error('The snapshot changed or a page is incomplete.');
      }
      page.rows.forEach((raw: string) => {
        const row: LegacyDeadlineRow = JSON.parse(raw) as LegacyDeadlineRow;
        if (row === null || typeof row.id !== 'string' || !manifest.ids.includes(row.id)) {
          throw new Error('A page has an unexpected or missing record identity.');
        }
        if (name === 'tasks') {
          const task: LegacyTaskRow = JSON.parse(raw) as LegacyTaskRow;
          if (!d.manifests.some((m: LegacyTaskManifest) => m.deadlineId === task.deadline_id && m.taskIds.includes(task.id))) {
            throw new Error('A task belongs to another frozen project.');
          }
        }
        seen.add(row.id); rows.push(raw);
      });
      cursor = page.nextCursor;
    }
    if (JSON.stringify(Array.from(seen).sort()) !== JSON.stringify(manifest.ids)) { throw new Error('Not every declared record arrived.'); }
    // Stable under different page arrival/grouping; bad business values stay intact for per-project isolation.
    return Array.from(new Set<string>(rows)).sort();
  }
  static async collect(source: LegacySnapshotSource, verifyAccount: () => Promise<string>,
    control: LegacyReadControl = new LegacyReadControl()): Promise<FrozenLegacyRead> {
    const account: string = await verifyAccount();
    if (account.length === 0 || control.cancelled) { throw new Error('No active verified import account.'); }
    const d: LegacySnapshotDescriptor = LegacySnapshotReader.descriptor(
      await LegacySnapshotReader.checked(() => source.begin(account), account, verifyAccount, control), account);
    const journalRaw: string[] = await LegacySnapshotReader.section(source, d, 'journal', d.journal, verifyAccount, control);
    const journal: LegacyJournalRow[] = journalRaw.map((row: string) => JSON.parse(row) as LegacyJournalRow);
    LegacySnapshotReader.validateJournal(journal);
    const deadlines: string[] = await LegacySnapshotReader.section(source, d, 'deadlines', d.deadlines, verifyAccount, control);
    const tasks: string[] = await LegacySnapshotReader.section(source, d, 'tasks', d.tasks, verifyAccount, control);
    const sealed: LegacySnapshotDescriptor = LegacySnapshotReader.descriptor(await LegacySnapshotReader.checked(
      () => source.seal(JSON.parse(JSON.stringify(d)) as LegacySnapshotDescriptor), account, verifyAccount, control), account);
    if (JSON.stringify(sealed) !== JSON.stringify(d)) { throw new Error('The frozen export or its barriers changed during reading.'); }
    const data: LegacyCloudData = { deadlines: deadlines.map((row: string) => JSON.parse(row) as LegacyDeadlineRow),
      tasks: tasks.map((row: string) => JSON.parse(row) as LegacyTaskRow), manifests: d.manifests };
    return { accountId: account, sourceId: d.sourceId, payload: JSON.stringify(data), journal: journal,
      complete: true, oldWritesStopped: true, journalComplete: true };
  }
}
