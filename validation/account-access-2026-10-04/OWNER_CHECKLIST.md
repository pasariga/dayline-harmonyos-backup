# AGC 人工只读核对清单

日期：2026-10-04。**所有后台项均为 Needs Owner Verification**；本轮未访问后台。核对不是开通、改结构或启用交换的授权。不要上传、修改或删除原云记录，不发送账号、凭据或个人内容。

## 最短核对顺序

1. 先在当前 Phone 自行完成真实华为账号登录与 App 授权。若界面只支持模拟返回或拒绝登录，换 HarmonyOS 真机，保留原模拟器数据。
2. 在 AGC 选择现有 HarmonyOS 应用，确认团队、Bundle Name `com.gary.ddl`、应用级 App ID / Client ID；确认 DevEco 关联的是这一个注册应用。工程 manifests 未显式填写 `client_id` / `app_id`；Profile 存在 app-identifier，不能据此认定它就是正确 AGC App ID。不要把项目 Client ID、账号 OpenID、bundle signatureInfo.appId 与应用 Client ID 混用。
3. 核对 Account Kit 开放能力及当前登录权限、应用状态、账号区域限制；确认所选应用登记的当前调试证书指纹。
4. 核对以下数据服务及只读权限。全部清楚后，再审查独立接收库云注册是否准确映射原容器、是否会影响主库，以及只下载不上传的保证；不能仅翻转读取门禁试运行。

## 后台核对表

| 项目 | 源码/本地已知 | 必须人工确认的实际后台事实 | 状态 |
| --- | --- | --- | --- |
| 应用与团队 | HarmonyOS Phone、com.gary.ddl | 正确团队下的现有应用，无重名或误关联 | Needs Owner Verification |
| 应用身份 | Profile 有 app-identifier；未记录其值；无显式 app_id/client_id metadata | 应用级 App ID/Client ID 与实际签名关联；不是项目级 ID | Needs Owner Verification |
| 签名 | debug Profile，包名/安装证书/Profile 一致 | AGC 当前应用已登记 SHA-256 `DB117D9648FD290A59C00460924E9812DD04792A688A6B817B6717B60457D990`；Profile 关联此应用且设备在允许列表 | Needs Owner Verification |
| Account Kit | SDK Auth Syscap=true，静默请求返回未登录 | 开放能力已启用，应用登录权限与授权状态有效 | Needs Owner Verification |
| 数据处理位置 | 工程不能证明后台 region | 实际位置、账号地区与服务可用区域匹配 | Needs Owner Verification |
| 云数据服务 | ArkData relationalStore 云空间同步；不是 Cloud Foundation DatabaseZone.query | 现有应用云空间 API/云空间服务有效；原数据所属产品明确 | Needs Owner Verification |
| 环境 | 当前安装包是调试签名 | 当前实际访问开发环境；开发/生产环境原结构与数据位置各自明确；本轮不改生产环境 | Needs Owner Verification |
| 容器 | 原配置要求 ddl 对应 ddl.db | 实际存在 ddl；接收库同名 customDir 注册确实读取该容器且不改主库注册/同步状态 | Needs Owner Verification |
| 旧 Deadline 类型 | deadlines，下面 16 字段 | 实际字段、类型、可空、加密、主键、索引；缺列保留事实，不补写旧数据 | Needs Owner Verification |
| 旧任务类型 | deadline_subtasks，下面 7 字段 | 实际字段、父归属、空值和 ID 去重；不是另一环境的表 | Needs Owner Verification |
| 当前事件类型 | ddl_sync_events，仅 id/deadline_id/payload | 当前是否存在、三列类型、唯一 ID、加密、大小配额和授权；本轮不创建 | Needs Owner Verification |
| 查询权限 | manifest 已声明 DISTRIBUTED_DATASYNC；autoSync=false | 设备用户云空间授权、账户数据隔离、服务端读取权限；开发/生产权限分别核对 | Needs Owner Verification |
| 主键/索引/分页 | 端侧按 id 去重；接收后本地每页 200 | 实际主键/索引及服务分页/限额；本地分页不是服务端分页证明 | Needs Owner Verification |
| 旧业务数据 | 未实际读取，不知道云中行数 | 旧两表与历史是否保留、是否仍有旧端写入；只观察，不清空或迁移 | Needs Owner Verification |

### 现有映射要求（不是新增云结构）

- `deadlines`：String `id/name/type/deadline_date/deadline_time/note/progress_mode/remaining_state`；Integer `created_at/deadline_at/completed/progress/reminder_offset_minutes/remaining_updated_at`；Double `estimated_hours/remaining_hours`。合计 16 列，id 去重；业务字段可空。旧记录缺 V6 三列时只降级，不由进度推算剩余小时。
- `deadline_subtasks`：String `id/deadline_id/title/parent_id`；Integer `completed/created_at/sort_order`。合计 7 列，id 去重；业务字段可空。
- 当前协议预期仅交换 `ddl_sync_events`：String `id/deadline_id/payload`；载荷包含完整聚合、因果和永久删除事实；最低传输协议仍 2。本轮不增加字段、规则或表。
- 本机 `ddl_sync_archive/ddl_sync_issues/ddl_sync_owner/ddl_legacy_imports/deadline_reminder_states` 不配置云记录类型。业务投影不因扫描修改；系统提醒 ID 不上传。

## 实际读取前必须全部满足

- 真实 SDK 授权返回非空身份；再次静默核验同一身份；仅在内存比较，不记录 ID 或 token。
- 当前账号来源与正确 AGC 应用、环境、账户数据分区已确认，不能用 UI 昵称或保存的旧 ID 替代。
- 容器映射、读取权限及接收库云注册隔离有证据；只读扫描不会 Upload、不自动导入、不触及主业务库/提醒。
- 收到数据仅 raw → normalized → Shadow；输出只有数量/缺字段/空值/重复/孤儿/本机 ID 重叠/分类计数。未读取不能写为云中 0 条。

当前上述门禁未满足。两个源代码门禁保持 false。即便真实读取和 Shadow 将来完成，也不能单凭它们批准 Canary Write；本轮没有验证写权限、安全旧写边界或真实写入行为。

## 真机必须补验

使用支持当前 SDK 的 HarmonyOS Phone，由本人系统登录及授权；正确应用调试 Profile 包含该真机；检查真实 Account Kit 回调与再次静默身份一致，正确 AGC 环境/容器/设备云空间权限，再验独立接收库只读边界。只能在只读门禁全部满足后读取一次。不要对原主库执行同步来“试一试”。

参考：[华为自动签名（关联/未关联注册应用与开放能力）](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)。现代自动签名支持两种模式，存在 Profile 并不等于已关联正确注册应用；本清单不擅自添加身份 metadata 或更换签名。
