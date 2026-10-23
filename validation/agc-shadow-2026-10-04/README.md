# AGC 只读适配与 Shadow Validation — 2026-10-04

## 结论

**NO-GO：不能进入真实账号 + 隔离 Canary Write + 双设备交换。** 本轮完成本地 Shadow 引擎、原生隔离接收库候选实现、账号/同步日志边界修正和 Phone 本地验证。没有取得真实 AGC 数据，也没有把模拟来源证明作为真实服务端证明。

`CloudSyncService.EVENT_PROTOCOL_VALIDATED=false`；`AgcShadowReadAdapter.AGC_READ_ISOLATION_VERIFIED=false`。两个入口继续关闭。新读取候选未注册到页面、启动或普通同步流程；本轮无 AGC 上传、下载、后台配置变更、正式导入或历史压缩。DB 仍为 V8，主库表/列不变。

## 实际接口与能力

工程实际接入 Account Kit + ArkData `relationalStore` 的 `DISTRIBUTED_CLOUD` / `cloudSync`。历史业务同步使用 `SYNC_MODE_TIME_FIRST`，当前普通网络分支关闭。不是 Cloud Foundation Kit 的 Cloud DB `DatabaseZone.query`；后者是另一套对象类型/数据库区域/认证及权限接入，工程没有该接入，不能把其查询能力算成本项目现有能力。

当前 SDK `@ohos.data.relationalStore.d.ts` 中 `SYNC_MODE_CLOUD_FIRST` 是云到本地，`SYNC_MODE_PULL` 是设备到设备。本轮候选只准备 CLOUD_FIRST、显式三表、autoSync=false，要求完成回调、每表下载无失败和上传计数为0；不会使用 TIME_FIRST / NATIVE_FIRST。但只有本地文件路径隔离得到实证，**相同 ddl.db 名称的云注册是否共享、是否准确映射原 ddl 容器仍未知**。事后检查上传计数不能代替事前的真实只读/隔离证明，因此网络门禁不解除。

候选接收库使用 `customDir=agc-inspection/<随机目录>`、加密、allowRebuild=false、autoCleanDirtyData=false；在建表前检查 PRAGMA database_list 的实际路径。没有取得主业务 RdbStore，没有调用迁移、暂存、业务投影、账号绑定或提醒入口。库内部本地查询及200行缓冲分页不是服务端冻结分页。原生下载状态也没有提供来源 OpenID、跨表修订、完整删除覆盖或独立任务清单。

### 字段清单的证据等级

| 数据 | 当前可确认的映射 | 仍未确认 |
| --- | --- | --- |
| 旧 deadlines | CLOUD_SYNC_SETUP 第3节的16列；保留 SQL NULL；缺V6字段剩余量未知；estimated_hours为初始总量 | 后台实际记录类型、字段是否已全部配置、可空/加密/权限/环境及真实样本 |
| 旧 deadline_subtasks | id/deadline_id/title/completed/created_at/parent_id/sort_order | 实际完整任务清单、分页/过滤及跨表冻结 |
| ddl_sync_events | id、deadline_id、payload；最低传输协议2；可信旧历史封装保留原字节/因果身份 | 后台是否建表、字符串上限/加密/配额/开发生产隔离及旧写拒绝 |

客户端读写能力来自已注册本地表及原生同步接口，不是远程字段投影查询接口。历史客户端可写旧两业务表；未来新版只应交换事件表完整聚合载荷。**本轮没有证明后台真实表或写权限存在**，也没有实际写云。

本地 SDK 与源码是当前接入证据。辅助原始资料：[ArkData 同步枚举](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkdata/arkts-apis-data-relationalStore-e.md)、[StoreConfig](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkdata/arkts-apis-data-relationalStore-i.md)、[关系库同步说明](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/database/data-sync-of-rdb-store.md)、[Cloud Foundation 初始化](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/cloudfoundation-database-initialize-V13)。公开文档不是本项目后台权限/容器已验证的证据。

## Shadow 行为与输出

`AgcShadowInspection` 的检查输入和 `FrozenLegacyRead` 明确分离。先收齐数据、逐动作核验当前身份、检查页/游标/来源/结束状态和最终来源一致性，再仅在副本上规范化与比较。超时、取消、认证丢失、账号切换、缺页/重复游标、来源变化和异常载荷不会交付半成品。重试从头读取，不复用中断游标。

分析不持有任何业务数据库/绑定/导入写入能力。现有兼容映射器仅用于模拟；从已观测任务推导的清单不能成为独立完整性证明。摘要只包含固定分类、阻塞原因和匿名数量；所有结果 `importAllowed=false`，包括有完整模拟证明的夹具。

