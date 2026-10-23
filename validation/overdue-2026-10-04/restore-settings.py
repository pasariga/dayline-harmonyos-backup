"""Restore only appearance/language/capacity values changed for acceptance."""
from pathlib import Path
import runpy,time
OUT=Path(__file__).parent
u=runpy.run_path(str(OUT/'ui.py')); c=runpy.run_path(str(OUT/'cleanup.py'))
run=u['run']
def choose(index,label):
    controls=[n for n in u['nodes']() if n.get('type')=='Select']
    assert len(controls)>index
    run('shell','uitest uiInput click %d %d'%u['center'](controls[index]['bounds']))
    time.sleep(.5); c['click_last'](label)
u['restart'](); c['ready_home'](); u['tap']('设置'); u['tap']('任务与计划')
choose(3,'5 小时'); u['capture']('cleanup-restored-planning')
u['back'](); u['tap']('外观与语言')
choose(0,'跟随系统'); choose(1,'跟随系统')
u['capture']('cleanup-restored-appearance'); u['restart'](); c['ready_home']()
u['capture']('cleanup-restored-home')
