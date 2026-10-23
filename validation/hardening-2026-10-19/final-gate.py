from pathlib import Path
import json,hashlib
OUT=Path(__file__).parent
results={device:json.loads((OUT/('matrix-results-'+device+'.json')).read_text()) for device in ['pura','compact','wide']}
required={('zh_CN','light'),('zh_CN','dark'),('en_US','light'),('de_DE','dark')}
for device in ['pura','compact']:
 for font in [2,5]:
  actual={(r['locale'],r['theme']) for r in results[device] if r['font_setting']==font}
  assert required<=actual,(device,font,actual)
assert {2,5}<={r['font_setting'] for r in results['wide']}
assert any(r['locale']=='fr_FR' and r['font_setting']==3 for r in results['pura'])
assert len(json.loads((OUT/'keyboard-results.json').read_text()))==4
assert json.loads((OUT/'cleanup.json').read_text())['original_eight_table_digests_preserved']
assert json.loads((OUT/'screen-restore.json').read_text())['restored_original_bytes']
assert json.loads((OUT/'final-empty.json').read_text())['test_module_absent']
assert json.loads((OUT/'final-empty.json').read_text())['double_click_add_then_one_back_returns_home']
assert json.loads((OUT/'cache-cleanup.json').read_text())['only_guarded_test_cache_and_layout_files']
assert 'Tests run: 237, Failure: 0, Error: 0, Pass: 237' in (OUT/'test-final-result.txt').read_text()
assert 'BUILD SUCCESSFUL' in (OUT/'build-final.log').read_text(encoding='utf-8-sig')
assert 'default@SignHap' in (OUT/'build-final.log').read_text(encoding='utf-8-sig')
assert 'install bundle successfully' in (OUT/'install-final.log').read_text(encoding='utf-8-sig')
hap=Path('entry/build/default/outputs/default/entry-default-signed.hap')
digest=hashlib.sha256(hap.read_bytes()).hexdigest().upper()
assert digest==json.loads((OUT/'final-hap.json').read_text(encoding='utf-8-sig'))['Hash']
result={'host_tests':237,'host_failures':0,'full_flows':{d:len(r) for d,r in results.items()},
 'normal_and_large_four_locale_theme_flows_at_two_viewports':True,'signed_hap_sha256':digest,
 'original_data_preserved':True,'display_configuration_restored':True}
(OUT/'final-gate.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