| 模拟情形 | 结果 |
| --- | --- |
| 合成完整冻结旧行，无本机记录 | baseline_candidate；仅模拟，不导入 |
| 缺剩余字段、已有本机确认6小时 | local_equal；不清除本机事实 |
| 完整父历史证明本机/云端因果更新 | local_newer / cloud_newer；不比较时钟 |
| 不同字段并发 / 同字段名称或6对9小时 | safe_merge / conflict_confirmation |
| 同次扫描旧业务行与较新事件矛盾 | conflict_confirmation；不被“较新”标签掩盖 |
| 已导入基线同ID载荷改变 | cannot_decide；不偷偷接受新来源 |
| 本机墓碑 + 云旧活行 | local_tombstone；不复活 |
| 完整合法云删除事件 | cloud_deleted；仍只是模拟判断 |
| 云本次未返回本机行 | cannot_decide；绝不据此删除 |
| 缺父/循环/空历史无删除覆盖 | history_insufficient 或 cannot_decide |
| 缺任务父项、孤儿/跨项目任务 | incomplete_cloud |
| 异常JSON、同ID不同载荷、未知旧协议 | malformed_cloud / history_insufficient；不取最后一行 |
| 当前B、来源A或本机owner为另一账号 | account_mismatch |
| 原生来源未证明账号/冻结/删除/任务清单 | 保留 source_account_unattested、source_not_frozen、deletion_history_unattested、task_manifest_unattested 阻塞 |

实际旧云样本为**未取得**，不是数量为0。真实 Deadline/任务数量、空值模式、重复ID、孤儿、字段缺失和本机重叠均未知；不能宣称模拟数据与真实数据一致。

## 删除、旧客户端和账号边界

“当前仍有行”只能说明此次观察看到了该行；“没看到”可能是分页/过滤/认证/其他账号/断线或删除。只有完整合法永久删除历史才支持删除语义；下载成功或空事件表不证明原设备的删除均已上传。旧协议从未保存/上传且原设备也不再保留的删除信息不可凭空恢复。继续保留或要求确认，不能推断删除。

最低协议2过滤、客户端门禁和账号校验不能阻止已发布旧二进制继续写原云空间。本项目当前 ArkData 客户端 API 没有可以部署的服务器版本谓词；本轮没有取得后台管理权限/配置证据，因此**服务端旧写拒绝未落实，也不能断言整个 AGC 平台绝对没有相关能力**。后台实际能力仍需提供方/控制台核实。

V1.0 最小安全策略：保持正式交换暂停，保留原云和原设备；先拿到可执行并实证的旧写冻结/服务端拒写方案。如果原通道做不到，应先由提供方证明隔离新版通道的权限和容器边界，再在明确测试账号/环境验证，旧云只作保守恢复来源。此处是后续条件清单，不是本轮创建新容器或上线新云功能。仅要求用户升级不足以成为服务器保证。

真实 Account Kit 当前身份探测结果为 unavailable，只记录可用性枚举，没有持久化身份/绑定库。读取候选拒绝用Preferences旧OpenID替代当前认证；收集与分析检查来源/当前账号/本机owner。原生 SDK行来源仍未获认证证明，因此真实A/B账号边界没有验收通过。

## 云与本机数据边界

- 未来云通道：完整核心业务聚合、任务树、截止/剩余三元组、普通操作/明确恢复的新版本、必要父关系、永久Deadline/任务删除信息；传输表仅 id/deadline_id/payload。可信历史封装按已有协议交换，不机械同步全部本地表。
- 本机：业务投影、ddl_sync_archive、ddl_sync_issues、ddl_sync_owner、ddl_legacy_imports、账号会话/Token、系统reminderId/提醒调度签名、主题语言/设备配置、测试/调试资料、inspection数据库与Shadow报告。
- 剩余估计不按数量进度计算；旧缺字段不制造0或剩余小时。提醒设置属于业务聚合，系统提醒ID仍只留本机。

## 日志修正

账号页曾直接输出错误对象/JSON；账号服务包装错误拼接原SDK错误；通用 AppLogger.error 会打印原错误消息/栈。SDK异常可能带凭据或内容，本轮没有以真实凭据证明泄露，但存在明确输出路径。

仅账号/同步相关调用切换到 `AppLogger.cloudError`，固定上下文+有界数值错误码，不输出对象、message、stack。账号包装错误改固定描述。摘要不输出ID/来源账号/用户内容/任意输入字段名；验证文件仅匿名计数/摘要，测试中的secret是合成哨兵。没有修改全App其他日志规则，也不保证系统SDK自身日志已完成全量审计。

## 实际验证

### 定向测试

