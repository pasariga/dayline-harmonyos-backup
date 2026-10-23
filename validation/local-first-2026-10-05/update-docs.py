from pathlib import Path

root = Path(__file__).resolve().parents[2]
readme = root / 'README.md'
text = readme.read_text(encoding='utf-8')
text = text.replace('| 云能力 | 华为账号与 AppGallery Connect 云同步 |', '| 云能力 | 源码保留；V1.0 不开放账号登录与 App 云同步 |')
text = text.replace('当前已实现的主要能力：', 'V1.0 正式开放的主要能力：')
text = text.replace('- Deadline 新建、查看、编辑、删除和完成状态；', '- Deadline 新建、查看、编辑、删除、完成与恢复，以及逾期处理；')
text = text.replace('- 预计工作量、剩余工作量、风险分析和可解释的优先级；', '- 初始预计总工作量、主动确认的当前剩余工作量、风险分析和可解释的优先级；')
text = text.replace('- 自动倒排计划和基于最新状态的动态重排；\n- 截止提醒、通知策略、免打扰和权限引导；\n- 华为账号登录、云同步与本地优先使用；', '- 多 Deadline 共用每日容量、自动倒排计划和基于最新状态的动态重排；')
marker = '## 工程结构'
section = '''## V1.0 发布范围冻结（2026-10-05）

- **Local-first V1.0**：以上本地 Deadline、任务、工作量、风险、今日行动、容量、排期、逾期、设置、主题与多语言作为正式能力；UI/UX 冻结。
- **账号及 App 云同步不开放**：设置隐藏账号入口，原账号路由只说明暂未开放；首页不探测账号或自动同步，手动/自动同步与同步权限入口在原生调用之前退出。新增固定 `ReleaseScope.CLOUD_SYNC_AVAILABLE=false`，应用清单 `cloudStructuredDataSyncEnabled=false`。协议交换及 Shadow 读取门禁继续 false；旧实现、V8结构和历史数据保留，不能自行解除。
- **提醒是可选辅助，不承诺可靠后台定时送达**：保留底层和设置；新建、通知页及失败反馈说明系统权限/设备调度影响，提示在 App 核对截止日期。Calendar/Timer 1700002、真机后台送达/取消尚未验证；普通通知曾实际显示不等于定时提醒通过。商店卖点不列可靠后台提醒。
- **数据说明**：本版无账号登录或 App 云交换；本机记录可使用，系统备份可能按设备设置处理数据；通知可选，清除数据/卸载可能丢记录。设置可展开阅读，不能将这份功能说明当作正式法律政策。
- **权限**：保留 `PUBLISH_AGENT_REMINDER` 用于现有可选代理提醒；保留 `DISTRIBUTED_DATASYNC` 用于安全关闭历史云表注册（SDK 的关闭注册调用也要求此权限），当前不向用户发起同步授权。不新增敏感权限，不机械破坏历史数据库的关闭路径。
- **提交仍待本人补齐**：当前包内 `buildMode=release/debug=false`，但沿用的签名 Profile 为 **debug**，不宣称可直接上传；须提供与现有身份/包名匹配的 release Profile。`vendor=example` 需确认实际发布主体；正式公开隐私政策/用户协议入口仍未提供，不能编造主体、URL或法律条款。三项均待用户输入，本轮没有更换签名身份或替用户发布。
- 云及定时提醒 NO-GO 继续约束这些能力的开放；根据本次授权，它们不作为 Local-first V1.0 正式卖点。旧记录中的全功能 V1.0 阻塞结论属于当时范围，不能解释为真实云/定时送达已验收。

'''
assert section.splitlines()[0] not in text
text = text.replace(marker, section + marker, 1)
text = text.replace('│     ├─ CloudDiagnostic.ets', '│     ├─ ReleaseScope.ets          # V1.0固定产品范围，禁止账号/云入口\n│     ├─ CloudDiagnostic.ets', 1)
text = text.replace('- `pages/CloudAccount`', '- `pages/CloudAccount`（保留旧路由；V1.0只显示暂未开放）', 1)
status = '- **2026-10-05 Local-first V1.0 范围冻结（隔离与当前 Phone 本地回归完成，提交材料待补）**：隐藏账号入口并停止账号探测，原账号路由降为暂未开放；同步/权限在原生调用前退出、应用云能力声明关闭，真实云/Shadow门禁继续关闭。保留DB8/同步结构、云代码与通知实现，核心算法未改。九套资源修正数据/备份说明和提醒送达表述；公开异常日志93处及AppLogger仅输出数值诊断码。实际回归发现详情刚确认剩余量使用旧页面时钟的问题，已仅修正保存后的页面时钟并用最终包验证立即恢复风险/排期。最终230/230、四时区生产源码96/96、release隔离/日志检查通过；clean1s649ms、完整release assembleHap16s762ms/SignHap成功，最终包已安装并回归。原八表摘要保全，业务/任务/提醒0，原偏好恢复，DB8/integrity_check=ok。当前Profile仍debug、vendor仍example、正式隐私入口待本人提供，**不宣称AppGallery提交GO**。见[本轮冻结与验证记录](validation/local-first-2026-10-05/README.md)。\n'
text = text.replace('## 当前项目状态\n', '## 当前项目状态\n\n' + status, 1)
task = '''### 2026-10-05：Local-first V1.0 正式范围冻结

- 状态：产品隔离、代码修正、本地测试与当前Phone验收完成；停止本轮工作。签名Profile、发布主体和正式政策入口待本人补齐，未提交AppGallery。
- 修改：新增 `ReleaseScope.ets` 与 `ReleaseScope.test.ets`/List注册；调整 `CloudSyncService.ets`、`Settings.ets`、`Index.ets`、`CloudAccount.ets`、`NotificationSettings.ets`、`AppScope/app.json5` 的云能力声明和九套messages。`AppLogger.ets`以及10个页面/service的93处公开catch日志改为数值诊断码；其中数据库、旧Preferences迁移、本地化服务只改异常日志，未改事务/迁移/数据库结构。详情额外在确认剩余工时落库后刷新页面时钟，避免新确认比缓存时钟新而被误判过期；规则及336小时边界不变。
- 正式边界：Deadline全生命周期、多层任务、自动/手动进度、总量/剩余量、风险、今日行动、共享容量、排期、逾期、本地持久化、设置/主题/语言开放；账号/云不开放，可靠后台定时送达不承诺，底层保留。DB版本8、同步协议/表、账号底层/AGC、通知策略、工作量/风险/排期/时区算法、Bundle/SDK/签名身份未改。
- 验证：完整Hvigor test **230/230**（新增3项范围入口测试），test16s443ms；生产源码四区时间/容量 **96/96**，Kit/context代理实测同步入口I/O **0**且日志不含合成私密标记。九套资源键/占位符/旧品牌扫描通过；HAP内无验证/测试模块/私钥/构建凭据文件。clean **1s649ms**、完整 **release** assembleHap **16s762ms**，SignHap **1s431ms**，均BUILD SUCCESSFUL；保留未启用混淆提示及SDK Unsafe警告，没有为此扩改工程配置。
- 最终包：`entry/build/default/outputs/default/entry-default-signed.hap`，另复制 `release/Dayline-1.0.0-release-signed.hap`；SHA-256 **2BFCC95CAF44F97C078D881AFBB7F1608887669D9D575591D36DAF1A051A8EE6**。包内release/debug=false/cloud=false，但签名Profile仍debug，不能将文件名或SignHap成功当作正式分发签名。已使用此次最终包覆盖安装，而非旧包。
- Phone：空库覆盖安装（未卸载/擦历史）→创建10小时未来项目→编辑/自动2叶任务→完成1项保持1/2与工时未知→保存6小时→强停重启保留→新包保存9小时立即恢复风险/计划→完成/恢复→改历史日期/逾期/继续→调回未来日期→手动25%保存→删除→强停重启空首页；云关闭没有阻断本地使用。设置无账号入口，中英、浅深及跟随系统实际切换，通知权限保持关闭且提示清楚；数据说明可展开阅读。首次创建与自动切换阶段在时钟修正前的本轮包运行，后续强停持久化、确认、排期、生命周期、语言主题和删除在最终重建包复验；中间准备失败和错误状态证据保留，不冒充运行通过。
- 清理：唯一验收Deadline及2任务通过应用删除；业务/任务/提醒/owner/暂存0，触发器0，DB8/integrity_check=ok。原349事件/245归档/13问题摘要保留，现361/257/13，增加12条合法操作/永久删除历史不擦除；通知活动与逾期测试选择清理，主题/语言/容量及原通知偏好恢复，未修改设备时区或时间。
- 未验证/提交阻塞：真实Account Kit/AGC、双设备、生产云旧注册覆盖升级和真实定时后台送达继续未验；本轮没有重跑真机DST/系统时区事件。当前正式签名Profile、发布主体example替换、正式公开政策/协议入口待本人提供。已请求信息且未收到，未擅自换身份或编造法律内容。没有已确认未修复的新增本地业务回归。

'''
text = text.replace('## 最近一次任务记录\n', '## 最近一次任务记录\n\n' + task, 1)
changes = '''### 2026-10-05：V1.0产品范围隔离与发布表述

- 固定Local-first范围：隐藏正式账号入口、旧路由说明未开放、同步与权限入口在I/O前短路、应用云能力声明关闭；保留DB8/云协议和旧实现。
- 九套文案明确本机保存、系统备份边界与可选通知限制，设置支持阅读完整数据说明；不新增法律条款或保证真实云/后台提醒可靠。
- 公共错误日志收敛为数值诊断码；只更新详情保存剩余估计后的时钟，修复新确认被旧页面时钟误判过期，不改工作量算法。
- 全套230/230、生产时间/容量96/96、clean/release完整assembleHap/SignHap及最终signed Phone回归通过；清理验收数据并保留原历史。当前debug Profile/example主体/正式政策入口仍阻塞实际提交，尚未发布。

'''
text = text.replace('## 变更记录\n', '## 变更记录\n\n' + changes, 1)
readme.write_text(text, encoding='utf-8')

