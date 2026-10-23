from pathlib import Path
import hashlib, json, re, zipfile

OUT=Path(__file__).parent
result={}
folders=['base','zh_CN','zh_TW','en_US','ja_JP','ko_KR','de_DE','es_ES','fr_FR']
adjusted=['cloud_release_unavailable','settings_privacy_summary','settings_privacy_desc',
 'notification_delivery_notice','create_reminder_on_desc','message_saved_reminder_retry',
 'message_status_updated_reminder_retry','message_deadline_deleted_reminder_retry']
reference={};visible=[]
for folder in folders:
    values={}
    for kind in ['string','messages','product']:
        rows=json.loads((Path('entry/src/main/resources')/folder/'element'/(kind+'.json')).read_text(encoding='utf-8'))['string']
        names=[r['name'] for r in rows]
        assert len(names)==len(set(names))
        if folder=='base':reference[kind]=set(names)
        assert set(names)==reference[kind]
        values.update({r['name']:r['value'] for r in rows})
        for row in rows:
            if re.search(r'\b(?:DDL|Demo|Debug|Test)\b|追期',row['value'],re.I):
                visible.append({'locale':folder,'key':row['name']})
    assert all(k in values for k in adjusted)
    if folder=='base':base=values
    for k in adjusted:assert re.findall(r'\{\d+\}|%s',values[k])==re.findall(r'\{\d+\}|%s',base[k])
assert not visible,'Unexpected visible development label'
result.update({'resource_sets':9,'new_or_adjusted_messages':len(adjusted),
 'duplicate_keys':0,'placeholder_consistency':True,'visible_test_or_old_brand_matches':visible})

before={p.replace('\\','/'):v for p,v in json.loads((OUT/'source-before.json').read_text()).items()}
changed=[]
for p,digest in before.items():
    if hashlib.sha256(Path(p).read_bytes()).hexdigest()!=digest:changed.append(p)
db='entry/src/main/ets/services/DeadlineDatabaseService.ets'
text=Path(db).read_text(encoding='utf-8')
db_log_lines=[line for line in text.splitlines() if 'console.error' in line]
assert not any('JSON.stringify' in line for line in db_log_lines), 'Raw database error in public log'
assert not any('.message}' in line for line in db_log_lines), 'Unbounded database exception message in public log'
sanitized=json.loads((OUT/'log-sanitization.json').read_text())
assert sum(1 for line in db_log_lines if 'CloudDiagnostic.code' in line)==sanitized[db.replace('/','\\')]
for p in before:
    if any(key in p for key in ['SyncProtocol','ConflictRecovery','LegacyCloud','LegacySnapshot','AgcShadow','DeadlineInsight','DeadlineSchedule','TodayAction','ProgressService','NotificationPolicy','ReminderService']):
        assert p not in changed,'Frozen business/protocol service changed: '+p
assert 'build-profile.json5' not in changed and 'entry/build-profile.json5' not in changed
assert 'entry/src/main/module.json5' not in changed
result.update({'frozen_protocol_and_business_services_preserved':True,
 'database_public_errors_sanitized':True,'signing_sdk_module_permissions_preserved':True,
 'changed_baseline_services_and_configs':changed})
app=json.loads(Path('AppScope/app.json5').read_text())['app']
assert app['bundleName']=='com.gary.ddl' and app['cloudStructuredDataSyncEnabled'] is False
result['application_cloud_capability_declared']=False
result['vendor_placeholder_remaining']=app['vendor']=='example'
result['legal_policy_url_found']=bool(re.search(r'https://[^\s"\']+privacy',Path('README.md').read_text(encoding='utf-8'),re.I))

if Path('entry/build/default/outputs/default/entry-default-signed.hap').exists():
    hap=Path('entry/build/default/outputs/default/entry-default-signed.hap')
    with zipfile.ZipFile(hap) as z:
        names=z.namelist()
        forbidden=[n for n in names if re.search(r'\.(p12|pfx|pem|key|sql)$|(^|/)(validation|ohosTest|test)/|build-profile|\.before\.',n,re.I)]
        assert not forbidden,'Private/development file packed'
        manifest=json.loads(z.read('module.json'))
        result['package_build_mode']=manifest['app'].get('buildMode')
        result['package_debug_flag']=manifest['app'].get('debug')
        result['package_cloud_flag']=manifest['app'].get('cloudStructuredDataSyncEnabled')
        assert result['package_build_mode']=='release'
        assert result['package_debug_flag'] is False and result['package_cloud_flag'] is False
        result['private_or_validation_files_in_hap']=0
        result['signed_hap_sha256']=hashlib.sha256(hap.read_bytes()).hexdigest().upper()
(OUT/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PASS: resources, logging-only database changes, frozen services/config, package content checks.')
print(json.dumps({k:result[k] for k in ['package_build_mode','package_debug_flag','package_cloud_flag','vendor_placeholder_remaining']}))
