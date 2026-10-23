from pathlib import Path
import re,json
counts={}
for name in ['Index','CreateDeadline','DeadlineDetail','Settings','AppearanceLanguageSettings','PlanningSettings','NotificationSettings']:
 p=Path('entry/src/main/ets/pages')/(name+'.ets');s=p.read_text(encoding='utf-8')
 old=".fontColor($r('app.color.brand_accent'))"
 count=0
 for bg in ['surface_muted','surface_accent']:
  pattern=re.escape(old)+r'\s*'+re.escape(".backgroundColor($r('app.color."+bg+"'))")
  def replace(m):return m.group().replace(old,".fontColor($r('app.color.text_body'))",1)
  s,n=re.subn(pattern,replace,s);count+=n
 p.write_text(s,encoding='utf-8');counts[name]=count
Path('validation/hardening-2026-10-19/contrast-label-fixes.json').write_text(json.dumps(counts,indent=2))
print(counts)
