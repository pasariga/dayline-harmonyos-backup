import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { Deadline, DeadlineSubtask, DeadlineReminderState } from '../main/ets/models/Deadline';
import { DeadlineDataSnapshot } from '../main/ets/services/DeadlineDatabaseService';
import { DeadlineReminderService, DesiredReminder } from '../main/ets/services/DeadlineReminderService';
import { NotificationPolicy, NotificationRiskMark } from '../main/ets/services/NotificationPolicy';
import { NotificationSettings, NotificationRuntimeState } from '../main/ets/services/NotificationSettingsService';
import { AppSettings, AppSettingsRuntime } from '../main/ets/services/AppSettingsService';
import { DeadlineOverdueRuntime } from '../main/ets/services/DeadlineOverdueService';
import { TodayActionService } from '../main/ets/services/TodayActionService';

const NOW = new Date(2026, 9, 4, 7, 0).getTime();
function deadline(id: string = 'a', due: number = NOW + 86400000, hours: number = 3): Deadline {
  return new Deadline(id, id, '考试', '2026-10-05', '07:00', '', NOW, due, false,
    hours, 0, 'automatic', 2, 60, hours, 'confirmed', NOW);
}
function tasks(id: string = 'a'): DeadlineSubtask[] {
  return [new DeadlineSubtask(id+'-1', id, 'First', false, NOW), new DeadlineSubtask(id+'-2', id, 'Second', false, NOW+1)];
}
function plan(ds: Deadline[], ts: DeadlineSubtask[] = [], settings: NotificationSettings = new NotificationSettings(),
  runtime: NotificationRuntimeState = new NotificationRuntimeState(), states: DeadlineReminderState[] = [], now: number = NOW): DesiredReminder[] {
  return DeadlineReminderService.buildDesiredReminders(new DeadlineDataSnapshot(ds, ts), states, settings, runtime, now);
}
function basic(ds: Deadline[], settings: NotificationSettings = new NotificationSettings(), now: number = NOW,
  runtime: NotificationRuntimeState = new NotificationRuntimeState(), states: DeadlineReminderState[] = []): DesiredReminder[] {
  return plan(ds, [], settings, runtime, states, now).filter((item: DesiredReminder) => !item.key.startsWith('smart:'));
}
export default function notificationBehaviorTest() {
  describe('notificationBehavior', () => {
    beforeEach(() => {
      AppSettingsRuntime.apply(new AppSettings('system', 'automatic', 3, true, '23:59', 3));
      DeadlineOverdueRuntime.restore('[]');
    });
    it('creates one cutoff and changes its time when the due date changes', 0, () => {
      const d = deadline(); const s = new NotificationSettings(); s.quietEnabled = false;
      expect(basic([d],s)[0].scheduledAt).assertEqual(d.deadlineAt-3600000);
      const previous=basic([d],s)[0].signature;
      d.deadlineAt+=7200000;
      expect(basic([d],s)[0].signature === previous).assertFalse();
    });
    it('replaces the old offset without producing two cutoff keys', 0, () => {
      const d = deadline(); d.reminderOffsetMinutes=1440; d.deadlineAt+=86400000;
      const s = new NotificationSettings(); s.quietEnabled=false;
      expect(basic([d],s).length).assertEqual(1);
      expect(basic([d],s)[0].scheduledAt).assertEqual(d.deadlineAt-86400000);
    });
    it('removes completed and switched off reminders', 0, () => {
      const d=deadline(); d.completed=true; expect(basic([d]).length).assertEqual(0);
      d.completed=false; d.reminderOffsetMinutes=0; expect(basic([d]).length).assertEqual(0);
    });
    it('restores only a single future reminder and does not replay a past offset', 0, () => {
      const d=deadline(); expect(basic([d]).length).assertEqual(1);
      d.deadlineAt=NOW+1800000; expect(basic([d]).length).assertEqual(0);
    });
    it('deletion and same-name recreation use separate deadline identities', 0, () => {
      const s = new NotificationSettings(); s.quietEnabled=false;
      const old=deadline('old'); const next=deadline('new'); next.name=old.name;
      expect(basic([],s).length).assertEqual(0);
      expect(basic([next],s)[0].key).assertEqual('new');
    });
    it('keeps a reminder in the last two minutes before it fires', 0, () => {
      const s=new NotificationSettings(); s.quietEnabled=false;
      const d=deadline('near',NOW+3660000);
      expect(basic([d],s)[0].scheduledAt).assertEqual(NOW+60000);
    });
    it('ordinary task activity never postpones the explicit cutoff', 0, () => {
      const s=new NotificationSettings(); s.quietEnabled=false;
      const d=deadline('active',NOW+3720000);
      expect(basic([d],s,NOW,new NotificationRuntimeState(NOW,d.id))[0].scheduledAt).assertEqual(NOW+120000);
    });
    it('advances a cutoff before a cross-midnight quiet interval', 0, () => {
      const now=new Date(2026,9,4,20).getTime(); const due=new Date(2026,9,5,7).getTime();
      expect(basic([deadline('quiet',due)],new NotificationSettings(),now)[0].scheduledAt)
        .assertEqual(new Date(2026,9,4,22,29).getTime());
    });
    it('handles a quiet interval beginning at midnight', 0, () => {
      const s=new NotificationSettings();s.quietStartMinutes=0;s.quietEndMinutes=480;
      const now=new Date(2026,9,4,21).getTime(); const value=new Date(2026,9,5,6).getTime();
      expect(NotificationPolicy.basicTime(value,value+3600000,s,now)).assertEqual(new Date(2026,9,4,23,59).getTime());
    });
    it('retains an essential cutoff when a late creation has no quiet-free window', 0, () => {
      const s=new NotificationSettings();const now=new Date(2026,9,5,1).getTime();const value=now+3600000;
      expect(NotificationPolicy.basicTime(value,value+3600000,s,now)).assertEqual(value);
    });
    it('does not replay a cutoff already delivered early for quiet hours', 0, () => {
      const s=new NotificationSettings();const before=new Date(2026,9,4,20).getTime();
      const d=deadline('receipt',new Date(2026,9,5,7).getTime());const desired=basic([d],s,before)[0];
      const state=new DeadlineReminderState(d.id,42,desired.scheduledAt,desired.signature);
      expect(basic([d],s,new Date(2026,9,5,1).getTime(),new NotificationRuntimeState(),[state]).length).assertEqual(0);
    });
    it('does not suppress a genuinely changed cutoff with the old receipt', 0, () => {
      const s=new NotificationSettings();s.quietEnabled=false;
      const d=deadline();const previous=basic([d],s)[0];d.deadlineAt+=86400000;
      expect(basic([d],s,previous.scheduledAt+60000,new NotificationRuntimeState(),
        [new DeadlineReminderState(d.id,-1,previous.scheduledAt,previous.signature)]).length).assertEqual(1);
    });
    it('sends no digest for an empty or entirely completed portfolio', 0, () => {
      expect(plan([]).length).assertEqual(0);
      const d=deadline();d.completed=true;expect(plan([d],tasks()).length).assertEqual(0);
    });
    it('skips today after all anchored tasks were handled but keeps later help', 0, () => {
      const d=deadline('a',NOW+4*86400000); const ts=tasks();ts[0].completed=true;
      const runtime=new NotificationRuntimeState(0,'','2026-10-04',[ts[0].id]);
      const summaries=plan([d],ts,new NotificationSettings(),runtime).filter((item: DesiredReminder)=>item.key.startsWith('smart:daily:'));
      expect(summaries.some((item: DesiredReminder)=>item.key==='smart:daily:2026-10-04')).assertFalse();
      expect(summaries.length>0).assertTrue();
    });
    it('limits eight deadlines to one short priority digest per day', 0, () => {
      const ds:Deadline[]=[]; const ts:DeadlineSubtask[]=[];
      for(let i=0;i<8;i++){ds.push(deadline('d'+i,NOW+(i+2)*86400000));ts.push(...tasks('d'+i));}
      const daily=plan(ds,ts).filter((item: DesiredReminder)=>item.key.startsWith('smart:daily:'));
      expect(daily.length).assertEqual(3);
      expect(new Set<string>(daily.map((item: DesiredReminder)=>item.key)).size).assertEqual(3);
      expect(plan(ds,ts).some((item: DesiredReminder)=>item.key.startsWith('smart:replan:'))).assertFalse();
    });
    it('does not create catch-up digests after their local clock time', 0, () => {
      const now=new Date(2026,9,4,15).getTime();const d=deadline('a',NOW+4*86400000);
      expect(plan([d],tasks(),new NotificationSettings(),new NotificationRuntimeState(),[],now)
        .some((item: DesiredReminder)=>item.key==='smart:daily:2026-10-04')).assertFalse();
    });
    it('acknowledges stable high risk and alerts only a meaningful new signal', 0, () => {
      expect(NotificationPolicy.worsened('high','high')).assertFalse();
      expect(NotificationPolicy.worsened('medium','high')).assertFalse();
      expect(NotificationPolicy.worsened('medium','none')).assertTrue();
      expect(NotificationPolicy.worsened('high','medium')).assertTrue();
      expect(NotificationPolicy.worsened('confirm','high')).assertTrue();
    });
    it('does not invent risk alerts for missing workload input', 0, () => {
      const d=deadline('missing',NOW+86400000,0);d.remainingState='unknown';
      expect(NotificationPolicy.riskSignal(d,[d],NOW)).assertEqual('none');
    });
    it('keeps a pending risk notice but does not regenerate an acknowledged one', 0, () => {
      const d=deadline('high',NOW+3*86400000,100);
      const initial=plan([d],tasks(d.id)).find((item: DesiredReminder)=>item.key.startsWith('smart:risk:')) as DesiredReminder;
      expect(initial!==undefined).assertTrue();
      const runtime=new NotificationRuntimeState(0,'','',[],JSON.stringify([new NotificationRiskMark(d.id,'high')]),initial.scheduledAt);
      const state=new DeadlineReminderState(initial.key,42,initial.scheduledAt,initial.signature);
      expect(plan([d],tasks(d.id),new NotificationSettings(),runtime,[state]).some((item: DesiredReminder)=>item.key===initial.key)).assertTrue();
      expect(plan([d],tasks(d.id),new NotificationSettings(),runtime,[],initial.scheduledAt+60000)
        .some((item: DesiredReminder)=>item.key.startsWith('smart:risk:'))).assertFalse();
    });
    it('quiet-hour start is inclusive and end is exclusive', 0, () => {
      const s=new NotificationSettings();
      expect(NotificationPolicy.inQuiet(new Date(2026,9,4,22,30).getTime(),s)).assertTrue();
      expect(NotificationPolicy.inQuiet(new Date(2026,9,5,8).getTime(),s)).assertFalse();
      expect(NotificationPolicy.afterQuiet(new Date(2026,9,4,23).getTime(),s)).assertEqual(new Date(2026,9,5,8).getTime());
    });
    it('supports same-day and disabled quiet intervals', 0, () => {
      const s=new NotificationSettings();s.quietStartMinutes=600;s.quietEndMinutes=720;
      const at=new Date(2026,9,4,11).getTime();expect(NotificationPolicy.afterQuiet(at,s)).assertEqual(new Date(2026,9,4,12).getTime());
      s.quietEnabled=false;expect(NotificationPolicy.afterQuiet(at,s)).assertEqual(at);
    });
    it('uses natural calendar dates through month and year boundaries', 0, () => {
      expect(NotificationPolicy.calendarDay(new Date(2026,11,31,23).getTime(),1)).assertEqual(new Date(2027,0,1).getTime());
      expect(NotificationPolicy.calendarDay(new Date(2026,1,28).getTime(),1)).assertEqual(new Date(2026,2,1).getTime());
    });
    it('tolerates corrupt local risk history without reading business data as hours', 0, () => {
      expect(NotificationPolicy.readRiskMarks('null').length).assertEqual(0);
      expect(NotificationPolicy.readRiskMarks('[null, {"id":"a","signal":"not-real"}]').length).assertEqual(0);
      expect(NotificationPolicy.readRiskMarks('bad').length).assertEqual(0);
    });
    it('does not change original work estimates or leaf-task progress when planning notifications', 0, () => {
      const d=deadline();d.progress=50;d.remainingState='unknown';const previous=JSON.stringify(d);
      plan([d],tasks());expect(JSON.stringify(d)).assertEqual(previous);
    });
    it('does not stack risk and action notices when quiet hours move them together', 0, () => {
      const s=new NotificationSettings();s.quietStartMinutes=9*60;s.quietEndMinutes=9*60-30;
      const d=deadline('high',NOW+3*86400000,100);
      const result=plan([d],tasks(d.id),s);
      const daily=result.filter((item: DesiredReminder)=>item.key.startsWith('smart:daily:'));
      expect(result.filter((item: DesiredReminder)=>item.key.startsWith('smart:risk:')).every((risk: DesiredReminder)=>
        daily.every((summary: DesiredReminder)=>Math.abs(summary.scheduledAt-risk.scheduledAt)>1800000))).assertTrue();
    });
    it('keeps digest keys and day expiration stable across repeated recalculation', 0, () => {
      const d=deadline('stable',NOW+4*86400000);
      const a=plan([d],tasks(d.id));const b=plan([d],tasks(d.id));
      expect(JSON.stringify(a)).assertEqual(JSON.stringify(b));
      expect(a.filter((item: DesiredReminder)=>item.key.startsWith('smart:daily:')).every((item: DesiredReminder)=>
        item.autoDeletedAt===NotificationPolicy.calendarDay(item.scheduledAt,1))).assertTrue();
    });
    it('uses local midnight through spring and autumn clock transitions', 0, () => {
      // Node validation also executes the source in a timezone with 23h/25h days.
      const spring=new Date(2026,2,8).getTime();const autumn=new Date(2026,10,1).getTime();
      expect(NotificationPolicy.calendarDay(spring,1)).assertEqual(new Date(2026,2,9).getTime());
      expect(NotificationPolicy.calendarDay(autumn,1)).assertEqual(new Date(2026,10,2).getTime());
    });
    it('retains a local delivered receipt when permission is off then enabled again',0,() => {
      const d=deadline('receipt',new Date(2026,9,5,7).getTime());
      const at=new Date(2026,9,4,22,29).getTime();
      const state=new DeadlineReminderState(d.id,-1,at,`|cutoff=${d.deadlineAt}:60`);
      expect(NotificationPolicy.keepReceipt(state,d,new Date(2026,9,5,1).getTime())).assertTrue();
      d.completed=true;expect(NotificationPolicy.keepReceipt(state,d,new Date(2026,9,5,1).getTime())).assertFalse();
    });
    it('does not replay a previously observed cutoff after the wall clock moves backward',0,() => {
      const s=new NotificationSettings();s.quietEnabled=false;
      const d=deadline();const at=basic([d],s)[0];
      const state=new DeadlineReminderState(d.id,42,at.scheduledAt,at.signature+'|due_seen');
      expect(basic([d],s,NOW,new NotificationRuntimeState(),[state]).length).assertEqual(0);
      d.deadlineAt+=86400000;
      expect(basic([d],s,NOW,new NotificationRuntimeState(),[state]).length).assertEqual(1);
    });
    it('keeps explicitly continued overdue tasks in the daily action summary without an old cutoff',0,() => {
      const d=deadline('late',NOW-3600000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'continue'));
      const result=plan([d],tasks(d.id));
      // Local Hypium has no resource manager. Verify the real task identity
      // and summary presence rather than an unavailable translated template.
      expect(TodayActionService.buildPlan([d],tasks(d.id),NOW).actions[0].taskId).assertEqual('late-1');
      expect(result.filter((item: DesiredReminder)=>item.key.startsWith('smart:daily:')).length).assertEqual(3);
      expect(result.some((item: DesiredReminder)=>!item.key.startsWith('smart:daily:'))).assertFalse();
    });
    it('does not send recurring action summaries for unhandled or stopped overdue records',0,() => {
      const d=deadline('late',NOW-30*86400000);
      expect(plan([d],tasks(d.id)).length).assertEqual(0);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'stopped'));
      expect(plan([d],tasks(d.id)).length).assertEqual(0);
    });
  });
}
