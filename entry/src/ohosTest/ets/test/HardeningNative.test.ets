import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON, DisplayRotation } from '@ohos.UiTest';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';

export default function hardeningNativeTest() {
  describe('hardeningNative', () => {
    it('foregroundResumeKeepsHomeUsable', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({bundleName:'com.gary.ddl',moduleName:'entry',abilityName:'EntryAbility'});
      const driver = Driver.create();
      for (let i: number = 0; i < 20; i++) {
        if (await driver.findComponent(ON.id('homeAddDeadline')) !== null) { break; }
        await driver.delayMs(300);
      }
      await driver.pressHome();
      await driver.delayMs(500);
      await delegator.startAbility({bundleName:'com.gary.ddl',moduleName:'entry',abilityName:'EntryAbility'});
      await driver.delayMs(1500);
      expect(await driver.findComponent(ON.text('正在整理今天的优先事项…')) === null).assertTrue();
      expect(await driver.findComponent(ON.id('homeAddDeadline')) !== null).assertTrue();
    });
    it('followsRealSystemFontAndKeepsTouchSize', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ability = await delegator.getCurrentTopAbility();
      const mainWindow = await window.getLastWindow(ability.context);
      const ui = mainWindow.getUIContext();
      const driver = Driver.create();
      expect(ui.isFollowingSystemFontScale()).assertTrue();
      expect(ui.getKeyboardAvoidMode()).assertEqual(KeyboardAvoidMode.RESIZE);
      expect(Math.abs(ui.getMaxFontScale() - 3.2) < 0.0001).assertTrue();
      console.info('DAYLINE_HARDENING_FONT '+JSON.stringify({scale:ability.context.config.fontSizeScale,
        follows:ui.isFollowingSystemFontScale(),max:ui.getMaxFontScale(),size:await driver.getDisplaySize()}));
      const add = await driver.findComponent(ON.id('homeAddDeadline'));
      if (add === null) { throw new Error('Home add control missing'); }
      const bounds = await add.getBounds();
      expect(bounds.right-bounds.left >= ui.vp2px(43)).assertTrue();
      expect(bounds.bottom-bounds.top >= ui.vp2px(43)).assertTrue();
    });
    it('portraitRotationRequestPreservesDraftAndBack', 0, async () => {
      const driver=Driver.create();
      const original=await driver.getDisplayRotation();
      const add=await driver.findComponent(ON.id('homeAddDeadline'));
      if(add===null){throw new Error('Home add control missing');}
      await add.click();await driver.delayMs(350);
      const input=await driver.findComponent(ON.id('deadlineName'));
      if(input===null){throw new Error('Name input missing');}
      await input.inputText('UX19-Rotation-Draft');
      try {
        await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
        await driver.delayMs(650);
        const current=await driver.findComponent(ON.id('deadlineName'));
        if(current===null){throw new Error('Draft missing after rotation request');}
        expect(await current.getText()).assertEqual('UX19-Rotation-Draft');
        console.info('DAYLINE_HARDENING_ORIENTATION '+JSON.stringify({rotation:await driver.getDisplayRotation(),
          size:await driver.getDisplaySize(),policy:'portrait'}));
      } finally {await driver.setDisplayRotation(original);}
      const context=abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      await driver.screenCap(context.cacheDir+'/hardening-rotation-before-back.png');
      await driver.pressBack();await driver.delayMs(800);
      await driver.screenCap(context.cacheDir+'/hardening-rotation-first-back.png');
      let discard=await driver.findComponent(ON.text('放弃更改'));
      if(discard===null) {
        const current=await driver.findComponent(ON.id('deadlineName'));
        if(current===null){throw new Error('Neither draft nor confirmation remained after Back');}
        expect(await current.getText()).assertEqual('UX19-Rotation-Draft');
        await driver.pressBack();await driver.delayMs(800);
        discard=await driver.findComponent(ON.text('放弃更改'));
      }
      if(discard===null){throw new Error('Draft confirmation not reachable');}
      await discard.click();await driver.delayMs(400);
      expect(await driver.findComponent(ON.text('今天'))!==null).assertTrue();
    });
  });
}
