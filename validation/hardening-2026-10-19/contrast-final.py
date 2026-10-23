from pathlib import Path
import json
ROOT=Path('entry/src/main/resources');OUT=Path(__file__).parent
def luminance(value):
 value=value.lstrip('#')[-6:];xs=[int(value[i:i+2],16)/255 for i in [0,2,4]]
 rgb=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in xs]
 return sum(x*w for x,w in zip(rgb,[.2126,.7152,.0722]))
pairs=[('text_primary','app_background'),('text_body','app_background'),('text_secondary','app_background'),
 ('text_tertiary','app_background'),('danger','app_background'),('warning','app_background'),('success','app_background'),
 ('text_body','surface_muted'),('text_body','surface_accent')]
result={}
for mode in ['base','dark']:
 colors={r['name']:r['value'] for r in json.loads((ROOT/mode/'element/color.json').read_text())['color']}
 rows=[]
 for fg,bg in pairs:
  a,b=sorted([luminance(colors[fg]),luminance(colors[bg])]);ratio=(b+.05)/(a+.05)
  rows.append({'text':fg,'background':bg,'ratio':round(ratio,2),'normal_text_4_5':ratio>=4.5})
 assert all(r['normal_text_4_5'] for r in rows)
 result[mode]=rows
(OUT/'contrast-final.json').write_text(json.dumps(result,indent=2))
print('PASS: 18 sampled text/background pairs; not a full accessibility certification.')
