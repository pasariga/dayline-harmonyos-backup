from pathlib import Path
import json,re
out=Path(__file__).parent
labels={'base':'Remaining work (hours)','en_US':'Remaining work (hours)',
 'zh_CN':'当前剩余工作量（小时）','zh_TW':'目前剩餘工作量（小時）',
 'ja_JP':'残りの作業量（時間）','ko_KR':'남은 작업량(시간)',
 'de_DE':'Restaufwand (Stunden)','es_ES':'Trabajo restante (horas)','fr_FR':'Travail restant (heures)'}
for locale,value in labels.items():
 p=Path('entry/src/main/resources')/locale/'element/messages.json'
 data=p.read_bytes();backup=out/('messages-'+locale+'.before.json')
 if not backup.exists():backup.write_bytes(data)
 text=data.decode('utf-8')
 text,n=re.subn(r'("name"\s*:\s*"remaining_editor_hint"\s*,\s*"value"\s*:\s*)"(?:[^"\\]|\\.)*"',
  lambda m:m[1]+json.dumps(value,ensure_ascii=False),text)
 assert n==1,locale
 p.write_bytes(text.encode('utf-8'))
print('Nine existing field labels now state the unit without instructional examples.')
