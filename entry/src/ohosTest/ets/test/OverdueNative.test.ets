import { describe, beforeAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { Deadline, DeadlineSubtask } from '../../../main/ets/models/Deadline';
import { DeadlineDatabaseService } from '../../../main/ets/services/DeadlineDatabaseService';
import { DeadlineOverdueRuntime, DeadlineOverdueService } from '../../../main/ets/services/DeadlineOverdueService';

export default function overdueNativeTest() {
  describe('overdueNative', () => {
    let context: common.UIAbilityContext;
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      context = (await delegator.getCurrentTopAbility()).context;
    });
    it('flushes and reloads local intent without changing completion',0,async () => {
      await DeadlineOverdueService.load(context);
      const now = Date.now();
      const d = new Deadline('overdue-native-intent','synthetic','项目','','','',now,now-3600000,false);
      await DeadlineOverdueService.choose(context,d,'continue');
      DeadlineOverdueRuntime.restore('[]');
      await DeadlineOverdueService.load(context);
      expect(DeadlineOverdueRuntime.state(d)).assertEqual('continue');
      await DeadlineOverdueService.choose(context,d,'stopped');
      await DeadlineOverdueService.load(context);
      expect(DeadlineOverdueRuntime.state(d)).assertEqual('stopped');
      expect(d.completed).assertFalse();
      await DeadlineOverdueService.choose(context,d,'pending');
      await DeadlineOverdueService.load(context);
      expect(DeadlineOverdueRuntime.state(d)).assertEqual('pending');
    });
    it('prepares synthetic acceptance records through existing application writes',0,async () => {
      const existing = await DeadlineDatabaseService.getAllDeadlines(context);
      expect(existing.length).assertEqual(0);
      const now=Date.now();
      const names:string[]=['逾期一小时','昨天逾期','逾期七天','逾期三十天','明天考试','后天设计','正常复习'];
      const offsets:number[]=[-3600000,-86400000,-7*86400000,-30*86400000,86400000,2*86400000,4*86400000];
      for(let i=0;i<names.length;i++){
        const id='overdue-acceptance-'+i;
        const due=now+offsets[i]; const date=new Date(due);
        const dateText=`${date.getFullYear()}-${date.getMonth()+1}-${date.getDate()}`;
        const timeText=`${date.getHours()}:${date.getMinutes()}`;
        const d=new Deadline(id,names[i],'考试',dateText,timeText,'',now,due,false,
          10,50,'automatic',2,0,6,'confirmed',now);
        const tasks:DeadlineSubtask[]=[new DeadlineSubtask(id+'-small',id,'查资料（小任务）',true,now),
          new DeadlineSubtask(id+'-large',id,'完成复习（大任务）',false,now+1)];
        await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,tasks,false);
      }
      expect((await DeadlineDatabaseService.getAllDeadlines(context)).length).assertEqual(7);
    });
  });
  describe('overdueLiveClock', () => {
    it('prepares isolated native fixtures for three lifecycle boundaries',0,async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      // This runner's store is isolated. The validation script explicitly adopts
      // only these synthetic aggregates into the emulator's main test dataset.
      const context: common.UIAbilityContext = (await delegator.getCurrentTopAbility()).context;
      const now = Date.now();
      const names: string[] = ['临界详情检查','临界首页检查','临界后台检查'];
      for (let i = 0; i < names.length; i++) {
        const due = now + 180000 + i * 120000;
        const date = new Date(due);
        const id = 'overdue-acceptance-boundary3-' + i;
        const d = new Deadline(id,names[i],'考试',
          `${date.getFullYear()}-${date.getMonth()+1}-${date.getDate()}`,
          `${date.getHours()}:${date.getMinutes()}`,'',now,due,false,
          10,0,'automatic',1,0,6,'confirmed',now);
        await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,
          [new DeadlineSubtask(id+'-task',id,'继续复习',false,now)],false);
        expect((await DeadlineDatabaseService.getAllDeadlines(context)).some((item: Deadline) =>
          item.id === id && item.deadlineAt === due)).assertTrue();
      }
    });
  });
  describe('overdueBackgroundFixture', () => {
    it('prepares an isolated future record for background resumption',0,async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      const context: common.UIAbilityContext = (await delegator.getCurrentTopAbility()).context;
      const now = Date.now(); const due = now + 180000; const date = new Date(due);
      const id = 'overdue-acceptance-background3';
      const d = new Deadline(id,'独立后台临界检查','考试',
        `${date.getFullYear()}-${date.getMonth()+1}-${date.getDate()}`,
        `${date.getHours()}:${date.getMinutes()}`,'',now,due,false,10,0,'automatic',1,0,6,'confirmed',now);
      await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,
        [new DeadlineSubtask(id+'-task',id,'继续复习',false,now)],false);
      expect((await DeadlineDatabaseService.getAllDeadlines(context)).some((item: Deadline) =>
        item.id===id && item.deadlineAt===due)).assertTrue();
    });
  });
  describe('overdueFinalFixtures', () => {
    it('prepares two isolated expired aggregates for final signed package regression',0,async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.gary.ddl', abilityName: 'EntryAbility' });
      const context: common.UIAbilityContext = (await delegator.getCurrentTopAbility()).context;
      const now = Date.now();
      const due = now - 86400000;
      const date = new Date(due);
      const names: string[] = ['收尾逾期调整','收尾逾期恢复'];
      for (let i = 0; i < names.length; i++) {
        const id = 'overdue-acceptance-final-' + i;
        const d = new Deadline(id,names[i],'考试',
          `${date.getFullYear()}-${date.getMonth()+1}-${date.getDate()}`,
          `${date.getHours()}:${date.getMinutes()}`,'',now,due,false,
          10,50,'automatic',2,0,6,'confirmed',now);
        const tasks: DeadlineSubtask[] = [new DeadlineSubtask(id+'-small',id,'查资料',true,now),
          new DeadlineSubtask(id+'-large',id,'完成复习',false,now+1)];
        await DeadlineDatabaseService.saveDeadlineWithSubtasks(context,d,tasks,false);
        expect((await DeadlineDatabaseService.getAllDeadlines(context)).some((item: Deadline) =>
          item.id === id && !item.completed)).assertTrue();
      }
    });
  });
}
