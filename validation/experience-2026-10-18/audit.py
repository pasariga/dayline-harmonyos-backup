from pathlib import Path
import hashlib,json,re
OUT=Path(__file__).parent
before=json.loads((OUT/'protected-before.json').read_text())
changed=[p for p,digest in before.items() if hashlib.sha256(Path(p).read_bytes()).hexdigest()!=digest]
assert not changed,'Frozen source/config changed: '+str(changed)
pages=Path('entry/src/main/ets/pages')
def method(text,name):
 m=re.search(r'^  (?:private (?:async )?)?'+name+r'\(',text,re.M)
 assert m,name
 tail=text[m.start():]
 end=re.search(r'\n  (?:(?:private |on|@Builder|build\())',tail[1:])
 return tail[:end.start()+1] if end else tail
methods={
 'Index':['loadDeadlines','reconcileAutomaticProgress','completeRecommendedTask','undoRecommendedTask','armDeadlineClock'],
 'DeadlineDetail':['loadDeadline','applyDeadline','saveProgress','saveTask','toggleTask','undoTaskChange','removeTask','saveRemainingEstimate','toggleCompleted','chooseOverdue','deleteDeadline','hasPendingDraft','confirmDiscardChanges','navigateBack'],
 'CreateDeadline':['openDatePicker','openTimePicker','hasUnsavedChanges','navigateBack','saveTaskDraft','toggleTaskDraft','removeTaskDraft','undoDraftRemoval']}
for name,names in methods.items():
 old=(OUT/(name+'.before.ets')).read_text(encoding='utf-8');new=(pages/(name+'.ets')).read_text(encoding='utf-8')
 for func in names:assert method(old,func)==method(new,func),(name,func)
 if name=='CreateDeadline':
  a='    const unchangedDue:'; b='      if (!this.pageVisible) {'
  old=method(old,'saveDeadline');new=method(new,'saveDeadline')
  assert old[old.index(a):old.index(b)]==new[new.index(a):new.index(b)],'Creation domain/save contract changed'
folders=['base','zh_CN','zh_TW','en_US','ja_JP','ko_KR','de_DE','es_ES','fr_FR']
sets=[];reference={};base={}
for locale in folders:
 values={}
 for kind in ['messages','string','product']:
  rows=json.loads((Path('entry/src/main/resources')/locale/'element'/(kind+'.json')).read_text(encoding='utf-8'))['string']
  names=[r['name'] for r in rows];assert len(names)==len(set(names))
  if locale=='base':reference[kind]=set(names)
  assert set(names)==reference[kind],(locale,kind)
  values.update({r['name']:r['value'] for r in rows})
 current={k:v for k,v in values.items() if k.startswith('experience_')}
 if locale=='base':base=current
 assert current.keys()==base.keys()
 for k in current:assert re.findall(r'\{\d+\}',current[k])==re.findall(r'\{\d+\}',base[k]),(locale,k)
 sets.append(locale)
assert len(base)==33
for p in [pages/(name+'.ets') for name in methods]:
 refs=set(re.findall(r"['\"](experience_[a-z_]+)['\"]",p.read_text(encoding='utf-8')))
 assert refs<=base.keys(),str(refs-base.keys())
assert 'CLOUD_SYNC_AVAILABLE: boolean = false' in Path('entry/src/main/ets/services/ReleaseScope.ets').read_text()
result={'frozen_files_preserved':len(before),'changed_frozen_files':changed,'original_domain_handlers_preserved':sum(map(len,methods.values())),
 'creation_transaction_contract_preserved':True,'locale_sets':len(sets),'new_ui_keys_per_locale':len(base),'duplicates_or_placeholder_errors':0}
(OUT/'audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
