import { describe, it, expect } from '@ohos/hypium';
import { Deadline, DeadlineSubtask } from '../main/ets/models/Deadline';
import { AppSettings, AppSettingsRuntime } from '../main/ets/services/AppSettingsService';
import { DeadlineInsightService } from '../main/ets/services/DeadlineInsightService';
import { DeadlineProgressService } from '../main/ets/services/DeadlineProgressService';
import { DeadlineScheduleService } from '../main/ets/services/DeadlineScheduleService';
import { TodayActionService } from '../main/ets/services/TodayActionService';

function deadline(id: string, due: number, hours: number, mode: string = 'manual',
  progress: number = 0, taskCount: number = 0): Deadline {
  return new Deadline(id, id, '项目', '2026-09-29', '23:59', '', new Date(2026, 8, 28).getTime(), due, false,
    hours, progress, mode, taskCount, 0);
}

export default function corePlanningTest() {
  describe('corePlanning', () => {
    it('shares one daily capacity across deadlines', 0, () => {
      AppSettingsRuntime.apply(new AppSettings('system', 'manual', 2, true, '23:59', 2));
      const now: number = new Date(2026, 8, 29, 0, 0).getTime();
      const due: number = new Date(2026, 8, 29, 23, 59).getTime();
      const first: Deadline = deadline('first', due, 2);
      const second: Deadline = deadline('second', due, 2);
      const agenda = DeadlineScheduleService.buildAgenda([first, second], [], 1, now);
      expect(agenda.length).assertEqual(1);
      expect(agenda[0].estimatedHours <= agenda[0].capacityHours).assertTrue();
      expect(agenda[0].deferredHours > 1.9).assertTrue();
      expect(DeadlineInsightService.analyzePortfolio(second, [first, second], now).riskLevel)
        .assertEqual('high');
      expect(DeadlineScheduleService.buildPortfolioPlan(second, [first, second], [], now).isFeasible)
        .assertFalse();
    });

    it('gives earlier deadlines first claim on a three hour daily budget', 0, () => {
      AppSettingsRuntime.apply(new AppSettings('system', 'manual', 3, true, '23:59', 3));
      const now: number = new Date(2026, 8, 29, 0, 0).getTime();
      const early: Deadline = deadline('early', new Date(2026, 8, 29, 23, 59).getTime(), 2);
      const later: Deadline = deadline('later', new Date(2026, 8, 30, 23, 59).getTime(), 5);
      const agenda = DeadlineScheduleService.buildAgenda([later, early], [], 2, now);
      expect(agenda.length).assertEqual(2);
      expect(agenda[0].estimatedHours).assertEqual(3);
      expect(agenda[1].estimatedHours).assertEqual(3);
      expect(agenda[0].items[0].deadlineId).assertEqual('early');
      expect(agenda[0].items[0].estimatedHours).assertEqual(2);
      expect(agenda[0].items[1].deadlineId).assertEqual('later');
      expect(agenda[1].items[0].deadlineId).assertEqual('later');
      expect(agenda[1].deferredHours).assertEqual(1);
    });

    it('does not invent hours when workload is missing', 0, () => {
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const due: number = new Date(2026, 8, 30, 23, 59).getTime();
      const item: Deadline = deadline('unknown', due, 0);
      expect(DeadlineInsightService.analyze(item, now).riskLevel).assertEqual('unknown');
      expect(DeadlineScheduleService.buildPlan(item, [], now).days.length).assertEqual(0);
    });

    it('marks shared capacity unknown when an earlier workload is missing', 0, () => {
      AppSettingsRuntime.apply(new AppSettings('system', 'manual', 2, true, '23:59', 2));
      const now: number = new Date(2026, 8, 29, 0, 0).getTime();
      const early: Deadline = deadline('early', new Date(2026, 8, 29, 23, 59).getTime(), 0);
      const later: Deadline = deadline('later', new Date(2026, 8, 30, 23, 59).getTime(), 1);
      expect(DeadlineInsightService.analyzePortfolio(later, [early, later], now).riskLevel)
        .assertEqual('unknown');
    });

    it('keeps task completion separate from hours worked', 0, () => {
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const due: number = new Date(2026, 9, 2, 23, 59).getTime();
      const item: Deadline = deadline('auto', due, 10, 'automatic', 50, 2);
      const insight = DeadlineInsightService.analyze(item, now);
      const tasks: DeadlineSubtask[] = [
        new DeadlineSubtask('small', 'auto', 'small', true, 1),
        new DeadlineSubtask('large', 'auto', 'large', false, 2)
      ];
      expect(insight.progress).assertEqual(50);
      expect(insight.completedHours).assertEqual(0);
      expect(insight.remainingHours).assertEqual(0);
      expect(insight.workloadConfidence).assertEqual('unmeasured');
      expect(insight.riskLevel).assertEqual('unknown');
      expect(DeadlineScheduleService.buildPlan(item, tasks, now).days.length).assertEqual(0);
      expect(DeadlineScheduleService.buildAgenda([item], tasks, 1, now)[0].estimatedHours).assertEqual(0);
      item.progress = 0;
      expect(DeadlineInsightService.analyze(item, now).remainingHours).assertEqual(10);
      expect(DeadlineInsightService.analyze(item, now).workloadConfidence).assertEqual('rough');
    });

    it('uses a confirmed remaining estimate without subtracting task progress', 0, () => {
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const due: number = new Date(2026, 9, 2, 23, 59).getTime();
      const item: Deadline = deadline('auto', due, 10, 'automatic', 50, 2);
      const tasks: DeadlineSubtask[] = [
        new DeadlineSubtask('small', 'auto', 'ten minute task', true, 1),
        new DeadlineSubtask('large', 'auto', 'twenty hour task', false, 2)
      ];
      item.remainingState = 'confirmed';
      item.remainingUpdatedAt = now;
      item.remainingHours = 6;
      expect(DeadlineInsightService.analyze(item, now).remainingHours).assertEqual(6);
      expect(DeadlineScheduleService.buildPlan(item, tasks, now).totalRemainingHours).assertEqual(6);
      item.remainingHours = 9;
      expect(DeadlineInsightService.analyze(item, now).remainingHours).assertEqual(9);
      expect(DeadlineScheduleService.buildPlan(item, tasks, now).totalRemainingHours).assertEqual(9);
      const other: Deadline = deadline('other', due, 10);
      const agenda = DeadlineScheduleService.buildAgenda([item, other], tasks, 1, now);
      expect(agenda[0].estimatedHours <= agenda[0].capacityHours).assertTrue();
      expect(DeadlineInsightService.analyze(item, now).completedHours).assertEqual(0);
      item.remainingState = 'unknown';
      expect(DeadlineInsightService.analyze(item, now).riskLevel).assertEqual('unknown');
      expect(DeadlineScheduleService.buildPlan(item, tasks, now).days.length).assertEqual(0);
      expect(TodayActionService.buildPlan([item], tasks, now).actions.length > 0).assertTrue();
    });

    it('expires an old confirmation but keeps the last number for later reconfirmation', 0, () => {
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const item: Deadline = deadline('old', now + 5 * 86400000, 10, 'automatic', 50, 2);
      item.remainingHours = 6;
      item.remainingState = 'confirmed';
      item.remainingUpdatedAt = now - DeadlineInsightService.REMAINING_ESTIMATE_MAX_AGE_MS - 1;
      expect(DeadlineInsightService.analyze(item, now).workloadConfidence).assertEqual('stale');
      expect(DeadlineInsightService.analyze(item, now).remainingHours).assertEqual(0);
      expect(item.remainingHours).assertEqual(6);
      item.remainingUpdatedAt = now;
      expect(DeadlineInsightService.analyze(item, now).remainingHours).assertEqual(6);
    });

    it('does not turn manual progress or planned hours into completed work hours', 0, () => {
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const item: Deadline = deadline('manual', now + 5 * 86400000, 10, 'manual', 50);
      expect(DeadlineInsightService.analyze(item, now).riskLevel).assertEqual('unknown');
      item.remainingState = 'confirmed';
      item.remainingHours = 9;
      item.remainingUpdatedAt = now;
      const insight = DeadlineInsightService.analyze(item, now);
      expect(insight.completedHours).assertEqual(0);
      expect(insight.remainingHours).assertEqual(9);
      expect(DeadlineScheduleService.buildPlan(item, [], now).days[0].targetProgress).assertEqual(-1);
    });

    it('does not spread hourly work according to the number of leaf tasks', 0, () => {
      AppSettingsRuntime.apply(new AppSettings('system', 'manual', 3, true, '23:59', 3));
      const now: number = new Date(2026, 8, 29, 12, 0).getTime();
      const item: Deadline = deadline('auto', now + 10 * 86400000, 2, 'automatic', 0, 8);
      const manyTasks: DeadlineSubtask[] = [];
      for (let index: number = 0; index < 8; index++) {
        manyTasks.push(new DeadlineSubtask(`task-${index}`, 'auto', `task ${index}`, false, index));
      }
      const oneTask: DeadlineSubtask[] = [manyTasks[0]];
      const manyPlan = DeadlineScheduleService.buildPlan(item, manyTasks, now);
      const onePlan = DeadlineScheduleService.buildPlan(item, oneTask, now);
      expect(manyPlan.activeWorkDays).assertEqual(onePlan.activeWorkDays);
      expect(manyPlan.days[0].taskTitles.length).assertEqual(0);
    });

    it('counts leaf tasks without giving a parent extra weight', 0, () => {
      const tasks: DeadlineSubtask[] = [
        new DeadlineSubtask('group', 'd', 'group', false, 1),
        new DeadlineSubtask('a', 'd', 'a', true, 2, 'group'),
        new DeadlineSubtask('b', 'd', 'b', true, 3, 'group'),
        new DeadlineSubtask('c', 'd', 'c', true, 4, 'group'),
        new DeadlineSubtask('d', 'd', 'd', true, 5, 'group'),
        new DeadlineSubtask('other', 'd', 'other', false, 6)
      ];
      expect(DeadlineProgressService.calculateDeadlineProgress(tasks)).assertEqual(80);
      expect(DeadlineProgressService.deriveParentStates(tasks)[0].completed).assertTrue();
    });
  });
}
