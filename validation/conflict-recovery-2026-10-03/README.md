# 2026-10-03：用户冲突恢复验收证据

范围：本地 V7 协议识别出的普通内容冲突，明确用户选择与事务恢复。真实云交换保持关闭；没有真实华为账号、第二设备或 AGC 上传下载。数据库未卸载、重建或清空。

## 最终构建

- 新增恢复测试20项；保存的 [逐项结果](test-result.txt)：79/79，Failure 0 / Error 0。
- 该次测试成功29s614ms。此后仅修正德文代词，再次 [test](test.log) 成功28s111ms；该次临时测试输出随clean清除，前次同业务/测试代码的逐项结果保留。首次编译失败 [test-first.log](test-first.log) 也保留，不计为通过。
- 最终 [clean](clean.log) 成功1s730ms；完整 [assembleHap/SignHap](build.log) 成功31s462ms，无ArkTS/项目warning，仅SDK Unsafe环境警告。
- 最终 `entry-default-signed.hap` SHA-256：`1469E75FFA2E01D78EBA65F38D0924D94F9D33C075F810BEEBA9925583BBDC33`。最终包已覆盖安装，实际完成德文深色选择/成功返回、英文浅色详情与重启持久化、中文首页。
- [最终静态审计](final-static-audit.txt)：九套401键、56恢复文案，键/占位符一致、无重复/乱码；已有services/config除数据库服务、协议服务外与 [开始时哈希](before-hashes.json) 相同。CloudSync门禁false。

## 实际设备方法

Phone：`127.0.0.1:5555`，1320×2856。开始业务主项/任务0，V7、完整性ok、原事件54/归档55保留；开始状态见 [before-state](before-state.txt)。强停后主数据库备份保留于本机临时目录 `dayline-conflict-before/ddl.db`。原先没有WAL/SHM文件，不将可选文件读取失败当作备份成功。

[device-check.py](device-check.py) 将 [fixture.json](fixture.json) 中八组合成项目的合法事件注入设备真实 `ddl_sync_events`，由App冷启动完成归档/合并/投影；[ui-check.py](ui-check.py) 用HDC操作实际页面。没有Mock页面或跳过数据库恢复流程。

## 关键证据索引

| 场景 | 证据 |
| --- | --- |
| 多项目真正冲突；首页及详情中性提示、限制受影响编辑 | [首页](zh-light-home.jpeg)、[详情](zh-light-detail.jpeg)、[初始DB](conflicts-initial.txt) |
| 名称两个版本及本机旧值，无默认选择 | [中文选择](zh-final-title-options.jpeg)、[最终德文深色选择](signed-final-de-dark-options.jpeg) |
| 事务提交后立即可返回 | [中文成功](zh-final-stable-success.jpeg)、[最终包德文成功](signed-final-de-dark-success.jpeg) |
| 选择页打开后新数据到达，拒绝旧选择 | [错误反馈](zh-light-arrival-rejected.jpeg)；随后重新加载保存，完整截止三元组与新备注保留 |
| 剩余6与9，保留总10和原确认时间 | [选择](zh-final-hours-choices.jpeg)、[最终包重启英文详情](signed-final-en-detail.jpeg)、[最终SQL与重启](ui-finish-copy.log) |
| 同任务改名与完成；合成循环树 | [德文任务](de-dark-task-options.jpeg)、[整树](de-dark-tree-options.jpeg)、[运行日志](ui-tree.log) |
| 删除优先，无复活入口；取消与确认 | [英文主项删除](en-light-deleted-deadline.jpeg)、[英文任务删除](en-light-task-deletion.jpeg)、[已读后状态](ui-en.log) |
| 前后切换、取消、重启后仍待处理，跨字段选择 | [名称](zh-final-multi-name.jpeg)、[剩余量](zh-final-multi-hours.jpeg)、[取消](zh-final-multi-cancel.jpeg)、[最终详情](zh-final-multi-detail.jpeg) |
| ABORT，已插event但archive失败，整体回滚 | [失败反馈](zh-final-save-failure.jpeg)、[操作前](before-failure.txt)、[回滚后](after-failure.txt)，完整快照一致 |
| 原生慢事务中force-stop，不是仅在保存前杀进程 | [重启后](after-force-stop.txt) 与操作前完全一致；原事件/归档8/8，重试后9/9，无重复任务 |
| 重复原冲突与已解决后的旧事件重放 | [replay](replay-state.txt)、[独立备注与解决结果](final-review-and-independent-note.txt) |
| 恢复只明确名称，不误写独立备注 | [最终名称测试](final-name-fixture.json)、[SQL](final-review-and-independent-note.txt)：Checkpoint A/总10/剩余9/新备注、问题0、任务2/不同ID2、resolvedFields只有name |
| 缺祖先不可强制选择，补齐后恢复 | [保护说明](zh-final-waiting.jpeg)、[暂存](pending-held.txt)、[补齐](pending-resumed.txt) |
| 其他项目仍可完成任务 | [正常项目](en-light-unaffected-after.jpeg)、[运行日志](ui-unaffected.log) |
| 最终包中文首页与英文首页 | [中文](signed-final-zh-home.jpeg)、[英文](signed-final-en-home.jpeg) |

部分早期截图捕获到过渡帧或旧滚动位置，保留作为过程记录，不作为最终成功画面的证据。脚本中数次因旧项目名称或首页已滚到页底而找不到设置入口，属于定位假设；冷启动定位后继续验收，不冒充App写入失败。最终成功/错误定位与提交后可返回均已实际复测。

## 清理与边界

本轮只用观察全部当前历史头的合法永久墓碑清理八组合成业务项目。以前验收遗留的11项已删合成项目说明，经页面确认“知道了”，不删除原历史或墓碑。已读信息只是本机回执，不算未解决冲突；同一证据不会反复提示。

最终数据库核对见 [cleanup.txt](cleanup.txt)，最终跟随系统语言/主题与空首页见 [截图](final-empty-system-home.jpeg) / [运行日志](ui-restore-zh.log)。测试触发器全部移除，原历史、永久删除及已读信息保留。不是对用户数据库的清库迁移方案。

[重启后的最终计数](final-state.txt)：V7 / integrity_check=ok；Deadline、任务、提醒状态各0；未解决问题0；本机已读回执13（本轮2、既往合成项目11）；事件106、归档107；账号关联0，测试触发器0。归档比原表多1的差异在开始时54/55已存在，本轮未删除既有异常历史来凑数量。

已完成单Phone默认字号、简中/English/Deutsch、浅/深、选择/取消/返回/成功/失败/强停/重启抽查。不宣称九语言全设备、大字体、其他Phone尺寸或学生可用性测试通过。

仍需真实账号/双设备：两端同时解决、原生事件到达与恢复事务交错、旧客户端与新选择元数据版本边界。坏/永久缺项历史不能靠任意内容选择恢复。旧云导入、AGC实际交换、历史长期负载/压缩和既有提醒配额问题均未处理，云相关发布阻塞继续保留。详见[同步可靠性报告第10节](../../SYNC_RELIABILITY_REPORT.md)。
