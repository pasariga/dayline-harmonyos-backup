"""Change only display geometry in the same stopped emulator; never touch userdata."""
from pathlib import Path
import os,json,subprocess,hashlib,sys
OUT=Path(__file__).parent
ROOT=(Path(os.environ['LOCALAPPDATA'])/'Huawei/Emulator/deployed').resolve()
TARGET=(ROOT/'Pura 90/config.ini').resolve()
assert TARGET.parent.name=='Pura 90' and TARGET.parent.parent==ROOT
BACKUP=OUT/'pura-screen-original.ini'
EMU=r'C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe'
def parse(data):return {line.split('=',1)[0]:line.split('=',1)[1] for line in data.decode('utf-8').splitlines() if '=' in line}
def geometry(key):return key.startswith('hw.lcd.') or key=='isCustomize'
mode=sys.argv[1]
if not BACKUP.exists():
 data=TARGET.read_bytes();p=parse(data)
 assert (p['hw.lcd.single.width'],p['hw.lcd.single.height'],p['hw.lcd.density'])==('1320','2856','560')
 BACKUP.write_bytes(data)
if mode=='backup':print('Original display configuration backed up.');raise SystemExit(0)
result=subprocess.run([EMU,'-list','-details'],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30)
raw=result.stdout;instances=json.loads(raw[raw.index('['):raw.rindex(']')+1])
primary=next(x for x in instances if x['name']=='Pura 90')
assert str(primary['isRunning']).lower()=='false','Stop the emulator normally before changing display geometry'
original=BACKUP.read_bytes();base=parse(original)
if mode=='restore':TARGET.write_bytes(original)
else:
 name={'compact':'Dayline Hardening Small','wide':'Dayline Hardening Large'}[mode]
 sample=(ROOT/name/'config.ini').resolve();assert sample.parent.parent==ROOT
 reference=parse(sample.read_bytes());lines=[]
 # This existing OS retains its display ratio. Keep the original DPI and vary
 # real pixels so the actual viewports are 320vp and 480vp, verified after boot.
 reference['hw.lcd.density']=base['hw.lcd.density']
 reference['hw.lcd.single.width']='1120' if mode=='compact' else '1680'
 reference['hw.lcd.single.height']='2000' if mode=='compact' else '3360'
 for line in original.decode('utf-8').splitlines(keepends=True):
  key=line.split('=',1)[0]
  if not geometry(key):lines.append(line)
 ending='\r\n' if b'\r\n' in original else '\n'
 for key,value in reference.items():
  if geometry(key):lines.append(key+'='+value+ending)
 TARGET.write_bytes(''.join(lines).encode('utf-8'))
after=parse(TARGET.read_bytes())
assert {k:v for k,v in base.items() if not geometry(k)}=={k:v for k,v in after.items() if not geometry(k)}
record={'mode':mode,'width':int(after['hw.lcd.single.width']),'height':int(after['hw.lcd.single.height']),
 'dpi':int(after['hw.lcd.density']),'same_emulator_identity_and_userdata':True,'non_geometry_settings_preserved':True,
 'restored_original_bytes':mode=='restore' and TARGET.read_bytes()==original}
(OUT/('screen-'+mode+'.json')).write_text(json.dumps(record,indent=2))
print(json.dumps(record,indent=2))
