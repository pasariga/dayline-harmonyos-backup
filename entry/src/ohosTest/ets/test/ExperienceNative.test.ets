import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON, DisplayRotation } from '@ohos.UiTest';
import { abilityDelegatorRegistry } from '@kit.TestKit';

async function openPlan(driver: Driver): Promise<void> {
  for (let attempt: number = 0; attempt < 10; attempt++) {
    const plan = await driver.findComponent(ON.text('工作量与计划'));
    if (plan !== null) { await plan.click(); await driver.delayMs(600); return; }
    const start = await driver.findComponent(ON.text('开始这一步'));
    if (start !== null) { await start.click(); await driver.delayMs(800); continue; }
    const discard = await driver.findComponent(ON.text('放弃更改'));
    if (discard !== null) { await discard.click(); await driver.delayMs(1000); continue; }
    const creator = await driver.findComponent(ON.id('deadlineName'));
    if (creator !== null) { await driver.pressBack(); await driver.delayMs(600); continue; }
    const today = await driver.findComponent(ON.text('今天'));
    if (today !== null) { await today.click(); await driver.delayMs(600); continue; }
    await driver.pressBack();
    await driver.delayMs(600);
  }
  throw new Error('UI fixture could not reach the plan workspace');
}

// UI-only acceptance. No account, database, cloud or reminder calls.
export default function experienceNativeTest() {
  describe('experienceNative', () => {
    it('rotateDraft', 0, async () => {
      const driver = Driver.create();
      const original = await driver.getDisplayRotation();
      // aa test starts its own runner, so establish the UI precondition here.
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({bundleName:'com.gary.ddl',abilityName:'EntryAbility'});
      await driver.delayMs(1800);
      const add = await driver.findComponent(ON.text('+'));
      if (add === null) { throw new Error('UI fixture needs a home add control'); }
      await add.click();
      await driver.delayMs(400);
      const draft = await driver.findComponent(ON.id('deadlineName'));
      if (draft === null) { throw new Error('Name input not found on the fixture form'); }
      await draft.inputText('UX18-DraftRotation');
      expect(await draft.getText()).assertEqual('UX18-DraftRotation');
      try {
        await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
        await driver.delayMs(700);
        const size = await driver.getDisplaySize();
        console.info('DAYLINE_EXPERIENCE_ROTATION '+JSON.stringify({rotation:await driver.getDisplayRotation(),width:size.x,height:size.y}));
        expect(await (await driver.findComponent(ON.id('deadlineName'))).getText()).assertEqual('UX18-DraftRotation');
        const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        expect(await driver.screenCap(context.cacheDir+'/experience-2026-10-18-landscape.png')).assertTrue();
      } finally {
        await driver.setDisplayRotation(original);
      }
      expect(await (await driver.findComponent(ON.id('deadlineName'))).getText()).assertEqual('UX18-DraftRotation');
    });
    it('rotateWorkspace', 0, async () => {
      const driver = Driver.create();
      await openPlan(driver);
      const original = await driver.getDisplayRotation();
      try {
        await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
        await driver.delayMs(700);
        const size = await driver.getDisplaySize();
        const calibration = await driver.findComponent(ON.text('校准剩余时间'));
        if (calibration === null) { throw new Error('Calibration not available after rotation'); }
        expect((await calibration.getBounds()).top < size.y).assertTrue();
        const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
        expect(await driver.screenCap(context.cacheDir+'/experience-2026-10-18-workspace-landscape.png')).assertTrue();
      } finally { await driver.setDisplayRotation(original); }
    });
  });
}
