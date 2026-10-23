// Experimental runner-window probe. Not a passing keyboard gate; use direct device evidence.
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON } from '@ohos.UiTest';

function keyboardSuite(suite: string, id: string): void {
  describe(suite, () => {
    it('realKeyboardBackPreservesInputAndSubmitRemainsReachable', 0, async () => {
      const driver=Driver.create();
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({bundleName:'com.gary.ddl',abilityName:'EntryAbility'});
      await driver.delayMs(700);
      let field=await driver.findComponent(ON.id(id));
      if(field===null) {
        const scroller=await driver.findComponent(ON.type('Scroll'));
        if(scroller!==null){field=await scroller.scrollSearch(ON.id(id));}
      }
      if(field===null){throw new Error('Prepared input is not visible: '+id);}
      const original: string=await field.getText();
      const value: string=id==='detailTaskName'?'UX19-Keyboard-Task':(id==='remainingEstimate'?'6':original);
      await field.click();await field.inputText(value);await driver.delayMs(700);
      const context=abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      expect(await driver.screenCap(context.cacheDir+'/hardening-keyboard-'+id+'.png')).assertTrue();
      await driver.pressBack();await driver.delayMs(650);
      let after=await driver.findComponent(ON.id(id));
      if(after===null) {
        const scroller=await driver.findComponent(ON.type('Scroll'));
        if(scroller!==null){after=await scroller.scrollSearch(ON.id(id));}
      }
      if(after===null){throw new Error('Back left the page while the keyboard was open');}
      expect(await after.getText()).assertEqual(value);
      expect(await driver.screenCap(context.cacheDir+'/hardening-keyboard-'+id+'-back.png')).assertTrue();
      const label: string=id==='detailTaskName'?'添加':(id==='remainingEstimate'?'保存新估计':'保存修改');
      let button=await driver.findComponent(ON.text(label));
      if(button===null) {
        const scroller=await driver.findComponent(ON.type('Scroll'));
        if(scroller===null){throw new Error('Submit button and scroller are not available');}
        button=await scroller.scrollSearch(ON.text(label));
      }
      if(button===null){throw new Error('Submit is not reachable after closing the keyboard');}
      await button.click();await driver.delayMs(900);
      expect(await driver.screenCap(context.cacheDir+'/hardening-keyboard-'+id+'-submitted.png')).assertTrue();
    });
  });
}

export default function hardeningKeyboardTest() {
  keyboardSuite('hardeningKeyboardRemaining','remainingEstimate');
  keyboardSuite('hardeningKeyboardTask','detailTaskName');
  keyboardSuite('hardeningKeyboardName','deadlineName');
  keyboardSuite('hardeningKeyboardNote','deadlineNote');
}
