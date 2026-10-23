from pathlib import Path
import runpy,time,json
o=runpy.run_path(str(Path(__file__).with_name('ops.py')))
u=o['u'];tap=o['tap'];fill=o['fill'];shot=o['snapshot']
u['back']();o['system_tap']('取消')
assert not any(n.get('type')=='AlertDialog' for n in u['nodes']())
shot('final-discard-cancel',('9','更改未保存'))
text=Path(__file__).with_name('runtime-core.py').read_text(encoding='utf-8')
suffix=text[text.index("tap('保存新估计',True);shot('final-confirm-nine'"):]
exec(compile(suffix,'runtime-core-resume','exec'))
