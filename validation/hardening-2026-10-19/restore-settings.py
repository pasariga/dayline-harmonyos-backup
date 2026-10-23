from pathlib import Path
import runpy,time,json
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];v=h['values']('zh_CN')
h['appearance']('de_DE','zh_CN','light');h['system_font'](2,'final-restored')
h['wait'](v['settings_title']);h['home']('zh_CN');h['tap'](v['settings_title']);h['tap'](v['settings_appearance_language'])
h['select'](0,v['settings_theme_system']);h['select'](1,v['settings_language_system'])
time.sleep(1);u['restart']();h['wait'](v['settings_title'])
record=json.loads((OUT/'final-restored-system-font.json').read_text())
assert [float(s['value']) for s in record['sliders']]==[2,1,1]
print('PASS: original App System theme/language and system font/weight/display settings restored.',flush=True)