report = root / 'SYNC_RELIABILITY_REPORT.md'
text = report.read_text(encoding='utf-8')
old = '更新日期：2026-10-04。状态：**部分完成；V8本地/Shadow验证完成，真实AGC读取未验收，实际云交换暂停，Canary双向NO-GO，仍阻塞 V1.0 发布**。'
assert old in text
text = text.replace(old, '更新日期：2026-10-05。状态：**云验证仍部分完成，真实AGC读取/交换/Canary继续NO-GO；按本次用户授权，Local-first V1.0 不开放账号/云能力。签名和正式发布材料待补，不宣称上架GO**。', 1)
text += '''
## 15. 2026-10-05：Local-first V1.0 发布范围冻结

- 用户明确暂停真实账号/AGC验证，云不作为本版正式能力；第1–14节证据和未完成门禁全部保留，不能解释为真实云已通过。协议、DB8、表/事件/迁移格式不变，也不清理事件历史。
- `ReleaseScope.CLOUD_SYNC_AVAILABLE=false`：设置隐藏账号目录、原路由仅说明未开放；首页不加载账号/自动交换；同步及权限服务先拒绝再进入任何原生/账户/偏好读写。`cloudStructuredDataSyncEnabled=false`，原协议交换与Shadow读取门禁继续false。
- 两项权限保留原声明：代理提醒仍可选；同步权限仅因关闭历史注册的SDK调用仍需要，不在V1.0用户路径申请。历史已云注册库的真实覆盖升级仍未验，本轮没有模拟生产注册或执行网络请求。
- 定向230/230、实际生产源码隔离检查I/O0、96项时间/容量检查与最终Phone本地流程通过；本地数据、总量/剩余量/进度/逾期语义保留。日志仅诊断码，不在报告记录账号/私密内容。
- 最终release模式signed HAP已构建安装，Profile仍debug；发布主体与正式政策入口待本人补齐。此轮完成产品隔离，不等同AGC/双设备/后台定时送达或AppGallery提交验收。详细结果见[本轮记录](validation/local-first-2026-10-05/README.md)。
'''
report.write_text(text, encoding='utf-8')
print('README state, latest task, changelog and sync release-scope boundary updated.')
