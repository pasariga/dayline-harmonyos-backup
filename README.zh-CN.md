[English](README.md) | [简体中文](README.zh-CN.md)

# Dayline

面向学生的 HarmonyOS 本地优先 Deadline 规划应用。它把任务拆解、完成进度、主动确认的剩余工作量与共享每日容量联系起来，帮助回答：**今天应该先做什么？**

本仓库是既有 ArkTS／ArkUI 应用的源码备份，内部代号 DDL，不是 AppGallery 发行版或完整签名分发包。最新源码备份提交早于本次纯文档整理，不能据此承诺持续维护。

## 产品流程

用名称和截止日期新建 Deadline，按需补充任务和工时，执行推荐的下一步行动，情况变化时重新确认剩余工作量。风险和倒排计划依赖现有输入计算，不把任务完成百分比直接当作已完成工时。

已有本地功能包括多层任务、手动／自动进度、逾期处理、撤销与草稿保护、多 Deadline 共享容量、本地关系型存储、外观设置和多语言资源。界面区分今天／Deadlines，以及详情中的行动／工作量与计划两个工作面。

## 仓库保留的工程改进

| 范围 | 实现与既有资料 |
| --- | --- |
| 工作量与排期 | 当前剩余工作量独立于初始估计和任务进度，未知／过期估计明确降级，多 Deadline 共用每日容量；见 `DeadlineInsightService`、`DeadlineScheduleService`、`TodayActionService`。 |
| 持久化 | `entry/src/main/ets/services/` 保留关系型存储、迁移、事务更新和历史冲突处理。 |
| 时间语义 | `DeadlineTime.ets` 和时间边界资料区分固定时刻与自然日，并覆盖时区和夏令时情形。 |
| 交互 | 既有体验重构重新组织行动与解释；草稿保留、撤销、小屏／大字号和无障碍标签有对应记录。 |
| 云能力边界 | `ReleaseScope.ets` 固定 `CLOUD_SYNC_AVAILABLE=false`；保留历史同步与冲突代码，但当前本地优先范围不开放账号登录和真实 App 云交换。 |

以上均可对应源码。历史验证结果作为带日期的资料保留，不表述为本轮重新运行的测试。

## 当前限制

- 通知属于可选辅助，**尚未建立可靠后台定时送达／取消的验证结论**；历史 Calendar／Timer `1700002` 问题及设备验收限制仍保留。
- 当前范围不开放账号与云同步；存在协议和 AGC 集成源码不代表云服务已就绪。
- 原项目记录明确列出商店提交前的 release Profile、发布主体和正式政策入口要求，本次不宣称已上架或生成新签名包。

## 阅读与构建

从 `entry/src/main/ets/pages/` 开始，再查看 `models/Deadline.ets` 和各业务服务。记录中的环境是 DevEco Studio、HarmonyOS 6.1.1／API 24、Stage 模型、Phone 目标。

请在匹配的 DevEco Studio 环境打开工程。备份含模块配置与 Hvigor 文件，但没有根目录 `build-profile.json5` 和私有签名材料；尝试签名构建前，应提供自己合法持有的工程／产品配置，不复制他人的签名凭据。本轮文档任务没有验证全新克隆构建。

- [历史项目与开发记录](docs/PROJECT-HISTORY.zh-CN.md)
- [云配置边界](CLOUD_SYNC_SETUP.md)与[同步可靠性记录](SYNC_RELIABILITY_REPORT.md)
- [体验重构](validation/experience-2026-10-18/README.md)、[布局与无障碍加固](validation/hardening-2026-10-19/README.md)、[时间语义](validation/time-boundaries-2026-10-05/README.md)

较长的实现历史独立保留，首页只呈现当前定位。记录中的设备／模拟器观察只适用于当时明确的条件，不代表广泛兼容性或当前服务保证。

## 许可与署名

源码的应用名称为 Dayline，Bundle 为 `com.gary.ddl`。快照中没有仓库级许可证文件，本 README 不新增授权，也不替第三方材料确认再分发权利。既有作者和历史保留，发布主体和发行授权仍由所有者确认。
