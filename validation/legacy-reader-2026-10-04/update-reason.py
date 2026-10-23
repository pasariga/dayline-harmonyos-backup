from pathlib import Path
import json,re
values={
'base':'Confirm roughly how much work remains to assess the risk.',
'en_US':'Confirm roughly how much work remains to assess the risk.',
'zh_CN':'请先确认大约还需多久，才能判断风险。',
'zh_TW':'請先確認大約還需多久，才能判斷風險。',
'de_DE':'Bestätige ungefähr, wie viel Zeit noch nötig ist, um das Risiko einzuschätzen.',
'es_ES':'Confirma cuánto tiempo necesitas aún para evaluar el riesgo.',
'fr_FR':'Confirmez le temps de travail restant pour évaluer le risque.',
'ja_JP':'リスクを判断するには、残りの作業におよそ何時間かかるか確認してください。',
'ko_KR':'위험도를 판단하려면 남은 작업에 필요한 시간을 대략 확인해 주세요.'}
changes=[]
for locale,value in values.items():
    p=Path('entry/src/main/resources')/locale/'element/messages.json'
    text=p.read_text(encoding='utf-8-sig')
    data=json.loads(text); rows=data['string']
    keys=[r['name'] for r in rows]
    assert len(keys)==len(set(keys))==403
    before=next(r['value'] for r in rows if r['name']=='risk_reason_missing_workload')
    pattern=r'("name": "risk_reason_missing_workload",\s*"value": )"(?:[^"\\]|\\.)*"'
    changed,count=re.subn(pattern,lambda m:m[1]+json.dumps(value,ensure_ascii=False),text)
    assert count==1
    updated=json.loads(changed)
    assert [r['name'] for r in updated['string']]==keys
    p.write_text(changed,encoding='utf-8')
    changes.append(dict(path=str(p),before=before,after=value))
Path('validation/legacy-reader-2026-10-04/localized-reason-change.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: one existing key updated in nine locales; 403 keys each, unchanged key topology.')
