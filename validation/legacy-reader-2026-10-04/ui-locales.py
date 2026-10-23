from pathlib import Path
import time
exec(Path(__file__).with_name('ui-check.py').read_text(encoding='utf-8').split('\nlog=[]')[0])
restart=h['restart']
def select(index):
    n=[n for n in nodes() if n.get('type')=='Select'][index]
    nums=list(map(int,re.findall(r'\d+',n['bounds'])))
    call('shell','uitest','uiInput','click',str((nums[0]+nums[2])//2),str((nums[1]+nums[3])//2));time.sleep(.5)
log=[]
try:
    t=texts();assert any('请先确认大约还需多久' in s for s in t),t
    capture('final-copy-zh-light-home');log.append('ZH LIGHT\n'+'\n'.join(t))
    tap('设置');tap('外观与语言');select(0);tap('深色');select(1);tap('English');restart()
    t=texts();assert any('Confirm roughly how much work remains' in s for s in t),t
    capture('final-copy-en-dark-home');log.append('EN DARK\n'+'\n'.join(t))
    tap('Settings');tap('Appearance');select(1);tap('Deutsch');restart()
    t=texts();assert any('wie viel Zeit noch nötig ist' in s for s in t),t
    capture('final-copy-de-dark-home');log.append('DE DARK\n'+'\n'.join(t))
    tap('Einstellungen');tap('Darstellung');select(1);tap('English');restart()
    tap('Settings');tap('Appearance');select(0);tap('Use device setting');select(1);tap('Follow system');restart()
    t=texts();assert any('请先确认大约还需多久' in s for s in t),t
    log.append('PASS: final signed package reason verified in Chinese light / English dark / German dark; system settings restored.')
finally:
    (OUT/'ui-locales-final.log').write_text('\n\n'.join(log),encoding='utf-8');call('shell','rm '+remote)
