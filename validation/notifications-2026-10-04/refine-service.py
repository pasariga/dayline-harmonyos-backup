from pathlib import Path
p=Path('entry/src/main/ets/services/DeadlineReminderService.ets')
s=p.read_text(encoding='utf-8')
def replace(a,b):
    global s
    assert a in s,a[:90]
    s=s.replace(a,b,1)
def method(name,next_name,body):
    global s
    a=s.index('  private static '+name)
    b=s.index('  private static '+next_name,a)
    s=s[:a]+body+'\n\n'+s[b:]
method('isInQuietHours','groupTasks', '''  private static moveProactiveAfterQuiet(value: number, settings: NotificationSettings): number {
    return NotificationPolicy.afterQuiet(value, settings);
  }''')
replace("    const cooldownUntil: number = runtime.lastActivityAt + NotificationSettingsService.getActivityCooldown(settings);\n    for (let index: number = 0; index < selectedCount; index++)", "    for (let index: number = 0; index < selectedCount; index++)")
replace('''      let scheduledAt: number = DeadlineReminderService.moveBasicBeforeQuiet(
        DeadlineReminderService.getScheduledAt(deadline),
        deadline.deadlineAt,
        settings
      );
      if (runtime.lastActivityDeadlineId === deadline.id && scheduledAt < cooldownUntil) {
        scheduledAt = DeadlineReminderService.ceilToMinute(cooldownUntil);
      }
      if (scheduledAt <= now + MIN_FUTURE_DELAY || scheduledAt >= deadline.deadlineAt)''','''      const scheduledAt: number = NotificationPolicy.basicTime(
        DeadlineReminderService.getScheduledAt(deadline), deadline.deadlineAt, settings, now);
      if (scheduledAt <= now || scheduledAt >= deadline.deadlineAt)''')
replace('const dayAt: number = todayAt + dayOffset * DAY_MILLISECONDS;', 'const dayAt: number = NotificationPolicy.calendarDay(todayAt, dayOffset);')
replace('''      if (scheduledAt <= now + MIN_FUTURE_DELAY || DeadlineReminderService.getDateKey(scheduledAt) !==
        DeadlineReminderService.getDateKey(dayAt))''','''      if ((dayOffset === 0 && NotificationPolicy.finishedToday(runtime, DeadlineReminderService.getDateKey(now), deadlines, tasks)) ||
        scheduledAt <= now || DeadlineReminderService.getDateKey(scheduledAt) !== DeadlineReminderService.getDateKey(dayAt))''')
# A missed day changes the next digest, rather than generating another notification on every reopen.
replace('''      const activityWasToday: boolean = runtime.lastActivityAt > 0 &&
        DeadlineReminderService.getDateKey(runtime.lastActivityAt) === DeadlineReminderService.getDateKey(now);
      if (dayOffset === 1 && settings.replanAlertsEnabled && settings.intensity !== 'concise' && activityWasToday)''','''      if (settings.replanAlertsEnabled && runtime.lastPlanDate.length > 0 &&
        runtime.lastPlanDate < DeadlineReminderService.getDateKey(scheduledAt))''')
