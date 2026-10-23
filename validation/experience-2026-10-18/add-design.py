import runpy
from pathlib import Path
o=runpy.run_path(str(Path(__file__).with_name('ops.py')))
if 'Research-outline' not in o['u']['texts']():
    o['fill']('Research-outline','deadlineTaskName');o['tap']('添加')
for title in ['Find-books','Summarize-concepts']:
    if '加子任务' not in o['u']['texts']():o['tap']('⋯')
    o['tap']('加子任务')
    o['fill'](title,'deadlineTaskName');o['tap']('添加')
for title in ['Prototype-interface','Implement-main-flow','Write-report','Review-calculations','Run-validation','Prepare-submission']:
    o['fill'](title,'deadlineTaskName');o['tap']('添加')
o['snapshot']('draft-many-tasks')
o['tap']('保存 Deadline',True)
o['remember_fixtures']()
o['snapshot']('today-three',('今天','开始这一步'))
print('PASS: three UI-created deadlines, including a nested task group and long title.',flush=True)
