import { describe, it, expect } from '@ohos/hypium';
import { ExperiencePresentation, ExperienceRouteParams } from '../main/ets/services/ExperiencePresentation';
import { ScheduleAgendaDay, ScheduleAgendaItem } from '../main/ets/services/DeadlineScheduleService';
import { DeadlineTime } from '../main/ets/services/DeadlineTime';
import { TodayAction } from '../main/ets/services/TodayActionService';

export default function experiencePresentationTest() {
  describe('experiencePresentation', () => {
    const now: number = new Date(2026, 9, 18, 12).getTime();
    it('keeps scheduled hours distinct from other unknown work', 0, () => {
      const day = new ScheduleAgendaDay(DeadlineTime.calendarDay(now), '', 1.5, 3, 0,
        [new ScheduleAgendaItem('a', '', '', 1.5, 'work', 'low'),
          new ScheduleAgendaItem('b', '', '', 0, 'unknown', 'unknown')]);
      const result = ExperiencePresentation.todayContext([day], now);
      expect(result.scheduledHours).assertEqual(1.5);
      expect(result.hasUnknownWork).assertTrue();
      expect(result.hasSchedule).assertTrue();
    });
    it('does not turn an unknown-only day into zero required work', 0, () => {
      const day = new ScheduleAgendaDay(DeadlineTime.calendarDay(now), '', 0, 3, 0,
        [new ScheduleAgendaItem('a', '', '', 0, 'unknown', 'unknown')]);
      expect(ExperiencePresentation.todayContext([day], now).hasUnknownWork).assertTrue();
    });
    it('does not substitute tomorrow for today or claim a missing plan is empty', 0, () => {
      const tomorrow = new ScheduleAgendaDay(DeadlineTime.calendarDay(now, 1), '', 3, 3, 0, []);
      expect(ExperiencePresentation.todayContext([tomorrow], now).hasSchedule).assertFalse();
      expect(ExperiencePresentation.todayContext([], now).hasSchedule).assertFalse();
    });
    it('does not count unallocated work as an hourly allocation', 0, () => {
      const day = new ScheduleAgendaDay(DeadlineTime.calendarDay(now), '', 3, 3, 7, []);
      expect(ExperiencePresentation.todayContext([day], now).scheduledHours).assertEqual(3);
    });
    it('shows a committed creation receipt once without business persistence', 0, () => {
      ExperiencePresentation.recordCreated('synthetic-ui-id', 'Synthetic name');
      const result = ExperiencePresentation.consumeCreated();
      expect(result?.deadlineId).assertEqual('synthetic-ui-id');
      expect(ExperiencePresentation.consumeCreated() === undefined).assertTrue();
    });
    it('carries a workspace across editing without changing the deadline identity', 0, () => {
      const route = new ExperienceRouteParams('same-deadline', 1);
      expect(route.deadlineId).assertEqual('same-deadline');
      expect(route.workspace).assertEqual(1);
    });
    it('refreshes visible context when only the project name or due instant changes', 0, () => {
      const action = new TodayAction('same-project', 'Math', now, 'same-task', 'Read notes', '', '', '',
        'high', 'High risk', 'task', true, 100);
      const original = ExperiencePresentation.actionKey(action);
      expect(ExperiencePresentation.actionKey(action)).assertEqual(original);
      action.deadlineName = 'Renamed exam';
      expect(ExperiencePresentation.actionKey(action) === original).assertFalse();
      action.deadlineName = 'Math';
      action.deadlineAt = now + 3600000;
      expect(ExperiencePresentation.actionKey(action) === original).assertFalse();
    });
  });
}
