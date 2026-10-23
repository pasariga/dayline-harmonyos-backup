from pathlib import Path
import runpy,json,re
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'));sql,run=h['sql'],h['call']
ids=['notification-acceptance-'+str(i) for i in range(3)]
def lit(v):
    if v is None:return 'NULL'
    if isinstance(v,(int,float)):return str(v)
    return "'"+str(v).replace("'","''")+"'"
run('shell','aa force-stop com.gary.ddl')
assert sql('SELECT count(*) FROM deadlines;')=='0'
result={};attach="ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture; "
for table in ['deadlines','deadline_subtasks','ddl_sync_events','ddl_sync_archive']:
    cols=[line.split('|')[1] for line in sql(attach+'PRAGMA fixture.table_info('+table+');').splitlines()]
    col='id' if table=='deadlines' else 'deadline_id'
    query='SELECT json_group_array(json_object('+','.join(lit(c)+','+c for c in cols)+')) FROM fixture.'+table
    result[table]=json.loads(sql(attach+query+' WHERE '+col+' IN ('+','.join(lit(i) for i in ids)+');'))
assert len(result['deadlines'])==3 and len(result['deadline_subtasks'])==3 and len(result['ddl_sync_events'])==3
q='BEGIN IMMEDIATE; '
for table,rows in result.items():
    for row in rows:
        assert row['id' if table=='deadlines' else 'deadline_id'] in ids
        assert all(re.fullmatch('[a-z_]+',key) for key in row)
        q+='INSERT INTO '+table+' ('+','.join(row)+') VALUES ('+','.join(lit(v) for v in row.values())+'); '
sql(q+'COMMIT;');assert sql('PRAGMA integrity_check;')=='ok'
(OUT/'fixture-manifest.json').write_text(json.dumps({row['id']:row['name'] for row in result['deadlines']},ensure_ascii=False),encoding='utf-8')
print('Adopted only 3 isolated application-generated synthetic aggregates; no original row changed.')
