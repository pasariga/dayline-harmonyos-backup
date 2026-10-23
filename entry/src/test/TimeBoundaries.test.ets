import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { Deadline } from '../main/ets/models/Deadline';
import { DeadlineTime } from '../main/ets/services/DeadlineTime';
import { DeadlineInsightService } from '../main/ets/services/DeadlineInsightService';
import { DeadlineScheduleService } from '../main/ets/services/DeadlineScheduleService';
import { TodayActionService } from '../main/ets/services/TodayActionService';
import { AppSettings, AppSettingsRuntime } from '../main/ets/services/AppSettingsService';
import { NotificationSettings, NotificationRuntimeState } from '../main/ets/services/NotificationSettingsService';
import { DeadlineDataSnapshot } from '../main/ets/services/DeadlineDatabaseService';
import { DeadlineReminderService } from '../main/ets/services/DeadlineReminderService';
import { NotificationPolicy } from '../main/ets/services/NotificationPolicy';
import { DeadlineOverdueRuntime } from '../main/ets/services/DeadlineOverdueService';

const NOW = new Date(2026, 9, 5, 12).getTime();
function item(due: number = new Date(2026, 9, 7, 23).getTime(), id: string = 'time'): Deadline {
  return new Deadline(id, id, '项目', DeadlineTime.dateKey(due), DeadlineTime.timeKey(due), '', NOW,
    due, false, 10, 0, 'manual', 0, 1440, 10, 'confirmed', NOW);
}
export default function timeBoundariesTest() {
  describe('timeBoundaries', () => {
    beforeEach(() => { AppSettingsRuntime.apply(new AppSettings('system','manual',3,true,'23:59',3)); DeadlineOverdueRuntime.restore('[]'); });
    it('rejects a past creation but allows editing the same historical time',0,() => {
      const date=DeadlineTime.dateKey(NOW);
      expect(DeadlineTime.inputError(date,'11:00',false,NOW)).assertEqual('validation_time_past');
      expect(DeadlineTime.inputError(date,'11:00',true,NOW)).assertEqual('');
    });
    it('does not create a new deadline at the current instant',0,() => {
      expect(DeadlineTime.inputError(DeadlineTime.dateKey(NOW),'12:00',false,NOW)).assertEqual('validation_time_past');
    });
    it('keeps a future creation available',0,() => {
      expect(DeadlineTime.inputError(DeadlineTime.dateKey(NOW),'13:00',false,NOW)).assertEqual('');
    });
    it('rejects impossible calendar inputs rather than normalizing them',0,() => {
      expect(DeadlineTime.inputError('2026-02-30','12:00',true,NOW)).assertEqual('validation_time_missing');
    });
    it('counts calendar labels across month and year boundaries',0,() => {
      expect(DeadlineTime.daysBetween(new Date(2026,11,31,23).getTime(),new Date(2027,0,2).getTime())).assertEqual(2);
    });
    it('refreshes the agenda on the next day without user data changes',0,() => {
      const d=item();const before=new Date(2026,9,5,23,59).getTime();const after=new Date(2026,9,6).getTime();
      expect(DeadlineScheduleService.buildAgenda([d],[],1,before)[0].dateAt).assertEqual(DeadlineTime.calendarDay(before));
      expect(DeadlineScheduleService.buildAgenda([d],[],1,after)[0].dateAt).assertEqual(after);
      expect(TodayActionService.buildPlan([d],[],after).actions.length>0).assertTrue();
    });
    it('has one plan row per calendar date',0,() => {
      const rows=DeadlineScheduleService.buildPlan(item(),[],NOW).days;
      expect(rows.length).assertEqual(3);
      expect(new Set<string>(rows.map((row)=>DeadlineTime.dateKey(row.dateAt))).size).assertEqual(3);
    });
    it('orders same-day capacity by the earlier actual deadline',0,() => {
      const early=item(NOW+3600000,'early');const later=item(NOW+7200000,'late');
      expect(DeadlineScheduleService.buildAgenda([later,early],[],1,NOW)[0].items[0].deadlineId).assertEqual('early');
    });
    it('shares the same daily budget after a date change',0,() => {
      const d=item();const other=item(d.deadlineAt,'other');
      const rows=DeadlineScheduleService.buildAgenda([d,other],[],3,NOW);
      expect(rows.every((row)=>row.estimatedHours<=row.capacityHours && row.capacityHours<=3)).assertTrue();
    });
    it('uses the strict overdue boundary before and after a clock jump',0,() => {
      const d=item(NOW);
      expect(DeadlineInsightService.analyze(d,NOW).riskLevel==='overdue').assertFalse();
      expect(DeadlineInsightService.analyze(d,NOW+1).riskLevel).assertEqual('overdue');
      expect(DeadlineScheduleService.buildPlan(d,[],NOW+1).days.length).assertEqual(0);
    });
    it('drops an expired hourly plan after a long background interval',0,() => {
      const d=item();const later=d.deadlineAt+3600000;
      expect(DeadlineInsightService.analyze(d,later).riskLevel).assertEqual('overdue');
      expect(DeadlineScheduleService.buildAgenda([d],[],1,later)[0].items.length).assertEqual(0);
      expect(TodayActionService.buildPlan([d],[],later).actions[0].kind).assertEqual('overdue-review');
    });
    it('keeps the saved estimate when the clock moves before its confirmation',0,() => {
      const d=item();expect(DeadlineInsightService.analyze(d,NOW-60000).workloadConfidence).assertEqual('stale');
      expect(d.remainingHours).assertEqual(10);
      expect(DeadlineInsightService.analyze(d,NOW).remainingHours).assertEqual(10);
    });
    it('defines two weeks as elapsed duration and includes the exact boundary',0,() => {
      const d=item(NOW+30*86400000);const age=DeadlineInsightService.REMAINING_ESTIMATE_MAX_AGE_MS;
      expect(DeadlineInsightService.analyze(d,NOW+age).workloadConfidence).assertEqual('rough');
      expect(DeadlineInsightService.analyze(d,NOW+age+1).workloadConfidence).assertEqual('stale');
    });
    it('keeps original timestamps independent of formatting or planning',0,() => {
      const d=item();const value=JSON.stringify(d);
      TodayActionService.buildPlan([d],[],NOW);DeadlineScheduleService.buildPlan(d,[],NOW);
      expect(JSON.stringify(d)).assertEqual(value);
    });
    it('refreshes at midnight sooner than the normal visible-page minute',0,() => {
      const at=new Date(2026,9,5,23,59,59).getTime();expect(DeadlineTime.refreshDelay(at,[])).assertEqual(1001);
    });
    it('refreshes immediately after a nearby cutoff',0,() => {
      expect(DeadlineTime.refreshDelay(NOW,[NOW+5000])).assertEqual(5001);
      expect(DeadlineTime.refreshDelay(NOW,[])).assertEqual(60000);
    });
    it('notifies visible consumers and stops notifying after unsubscription',0,() => {
      let count=0;const listener=():void=>{count++;};
      DeadlineTime.onClockChanged(listener);DeadlineTime.clockChanged();DeadlineTime.offClockChanged(listener);
      DeadlineTime.clockChanged();expect(count).assertEqual(1);
    });
    it('builds one local-clock daily summary per date and no past catch-up',0,() => {
      const d=item(new Date(2026,9,10,23).getTime());const settings=new NotificationSettings();settings.quietEnabled=false;
      const now=new Date(2026,9,6,7).getTime();
      const reminders=DeadlineReminderService.buildDesiredReminders(new DeadlineDataSnapshot([d],[]),[],settings,new NotificationRuntimeState(),now);
      const daily=reminders.filter((row)=>row.key.startsWith('smart:daily:'));
      expect(daily.length).assertEqual(3);
      expect(daily.every((row)=>new Date(row.scheduledAt).getHours()===8 && new Date(row.scheduledAt).getMinutes()===30)).assertTrue();
      expect(new Set<string>(daily.map((row)=>row.key)).size).assertEqual(3);
    });
    it('keeps cross-midnight quiet hours aligned with the following local morning',0,() => {
      const at=new Date(2026,9,5,23).getTime();const settings=new NotificationSettings();
      expect(NotificationPolicy.afterQuiet(at,settings)).assertEqual(new Date(2026,9,6,8).getTime());
    });
    it('uses calendar days for day-offset reminders and elapsed time for an hour',0,() => {
      const due=new Date(2026,9,7,23).getTime();
      expect(DeadlineTime.reminderAt(due,1440)).assertEqual(new Date(2026,9,6,23).getTime());
      expect(DeadlineTime.reminderAt(due,60)).assertEqual(due-3600000);
    });
    it('keeps all plan dates through a 23 hour spring day when the zone observes DST',0,() => {
      let spring=new Date(2026,2,8).getTime();
      if (DeadlineTime.calendarDay(spring,1)-spring===86400000) { spring=new Date(2026,2,29).getTime(); }
      const due=DeadlineTime.atMinute(spring,23*60,2);const d=item(due);d.remainingUpdatedAt=spring;
      expect(DeadlineScheduleService.buildPlan(d,[],spring).days.length).assertEqual(3);
      expect(AppSettingsRuntime.getAvailableHoursBetween(spring,DeadlineTime.calendarDay(spring,1))).assertEqual(3);
      expect(DeadlineTime.daysBetween(spring,due)).assertEqual(2);
    });
    it('does not repeat a plan date through a 25 hour autumn day',0,() => {
      let autumn=new Date(2026,10,1).getTime();
      if (DeadlineTime.calendarDay(autumn,1)-autumn===86400000) { autumn=new Date(2026,9,25).getTime(); }
      const d=item(DeadlineTime.atMinute(autumn,23*60,2));d.remainingUpdatedAt=autumn;
      const rows=DeadlineScheduleService.buildAgenda([d],[],3,autumn);
      expect(new Set<string>(rows.map((row)=>DeadlineTime.dateKey(row.dateAt))).size).assertEqual(3);
      expect(rows.every((row)=>row.capacityHours===3 && row.estimatedHours<=3)).assertTrue();
    });
    it('computes real spring reminder candidates by the preceding local date',0,() => {
      let spring=new Date(2026,2,8).getTime();
      if (DeadlineTime.calendarDay(spring,1)-spring===86400000) { spring=new Date(2026,2,29).getTime(); }
      const now=DeadlineTime.calendarDay(spring,-2);const d=item(DeadlineTime.atMinute(spring,8*60+30,1));d.remainingUpdatedAt=now;
      const settings=new NotificationSettings();settings.quietEnabled=false;
      const result=DeadlineReminderService.buildDesiredReminders(new DeadlineDataSnapshot([d],[]),[],settings,new NotificationRuntimeState(),now);
      expect(result.find((row)=>row.key===d.id)?.scheduledAt).assertEqual(DeadlineTime.atMinute(spring,8*60+30));
    });
    it('computes real autumn summary candidates once per date at the chosen clock time',0,() => {
      let autumn=new Date(2026,10,1).getTime();
      if (DeadlineTime.calendarDay(autumn,1)-autumn===86400000) { autumn=new Date(2026,9,25).getTime(); }
      const now=DeadlineTime.atMinute(autumn,7*60,-1);const d=item(DeadlineTime.calendarDay(autumn,8));d.remainingUpdatedAt=now;
      const settings=new NotificationSettings();settings.quietEnabled=false;
      const rows=DeadlineReminderService.buildDesiredReminders(new DeadlineDataSnapshot([d],[]),[],settings,new NotificationRuntimeState(),now)
        .filter((row)=>row.key.startsWith('smart:daily:'));
      expect(rows.length).assertEqual(3);expect(new Set<string>(rows.map((row)=>row.key)).size).assertEqual(3);
      expect(rows.every((row)=>DeadlineTime.timeKey(row.scheduledAt)==='08:30')).assertTrue();
    });
    it('rejects missing spring clock time in a DST zone',0,() => {
      let spring=new Date(2026,2,8).getTime();
      if (DeadlineTime.calendarDay(spring,1)-spring===86400000) { spring=new Date(2026,2,29).getTime(); }
      const usesDst=DeadlineTime.calendarDay(spring,1)-spring===23*3600000;
      expect(DeadlineTime.inputError(DeadlineTime.dateKey(spring),'02:30',true,spring))
        .assertEqual(usesDst?'validation_time_missing':'');
    });
    it('rejects a repeated autumn clock time in a DST zone',0,() => {
      let autumn=new Date(2026,10,1).getTime();let time='01:30';
      if (DeadlineTime.calendarDay(autumn,1)-autumn===86400000) { autumn=new Date(2026,9,25).getTime();time='02:30'; }
      const usesDst=DeadlineTime.calendarDay(autumn,1)-autumn===25*3600000;
      expect(DeadlineTime.inputError(DeadlineTime.dateKey(autumn),time,true,autumn)).assertEqual(usesDst?'validation_time_ambiguous':'');
    });
    it('does not encode the second repeated instant as the first in the system calendar',0,() => {
      let first=new Date(2026,10,1,1,30).getTime();
      if (!DeadlineTime.isAmbiguous(first)) { first=new Date(2026,9,25,2,30).getTime(); }
      expect(DeadlineTime.calendarCanRepresent(first)).assertTrue();
      expect(DeadlineTime.calendarCanRepresent(first+3600000)).assertEqual(!DeadlineTime.isAmbiguous(first));
    });
  });
}
