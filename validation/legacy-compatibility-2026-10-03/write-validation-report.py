from pathlib import Path
import json,hashlib
OUT=Path('validation/legacy-compatibility-2026-10-03')
counts=(OUT/'after-native-counts.txt').read_text(encoding='utf-8').strip().splitlines()
assert counts[:5]==['8','ok','0','0','0'] and counts[7:]==['0','13','0','0','0'],counts
hap=Path('entry/build/default/outputs/default/entry-default-signed.hap');digest=hashlib.sha256(hap.read_bytes()).hexdigest().upper()
report=f'''# 旧云兼容验证：2026-10-03开始，2026-10-04收尾

## 结论和证据边界

本地协议/导入处理器和单Phone真实RDB验证完成；**正式旧云兼容仍部分完成，真实云保持暂停，尚有发布阻塞**。本轮没有AGC请求、后台变更、真实华为账号、第二台设备或旧客户端联网实验。`FrozenLegacyRead` 的可信来源由本地测试夹具模拟，不能据此声明线上冻结、分页完整或账号授权通过。

数据库仍为原ddl.db/relationalStore；7→8只增本地暂存表，不替换数据库、不重建业务表。业务模型V7、云最低协议2、数据库8必须分别理解。受保护Bundle/SDK/签名/AGC及核心算法/工作量/账号/云/通知服务哈希不变；仅原DB/协议/冲突恢复三服务变化，另增三个限定服务。见 changed-existing-services-configs.json。

## 定向测试、构建与最终包

| 步骤 | 本轮实际结果 |
| --- | --- |
| 22项新增 + 原79项 | **101/101**；test-result.txt保留逐项结果 |
| 最终test --no-daemon | BUILD SUCCESSFUL in35s612ms |
| clean --no-daemon | BUILD SUCCESSFUL in2s447ms |
| 完整debug assembleHap | BUILD SUCCESSFUL in38s615ms，含SignHap |
| 最终signed HAP | SHA-256 `{digest}`；已覆盖安装 |
| 资源 | 9套messages各403键，无重复、新文案键/占位符一致 |

测试/构建使用README中的DevEco Node/Hvigor；最终构建前已保存实际underscore路径test_result.txt，最终包之后未再执行可能重生HAP的test任务。只有SDK Unsafe警告，无ArkTS/项目warning。第一次编译中的import位置/类型错误和异常处理warning已修正，不计通过。中间SQL传输/脚本字段顺序/大小写定位失败属于验收脚本，修正后按真实最终数据库核对；不把失败记录当作App验收通过。

## 实际Phone运行

Pura90，API24，1320×2856，hdc127.0.0.1:5555。使用现有实例coldboot保留数据，未reset/卸载。10月4日继续时Phone不在线，再启动同一实例并验证数据持久化。模拟器/uitest偶发空布局及等待故障不作为应用数据回归结论；冷启动等实际首页就绪后再操作，最终签名包重新检查。

| 要求场景 | 真实本地RDB / 页面结果与证据 |
| --- | --- |
| 7→8覆盖安装 | 原业务、107归档、13ACK、owner0及106原事件逐字不变；新增105传输封装，再启动不增长；native-db7-to8 / native-migration-repeat |
| 纯旧记录及多层树 | 3节点、2叶子完成1个、进度50、总10、剩余unknown；native-fresh-tree-unknown |
| 同ID本机有新字段 | 本机总10、confirmed6、数量进度50保留，无冲突；native-local-confirmed-preserved |
| 名称/日期/完整树同时不同 | 原本机完整投影保留；页面三个步骤、不预选、取消后仍完整；再选择本机三项保存成功，重启总10/剩余6/3唯一任务/无锁；zh-choice-*及final-package-idempotency-and-choice |
| 本机已删除、旧云仍活 | 业务/任务0，不新增legacy事件，deleted回执；native-deleted-not-restored |
| 已删除父任务旧子孙 | 分支0，无孤儿/复活；native-deleted-parent-descendants |
| 同任务重复/版本不同 | 相同版本折叠为3唯一任务；不同版本隔离，不猜最后版本；native-duplicate-collapse / native-bad-rows-isolated |
| 坏格式、缺ID/父、独立好记录 | 坏项目隔离，好项目仍恢复，App可启动；native-bad-rows-isolated |
| 来源B vs关联A、旧写未停、历史未完整 | 三种均waiting，无业务/事件投影；native-auth-writer-history-barriers；不是AccountKit真账号测试 |
| 导入1/2/10次 | 一个稳定基线/归档/回执，三唯一任务，规范载荷相同；native-ten-imports |
| 冻结后旧源变了 | 隔离变化来源，原名称/基线不变；native-source-mutation-isolated |
| 回执前SQLite ABORT | event/archive/业务/树均0、batch retry；移除触发器后各一份；native-import-rollback* |
| 原生写事务中强停 | 通过SQLite写锁确认事务已开始；强停后业务/树/事件/归档/回执全部0、batch staged；重试各一份；native-force-stop-* |
| 早期协议1新修改 | 本机名称保留、upgrade隔离、只1原归档；native-older-client-held |
| 新设备收到协议2封装历史父 + 后续子 | 子先到为pending；父后到恢复新名称和6小时，原父ID保留、2归档，封装不入归档，重启稳定；native-carrier-* |
| 没有工时依据的页面 | zh/en-restored-detail：任务1/2，工时待确认、风险降级，仍推荐Practice exam；不按数量折工时 |
| 升级保护、返回/稍后、账号安全说明 | 中英德实际截图，无伪安全保存按钮；de-dark-upgrade / en-light-upgrade / final-signed-upgrade |
| 旧资料单独待导入提示 | 无其他冲突后账号页显示简短本机安全/旧资料说明；zh-old-data-pending |
| 最终包持久化/重复 | final-package-*、final-signed-*；处理过的冲突不重新出现，估计6/总10不变 |

实际查看首页、详情、选择步骤、成功、未登录账号状态；简中/English/Deutsch以及浅/深抽查，截图为真实设备输出而非生成图。已有整树选择的“仅保留选中列表”解释沿用，没有改UI风格。其余六资源套只做资源检查，不冒充设备验收。没有验证真实通知触发，原Reminder配额限制仍在。

## 收尾

只对本轮明确compat-*项目写观察当前全部可信历史头的合法永久墓碑，不清除任何原事件/归档或删除事实。仅删除本轮测试暂存/回执、测试触发器及开始时没有的模拟owner。原不可变事件/归档/ACK全部再次逐字校验，语言/主题恢复系统设置。fixture-state-before-cleanup.json保留合成数据/批次诊断，after-native-state.json保留收尾事实。

| 最终状态 | 实际数值 |
| --- | --- |
| DB版本/完整性 | {counts[0]} / {counts[1]} |
| Deadline / 任务 / 提醒状态 | {counts[2]} / {counts[3]} / {counts[4]} |
| 交换行 / 归档 | {counts[5]} / {counts[6]} |
| 未处理问题 / 原ACK | {counts[7]} / {counts[8]} |
| owner / 暂存 / 测试触发器 | {counts[9]} / {counts[10]} / {counts[11]} |

交换行含历史封装/被拒绝测试输入，归档保留原既有差异，计数不必相等；没有为了数字一致清除历史。最终空首页截图和HAP哈希单独复核。

## 仍然阻塞的线上条件

1. 实际隔离旧云读取器、可信冻结来源/跨表完整清单/分页一致性、完整V7历史和墓碑恢复尚未实现并实测。
2. 服务器拒绝旧业务客户端写入及最低协议2通道尚未证明。新端过滤不能约束已发布旧端；若AGC能力无法提供可靠边界继续暂停。
3. 真实Huawei账号A/B切换、双设备、原设备离线未上传删除、新安装/备份恢复及AGC载荷/配额尚需真实验收。旧时代完全缺失的删除历史与混合账号来源不能自动猜测。

本地被测流程未发现未修复的数据回归；不能宣称真实云无回归。长期历史容量留到后续专项，完成本轮后停止。
'''
(OUT/'README.md').write_text(report,encoding='utf-8')
(OUT/'final-package.json').write_text(json.dumps({'sha256':digest,'bytes':hap.stat().st_size,'cloudExchangeEnabled':False,'databaseVersion':8,'cloudProtocol':2,'testsPassed':101},indent=2),encoding='utf-8')
print('Validation report written; final immutable original data verified')
