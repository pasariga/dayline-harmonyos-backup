from pathlib import Path
import runpy,json,re
o=runpy.run_path(str(Path(__file__).with_name('ops.py')))
u=o['u'];tap=o['tap'];shot=o['snapshot'];fill=o['fill']
tap('开始这一步')
shot('final-long-action',('UX18-Design-Coursework-with-a-very-long-project-title','0 / 8','Find-books'))
tap('Prepare-submission',True)
shot('final-deep-task-feedback',('已完成','Prepare-submission','撤销'))
tap('行动')
shot('final-return-action-start',('下一步','1 / 8','Find-books','剩余工作量待确认'))
tap('撤销');shot('final-deep-task-undo',('0 / 8',))
tap('校准剩余时间')
# Focus only: UiTest did not prove the software keyboard was displayed here.
# Actual visible keyboard evidence is recorded separately in final-real-keyboard-*.
fields=[n for n in u['nodes']() if n.get('id')=='remainingEstimate']
assert len(fields)==1
u['run']('shell','uitest uiInput click %d %d'%u['center'](fields[0]['bounds']))
shot('final-keyboard-estimate')
u['run']('shell','uitest uiInput keyEvent 2070')
fill('20','remainingEstimate');tap('保存新估计',True)
u['back']();tap('Deadlines');tap('UX18-Quick')
# A manual progress draft must survive workspace changes without looking saved.
sliders=[n for n in u['nodes']() if n.get('type')=='Slider']
assert sliders
x1,y1,x2,y2=map(int,re.findall(r'\d+',sliders[0]['bounds']))
u['run']('shell','uitest uiInput click %d %d'%(x1+(x2-x1)//4,(y1+y2)//2))
shot('final-manual-draft',('25%','更改未保存'))
tap('工作量与计划');shot('final-manual-draft-other-space',('更改未保存',))
tap('行动');tap('保存进度',True)
shot('final-manual-saved',('25%','进度已保存'))
tap('校准剩余时间');tap('暂不确定',True)
shot('final-uncertain-workload',('剩余工作量待确认',))
u['back']();tap('今天');shot('final-today-with-unknown')
Path(__file__).with_name('runtime-long.json').write_text(json.dumps({'long_title_and_nested_tasks':True,
 'deep_task_receipt_and_undo':True,'workspace_returns_to_start':True,'manual_draft_survives_view_switch':True,
 'manual_progress_saved':True,'unknown_workload_degrades_without_stopping_actions':True},indent=2))
print('PASS: long-task, draft, input-focus and unknown-workload paths; visible keyboard checked separately.',flush=True)
