"""Stage/adopt only two application-generated synthetic records; no cloud path."""
from pathlib import Path
import runpy,json,re,sys
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
sql=h['sql']; ids=['overdue-acceptance-final-'+str(i) for i in range(2)]
tables=['deadlines','deadline_subtasks','ddl_sync_events','ddl_sync_archive']
file=OUT/'final-native-fixtures.json'
def literal(value):
    if value is None:return 'NULL'
    if isinstance(value,(int,float)):return str(value)
    return "'"+str(value).replace("'","''")+"'"
if sys.argv[1]=='stage':
    assert sql("SELECT count(*) FROM deadlines WHERE id IN ('"+"','".join(ids)+"');")=='0', 'Fixture unexpectedly wrote the main database.'
    sql("ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture;")
    # sqlite3 sessions are independent: attach in each query.
    result={}
    for table in tables:
        attach="ATTACH DATABASE '/data/app/el2/100/database/com.gary.ddl/entry_test/rdb/ddl.db' AS fixture; "
        cols=[line.split('|')[1] for line in sql(attach+'PRAGMA fixture.table_info('+table+');').splitlines()]
        col='id' if table=='deadlines' else 'deadline_id'
        select='SELECT json_group_array(json_object('+','.join(literal(c)+','+c for c in cols)+')) FROM fixture.'+table
        result[table]=json.loads(sql(attach+select+" WHERE "+col+" IN ('"+"','".join(ids)+"');"))
    assert len(result['deadlines'])==2 and len(result['deadline_subtasks'])==4 and len(result['ddl_sync_events'])==2
    file.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Staged only two isolated synthetic aggregates for the final package.')
elif sys.argv[1]=='adopt':
    value=json.loads(file.read_text(encoding='utf-8'))
    assert sql("SELECT count(*) FROM deadlines WHERE id IN ('"+"','".join(ids)+"');")=='0'
    q='BEGIN IMMEDIATE; '
    for table in tables:
        for row in value[table]:
            assert row.get('id' if table=='deadlines' else 'deadline_id') in ids
            assert all(re.fullmatch('[a-z_]+',c) for c in row)
            q+='INSERT INTO '+table+' ('+','.join(row)+') VALUES ('+','.join(literal(x) for x in row.values())+'); '
    sql(q+'COMMIT;')
    assert sql('PRAGMA integrity_check;')=='ok'
    print('Adopted two synthetic fixtures; original records untouched.')
