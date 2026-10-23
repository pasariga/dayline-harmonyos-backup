"""Check actual final-package screen evidence and scoped persistent records."""
from pathlib import Path
import runpy,json
OUT=Path(__file__).parent
h=runpy.run_path(str(OUT.parent/'legacy-reader-2026-10-04/device-check.py'))
sql=h['sql']
def screen(name): return (OUT/(name+'.txt')).read_text(encoding='utf-8')
assert '创建第一个 Deadline' in screen('release-empty')
assert '约 10 小时' in screen('release-normal-detail')
mixed=screen('release-mixed-home').split('全部 Deadline')[0]
assert mixed.index('FinalNormalCheck')<mixed.index('收尾逾期调整')
assert '需要处理' in screen('release-pending') and '已过期' in screen('release-pending')
assert '继续完成' in screen('release-continued')
assert '完成复习' in screen('release-continued-home').split('全部 Deadline')[0]
assert '原截止时间已过' in screen('release-continued-plan')
assert '执行日日均' not in screen('release-continued-plan')
assert '已逾期' not in screen('release-rescheduled-future')
assert '执行日日均' in screen('release-rescheduled-plan')
assert '已完成' in screen('release-completed')
assert '需要处理' in screen('release-restored') and '已过期' in screen('release-restored')
assert '剩余工作量待确认' in screen('release-restored')
assert '收尾逾期恢复' not in screen('release-stopped-home').split('全部 Deadline')[0]
assert '收尾逾期恢复' not in screen('release-restart-home').split('全部 Deadline')[0]
assert '不再追踪' in screen('release-stopped-after-restart')
q="SELECT json_group_array(json_object('id',id,'completed',completed,'estimated_hours',estimated_hours,'remaining_hours',remaining_hours,'remaining_state',remaining_state,'progress',progress,'deadline_at',deadline_at)) FROM deadlines;"
rows=json.loads(sql(q)); cleanup=runpy.run_path(str(OUT/'cleanup.py')); mapping=cleanup['owned']()
assert len(rows)==3 and all(r['id'] in mapping for r in rows)
ordinary=[r for r in rows if not r['id'].startswith('overdue-acceptance-')][0]
assert ordinary['completed']==0 and ordinary['estimated_hours']==10 and ordinary['remaining_hours']==10
adjusted=[r for r in rows if r['id']=='overdue-acceptance-final-0'][0]
assert adjusted['completed']==0 and adjusted['estimated_hours']==10 and adjusted['remaining_hours']==6 and adjusted['progress']==50
restored=[r for r in rows if r['id']=='overdue-acceptance-final-1'][0]
assert restored['completed']==0 and restored['estimated_hours']==10 and restored['remaining_state']=='unknown' and restored['progress']==50
assert sql('PRAGMA integrity_check;')=='ok'
(OUT/'release-domain-state.json').write_text(json.dumps({'screens_passed':True,'integrity':'ok','synthetic_records':rows},indent=2),encoding='utf-8')
print('PASS: final signed package creation, priority, continue, reschedule, complete/restore, stop, back and force-stop persistence.')
