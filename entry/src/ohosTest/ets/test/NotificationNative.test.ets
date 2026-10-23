import { describe, beforeAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Deadline, DeadlineSubtask } from '../../../main/ets/models/Deadline';
import { DeadlineDatabaseService } from '../../../main/ets/services/DeadlineDatabaseService';
import { DeadlineReminderService } from '../../../main/ets/services/DeadlineReminderService';
import { NotificationSettings, NotificationSettingsService } from '../../../main/ets/services/NotificationSettingsService';

class NativeNotificationEvidence {
  permissionEnabled: boolean = false;
  initialReminderCount: number = 0;
  calendarRegistered: boolean = false;
  calendarCode: number = 0;
  timerRegistered: boolean = false;
  timerCode: number = 0;
  finalReminderCount: number = 0;
  applicationResult: string = '';
  savedDeadlines: number = 0;
  controlPublished: boolean = false;
  controlCode: number = 0;
}

function synthetic(id: string, due: number): Deadline {
  const date=new Date(due);
  return new Deadline(id, '通知验收 '+id.substring(id.lastIndexOf('-')+1),'考试',
    `${date.getFullYear()}-${date.getMonth()+1}-${date.getDate()}`,
    `${date.getHours()}:${date.getMinutes()}`,'',Date.now(),due,false,10,0,'automatic',1,60,10,'initial',Date.now());
}

