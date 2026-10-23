# Account Kit → AGC 只读 → Shadow 诊断

2026-10-04，**部分完成，NO-GO**。目标链路未打通；本轮已经定位当前第一处运行阻断。不扩展同步协议，不改数据库/生产源码/身份/界面/算法/通知。普通交换及真实读取门禁仍 false，无 AGC 请求、上传、导入或后台变更。

## 实际运行结论

在线设备 `127.0.0.1:5555`，Pura 90 Phone，本地模拟器系统 OpenHarmony-6.1.1.125。真实 SDK 诊断日志见 sdk-probe.txt：

- `AUTH_SYSCAP=true`，`RDB_SYSCAP=true`；HuaweiIDProvider、请求及 AuthenticationController 创建成功。
- `forceLogin=false` 的 executeRequest 返回 **1001502001**。安装 SDK 对应枚举是 `ACCOUNT_NOT_LOGGED_IN`：用户未登录华为账号。不是此前笼统“Account Kit unavailable”所能区分的情况。
- 从首页→设置→账号→华为账号登录，实际出现“登录华为账号”交互界面。仅打开登录界面，不等于真实账号登录或授权成功。设备尚未返回可确认的真实身份。
- 用户本人登录请求已发出；本轮记录截止尚未收到完成结果。未输入凭据、未选择伪账号、未将 UI 状态或旧 Preferences ID 当作授权结果。界面留给本人继续操作。
- 未观察到明确“模拟器不支持”提示，亦未获得模拟器真实账号+ArkData 云读取成功证明。因此不把错误1001502001推断为模拟器绝对不支持，也不宣称模拟器足够。若登录不支持或仅模拟返回，使用真机，不绕过。

## A–H 层级

| 层 | 本轮证据 | 结论 |
| --- | --- | --- |
| A Account Kit 可用性 | Syscap true，实际请求可执行 | 当前设备接口入口可用；不等于真实后台可用 |
| B 用户登录/授权 | 静默执行返回1001502001；交互页已打开 | **当前第一处阻断：系统账号尚未登录，真实 App 授权未完成** |
| C 账号身份 | 没有真实 SDK 成功返回 | 未取得可信身份，不能核验稳定性/云账号来源 |
| D AGC 应用匹配 | 本地 Profile/证书/已安装签名一致 | 后台 App ID/Client ID/开放能力关联 Needs Owner Verification |
| E ArkData 云初始化 | 原本地 RDB 正常；真实云分支未执行 | 本地成功不能替代真实云初始化验证 |
| F 容器/数据类型注册 | 源码期望 ddl 及三类型；只读注册隔离未证 | 未验真实映射，不能直接开启接收库注册 |
| G 查询权限 | manifest 声明 DISTRIBUTED_DATASYNC | 设备授权/服务端账号分区/只读权限未验 |
| H 真正读取 | 读取门禁 false | 未执行；实际云行数、分页、缺字段/重复/孤儿/重叠及 Shadow 计数未知 |

## 工程与签名

identity-config.json 只含公开签名信息及布尔比对：Bundle Name com.gary.ddl；SDK API24；debug Profile 包名一致；Profile app-identifier 存在且和安装包一致；当前签名证书链含3个证书，叶证书 SHA-256 与 Profile development-certificate 及已安装应用一致。HAP 签名验证 exit0，包内 Profile 与配置 Profile 相同。

叶证书公开指纹为 DB117D9648FD290A59C00460924E9812DD04792A688A6B817B6717B60457D990。最初辅助脚本误将 PEM 链首个根证书作为叶证书比较，现已修正；没有据此修改签名或宣称工程签名不匹配。设备安装 HAP 文件读取因权限限制失败，不能声称二进制哈希相同；签名身份由实际 bundleManager API 和设备元数据交叉核验。

app.json5 的 cloudStructuredDataSyncEnabled=true，module 为 Phone/entry，声明 DISTRIBUTED_DATASYNC；manifests 无显式 client_id/app_id，Profile app-identifier 不能替代 AGC 后台关联证明。当前错误不是指纹错误1001500001，尚无证据支持擅自补 Client ID/更换 Profile。按照[华为自动签名文档](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)，需本人核实 DevEco 是否关联正确注册应用，而非只使用未关联自动签名。

