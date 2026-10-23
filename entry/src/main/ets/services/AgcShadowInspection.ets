import { LegacyCloudData, LegacyCloudImport, LegacyDeadlineRow, LegacyTaskRow, LegacyTaskManifest } from './LegacyCloudImport';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate } from './DeadlineSyncProtocol';
import { CloudProtocolPolicy } from './CloudProtocolPolicy';
import { LegacyJournalRow, LegacyReadControl } from './LegacySnapshotReader';

// Inspection evidence is deliberately weaker than FrozenLegacyRead. An observed
// task list is NOT an independent manifest, nor is a finished download a freeze.
export interface AgcInspectionMetadata {
  account: string; source: string; revision: string;
  accountAttested: boolean; writersStopped: boolean; deletionCoverage: boolean; treeAttested: boolean;
}
export interface AgcInspectionPage {
  account: string; source: string; section: string; cursor: string;
  nextCursor: string; finished: boolean; rows: string[];
}
export interface AgcInspectionSource {
  begin(): Promise<AgcInspectionMetadata>;
  page(section: string, cursor: string): Promise<AgcInspectionPage>;
  end(): Promise<AgcInspectionMetadata>;
}
export interface AgcObservation {
  metadata: AgcInspectionMetadata; deadlines: string[]; tasks: string[]; journal: string[];
}
export interface AgcShadowLocal {
  owner: string; aggregates: SyncAggregate[]; events: DeadlineSyncEvent[];
}
export class AgcShadowItem {
  // IDs and content belong only in private memory, never in the validation report.
  id: string; classification: string; comparison: string; blockers: string[];
  constructor(id: string, classification: string, comparison: string, blockers: string[]) {
    this.id = id; this.classification = classification; this.comparison = comparison; this.blockers = blockers;
  }
}
export interface AgcShadowStatistics {
  deadlineRows: number; taskRows: number; journalRows: number; duplicateRows: number;
  malformedRows: number; orphanTasks: number; missingFields: number; nullFields: number; overlap: number;
}
export interface AgcShadowSummary {
  importAllowed: boolean; classifications: Record<string, number>; comparisons: Record<string, number>;
  blockers: string[]; statistics: AgcShadowStatistics;
}
export class AgcShadowResult {
  items: AgcShadowItem[] = [];
  blockers: string[] = [];
  statistics: AgcShadowStatistics = { deadlineRows: 0, taskRows: 0, journalRows: 0,
    duplicateRows: 0, malformedRows: 0, orphanTasks: 0, missingFields: 0, nullFields: 0, overlap: 0 };
  // No raw rows, IDs, account, credentials, values or arbitrary input keys leave this boundary.
  summary(): AgcShadowSummary {
    const counts: Record<string, number> = {};
    const comparisons: Record<string, number> = {};
    this.items.forEach((item: AgcShadowItem) => {
      counts[item.classification] = (counts[item.classification] ?? 0) + 1;
      comparisons[item.comparison] = (comparisons[item.comparison] ?? 0) + 1;
    });
    return { importAllowed: false, classifications: counts, comparisons: comparisons,
      blockers: this.blockers.slice().sort(), statistics: this.statistics };
  }
}