export default function notificationNativeTest() {
  describe('notificationNative', () => {
    let context: common.UIAbilityContext;
    let originalSettings: NotificationSettings;
    let initialDeadlineCount: number = 0;
    const ownId: string = 'notification-acceptance-native-'+Date.now();
    const evidence=new NativeNotificationEvidence();
    beforeAll(async () => {
      const delegator=abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({bundleName:'com.gary.ddl',abilityName:'EntryAbility'});
      context=(await delegator.getCurrentTopAbility()).context;
    });
    it('records actual permission inventory and agent registration outcomes',0,async () => {
      evidence.permissionEnabled=await notificationManager.isNotificationEnabled();
      const before=await reminderAgentManager.getAllValidReminders();
      evidence.initialReminderCount=before.length;
      const at=new Date(Math.ceil((Date.now()+180000)/60000)*60000);
      const request:reminderAgentManager.ReminderRequestCalendar={
        reminderType:reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime:{year:at.getFullYear(),month:at.getMonth()+1,day:at.getDate(),hour:at.getHours(),minute:at.getMinutes()},
        title:'Dayline calendar acceptance',content:'Synthetic notification test',notificationId:190004001,
        groupId:'notification-native-calendar',slotType:notificationManager.SlotType.SERVICE_INFORMATION,
        wantAgent:{pkgName:'com.gary.ddl',abilityName:'EntryAbility'}
      };
      try { const id=await reminderAgentManager.publishReminder(request); evidence.calendarRegistered=true;
        await reminderAgentManager.cancelReminder(id); }
      catch(error){evidence.calendarCode=(error as BusinessError).code;}
      try { const id=await reminderAgentManager.publishReminder({
        reminderType:reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,triggerTimeInSeconds:10,
        title:'Dayline timer acceptance',content:'Synthetic timer test',notificationId:190004002,
        groupId:'notification-native-timer',wantAgent:{pkgName:'com.gary.ddl',abilityName:'EntryAbility'}
      } as reminderAgentManager.ReminderRequestTimer);evidence.timerRegistered=true;
        await reminderAgentManager.cancelReminder(id); }
      catch(error){evidence.timerCode=(error as BusinessError).code;}
      // Passing this diagnostic test does NOT mean a system reminder was displayed.
      expect(evidence.calendarRegistered || evidence.calendarCode>0).assertTrue();
      expect(evidence.timerRegistered || evidence.timerCode>0).assertTrue();
      console.info('NOTIFICATION_NATIVE_GATE '+JSON.stringify(evidence));
    });
    it('keeps committed data and reports registration failure accurately',0,async () => {
      const existing=await DeadlineDatabaseService.getAllDeadlines(context);
      expect(existing.some((item: Deadline)=>item.id===ownId)).assertFalse();
      initialDeadlineCount=existing.length;
      originalSettings=await NotificationSettingsService.getSettings(context);
      await NotificationSettingsService.saveSettings(context,new NotificationSettings('concise',false,false,false,8,30,false));
      const now=Date.now();
      const d=synthetic(ownId,Math.ceil((now+3780000)/60000)*60000);
      await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,[],false);
      const result=await DeadlineReminderService.applyDeadline(context,d,false);
      evidence.applicationResult=result.code;
      evidence.savedDeadlines=(await DeadlineDatabaseService.getAllDeadlines(context)).length-initialDeadlineCount;
      expect(evidence.savedDeadlines).assertEqual(1);
      if (!evidence.permissionEnabled) { expect(result.code).assertEqual('permission_disabled'); }
      else if (!evidence.calendarRegistered) { expect(result.code).assertEqual('failed'); }
      else { expect(result.code).assertEqual('scheduled'); }
    });
    it('cancels completion restores once and leaves no deleted reminder state',0,async () => {
      let d=(await DeadlineDatabaseService.getAllDeadlines(context)).find((item: Deadline)=>item.id===ownId)!;
      expect(d!==undefined).assertTrue();
      await DeadlineDatabaseService.updateCompleted(context,d,true);
      d=(await DeadlineDatabaseService.getAllDeadlines(context)).find((item: Deadline)=>item.id===ownId)!;
      await DeadlineReminderService.applyDeadline(context,d,false);
      expect((await DeadlineDatabaseService.getAllReminderStates(context)).filter(state=>state.deadlineId===ownId).length).assertEqual(0);
      await DeadlineDatabaseService.updateCompleted(context,d,false);
      d=(await DeadlineDatabaseService.getAllDeadlines(context)).find((item: Deadline)=>item.id===ownId)!;
      await DeadlineReminderService.applyDeadline(context,d,false);
      try {await Promise.all([DeadlineReminderService.reconcileAll(context),DeadlineReminderService.reconcileAll(context)]);} catch (_) {}
      expect((await DeadlineDatabaseService.getAllReminderStates(context)).filter(state=>state.deadlineId===ownId).length<=1).assertTrue();
      await DeadlineReminderService.cancelForDeadline(context,d.id);
      await DeadlineDatabaseService.deleteDeadline(context,d);
      await DeadlineReminderService.onUserDataChanged(context,d.id);
      expect((await DeadlineDatabaseService.getAllReminderStates(context)).filter(state=>state.deadlineId===ownId).length).assertEqual(0);
      evidence.finalReminderCount=(await reminderAgentManager.getAllValidReminders()).length;
      expect(evidence.finalReminderCount).assertEqual(evidence.initialReminderCount);
      const previousRuntime=await NotificationSettingsService.getRuntimeState(context);
      await NotificationSettingsService.saveRiskHistory(context,'[{"id":"notification-synthetic","signal":"high"}]',123);
      const runtime=await NotificationSettingsService.getRuntimeState(context);
      expect(runtime.lastRiskAt).assertEqual(123);
      expect(runtime.riskMarks.includes('notification-synthetic')).assertTrue();
      await NotificationSettingsService.saveRiskHistory(context,previousRuntime.riskMarks,previousRuntime.lastRiskAt);
      await NotificationSettingsService.saveSettings(context,originalSettings);
      expect((await DeadlineDatabaseService.getAllDeadlines(context)).length).assertEqual(initialDeadlineCount);
      const file=fileIo.openSync(context.filesDir+'/notification-native-evidence.json',fileIo.OpenMode.CREATE|fileIo.OpenMode.READ_WRITE|fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd,JSON.stringify(evidence));fileIo.closeSync(file);
      console.info('NOTIFICATION_NATIVE_FINAL '+JSON.stringify(evidence));
    });
  });
  describe('notificationControl', () => {
    it('publishes an isolated ordinary notification as a permission control only',0,async () => {
      try {
        await notificationManager.publish({id:190004003,autoDeletedTime:Date.now()+300000,
          // SDK API24's shared content interface still refers to the legacy
          // enum. Both enums define BASIC_TEXT as 0; avoid an enum-type mismatch.
          content:{contentType:0,
            normal:{title:'Dayline 通知通道检查',text:'仅验证系统通知显示，不代表截止提醒已通过。'}}});
        console.info('NOTIFICATION_CONTROL_PUBLISHED');
      } catch(error){console.info('NOTIFICATION_CONTROL_FAILED '+(error as BusinessError).code);}
    });
  });
  describe('notificationUiFixtures', () => {
    it('creates only isolated synthetic aggregates for signed application acceptance',0,async () => {
      const delegator=abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({bundleName:'com.gary.ddl',abilityName:'EntryAbility'});
      const context=(await delegator.getCurrentTopAbility()).context;
      expect((await DeadlineDatabaseService.getAllDeadlines(context)).length).assertEqual(0);
      const now=Date.now();
      for(let i=0;i<3;i++){
        const id='notification-acceptance-'+i;
        const d=synthetic(id,Math.ceil((now+(i+1)*86400000)/60000)*60000);
        const ts:DeadlineSubtask[]=[new DeadlineSubtask(id+'-task',id,'复习重点',false,now)];
        await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,ts,false);
      }
    });
  });
  describe('notificationCleanup', () => {
    it('clears only the synthetic permission-control notification',0,async () => {
      try { await notificationManager.cancel(190004003); } catch (_) {}
      const active=await notificationManager.getActiveNotifications();
      expect(active.some((request: notificationManager.NotificationRequest)=>request.id===190004003)).assertFalse();
      expect((await reminderAgentManager.getAllValidReminders()).length).assertEqual(0);
    });
  });
  describe('notificationPermissionEntry', () => {
    it('opens the real system notification setting for explicit permission verification',0,async () => {
      const delegator=abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({bundleName:'com.gary.ddl',abilityName:'EntryAbility'});
      const context=(await delegator.getCurrentTopAbility()).context;
      await notificationManager.openNotificationSettings(context);
    });
  });
}
