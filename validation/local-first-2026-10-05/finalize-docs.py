from pathlib import Path
import json, hashlib
OUT = Path(__file__).parent
root = OUT.resolve().parents[1]
cleanup = json.loads((OUT/'cleanup.json').read_text())
counts = cleanup['counts_after']
hap = root/'entry/build/default/outputs/default/entry-default-signed.hap'
digest = hashlib.sha256(hap.read_bytes()).hexdigest().upper()
assert digest == '119A39512687E47601F349F73A0E40931E86D6CA00CCCBCC7663380BE0B76020'
assert hashlib.sha256((root/'release/Dayline-1.0.0-release-signed.hap').read_bytes()).hexdigest().upper() == digest
assert 'PASS: last signed HAP' in (OUT/'final-smoke.log').read_text(encoding='utf-16')

p = root/'README.md'
s = p.read_text(encoding='utf-8')
start = s.index('- Phone：空库覆盖安装（未卸载/擦历史）')
end = s.index('\n- 清理：', start)
s = s[:start] + '''- Phone：最终119A…包实际运行 `final-smoke.py` 并断言通过：空首页→UI创建10小时未来自动项目与2叶任务→完成1项显示1/2/工时待确认→确认6小时立即恢复风险/计划→完成/恢复→改过去日期/逾期待处理/继续无完工预测→改回未来/手动25%保存→强停重启保留→删除。设置无账号入口，中英、浅深/跟随系统实际切换，最终包再次抽查英文深色的目录/数据说明并恢复系统值；通知权限保持关闭且提示清楚。原生账号/同步与通知送达未验，未宣称全新卸载或重复全量多Deadline/任务树Phone矩阵。第一遍 `final-*` 同时包含6→9小时、旧页面时钟误判及修复后的证据，最后构建核心回归见 `last-*`；准备/编译/审计失败证据保留，不计为通过。''' + s[end:]
s = s.replace('唯一验收Deadline及2任务通过应用删除', '两条验收Deadline及各2任务通过应用删除')
s = s.replace('现361/257/13，增加12条', f"现{counts['ddl_sync_events']}/{counts['ddl_sync_archive']}/13，增加21条")
p.write_text(s, encoding='utf-8')

p = OUT/'README.md'
s = p.read_text(encoding='utf-8')
s = s.replace('最终八表摘要保全、DB8/integrity_check=ok、触发器0',
              '最终八表摘要保全、DB8/integrity_check=ok、触发器0；原事件349/归档245/问题13保留，现370/266/13（本轮21条合法操作/永久删除历史）')
p.write_text(s, encoding='utf-8')
(OUT/'final-artifact.json').write_text(json.dumps({'sha256':digest,'build_mode':'release',
    'debug':False,'cloud_capability':False,'signing_profile_type':'debug',
    'local_phone_core_smoke':'PASS','owner_release_inputs_pending':True,
    'post_build_production_source_changes':False},indent=2))
print('Final package, last-device regression and preserved-data evidence recorded.')
