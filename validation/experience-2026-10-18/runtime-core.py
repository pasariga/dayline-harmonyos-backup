from pathlib import Path
import runpy,time,json
o=runpy.run_path(str(Path(__file__).with_name('ops.py')))
u=o['u'];tap=o['tap'];fill=o['fill'];shot=o['snapshot']
tap('Deadlines');tap('UX18-Exam')
shot('final-exam-action',('0 / 2','Find-notes-10min'))
tap('完成任务')
shot('final-task-recorded',('1 / 2','已完成','撤销','Practice-questions-6h','剩余工作量待确认'))
tap('撤销')
shot('final-task-undo',('0 / 2','Find-notes-10min'))
tap('完成任务')
tap('校准剩余时间');fill('6','remainingEstimate');tap('保存新估计',True)
shot('final-confirm-six',('约 6 小时',))
tap('校准剩余时间');fill('9','remainingEstimate')
before=u['run']('shell','pidof com.gary.ddl').strip()
u['run']('shell','uitest uiInput keyEvent Home');time.sleep(.8)
u['run']('shell','aa start -a EntryAbility -b com.gary.ddl');time.sleep(1.5)
after=u['run']('shell','pidof com.gary.ddl').strip()
assert before==after,'Background test must not be a cold restart'
shot('final-background-estimate-draft',('9','更改未保存'))
u['back']();assert '放弃未保存的更改' in '\n'.join(u['texts']())
o['system_tap']('取消');shot('final-discard-cancel',('9','更改未保存'))
tap('保存新估计',True);shot('final-confirm-nine',('约 9 小时',))
tap('编辑');fill('UX18-Exam-Updated','deadlineName');tap('保存修改',True)
value=shot('final-edit-return-workspace',('UX18-Exam-Updated','工作量与计划','约 9 小时'))
assert '下一步' not in value,'Editing from the plan must return to that working surface'
u['back']();tap('今天');shot('final-today-after-rename',('UX18-Exam-Updated',))
# Explicitly use the project space to reopen the same work object.
tap('Deadlines');tap('UX18-Exam-Updated');tap('工作量与计划');tap('编辑')
tap('2026年10月19日');o['system_tap']('17日');o['system_tap']('确定');tap('保存修改',True)
shot('final-overdue-plan',('已逾期','工作量与计划'))
tap('行动');shot('final-overdue-decision',('需要处理','继续完成','不再追踪'))
tap('继续完成');shot('final-overdue-continue',('暂不预测完工时间','Practice-questions-6h'))
u['back']();tap('今天');value=shot('final-future-before-overdue')
# The primary action must be normal work; the late Exam may only be secondary.
first=value.index('开始这一步');assert 'UX18-Exam-Updated' not in value[:first]
tap('Deadlines');tap('UX18-Exam-Updated');tap('标记完成',True)
shot('final-completed',('已完成','恢复未完成'))
tap('恢复未完成',True);shot('final-restored-overdue',('需要处理',))
tap('不再追踪',True);shot('final-stopped',('不再追踪',))
u['back']();tap('今天');shot('final-stopped-not-today')
o['remember_fixtures']()
Path(__file__).with_name('runtime-core.json').write_text(json.dumps({'task_complete_and_undo':True,'confirmed_six_and_nine':True,
 'background_draft_same_process':True,'discard_cancel_preserves_input':True,'rename_visible_on_today':True,
 'edit_returns_to_plan':True,'overdue_continued_without_forecast':True,'future_work_before_overdue':True,
 'completion_restore_pending_and_stop':True},indent=2))
print('PASS: core experience lifecycle and state consistency.',flush=True)