replace('taskIdIndex < plannedTaskIds.length','taskIdIndex < runtime.lastPlanTaskIds.length')
replace('taskMap.get(plannedTaskIds[taskIdIndex])','taskMap.get(runtime.lastPlanTaskIds[taskIdIndex])')
s=s.replace('DeadlineReminderService.startOfDay(scheduledAt) + DAY_MILLISECONDS','NotificationPolicy.calendarDay(scheduledAt, 1)')
method('buildRiskReminders','getTodayPlannedTaskIds', '''  private static buildRiskReminders(deadlines: Deadline[], tasks: DeadlineSubtask[], settings: NotificationSettings,
    runtime: NotificationRuntimeState, states: DeadlineReminderState[], now: number): DesiredReminder[] {
    if (NotificationSettingsService.getRiskReminderLimit(settings) === 0) { return []; }
    const marks = NotificationPolicy.readRiskMarks(runtime.riskMarks);
    const pending = states.find((state: DeadlineReminderState) => state.deadlineId.startsWith(`${SMART_PREFIX}risk:`) &&
      state.scheduledAt > now);
    const pendingMarks = pending === undefined ? [] : DeadlineReminderService.riskMarksFromSignature(pending.signature);
    const risky = deadlines.filter((deadline: Deadline) => {
      const signal = NotificationPolicy.riskSignal(deadline, deadlines, now);
      const previous = marks.find((mark: NotificationRiskMark) => mark.id === deadline.id)?.signal ?? 'none';
      return NotificationPolicy.worsened(signal, previous) ||
        pendingMarks.some((mark: NotificationRiskMark) => mark.id === deadline.id && mark.signal === signal && signal !== 'none');
    });
    if (risky.length === 0) { return []; }
    risky.sort((left: Deadline, right: Deadline) => left.deadlineAt - right.deadlineAt);
    const cooldown = runtime.lastActivityAt + NotificationSettingsService.getActivityCooldown(settings);
    for (let offset = 0; offset < 7; offset++) {
      let at = pending !== undefined ? pending.scheduledAt :
        DeadlineReminderService.atMinuteOfDay(NotificationPolicy.calendarDay(now, offset), 18 * 60 + 30);
      if (pending === undefined) { at = DeadlineReminderService.moveProactiveAfterQuiet(Math.max(at,
        DeadlineReminderService.ceilToMinute(cooldown)), settings); }
      const key = `${SMART_PREFIX}risk:${DeadlineReminderService.getDateKey(at)}`;
      if (at <= now || (pending === undefined && states.some((state: DeadlineReminderState) => state.deadlineId === key)) ||
        (pending === undefined && runtime.lastRiskAt > 0 && at - runtime.lastRiskAt <
          (settings.intensity === 'active' ? 2 : 3) * DAY_MILLISECONDS)) { continue; }
      const eligible = risky.filter((deadline: Deadline) => deadline.deadlineAt > at);
      if (eligible.length === 0) { continue; }
      const primary = eligible[0];
      const insight = DeadlineInsightService.analyzePortfolio(primary, deadlines, at);
      const plan = TodayActionService.buildPlan(DeadlineReminderService.getActiveFutureDeadlines(deadlines, at), tasks, at);
      const action = DeadlineReminderService.findActionForDeadline(plan, primary.id);
      const desired = new DesiredReminder(key, at, LocalizationService.text('notification_risk_title'),
        LocalizationService.text('notification_risk_content', primary.name, action?.suggestion ?? insight.riskReason),
        LocalizationService.text('notification_risk_expired'), NotificationPolicy.calendarDay(at, 1), 'ddl_smart_risk');
      desired.riskMarks = eligible.map((deadline: Deadline) => new NotificationRiskMark(deadline.id,
        NotificationPolicy.riskSignal(deadline, deadlines, now)));
      desired.signature += `|signals=${JSON.stringify(desired.riskMarks)}`;
      return [desired];
    }
    return [];
  }

  private static riskMarksFromSignature(signature: string): NotificationRiskMark[] {
    const separator = signature.lastIndexOf('|signals=');
    return separator < 0 ? [] : NotificationPolicy.readRiskMarks(signature.substring(separator + 9));
  }''')
replace('private static buildDesiredReminders','static buildDesiredReminders')
a=s.index('    let previousRiskReminderAt: number = 0;')
b=s.index('    desired.sort(',a)
s=s[:a]+'''    desired = desired.concat(DeadlineReminderService.buildRiskReminders(
      snapshot.deadlines, snapshot.subtasks, settings, runtime, states, now));
'''+s[b:]
p.write_text(s,encoding='utf-8')
print('Applied notification-only planning changes.')
