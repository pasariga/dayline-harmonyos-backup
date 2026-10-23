"""Continue the untouched foreground process after correcting a harness assertion."""
from pathlib import Path
import runpy,json,time
OUT=Path(__file__).parent
l=runpy.run_path(str(OUT/'lifecycle.py'))
proof=json.loads((OUT/'lifecycle-timeline.json').read_text(encoding='utf-8'))
l['proof'].extend(proof)
due=proof[0]['due'][2]
u=l['u']; run=l['run']; tap=l['tap']; capture=l['capture']; note=l['note']
assert '临界后台检查' in (OUT/'lifecycle-home-after.txt').read_text(encoding='utf-8').split('全部 Deadline')[0]
assert '临界首页检查' not in (OUT/'lifecycle-home-after.txt').read_text(encoding='utf-8').split('全部 Deadline')[0]
note('home and today action automatic transition passed; pending reminder not forced into a full action list')
tap('临界后台检查')
l['ready']()
tap('更新剩余估计')
fields=[n for n in u['nodes']() if n.get('type')=='TextInput' and n.get('text')=='6']
assert len(fields)==1
run('shell','uitest uiInput inputText %d %d 9'%u['center'](fields[0]['bounds']))
u['back']()
before=capture('lifecycle-background-before')
assert '9' in before and '已过期' not in before and l['epoch']()<due
pid=run('shell','pidof com.gary.ddl').strip()
run('shell','uitest uiInput keyEvent Home')
note('app background with preserved draft',due=due,pid=pid)
l['wait_cross'](due)
run('shell','aa start -a EntryAbility -b com.gary.ddl')
time.sleep(2)
after=capture('lifecycle-background-after')
assert run('shell','pidof com.gary.ddl').strip()==pid
assert '需要处理' in after and '已过期' in after and '9' in after
note('foreground resumption passed; draft preserved; same process')
tap('沿用上次',True)
u['back'](); l['ready'](); capture('lifecycle-return-home')
note('all three lifecycle cases passed')