CloudAccountService.getCurrentOpenId 捕获底层异常后统一包装为固定错误，因此之前“unavailable”无法指出 SDK 根因。测试直接调用相同 SDK，记录阶段+数值码，不改账号业务，不使用存储身份回退。当前 API 的 forceLogin=false 正常用于静默核验；本机未登录时返回错误符合安装 SDK 约定。既有交互按钮使用 forceLogin=true，只有回调成功取得 openID 才绑定会话；本轮没有收到成功回调。

## 分类与最短下一步

| 类别 | 目前可确认事实 | 下一步 |
| --- | --- | --- |
| 工程代码 | 静默包装隐藏诊断码；直接 SDK 探测已辨明当前根因；未证明调用配置错误 | 保持业务逻辑冻结，用测试探测具体阶段/安全码 |
| 签名/Profile | 本地链、Profile、安装身份一致 | 后台关联及新真机设备登记本人核对 |
| Account Kit 后台 | 没有后台证据 | 确认应用级身份/开放能力与授权 |
| AGC 数据配置 | 映射要求有文档，实际配置未知 | 按 OWNER_CHECKLIST.md 只读核对，不建新表 |
| 权限 | 仅 manifest 声明已证 | 设备云空间授权、账号分区及读取权限核对 |
| 模拟器限制 | 接口与交互入口可调用，真实能力未证 | 真实授权能完成才继续；不能完成立即换真机 |
| 本人操作 | 真实登录、授权、后台访问不能代办凭据 | 在已打开界面自行完成，告知成功/限制结果，无需发送账号或凭据 |
| 真机 | 尚未连接 | 在受支持 HarmonyOS Phone 验真实身份与再次静默核验、AGC环境/原容器/只读隔离；不执行原业务同步 |

先完成本人登录与后台只读核对，再核验 D–G，全部读取门禁满足后才允许一次 raw→normalized→Shadow。不是因为登录成功就翻转门禁；本轮禁止 Canary Write 的决定不变。

## 实际验证与保全

- 新增 ohosTest/AccountAccessNative.test.ets 与独立套件注册；只探测 Syscap、公开签名元数据和 Account Kit，不访问业务 DB、CloudSync、receiver 或保存会话。
- 独立测试包 assembleHap/SignHap 成功24s202ms，Phone `aa test ... -s class accountAccess` 结果2/2。**这是诊断完成，不是账号登录通过或云验收通过。** 初次测试包 import 使用不可用 BundleKit 导致编译失败，修正为 AbilityKit 后通过，失败日志保留。
- 本轮 clean BUILD SUCCESSFUL 2s65ms；完整主模块 debug assembleHap 含 SignHap BUILD SUCCESSFUL 30s488ms。仅 SDK Unsafe 环境警告；未执行152项协议测试，不将上一轮结果冒充本轮。
- final-artifact.json：主 signed HAP 2,392,972字节，SHA-256 E4365BC2E0C28B0F50AD73FD62A3745FF789FDA4926D4DA382C9FBBC7F873605。生产源码/配置未变；当前登录界面仍待本人操作，未重新覆盖安装打断流程。已安装主包原签名验证另见 identity-config.json。
- main-after-diagnostic.json：八表 SHA 与既有基线一致，版本8，integrity_check=ok，事件251、归档147、问题13；业务、任务、提醒、owner、暂存均0。检查不关闭当前交互登录窗口；没有实际云样本，不能把主库0记录说成云中0记录。
- 为保留当前本人登录界面，本轮暂留诊断 entry_test 模块；发布主 HAP 不含该模块。后续本人授权检查完只卸载 entry_test，不卸载主 App/清库。
- UI 临时布局只在临时目录解析，随后删除；只输出静态白名单、布尔状态、公开指纹和数值码。不落地全量账号布局、响应、token、授权码、完整账号ID或用户业务内容。

生产协议/DB/配置没有本轮改动。仍未证明真实读取、更不能允许 Canary Write。**NO-GO**。
