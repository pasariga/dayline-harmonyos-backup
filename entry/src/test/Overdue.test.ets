import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { Deadline, DeadlineSubtask } from '../main/ets/models/Deadline';
import { AppSettings, AppSettingsRuntime } from '../main/ets/services/AppSettingsService';
import { DeadlineOverdueRuntime } from '../main/ets/services/DeadlineOverdueService';
import { DeadlineInsightService } from '../main/ets/services/DeadlineInsightService';
import { DeadlineScheduleService } from '../main/ets/services/DeadlineScheduleService';
import { TodayActionService } from '../main/ets/services/TodayActionService';

const NOW: number = new Date(2026, 9, 4, 0, 0).getTime();
function item(id: string, due: number, hours: number = 6): Deadline {
  return new Deadline(id, id, '项目', '2026-10-04', '23:59', '', NOW - 86400000, due, false,
    10, 50, 'automatic', 2, 0, hours, 'confirmed', NOW);
}
function tasks(id: string): DeadlineSubtask[] {
  return [new DeadlineSubtask(id+'small',id,'10 minute task',true,1),
    new DeadlineSubtask(id+'large',id,'20 hour task',false,2)];
}
export default function overdueTest() {
  describe('overdue', () => {
    beforeEach(() => {
      DeadlineOverdueRuntime.restore('[]');
      AppSettingsRuntime.apply(new AppSettings('system','automatic',3,true,'23:59',3));
    });
    it('uses exact due instant and excludes completed items',0,() => {
      const d=item('boundary',NOW);
      expect(DeadlineOverdueRuntime.state(d,NOW)).assertEqual('normal');
      expect(DeadlineOverdueRuntime.state(d,NOW+1)).assertEqual('pending');
      d.completed=true;
      expect(DeadlineOverdueRuntime.state(d,NOW+1)).assertEqual('normal');
    });
    it('distinguishes overdue from high risk at one hour one seven and thirty days',0,() => {
      [3600000,86400000,7*86400000,30*86400000].forEach((age:number) => {
        const d=item('late',NOW-age);
        expect(DeadlineInsightService.analyze(d,NOW).riskLevel).assertEqual('overdue');
        expect(DeadlineOverdueRuntime.state(d,NOW)).assertEqual('pending');
        expect(DeadlineScheduleService.buildPlan(d,tasks(d.id),NOW).days.length).assertEqual(0);
      });
    });
    it('does not let yesterday or thirty day old work displace tomorrow',0,() => {
      const future=item('exam',NOW+2*86400000);
      const old=item('old',NOW-30*86400000);
      const recent=item('yesterday',NOW-86400000);
      const p=TodayActionService.buildPlan([old,recent,future],tasks(old.id).concat(tasks(recent.id),tasks(future.id)),NOW);
      expect(p.actions[0].deadlineId).assertEqual('exam');
      expect(p.actions.filter((a) => a.kind==='overdue-review').length).assertEqual(1);
      expect(p.actions.find((a) => a.kind==='overdue-review')?.deadlineId).assertEqual('yesterday');
    });
    it('does not turn an undecided late item into a completable task',0,() => {
      const d=item('late',NOW-3600000);
      const p=TodayActionService.buildPlan([d],tasks(d.id),NOW);
      expect(p.actions[0].kind).assertEqual('overdue-review');
      expect(p.actions[0].canComplete).assertFalse();
    });
    it('allows continued tasks without pretending they can meet the old date',0,() => {
      const d=item('late',NOW-86400000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'continue'));
      const p=TodayActionService.buildPlan([d],tasks(d.id),NOW);
      expect(p.actions[0].kind).assertEqual('task');
      expect(p.actions[0].canComplete).assertTrue();
      expect(p.actions[0].riskLevel).assertEqual('overdue');
      expect(DeadlineScheduleService.buildPortfolioPlan(d,[d],tasks(d.id),NOW).isFeasible).assertFalse();
      expect(DeadlineScheduleService.buildAgenda([d],tasks(d.id),1,NOW)[0].items.length).assertEqual(0);
    });
    it('does not subtract task count progress from confirmed remaining work',0,() => {
      const d=item('late',NOW-86400000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'continue'));
      expect(DeadlineInsightService.analyze(d,NOW).remainingHours).assertEqual(6);
      expect(d.estimatedHours).assertEqual(10);
      expect(DeadlineInsightService.analyze(d,NOW).completedHours).assertEqual(0);
      d.remainingState='unknown';
      expect(DeadlineInsightService.analyze(d,NOW).remainingHours).assertEqual(0);
      expect(TodayActionService.buildPlan([d],tasks(d.id),NOW).actions[0].kind).assertEqual('task');
    });
    it('excludes overdue demand from normal before due capacity',0,() => {
      const old=item('old',NOW-86400000,100);
      const normal=item('normal',NOW+2*86400000,1);
      expect(DeadlineInsightService.analyzePortfolio(normal,[old,normal],NOW).riskLevel).assertEqual('low');
      old.remainingState='unknown';
      expect(DeadlineInsightService.analyzePortfolio(normal,[old,normal],NOW).riskLevel).assertEqual('low');
    });
    it('does not declare whole capacity reliable when continued undated work exists',0,() => {
      const old=item('old',NOW-86400000);
      const normal=item('normal',NOW+2*86400000,1);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(old,'continue'));
      expect(DeadlineInsightService.analyzePortfolio(normal,[old,normal],NOW).riskLevel).assertEqual('unknown');
      expect(TodayActionService.buildPlan([old,normal],tasks(old.id).concat(tasks(normal.id)),NOW).actions[0].deadlineId).assertEqual('normal');
    });
    it('stopping is reversible and never changes completed state or tasks',0,() => {
      const old=item('old',NOW-86400000);
      const t=tasks(old.id);
      const before=JSON.stringify(t);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(old,'stopped'));
      expect(TodayActionService.buildPlan([old],t,NOW).actions.length).assertEqual(0);
      expect(old.completed).assertFalse();
      expect(JSON.stringify(t)).assertEqual(before);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(old,'pending'));
      expect(TodayActionService.buildPlan([old],t,NOW).actions[0].kind).assertEqual('overdue-review');
    });
    it('changing the due date invalidates intent and restores scheduling',0,() => {
      const d=item('date',NOW-86400000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'stopped'));
      d.deadlineAt=NOW+2*86400000;
      expect(DeadlineOverdueRuntime.state(d,NOW)).assertEqual('normal');
      expect(DeadlineScheduleService.buildPortfolioPlan(d,[d],tasks(d.id),NOW).days.length>0).assertTrue();
      d.deadlineAt=NOW-3600000;
      expect(DeadlineOverdueRuntime.state(d,NOW)).assertEqual('pending');
    });
    it('restored overdue completion waits for a new decision',0,() => {
      const d=item('restore',NOW-86400000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'continue'));
      d.completed=true;
      expect(TodayActionService.buildPlan([d],tasks(d.id),NOW).actions.length).assertEqual(0);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(d,'pending'));
      d.completed=false; d.remainingState='unknown';
      expect(DeadlineOverdueRuntime.state(d,NOW)).assertEqual('pending');
      expect(TodayActionService.buildPlan([d],tasks(d.id),NOW).actions[0].kind).assertEqual('overdue-review');
    });
    it('keeps a shared three hour ceiling amid late work and capacity shortage',0,() => {
      const old=item('old',NOW-86400000,100);
      const first=item('first',NOW+86400000,7);
      const second=item('second',NOW+2*86400000,8);
      const agenda=DeadlineScheduleService.buildAgenda([old,second,first],[],2,NOW);
      expect(agenda.every((day) => day.estimatedHours<=3 && day.items.every((i) => i.deadlineId!=='old'))).assertTrue();
      expect(agenda[0].items[0].deadlineId).assertEqual('first');
      expect(TodayActionService.buildPlan([old,second,first],tasks(old.id).concat(tasks(first.id),tasks(second.id)),NOW).actions[0].deadlineId!=='old').assertTrue();
    });
    it('limits thirty old pending items to one action reminder',0,() => {
      const many:Deadline[]=[];
      for(let i=0;i<30;i++){many.push(item('old'+i,NOW-(i+1)*86400000));}
      const p=TodayActionService.buildPlan(many,[],NOW);
      expect(p.actions.length).assertEqual(1);
      expect(p.actions[0].deadlineId).assertEqual('old0');
    });
    it('keeps a future action ahead of late work even when no hours remain today',0,() => {
      const now = NOW+86400000-1;
      const late=item('late',NOW-86400000);
      const exam=item('exam',NOW+3*86400000,1);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(late,'continue'));
      const p=TodayActionService.buildPlan([late,exam],tasks(late.id).concat(tasks(exam.id)),now);
      expect(p.actions[0].deadlineId).assertEqual('exam');
    });
    it('recomputes overdue risk actions and plans across a midnight due instant',0,() => {
      const midnight = new Date(2026,9,5,0,0).getTime();
      const d = item('midnight',midnight);
      const next = item('tomorrow',midnight+86400000);
      const t = tasks(d.id).concat(tasks(next.id));
      expect(DeadlineOverdueRuntime.state(d,midnight-1)).assertEqual('normal');
      expect(DeadlineInsightService.analyze(d,midnight-1).riskLevel).assertEqual('high');
      expect(DeadlineOverdueRuntime.state(d,midnight+1)).assertEqual('pending');
      expect(DeadlineInsightService.analyze(d,midnight+1).riskLevel).assertEqual('overdue');
      expect(DeadlineScheduleService.buildPortfolioPlan(d,[d,next],t,midnight+1).days.length).assertEqual(0);
      const plan = TodayActionService.buildPlan([d,next],t,midnight+1);
      expect(plan.actions[0].deadlineId).assertEqual('tomorrow');
      expect(plan.actions.find((a) => a.deadlineId==='midnight')?.kind).assertEqual('overdue-review');
    });
    it('advances the agenda date and countdown across a natural day without editing',0,() => {
      const midnight = new Date(2026,9,5,0,0).getTime();
      const d = item('future',midnight+2*86400000);
      const late = item('late',midnight-86400000);
      const before = DeadlineScheduleService.buildAgenda([d,late],[],1,midnight-1);
      const after = DeadlineScheduleService.buildAgenda([d,late],[],1,midnight+1);
      expect(before[0].dateAt).assertEqual(new Date(2026,9,4,0,0).getTime());
      expect(after[0].dateAt).assertEqual(midnight);
      expect(after[0].items.some((a) => a.deadlineId==='late')).assertFalse();
      expect(DeadlineInsightService.analyze(d,midnight+1).remainingHoursToDeadline <
        DeadlineInsightService.analyze(d,midnight-1).remainingHoursToDeadline).assertTrue();
      expect(TodayActionService.buildPlan([late,d],tasks(late.id).concat(tasks(d.id)),midnight+1)
        .actions[0].deadlineId).assertEqual('future');
    });
    it('serializes independent decisions and rejects corrupt preferences',0,() => {
      const a=item('a',NOW-86400000), b=item('b',NOW-86400000);
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(a,'continue'));
      DeadlineOverdueRuntime.restore(DeadlineOverdueRuntime.next(b,'stopped'));
      const saved=DeadlineOverdueRuntime.serialize();
      DeadlineOverdueRuntime.restore('[]'); DeadlineOverdueRuntime.restore(saved);
      expect(DeadlineOverdueRuntime.state(a,NOW)).assertEqual('continue');
      expect(DeadlineOverdueRuntime.state(b,NOW)).assertEqual('stopped');
      let rejected:boolean=false;
      try{DeadlineOverdueRuntime.restore('[{"id":"a","deadlineAt":1,"mode":"done"}]');}catch(error){rejected=true;}
      expect(rejected).assertTrue();
      expect(DeadlineOverdueRuntime.state(b,NOW)).assertEqual('stopped');
    });
  });
}
