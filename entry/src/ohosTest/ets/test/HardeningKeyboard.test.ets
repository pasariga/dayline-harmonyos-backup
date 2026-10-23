// Native UI flow: establish its own owned work object after the runner opens a window.
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Driver, ON } from '@ohos.UiTest';
import { fileIo } from '@kit.CoreFileKit';

async function inputOnOwnedProject(driver: Driver, id: string) {
  const delegator=abilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({bundleName:'com.gary.ddl',moduleName:'entry',abilityName:'EntryAbility'});
  await driver.delayMs(900);
  const ability=await delegator.getCurrentTopAbility();
  console.info('DAYLINE_KEYBOARD_MODULE '+ability.context.abilityInfo.moduleName);
  const projectTab=await driver.findComponent(ON.text('Deadlines'));
  if(projectTab===null){throw new Error('Start this fixture from the normal home screen');}
  await projectTab.click();await driver.delayMs(300);
  let project=await driver.findComponent(ON.text('UX19-Mathematik-Pruefung-Abschlussprojekt-langer-Titel'));
  for(let i: number=0;project===null&&i<20;i++) {
    await driver.delayMs(300);
    project=await driver.findComponent(ON.text('UX19-Mathematik-Pruefung-Abschlussprojekt-langer-Titel'));
  }
  if(project===null){await driver.screenCap(delegator.getAppContext().cacheDir+'/hardening-keyboard-missing-fixture.png');}
  if(project===null){throw new Error('The owned keyboard fixture is missing');}
  const projectBounds=await project.getBounds();
  await driver.click(Math.floor((projectBounds.left+projectBounds.right)/2),Math.floor((projectBounds.top+projectBounds.bottom)/2));
  await driver.delayMs(900);
  if(id==='deadlineName'||id==='deadlineNote') {
    const edit=await driver.findComponent(ON.text('编辑'));
    if(edit===null){throw new Error('Project edit action is not available');}
    await edit.click();await driver.delayMs(650);
    const collapseText=id==='deadlineName'?'收起补充信息':'任务与进度';
    let collapse=await driver.findComponent(ON.text(collapseText));
    if(collapse===null) {
      const scroller=await driver.findComponent(ON.type('Scroll'));
      if(scroller!==null){collapse=await scroller.scrollSearch(ON.text(collapseText));}
    }
    if(collapse!==null) {
      const b=await collapse.getBounds();await driver.click(Math.floor((b.left+b.right)/2),Math.floor((b.top+b.bottom)/2));
      await driver.delayMs(250);
    }
  } else if(id==='remainingEstimate') {
    const plan=await driver.findComponent(ON.text('工作量与计划'));
    if(plan===null){throw new Error('Plan workspace missing');}
    await plan.click();await driver.delayMs(300);
    let calibration=await driver.findComponent(ON.text('校准剩余时间'));
    if(calibration===null) {
      const scroller=await driver.findComponent(ON.type('Scroll'));
      if(scroller!==null){calibration=await scroller.scrollSearch(ON.text('校准剩余时间'));}
    }
    if(calibration===null){throw new Error('Calibration is not reachable');}
    await calibration.click();await driver.delayMs(300);
  }
  let field=await driver.findComponent(ON.id(id));
  if(field===null) {
    const scroller=await driver.findComponent(ON.type('Scroll'));
    if(scroller!==null){field=await scroller.scrollSearch(ON.id(id));}
  }
  return field;
}

function keyboardSuite(suite: string, id: string): void {
  describe(suite, () => {
    it('realKeyboardBackPreservesInputAndSubmitRemainsReachable', 0, async () => {
      const driver=Driver.create();
      const field=await inputOnOwnedProject(driver,id);
      if(field===null){throw new Error('Prepared input is not visible: '+id);}
      const original: string=await field.getText();
      const value: string=id==='detailTaskName'?'UX19-Keyboard-Task-Resize':(id==='remainingEstimate'?'6':original);
      await field.click();await field.clearText();await field.inputText(value);await driver.delayMs(700);
      const context=abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const typedValue: string=await field.getText();
      if(id!=='deadlineNote'){expect(typedValue).assertEqual(value);}
      const metadata=fileIo.openSync(context.cacheDir+'/hardening-keyboard-'+id+'-value.json',fileIo.OpenMode.CREATE|fileIo.OpenMode.READ_WRITE|fileIo.OpenMode.TRUNC);
      try{fileIo.writeSync(metadata.fd,JSON.stringify({field:id,value:typedValue}));}finally{fileIo.closeSync(metadata);}
      expect(await driver.screenCap(context.cacheDir+'/hardening-keyboard-'+id+'.png')).assertTrue();
      await driver.pressBack();await driver.delayMs(650);
      let after=await driver.findComponent(ON.id(id));
      if(after===null) {
        const scroller=await driver.findComponent(ON.type('Scroll'));
        if(scroller!==null){after=await scroller.scrollSearch(ON.id(id));}
      }
      if(after===null){throw new Error('Back left the page while the keyboard was open');}
      expect(await after.getText()).assertEqual(typedValue);
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
