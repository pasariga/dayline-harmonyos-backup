import { describe, expect, it } from '@ohos/hypium';
import { LegacyCloudData, LegacyCloudImport, LegacyImportTrust } from '../main/ets/services/LegacyCloudImport';
import { CloudProtocolPolicy } from '../main/ets/services/CloudProtocolPolicy';
import { DeadlineSyncEvent, DeadlineSyncProtocol, SyncAggregate } from '../main/ets/services/DeadlineSyncProtocol';
import { DeadlineConflictRecovery, RecoverySelection } from '../main/ets/services/DeadlineConflictRecovery';
import { DeadlineSubtask } from '../main/ets/models/Deadline';

function data(): LegacyCloudData {
  return { deadlines: [{ id: 'old-x', name: 'Old exam', type: '考试', deadline_date: '2026-11-01',
    deadline_time: '18:00', deadline_at: 1793527200000, created_at: 1791000000000,
    completed: 0, estimated_hours: 10, progress: 0, progress_mode: 'automatic', reminder_offset_minutes: 60 }],
    tasks: [], manifests: [{ deadlineId: 'old-x', taskIds: [] }] };
}
function imported(d: LegacyCloudData): DeadlineSyncEvent {
  return LegacyCloudImport.plan(JSON.stringify(d)).items[0].event as DeadlineSyncEvent;
}
function local(d: LegacyCloudData): DeadlineSyncEvent {
  const a: SyncAggregate = DeadlineSyncProtocol.normalize((imported(d).snapshot as SyncAggregate));
  return new DeadlineSyncEvent('local-root', 'old-x', [], undefined, a);
}
function resolved(events: DeadlineSyncEvent[], current: SyncAggregate): DeadlineSyncEvent {
  const review = DeadlineConflictRecovery.review(events, 'old-x', current);
  return DeadlineConflictRecovery.resolve(review, review.fields.map((f) =>
    new RecoverySelection(f.key, f.currentValue || f.values[0])), events, current, 'chosen');
}
export default function legacyCloudImportTest() {
  describe('legacyCloudImport', () => {
    it('only byte exact known old archives can receive a trusted transport carrier', 0, () => {
      const event = local(data()); event.version = 1;
      const canonical = JSON.stringify(DeadlineSyncProtocol.decode(JSON.stringify(event)));
      expect(CloudProtocolPolicy.canCarryHistorical(event.id, canonical)).assertTrue();
      expect(CloudProtocolPolicy.canCarryHistorical('other-id', canonical)).assertFalse();
      expect(CloudProtocolPolicy.canCarryHistorical(event.id, canonical.slice(0, -1) + ',"unknownFutureField":true}')).assertFalse();
      expect(CloudProtocolPolicy.canCarryHistorical(event.id, ' ' + canonical)).assertFalse();
      expect(CloudProtocolPolicy.canCarryHistorical(event.id, '{broken')).assertFalse();
    });
    it('old Deadline enters as an unsequenced baseline with unknown hours', 0, () => {
      const e = imported(data()); const r = DeadlineSyncProtocol.merge([e], 'old-x');
      expect(e.version).assertEqual(2); expect(e.legacy).assertTrue(); expect(e.parents.length).assertEqual(0);
      expect(r.aggregate?.deadline.estimatedHours).assertEqual(10);
      expect(r.aggregate?.deadline.remainingState).assertEqual('unknown'); expect(r.conflicts.length).assertEqual(0);
    });
    it('complete multi-level old task tree is preserved', 0, () => {
      const d = data(); d.tasks = [
        { id:'p', deadline_id:'old-x', title:'Parent', completed:0, created_at:10, parent_id:'', sort_order:0 },
        { id:'t', deadline_id:'old-x', title:'Task', completed:1, created_at:11, parent_id:'p', sort_order:0 }];
      d.manifests[0].taskIds = ['p','t']; const r = DeadlineSyncProtocol.merge([imported(d)],'old-x');
      expect(r.aggregate?.tasks.length).assertEqual(2); expect(r.aggregate?.tasks[1].parentId).assertEqual('p');
      expect(r.aggregate?.deadline.remainingState).assertEqual('unknown');
    });
    it('one two ten imports have one canonical event and identical full state', 0, () => {
      const e = imported(data()); const events: DeadlineSyncEvent[] = [];
      for (let i=0;i<10;i++) { events.push(imported(data())); }
      expect(new Set<string>(events.map((x) => x.id)).size).assertEqual(1);
      expect(JSON.stringify(DeadlineSyncProtocol.merge(events,'old-x')))
        .assertEqual(JSON.stringify(DeadlineSyncProtocol.merge([e],'old-x')));
    });
    it('partial task transfer is held then a full retry produces the tree', 0, () => {
      const d = data(); d.manifests[0].taskIds = ['t'];
      expect(imported(d) === undefined).assertTrue();
      d.tasks = [{id:'t',deadline_id:'old-x',title:'Task',completed:0,created_at:1}];
      expect(DeadlineSyncProtocol.merge([imported(d)],'old-x').aggregate?.tasks.length).assertEqual(1);
    });
    it('matching old data does not compete with locally confirmed newer fields', 0, () => {
      const d = data(); const l = local(d); (l.snapshot as SyncAggregate).deadline.remainingHours=6;
      (l.snapshot as SyncAggregate).deadline.remainingState='confirmed'; (l.snapshot as SyncAggregate).deadline.remainingUpdatedAt=1791000001000;
      const r = DeadlineSyncProtocol.merge([l,imported(d)],'old-x');
      expect(r.conflicts.length).assertEqual(0); expect(r.aggregate?.deadline.remainingHours).assertEqual(6);
    });
    it('local permanent deletion absorbs the still-live old row in both orders', 0, () => {
      const e = imported(data()); const del = new DeadlineSyncEvent('deleted','old-x',[],undefined,undefined);
      expect(DeadlineSyncProtocol.merge([del,e],'old-x').deleted).assertTrue();
      expect(DeadlineSyncProtocol.merge([e,del],'old-x').deleted).assertTrue();
    });
    it('null or absent workload evidence never becomes known zero or completion-weighted hours', 0, () => {
      const d=data(); d.deadlines[0].remaining_hours=null; d.deadlines[0].remaining_state=null;
      d.deadlines[0].progress=75; const e=imported(d); const r=DeadlineSyncProtocol.merge([e],'old-x');
      expect(e.importFields?.includes('remaining')).assertFalse(); expect(r.aggregate?.deadline.remainingState).assertEqual('unknown');
      expect(r.aggregate?.deadline.estimatedHours).assertEqual(10);
      d.deadlines[0].estimated_hours=null; expect(imported(d).importFields?.includes('total')).assertFalse();
    });
    it('missing task ancestor keeps the old aggregate quarantined', 0, () => {
      const d=data(); d.tasks=[{id:'t',deadline_id:'old-x',title:'Task',completed:0,created_at:1,parent_id:'missing'}];
      d.manifests[0].taskIds=['t']; expect(imported(d) === undefined).assertTrue();
    });
    it('identical old task repeats collapse but different versions never get guessed', 0, () => {
      const d=data(); d.tasks=[{id:'t',deadline_id:'old-x',title:'Task',completed:0,created_at:1},
        {id:'t',deadline_id:'old-x',title:'Task',completed:0,created_at:1}]; d.manifests[0].taskIds=['t'];
      expect(imported(d).snapshot?.tasks.length).assertEqual(1); d.tasks[1].title='Other';
      expect(imported(d) === undefined).assertTrue();
    });
    it('bad format and missing IDs cannot become projects while independent good rows survive', 0, () => {
      expect(LegacyCloudImport.plan('{broken').items[0].event === undefined).assertTrue();
      const d=data(); d.deadlines[0].id=''; expect(imported(d) === undefined).assertTrue();
      const good=data(); good.deadlines.push(d.deadlines[0]); const plan=LegacyCloudImport.plan(JSON.stringify(good));
      expect(plan.items.filter((x)=>x.event!==undefined).length).assertEqual(1);
    });
    it('account A B and unverifiable sources are denied before import', 0, () => {
      expect(LegacyCloudImport.authorized('A',new LegacyImportTrust('B','A','snapshot',true,true,true))).assertFalse();
      expect(LegacyCloudImport.authorized('A',new LegacyImportTrust('B','B','snapshot',true,true,true))).assertFalse();
      expect(LegacyCloudImport.authorized('',new LegacyImportTrust('','A','snapshot',true,true,true))).assertFalse();
      expect(LegacyCloudImport.authorized('A',new LegacyImportTrust('A','A','snapshot',true,true,true))).assertTrue();
    });
    it('old clients cannot exchange and missing writer/history barriers stay closed', 0, () => {
      expect(CloudProtocolPolicy.canExchange(1)).assertFalse(); expect(CloudProtocolPolicy.canExchange(2)).assertTrue();
      expect(CloudProtocolPolicy.canExchange(3)).assertFalse();
      expect(LegacyCloudImport.authorized('A',new LegacyImportTrust('A','A','s',true,false,true))).assertFalse();
      expect(LegacyCloudImport.authorized('A',new LegacyImportTrust('A','A','s',true,true,false))).assertFalse();
    });
    it('old children of permanently removed parents cannot revive the branch', 0, () => {
      const d=data(); d.tasks=[{id:'p',deadline_id:'old-x',title:'Parent',completed:0,created_at:1},
        {id:'t',deadline_id:'old-x',title:'Task',completed:0,created_at:2,parent_id:'p'}]; d.manifests[0].taskIds=['p','t'];
      const e=imported(d); const remove=new DeadlineSyncEvent('remove','old-x',[],undefined,
        new SyncAggregate((e.snapshot as SyncAggregate).deadline,[]),['p']);
      const r=DeadlineSyncProtocol.merge([e,remove],'old-x'); expect(r.aggregate?.tasks.length).assertEqual(0);
    });
    it('old baseline and its later new-protocol descendant tolerate reversed arrival', 0, () => {
      const e=imported(data()); const a=DeadlineSyncProtocol.normalize(e.snapshot as SyncAggregate);a.deadline.name='After';
      const child=new DeadlineSyncEvent('new','old-x',[e.id],e.snapshot,a);
      expect(DeadlineSyncProtocol.merge([child],'old-x').pending).assertTrue();
      expect(JSON.stringify(DeadlineSyncProtocol.merge([child,e],'old-x')))
        .assertEqual(JSON.stringify(DeadlineSyncProtocol.merge([e,child],'old-x')));
      expect(DeadlineSyncProtocol.merge([child,e],'old-x').aggregate?.deadline.name).assertEqual('After');
    });
    it('new installation recovers only the complete frozen source into stable IDs', 0, () => {
      const e=imported(data());const r=DeadlineSyncProtocol.merge([e],'old-x');
      expect(r.aggregate?.deadline.id).assertEqual('old-x'); expect(e.id).assertEqual(imported(data()).id);
    });
    it('different names and deadlines require review rather than a fixed winner', 0, () => {
      const d=data();const l=local(d);(l.snapshot as SyncAggregate).deadline.name='Local';
      (l.snapshot as SyncAggregate).deadline.deadlineAt+=86400000;
      const events=[l,imported(d)];const r=DeadlineSyncProtocol.merge(events,'old-x');
      expect(r.conflicts.includes('name')).assertTrue();expect(r.conflicts.includes('due')).assertTrue();
      expect(DeadlineSyncProtocol.merge(events.concat([resolved(events,l.snapshot as SyncAggregate)]),'old-x').conflicts.length).assertEqual(0);
    });
    it('different old and local task lists require a whole-tree choice alongside ordinary fields', 0, () => {
      const d=data();const l=local(d);const a=l.snapshot as SyncAggregate;a.deadline.name='Local';
      a.tasks.push(new DeadlineSubtask('local-task','old-x','New task',false,1));
      const events=[l,imported(d)];const review=DeadlineConflictRecovery.review(events,'old-x',a);
      expect(review.fields.some((f)=>f.key==='name')).assertTrue();expect(review.fields.some((f)=>f.key==='tasks')).assertTrue();
      const result=DeadlineSyncProtocol.merge(events.concat([resolved(events,a)]),'old-x');
      expect(result.conflicts.length).assertEqual(0);expect(result.aggregate?.tasks.length).assertEqual(1);
    });
    it('a changed old row is not interpreted as a newer causal write', 0, () => {
      const a=imported(data());const d=data();d.deadlines[0].name='Changed by old client';const b=imported(d);
      expect(a.id).assertEqual(b.id);expect(DeadlineSyncProtocol.merge([a,b],'old-x').conflicts.includes('invalid')).assertTrue();
    });
    it('historical carriers preserve old bytes identity ancestry and deletion', 0, () => {
      const e=local(data());e.version=1;const before=JSON.stringify(e);const wrapped=CloudProtocolPolicy.wrapHistorical(e);
      const received=CloudProtocolPolicy.readTransport(CloudProtocolPolicy.historicalId(e.id),'old-x',wrapped);
      expect(JSON.stringify(received)).assertEqual(before);expect(JSON.stringify(e)).assertEqual(before);
      const del=new DeadlineSyncEvent('old-delete','old-x',[e.id],undefined,undefined);del.version=1;
      const dead=CloudProtocolPolicy.readTransport(CloudProtocolPolicy.historicalId(del.id),'old-x',CloudProtocolPolicy.wrapHistorical(del));
      expect(DeadlineSyncProtocol.merge([received,dead],'old-x').deleted).assertTrue();
    });
    it('new installation can recover old V7 ancestors via protocol two carriers', 0, () => {
      const e=local(data());e.version=1;const a=DeadlineSyncProtocol.normalize(e.snapshot as SyncAggregate);a.deadline.name='New client';
      const child=new DeadlineSyncEvent('child','old-x',[e.id],e.snapshot,a);
      const parent=CloudProtocolPolicy.readTransport(CloudProtocolPolicy.historicalId(e.id),'old-x',CloudProtocolPolicy.wrapHistorical(e));
      const r=DeadlineSyncProtocol.merge([child,parent],'old-x');expect(r.pending).assertFalse();
      expect(r.aggregate?.deadline.name).assertEqual('New client');
    });
    it('historical carrier identity cannot be swapped between projects', 0, () => {
      const e=local(data());e.version=1;let denied=false;
      try { CloudProtocolPolicy.readTransport(CloudProtocolPolicy.historicalId(e.id),'another',CloudProtocolPolicy.wrapHistorical(e)); }
      catch(error){ denied=true; }expect(denied).assertTrue();
    });
  });
}