export class AgcShadowInspection {
  private static validMetadata(m: AgcInspectionMetadata): boolean {
    return m !== null && typeof m.account === 'string' && typeof m.source === 'string' && m.source.length > 0 &&
      typeof m.revision === 'string' && typeof m.accountAttested === 'boolean' && typeof m.writersStopped === 'boolean' &&
      typeof m.deletionCoverage === 'boolean' && typeof m.treeAttested === 'boolean';
  }
  private static async checked<T>(action: () => Promise<T>, account: string,
    verify: () => Promise<string>, control: LegacyReadControl): Promise<T> {
    if (control.cancelled || await verify() !== account) { throw new Error('Inspection identity unavailable.'); }
    const result: T = await new Promise<T>((resolve, reject) => {
      const timer: number = setTimeout(() => reject(new Error('Inspection timed out.')), control.timeoutMs);
      Promise.resolve().then(action).then((value: T) => { clearTimeout(timer); resolve(value); },
        () => { clearTimeout(timer); reject(new Error('Inspection read failed.')); });
    });
    if (control.cancelled || await verify() !== account) { throw new Error('Inspection identity changed.'); }
    return result;
  }
  static async collect(source: AgcInspectionSource, verify: () => Promise<string>,
    control: LegacyReadControl = new LegacyReadControl()): Promise<AgcObservation> {
    const account: string = await verify();
    if (account.length === 0) { throw new Error('Inspection identity unavailable.'); }
    const metadata: AgcInspectionMetadata = JSON.parse(JSON.stringify(await AgcShadowInspection.checked(
      () => source.begin(), account, verify, control))) as AgcInspectionMetadata;
    if (!AgcShadowInspection.validMetadata(metadata) || metadata.account !== account) { throw new Error('Inspection source mismatch.'); }
    const sections: string[][] = [];
    for (const section of ['journal', 'deadlines', 'tasks']) {
      const rows: string[] = []; const cursors: Set<string> = new Set<string>(); let cursor: string = '';
      while (true) {
        if (cursors.has(cursor) || cursors.size >= 1000) { throw new Error('Inspection paging incomplete.'); }
        cursors.add(cursor); const requested: string = cursor;
        const page: AgcInspectionPage = await AgcShadowInspection.checked(() => source.page(section, requested),
          account, verify, control);
        if (page.account !== account || page.source !== metadata.source || page.section !== section ||
          page.cursor !== requested || !Array.isArray(page.rows) || page.rows.some((r: string) => typeof r !== 'string') ||
          (page.finished ? page.nextCursor !== '' : page.nextCursor.length === 0)) {
          throw new Error('Inspection page mismatch.');
        }
        rows.push(...page.rows);
        if (rows.length > 100000) { throw new Error('Inspection size limit.'); }
        if (page.finished) { break; }
        cursor = page.nextCursor;
      }
      sections.push(rows);
    }
    const end = await AgcShadowInspection.checked(() => source.end(), account, verify, control);
    if (JSON.stringify(end) !== JSON.stringify(metadata)) { throw new Error('Inspection source changed.'); }
    return { metadata: metadata, journal: sections[0], deadlines: sections[1], tasks: sections[2] };
  }
  private static unique<T>(rows: string[], statistics: AgcShadowStatistics): T[] {
    const byId: Map<string, string> = new Map<string, string>(); const values: T[] = [];
    rows.forEach((raw: string) => {
      const value: LegacyDeadlineRow = JSON.parse(raw) as LegacyDeadlineRow;
      if (value === null || typeof value.id !== 'string' || value.id.length === 0) { throw new Error('Invalid inspection identity.'); }
      const keys: string[] = Object.keys(value).sort();
      const canonical: string = JSON.stringify(value, keys);
      const prior = byId.get(value.id);
      if (prior !== undefined) {
        statistics.duplicateRows++;
        if (prior !== canonical) { throw new Error('Different inspection rows share an identity.'); }
      } else { byId.set(value.id, canonical); values.push(JSON.parse(raw) as T); }
    });
    return values;
  }
  private static history(raw: string[], statistics: AgcShadowStatistics): DeadlineSyncEvent[] {
    const rows: LegacyJournalRow[] = AgcShadowInspection.unique<LegacyJournalRow>(raw, statistics);
    return rows.map((row: LegacyJournalRow) => {
      if (Object.keys(row).some((key: string) => !['id','deadline_id','payload'].includes(key))) {
        throw new Error('Unsupported inspection history.');
      }
      if (!CloudProtocolPolicy.canExchange(CloudProtocolPolicy.transportVersion(row.payload))) {
        throw new Error('Untrusted old inspection history.');
      }
      return CloudProtocolPolicy.readTransport(row.id, row.deadline_id, row.payload);
    });
  }
  private static ancestry(events: DeadlineSyncEvent[]): Map<string, Set<string>> {
    const byId: Map<string, DeadlineSyncEvent> = new Map<string, DeadlineSyncEvent>();
    events.forEach((e: DeadlineSyncEvent) => {
      const prior = byId.get(e.id);
      if (prior !== undefined && JSON.stringify(prior) !== JSON.stringify(e)) { throw new Error('Immutable history differs.'); }
      byId.set(e.id, e);
    });
    const result: Map<string, Set<string>> = new Map<string, Set<string>>(); const visiting: Set<string> = new Set<string>();
    const visit = (id: string): Set<string> => {
      const prior = result.get(id); if (prior !== undefined) { return prior; }
      const e = byId.get(id);
      if (e === undefined || visiting.has(id)) { throw new Error('History incomplete.'); }
      visiting.add(id); const parents: Set<string> = new Set<string>();
      e.parents.forEach((p: string) => {
        if (byId.get(p)?.deadlineId !== e.deadlineId) { throw new Error('History incomplete.'); }
        parents.add(p); visit(p).forEach((ancestor: string) => parents.add(ancestor));
      });
      visiting.delete(id); result.set(id, parents); return parents;
    };
    byId.forEach((e) => visit(e.id)); return result;
  }
  private static comparison(local: DeadlineSyncEvent[], cloud: DeadlineSyncEvent[],
    original: SyncAggregate | undefined, old: DeadlineSyncEvent | undefined): string {
    const all: DeadlineSyncEvent[] = local.concat(cloud);
    const graph = AgcShadowInspection.ancestry(all);
    const id: string = original?.deadline.id ?? old?.deadlineId ?? cloud[0]?.deadlineId ?? local[0]?.deadlineId ?? '';
    // Simulate the actual compatibility baseline alongside history. A causal
    // event must not hide a disagreeing old business row from this same scan.
    const proposed: DeadlineSyncEvent[] = old === undefined || all.some((e) => e.id === old.id) ? all : all.concat([old]);
    if (old !== undefined && all.some((e) => e.id === old.id && JSON.stringify(e) !== JSON.stringify(old))) {
      return 'cannot_decide';
    }
    const merged = DeadlineSyncProtocol.merge(proposed, id);
    if (merged.pending || merged.conflicts.includes('invalid') || merged.conflicts.includes('causal')) { return 'history_insufficient'; }
    if (merged.deleted) { return 'cloud_deleted'; }
    if (merged.conflicts.length > 0) { return 'conflict_confirmation'; }
    const localIds: Set<string> = new Set<string>(local.map((e) => e.id));
    const cloudIds: Set<string> = new Set<string>(cloud.map((e) => e.id));
    const covers = (a: DeadlineSyncEvent[], b: DeadlineSyncEvent[]): boolean =>
      b.every((e) => a.some((head) => head.id === e.id || graph.get(head.id)?.has(e.id)));
    if (cloud.length > 0 && local.length > 0) {
      if (covers(local, cloud) && local.some((e) => !cloudIds.has(e.id))) { return 'local_newer'; }
      if (covers(cloud, local) && cloud.some((e) => !localIds.has(e.id))) { return 'cloud_newer'; }
    }
    if (old !== undefined && original !== undefined && old.snapshot !== undefined) {
      const originalFields = DeadlineSyncProtocol.fields(DeadlineSyncProtocol.normalize(original));
      const oldFields = DeadlineSyncProtocol.fields(old.snapshot);
      const same: boolean = (old.importFields ?? []).every((key: string) => oldFields.get(key) === originalFields.get(key)) &&
        JSON.stringify(old.snapshot.tasks) === JSON.stringify(DeadlineSyncProtocol.normalize(original).tasks);
      if (same) { return 'local_equal'; }
      return 'cannot_decide';
    }
    if (original === undefined) { return 'baseline_candidate'; }
    if (merged.aggregate !== undefined && JSON.stringify(merged.aggregate) === JSON.stringify(DeadlineSyncProtocol.normalize(original))) {
      return 'local_equal';
    }
    return cloud.length > 0 ? 'safe_merge' : 'cannot_decide';
  }
  static analyze(observation: AgcObservation, input: AgcShadowLocal, verifiedAccount: string): AgcShadowResult {
    // The engine has no database, account binding, import, notification or write callback.
    const local: AgcShadowLocal = JSON.parse(JSON.stringify(input)) as AgcShadowLocal;
    const result: AgcShadowResult = new AgcShadowResult(); const m = observation.metadata;
    result.statistics.deadlineRows = observation.deadlines.length; result.statistics.taskRows = observation.tasks.length;
    result.statistics.journalRows = observation.journal.length;
    if (!AgcShadowInspection.validMetadata(m)) {
      result.blockers = ['inspection_metadata_invalid'];
      result.items.push(new AgcShadowItem('', 'cannot_decide', 'cannot_decide', result.blockers.slice())); return result;
    }
    if (verifiedAccount.length === 0 || m.account !== verifiedAccount ||
      (local.owner.length > 0 && local.owner !== verifiedAccount)) {
      result.items.push(new AgcShadowItem('', 'account_mismatch', 'cannot_decide', ['account_mismatch']));
      result.blockers = ['account_mismatch']; return result;
    }
    if (!m.accountAttested) { result.blockers.push('source_account_unattested'); }
    if (!m.writersStopped || m.revision.length === 0) { result.blockers.push('source_not_frozen'); }
    if (!m.deletionCoverage) { result.blockers.push('deletion_history_unattested'); }
    if (!m.treeAttested) { result.blockers.push('task_manifest_unattested'); }
    let deadlines: LegacyDeadlineRow[]; let tasks: LegacyTaskRow[]; let cloud: DeadlineSyncEvent[];
    try {
      deadlines = AgcShadowInspection.unique<LegacyDeadlineRow>(observation.deadlines, result.statistics);
      tasks = AgcShadowInspection.unique<LegacyTaskRow>(observation.tasks, result.statistics);
      cloud = AgcShadowInspection.history(observation.journal, result.statistics);
    } catch (error) {
      result.statistics.malformedRows++;
      result.items.push(new AgcShadowItem('', 'malformed_cloud', 'cannot_decide', ['malformed_cloud'])); return result;
    }
    try {
      local.events = local.events.map((e) => DeadlineSyncProtocol.decode(JSON.stringify(e)));
      local.aggregates = local.aggregates.map((a) => DeadlineSyncProtocol.normalize(a));
    } catch (error) {
      result.blockers.push('local_snapshot_unverifiable');
      result.items.push(new AgcShadowItem('', 'cannot_decide', 'cannot_decide', ['local_snapshot_unverifiable'])); return result;
    }
    const ids: Set<string> = new Set<string>(deadlines.map((d) => d.id));
    cloud.forEach((e) => ids.add(e.deadlineId)); local.aggregates.forEach((a) => ids.add(a.deadline.id));
    const taskOwners: Map<string, string> = new Map<string, string>();
    const ambiguous: Set<string> = new Set<string>();
    local.events.concat(cloud).forEach((e) => {
      [...(e.base?.tasks ?? []), ...(e.snapshot?.tasks ?? [])].forEach((t) => {
        const owner = taskOwners.get(t.id); if (owner !== undefined && owner !== t.deadlineId) { ambiguous.add(owner); ambiguous.add(t.deadlineId); }
        taskOwners.set(t.id, t.deadlineId);
      });
      e.removedTasks.forEach((id: string) => {
        const owner = taskOwners.get(id); if (owner !== undefined && owner !== e.deadlineId) { ambiguous.add(owner); ambiguous.add(e.deadlineId); }
        taskOwners.set(id, e.deadlineId);
      });
    });
    tasks.forEach((t) => {
      const owner = taskOwners.get(t.id); if (owner !== undefined && owner !== t.deadline_id) { ambiguous.add(owner); ambiguous.add(t.deadline_id); }
      taskOwners.set(t.id, t.deadline_id);
      if (!deadlines.some((d) => d.id === t.deadline_id)) { result.statistics.orphanTasks++; }
    });
    const data: LegacyCloudData = { deadlines: deadlines, tasks: tasks,
      manifests: deadlines.map((d): LegacyTaskManifest => ({ deadlineId: d.id, taskIds: tasks.filter((t) => t.deadline_id === d.id).map((t) => t.id) })) };
    // This manifest is observed, not attested. It is used ONLY to simulate the
    // compatibility mapper. Result blockers keep it out of the import contract.
    const plan = LegacyCloudImport.plan(JSON.stringify(data));
    Array.from(ids).sort().forEach((id: string) => {
      const original = local.aggregates.find((a) => a.deadline.id === id);
      const own = local.events.filter((e) => e.deadlineId === id);
      const other = cloud.filter((e) => e.deadlineId === id);
      const row = deadlines.find((d) => d.id === id);
      if (row !== undefined && original !== undefined) { result.statistics.overlap++; }
      if (row !== undefined) {
        ['estimated_hours','progress_mode','remaining_hours','remaining_state','remaining_updated_at'].forEach((key: string) => {
          if (!Object.keys(row).includes(key)) { result.statistics.missingFields++; }
        });
        const fields = JSON.parse(JSON.stringify(row)) as Record<string, string | number | null>;
        Object.keys(row).forEach((key: string) => { if (fields[key] === null) { result.statistics.nullFields++; } });
      }
      let comparison: string = 'cannot_decide'; let classification: string = 'cannot_decide';
      if (own.some((e) => e.deleted)) { comparison = classification = 'local_tombstone'; }
      else if (ambiguous.has(id)) { classification = 'incomplete_cloud'; }
      else if (row === undefined && other.length === 0) { classification = 'cannot_decide'; }
      else {
        const item = plan.items.find((i) => i.id === id);
        if (row !== undefined && item?.event === undefined) { classification = 'incomplete_cloud'; }
        else {
          try {
            comparison = AgcShadowInspection.comparison(own, other, original, item?.event);
            classification = comparison;
            if (comparison === 'baseline_candidate' && !m.deletionCoverage) { classification = 'history_insufficient'; }
            else if (comparison !== 'conflict_confirmation' && comparison !== 'local_equal' &&
              result.blockers.length > 0) { classification = 'cannot_decide'; }
          } catch (error) { classification = 'history_insufficient'; }
        }
      }
      result.items.push(new AgcShadowItem(id, classification, comparison, result.blockers.slice()));
    });
    if (result.statistics.orphanTasks > 0) { result.items.push(new AgcShadowItem('', 'incomplete_cloud', 'cannot_decide', ['orphan_tasks'])); }
    return result;
  }
}
