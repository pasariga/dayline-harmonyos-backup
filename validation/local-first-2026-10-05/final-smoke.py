"""UI-only local core regression on the last rebuilt signed HAP."""
import runpy, time, json
from pathlib import Path
OUT = Path(__file__).parent
u = runpy.run_path(str(OUT/'ui.py'))
def input_value(node, value):
    u['run']('shell', 'uitest uiInput click %d %d' % u['center'](node['bounds']))
    u['run']('shell', 'uitest uiInput keyEvent 2072 2017')
    u['run']('shell', 'uitest uiInput keyEvent 2055')
    u['run']('shell', 'uitest uiInput text '+value)
    time.sleep(.8)
    u['run']('shell', 'uitest uiInput click 1218 1847')
    time.sleep(.4)
def fill_first(value):
    inputs = [n for n in u['nodes']() if n.get('type') == 'TextInput']
    assert inputs
    input_value(inputs[0], value)
def system_tap(label):
    hits = [n for n in u['nodes'](True) if n.get('text') == label]
    assert hits, label
    u['run']('shell', 'uitest uiInput click %d %d' % u['center'](hits[-1]['bounds']))
    time.sleep(.7)

fill_first('LF-V1-Final')
u['tap']('请选择日期'); system_tap('6日'); system_tap('确定')
inputs = [n for n in u['nodes']() if n.get('type') == 'TextInput']
input_value(inputs[1], '10')
u['tap']('更多选项（可选）')
u['run']('shell', 'uitest uiInput swipe 650 2300 650 800 800')
u['tap']('自动进度', True)
u['run']('shell', 'uitest uiInput swipe 650 2300 650 1100 800')
fill_first('LF-Final-A'); u['tap']('添加')
fill_first('LF-Final-B'); u['tap']('添加')
u['tap']('保存 Deadline', True)
u['tap']('LF-V1-Final')
assert '约 10 小时' in u['capture']('last-created')
u['tap']('完成任务')
value = u['capture']('last-task-progress')
assert '1 / 2' in value and '剩余工作量待确认' in value
u['tap']('更新剩余估计'); fill_first('6'); u['tap']('保存新估计', True)
value = u['capture']('last-confirm-six')
assert '约 6 小时' in value and '风险等级\n信息不足' not in value
u['tap']('查看计划与详情', True)
assert '约 6 小时' in u['capture']('last-plan')
u['tap']('标记完成', True)
assert '已完成' in u['capture']('last-completed')
u['tap']('恢复未完成', True)
u['back'](); u['tap']('LF-V1-Final')
u['tap']('编辑'); u['tap']('2026年10月6日'); system_tap('4日'); system_tap('确定')
u['tap']('保存修改', True)
assert '需要处理' in u['capture']('last-overdue')
u['tap']('继续完成')
assert '暂不预测完工时间' in u['capture']('last-overdue-continue')
u['tap']('编辑'); u['tap']('2026年10月4日'); system_tap('6日'); system_tap('确定')
u['tap']('手动进度', True); u['tap']('保存修改', True)
sliders = [n for n in u['nodes']() if n.get('type') == 'Slider']
assert sliders
bounds = list(map(int, __import__('re').findall(r'\d+', sliders[0]['bounds'])))
x = bounds[0] + (bounds[2]-bounds[0])//4
u['run']('shell', 'uitest uiInput click %d %d' % (x,(bounds[1]+bounds[3])//2))
u['tap']('保存进度', True)
assert '25%' in u['capture']('last-manual-future')
u['restart'](); time.sleep(2)
u['tap']('LF-V1-Final')
assert '25%' in u['capture']('last-persistence')
h = runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
records = json.loads(h['sql']("SELECT json_group_array(json_object('id',id,'name',name)) FROM deadlines WHERE name='LF-V1-Final';"))
assert len(records) == 1
fixtures = json.loads((OUT/'fixtures.json').read_text())
(OUT/'fixtures.json').write_text(json.dumps(fixtures + records, indent=2))
u['tap']('删除', True); system_tap('删除')
assert '创建第一个 Deadline' in u['capture']('last-deleted')
print('PASS: last signed HAP local core lifecycle regression.', flush=True)
