from pathlib import Path
p=Path('entry/src/main/ets/services/DeadlineReminderService.ets')
s=p.read_text(encoding='utf-8')
a=s.index('  private static async performReconcile('); b=s.index('  static async reconcileAll(',a)
s=s[:a]+'''  private static ownsReminder(info: reminderAgentManager.ReminderInfo): boolean {
    const group = info.reminderReq.groupId ?? '';
    return group.startsWith('dayline:') || ['ddl_deadlines', 'ddl_smart_actions', 'ddl_smart_risk', 'ddl_smart_replan'].includes(group);
  }

  private static matchesSystem(info: reminderAgentManager.ReminderInfo, desired: DesiredReminder): boolean {
    if (info.reminderReq.reminderType !== reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR ||
      info.reminderReq.notificationId !== DeadlineReminderService.getNotificationId(desired.key) ||
      info.reminderReq.title !== DeadlineReminderService.truncate(desired.title, 80) ||
      info.reminderReq.content !== DeadlineReminderService.truncate(desired.content, 160)) { return false; }
    const time = (info.reminderReq as reminderAgentManager.ReminderRequestCalendar).dateTime;
    return new Date(time.year, time.month - 1, time.day, time.hour, time.minute, time.second ?? 0).getTime() === desired.scheduledAt;
  }

  private static async performReconcile(context: common.UIAbilityContext): Promise<void> {
    const values = await Promise.all([
      DeadlineDatabaseService.getDeadlineDataSnapshot(context), DeadlineDatabaseService.getAllReminderStates(context),
      NotificationSettingsService.getSettings(context), NotificationSettingsService.getRuntimeState(context)
    ]);
    const snapshot = values[0] as DeadlineDataSnapshot;
    const states = values[1] as DeadlineReminderState[];
    const settings = values[2] as NotificationSettings;
    const runtime = values[3] as NotificationRuntimeState;
    const now = Date.now();
    // Requiring a system inventory before publishing prevents a crash between
    // publishing and local persistence from creating a second system reminder.
    const system = await reminderAgentManager.getAllValidReminders();
    const enabled = await DeadlineReminderService.isNotificationEnabled();
    let failed = false;
    if (!enabled) {
      for (const state of states) { if (!await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; } }
      for (const info of system) {
        if (DeadlineReminderService.ownsReminder(info) && !await DeadlineReminderService.cancelSystemReminder(info.reminderId)) { failed = true; }
      }
      if (failed) { throw new Error('Notification permission is off; old reminder cancellation needs retry.'); }
      return;
    }

    let marks = NotificationPolicy.readRiskMarks(runtime.riskMarks);
    for (const state of states) {
      for (const mark of DeadlineReminderService.riskMarksFromSignature(state.signature)) {
        if (!marks.some((existing: NotificationRiskMark) => existing.id === mark.id)) { marks.push(mark); }
      }
    }
    marks = marks.filter((mark: NotificationRiskMark) => snapshot.deadlines.some((deadline: Deadline) => deadline.id === mark.id));
    for (const mark of marks) {
      const deadline = snapshot.deadlines.find((item: Deadline) => item.id === mark.id) as Deadline;
      const signal = NotificationPolicy.riskSignal(deadline, snapshot.deadlines, now);
      if (signal === 'none' || (signal === 'medium' && mark.signal === 'high')) { mark.signal = signal; }
    }
    runtime.riskMarks = JSON.stringify(marks);
    await NotificationSettingsService.saveRiskHistory(context, runtime.riskMarks, runtime.lastRiskAt);
    const desired = DeadlineReminderService.buildDesiredReminders(snapshot, states, settings, runtime, now);
    const desiredMap = new Map<string, DesiredReminder>();
    desired.forEach((item: DesiredReminder) => desiredMap.set(item.key, item));
    const retainedIds = new Set<number>();
    const stateMap = new Map<string, DeadlineReminderState>();
    for (const state of states) {
      const deadline = snapshot.deadlines.find((item: Deadline) => item.id === state.deadlineId);
      const retainDelivered = state.scheduledAt <= now && deadline !== undefined && !deadline.completed &&
        deadline.reminderOffsetMinutes > 0 && deadline.deadlineAt > now &&
        DeadlineReminderService.getScheduledAt(deadline) <= now;
      if (!desiredMap.has(state.deadlineId) && !retainDelivered) {
        if (!await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; retainedIds.add(state.reminderId); }
      } else { stateMap.set(state.deadlineId, state); retainedIds.add(state.reminderId); }
    }
    for (const info of system) {
      if (!DeadlineReminderService.ownsReminder(info) || retainedIds.has(info.reminderId)) { continue; }
      const adopt = desired.find((item: DesiredReminder) => DeadlineReminderService.matchesSystem(info, item));
      if (adopt !== undefined && !stateMap.has(adopt.key)) {
        const state = new DeadlineReminderState(adopt.key, info.reminderId, adopt.scheduledAt, adopt.signature);
        await DeadlineDatabaseService.saveReminderState(context, state);
        stateMap.set(adopt.key, state); retainedIds.add(info.reminderId);
      } else if (!await DeadlineReminderService.cancelSystemReminder(info.reminderId)) { failed = true; }
    }
    for (const item of desired) {
      const state = stateMap.get(item.key);
      const valid = state !== undefined && system.some((info: reminderAgentManager.ReminderInfo) => info.reminderId === state.reminderId);
      if (state !== undefined && valid && state.signature === item.signature && state.scheduledAt === item.scheduledAt) { continue; }
      if (state !== undefined && !await DeadlineReminderService.cancelStoredState(context, state)) { failed = true; continue; }
      if (item.scheduledAt <= Date.now()) { continue; } // never catch up expired reminders
      try {
        await DeadlineReminderService.publishAndSave(context, item);
        for (const mark of item.riskMarks) {
          const existing = marks.find((value: NotificationRiskMark) => value.id === mark.id);
          if (existing === undefined) { marks.push(mark); } else { existing.signal = mark.signal; }
        }
        if (item.riskMarks.length > 0) {
          runtime.lastRiskAt = item.scheduledAt;
          await NotificationSettingsService.saveRiskHistory(context, JSON.stringify(marks), runtime.lastRiskAt);
        }
      } catch (error) { failed = true; AppLogger.error('DeadlineReminder', 'System reminder reconciliation needs retry', error); }
    }
    const today = DeadlineReminderService.getDateKey(now);
    if (runtime.lastPlanDate !== today || runtime.lastPlanTaskIds.length === 0) {
      await NotificationSettingsService.savePlanSnapshot(context, today,
        DeadlineReminderService.getTodayPlannedTaskIds(snapshot.deadlines, snapshot.subtasks, now));
    }
    if (failed) { throw new Error('One or more system reminders were not updated; local Deadline data is saved.'); }
    AppLogger.info('DeadlineReminder', `Reconciled ${desired.length} local reminders`);
  }

'''+s[b:]
# Callers already isolate notification failures from business saves. Propagate
# to those callers so a failed system registration is never reported scheduled.
s=s.replace("      AppLogger.error('DeadlineReminder', 'Reminder reconciliation failed', error);", "      AppLogger.error('DeadlineReminder', 'Reminder reconciliation failed', error);\n      throw error;",1)
for marker in ['await NotificationSettingsService.recordUserActivity(context, deadlineId);','await NotificationSettingsService.recordUserActivity(context, deadline.id);']:
    assert marker in s
    ident='deadlineId' if 'deadlineId)' in marker else 'deadline.id'
    s=s.replace(marker,marker+f'''\n      const previous = await DeadlineDatabaseService.getReminderState(context, {ident});
      if (previous !== undefined && previous.scheduledAt <= Date.now()) {{
        await DeadlineReminderService.cancelStoredState(context, previous);
      }}''',1)
s=s.replace('const MIN_FUTURE_DELAY: number = 2 * MINUTE_MILLISECONDS;\n','')
p.write_text(s,encoding='utf-8')
print('Applied notification-only reconciliation and truthful failure propagation.')