- 新增29项，总 **152/152**；`test-final.log` 与 clean前复制的 `test-result.txt`，Tests run152 / Failure0 / Error0 / Pass152，31s440ms。
- 覆盖 raw→规范输入、NULL/缺字段、不同字段/同字段、6/9原子语义、因果新旧与旧行矛盾、已导入源变化、墓碑、缺历史/父树、协议1/2、重复数据/游标、账号切换失效、终态冻结、异常载荷、失败重试、取消/超时、20次幂等/重建和匿名日志。
- 收尾修正匿名重复统计漏计事件行的问题，在原重复用例增加事件重复断言；不改变合并结果。152项、最终12项原生、实际在途强停和clean/完整签名构建均重新执行。修正前日志以before-statistics-fix后缀保留，不冒充最终结果。
- 首次类型编译失败及第二次2条失败断言的日志保留。NULL与缺字段计数断言修正；错误码边界调整到SDK有符号32位整数范围。不能把当时BUILD SUCCESSFUL当成测试全通过；最终报告才是152/152。

### Phone 原生与中断

- 设备 `127.0.0.1:5555` 在线，原库覆盖安装；最终原生包 `native-build-final.log` 含SignHap，24s698ms。
- 原生测试包另有一条start_window_background同名资源警告；12项仍通过。最终主包clean后没有此资源警告，仅SDK Unsafe警告。没有为消除测试包警告修改业务资源或UI。
- **12/12**：之前独立模块旧协调5项+基础1项，新Shadow原生6项。新测试在独立 `entry/rdb/shadow-native.db` 和加密 customDir 接收库，旧协调在 entry_test 模块库；均不与原 `entry/rdb/ddl.db` 混用。
- 实际ResultSet保持总量10/剩余NULL；接收库路径物理隔离、下载门禁阻挡；失败后源行保留且可重试；20次扫描和重新打开摘要一致；Account Kit可用性探测未绑库，结果unavailable。
- `force-stop-shadow.py` 仅在独立合成源控制表准备暂停；收完历史及Deadline部分、读取任务页前产生**本次新** SHADOW_PAUSE_READY，再真实强停App。源行未变，未提交部分结果。重开后主八表摘要与before完全一致、PRAGMA user_version=8/integrity_check=ok。
- 最初主机中断脚本误指entry_test中不存在的辅助库，产生0字节文件后失败；已核对路径并只删除该0字节文件。此失败不是实际中断通过。可信中断证据仅 `identity-and-pause.txt`、`force-stop-result.txt`、`main-after-force-stop-verified.json`；旧 `main-after-force-stop.json` 只作早期保全检查，不计为在途扫描验证。
- 合成源、7个接收目录共28个空库文件（两次清理）、3个辅助源文件按检查后的精确路径清理；只卸载entry_test模块。没有卸载主App或删除ddl.db/历史。平台管理的加密密钥不自行修改。

### 主库、构建与最终安装

- `main-before.json` → `main-after-native.json` → `main-after-force-stop-verified.json` → `main-final.json`：八表逐行规范内容SHA一致（报告只保留摘要，无原内容）。业务/任务/提醒0行，事件251、归档147、问题13、owner0、暂存0；原历史及ACK全部保留。基线业务为空，不能把此结果声称为真实大量活数据/真实云回归。
- 最终clean **1s694ms**；完整debug assembleHap **29s939ms**，含SignHap，BUILD SUCCESSFUL。无ArkTS/项目warning，仅SDK Unsafe环境警告。
- 最终signed HAP 2,392,971字节，SHA-256 `DA1B58BB22300AC204120175EB7A7D76C6C4C65D7C34954E130D7274EAE6E179`；覆盖安装、强停/重开及主库检查通过。最终HAP之后未运行测试打包覆盖产物。
- 对39个原有源码/配置路径核对SHA；变化仅CloudAccount页日志、CloudAccountService固定错误描述、CloudSyncService日志和AppLogger。数据库/因果协议/兼容读取器/工作量/风险/排期/通知、Bundle/SDK/签名/AGC配置均未变，见 `protected-hashes-result.json`。

## 未满足的决策门

1. 可用真实账号 + 原AGC后台实际schema/权限/环境；本轮没有真实读取。
2. 正确云容器/账号映射和独立接收库**云注册隔离**实证；文件分离不等于云注册隔离。
3. 服务端或其他可验证可信来源的账号归属、跨表冻结、独立任务清单、完整删除历史覆盖；旧未记录删除的不可恢复边界需要明确处置。
4. 可执行旧客户端拒写/冻结策略及实际旧二进制拒绝测试；客户端门禁不替代服务器保证。
5. 真实样本字段/空值/大小/加密/配额、读取失败/账号切换、备份/新设备与双设备验证。

本地定向范围未发现未修复回归；真实云范围未知。**不批准下一阶段真实Canary双向交换，完成本轮后停止。**
