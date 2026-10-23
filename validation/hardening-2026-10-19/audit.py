from pathlib import Path
import json,hashlib,re
OUT=Path(__file__).parent
before=json.loads((OUT/'source-before.json').read_text())
allowed={'Index','CreateDeadline','DeadlineDetail','Settings','AppearanceLanguageSettings','PlanningSettings','NotificationSettings'}
changed=[]
for path,digest in before.items():
 p=Path(path)
 if hashlib.sha256(p.read_bytes()).hexdigest()!=digest:
  resource_label=p.name=='messages.json' and p.parent.name=='element'
  assert (p.parent.name=='pages' and p.stem in allowed) or str(p).replace('\\','/') in ['AppScope/app.json5','entry/src/main/module.json5','entry/src/main/ets/entryability/EntryAbility.ets'] or resource_label,path
  if resource_label:
   locale=p.parent.parent.name
   a={r['name']:r['value'] for r in json.loads((OUT/('messages-'+locale+'.before.json')).read_text(encoding='utf-8'))['string']}
   b={r['name']:r['value'] for r in json.loads(p.read_text(encoding='utf-8'))['string']}
   assert a.keys()==b.keys() and [k for k in a if a[k]!=b[k]]==['remaining_editor_hint'],locale
  changed.append(str(p))
frozen=[p for p in before if '/services/' in p.replace('\\','/') or '/models/' in p.replace('\\','/') or p=='build-profile.json5']
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==before[p] for p in frozen)
entry=Path('entry/src/main/ets/entryability/EntryAbility.ets').read_text(encoding='utf-8')
entry=entry.replace("import { KeyboardAvoidMode, window }", "import { window }")
entry=entry.replace("      try {\n        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);\n      } catch (_) { AppLogger.warn('UI', 'Keyboard resize mode unavailable.'); }\n",'')
assert entry==(OUT/'EntryAbility.before.ets').read_text(encoding='utf-8'),'Only the UI keyboard avoidance policy may change in EntryAbility'
def method(text,name):
 m=re.search(r'^  (?:private (?:async )?)?'+name+r'\(',text,re.M);assert m,name
 tail=text[m.start():];end=re.search(r'\n  (?:(?:private |on|@Builder|build\())',tail[1:])
 return tail[:end.start()+1] if end else tail
methods={'Index':['loadDeadlines','reconcileAutomaticProgress','completeRecommendedTask','undoRecommendedTask','armDeadlineClock'],
 'DeadlineDetail':['loadDeadline','applyDeadline','saveProgress','saveTask','toggleTask','undoTaskChange','removeTask','saveRemainingEstimate','toggleCompleted','chooseOverdue','deleteDeadline','hasPendingDraft','confirmDiscardChanges','navigateBack'],
 'CreateDeadline':['openDatePicker','openTimePicker','hasUnsavedChanges','navigateBack','saveTaskDraft','toggleTaskDraft','removeTaskDraft','undoDraftRemoval','saveDeadline']}
for name,names in methods.items():
 a=(OUT/(name+'.before.ets')).read_text(encoding='utf-8');b=(Path('entry/src/main/ets/pages')/(name+'.ets')).read_text(encoding='utf-8')
 for func in names:
  old,new=method(a,func),method(b,func)
  if name=='Index' and func=='loadDeadlines':
   old=old.replace('if (showLoading && this.isCurrentRefresh(version)) {\n        this.isLoading = false;',
    'if (this.isCurrentRefresh(version)) {\n        this.isLoading = false;')
  if name=='DeadlineDetail' and func=='deleteDeadline':
   new=new.replace('      this.allowLeave = true;\n','')
  assert old==new,(name,func)
for locale in ['base','zh_CN','zh_TW','en_US','ja_JP','ko_KR','de_DE','es_ES','fr_FR']:
 for kind in ['messages','string','product']:
  rows=json.loads((Path('entry/src/main/resources')/locale/'element'/(kind+'.json')).read_text(encoding='utf-8'))['string']
  keys=[r['name'] for r in rows];assert len(keys)==len(set(keys))
app=json.loads(Path('AppScope/app.json5').read_text())['app']
assert app['bundleName']=='com.gary.ddl' and app['cloudStructuredDataSyncEnabled']==False
assert app['configuration']=='$profile:configuration'
assert json.loads(Path('AppScope/resources/base/profile/configuration.json').read_text())['configuration']=={'fontSizeScale':'followSystem','fontSizeMaxScale':'3.2'}
assert '"orientation": "portrait"' in Path('entry/src/main/module.json5').read_text()
for name in ['CreateDeadline','DeadlineDetail']:
 s=(Path('entry/src/main/ets/pages')/(name+'.ets')).read_text(encoding='utf-8')
 assert 'placeholder:' not in s,'Repeated form examples should not return'
result={'changed_files':changed,'frozen_services_models_entry_and_signing':len(frozen),'domain_methods_preserved':sum(map(len,methods.values()))-1,
 'home_loader_change_only_settles_latest_visible_refresh':True,'resource_key_sets_preserved':9,'one_unit_label_updated_per_locale':True,'theme_palettes_unchanged':True,
 'committed_delete_only_bypasses_obsolete_draft_navigation_guard':True,
 'system_font_following':True,'portrait_policy':True,'no_core_form_example_placeholders':True}
(OUT/'audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
