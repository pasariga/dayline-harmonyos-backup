from pathlib import Path
import runpy,json
OUT=Path(__file__).parent;h=runpy.run_path(str(OUT/'harness.py'));u=h['u'];v=h['values']('zh_CN')
u['restart']();h['wait'](v['experience_now']);h['home']('zh_CN');h['tap'](v['experience_deadlines']);h['scroll']();h['scroll']();u['back']()
h['shot']('edge-list-back-fixed')
ns=u['nodes']();result={'home_header_visible':any(n.get('id')=='homeAddDeadline' for n in ns),
 'primary_action_visible':v['experience_now'] in u['texts']()}
assert all(result.values()),result
(OUT/'back-space-results.json').write_text(json.dumps(result,indent=2))
print('PASS: scrolled list -> Back -> Today starts at the primary action.',flush=True)
