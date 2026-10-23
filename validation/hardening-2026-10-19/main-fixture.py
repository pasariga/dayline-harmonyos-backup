from pathlib import Path
import runpy,time,json
OUT=Path(__file__).parent
o=runpy.run_path(str(OUT/'ops.py'));u=o['u'];tap=o['tap']
def input(id,value):
 for i in range(12):
  if any(n.get('id')==id for n in u['nodes']()):o['fill'](value,id);return
  u['run']('shell','uitest uiInput swipe 650 2350 650 800 700');time.sleep(.3)
 raise RuntimeError('Input unavailable '+id)
input('totalEstimate','10')
tap('任务与进度',True);tap('自动进度',True)
input('deadlineTaskName','Literaturrecherche-und-Zusammenfassung-aller-wichtigen-Pruefungsthemen');tap('添加',True)
input('deadlineTaskName','Solve-exercises');tap('添加',True)
tap('类型、提醒与备注',True)
areas=[n for n in u['nodes']() if n.get('type')=='TextArea']
for i in range(10):
 if areas:break
 u['run']('shell','uitest uiInput swipe 650 2350 650 850 700');areas=[n for n in u['nodes']() if n.get('type')=='TextArea']
assert areas
u['run']('shell','uitest uiInput click %d %d'%u['center'](areas[0]['bounds']))
u['run']('shell','uitest uiInput text '+__import__('shlex').quote(('UX19 long note: line one.\nSecond line: preserve input and make every action reachable.\n'*4)[:300]))
u['run']('shell','uitest uiInput keyEvent 2070')
o['snapshot']('max-create-note')
tap('保存 Deadline',True)
o['remember_fixtures']()
o['snapshot']('max-one-today')
tap('开始这一步');o['snapshot']('max-detail-before-layout')
print('PASS: main fixture created through the UI.',flush=True)
