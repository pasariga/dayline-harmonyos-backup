"""Publish the final record only when all required evidence gates exist."""
from pathlib import Path
import json,re
OUT=Path(__file__).parent
gate=json.loads((OUT/'final-gate.json').read_text())
clean=json.loads((OUT/'cleanup.json').read_text())
empty=json.loads((OUT/'final-empty.json').read_text())
cache=json.loads((OUT/'cache-cleanup.json').read_text())
assert gate['normal_and_large_four_locale_theme_flows_at_two_viewports'] and empty['test_module_absent']
assert clean['active_acceptance_data']==0 and clean['original_eight_table_digests_preserved']
sha=gate['signed_hap_sha256'];short=sha[:8]+'…'+sha[-8:]
def duration(name):
 text=(OUT/name).read_text(encoding='utf-8-sig')
 return re.findall(r'BUILD SUCCESSFUL in ([^\r\n]+)',text)[-1].strip()
build=duration('build-final.log');clean_time=duration('clean-final.log')
build_log=(OUT/'build-final.log').read_text(encoding='utf-8-sig')
sign=re.findall(r'default@SignHap\.\.\. after ([^\r\n]+)',build_log)[-1].strip()
counts=clean['counts_after'];flow_count=sum(gate['full_flows'].values())
report=f'''# Device / Accessibility / Layout Hardening — 完成

2026-10-19 开始，2026-10-21 完成当前 Phone 模拟器验收。本轮结束，Experience Layer 继续冻结。

## 范围与用户反馈

保留 Experience Redesign 的架构、色板、字体设计语言及业务规则。用户指出输入框示例与重复说明造成杂乱后，移除了核心创建/编辑、任务、备注、工时的示例 placeholder，以及创建页重复开场/页尾说明。用途由简短外部标签、控件顺序及小时单位表达；保留错误与无障碍描述、可编辑边界。

没有修改数据库版本/结构、同步协议、工作量/风险/排期/通知规则、Bundle Name、SDK、签名身份或 AGC 身份。真实云交换仍关闭。

## 实际矩阵

| Phone 实际视口 | 系统字号 | 完整流程 |
| --- | --- | --- |
| 377×816vp（1320×2856，density 3.5） | 标准2、特大5 | 中文浅/深、English浅、Deutsch深，共8条 |
| 同上 | 中档3 | Français浅，1条 |
| 320×571vp（1120×2000，density 3.5） | 标准2、特大5 | 同四组合，共8条 |
| 480×960vp（1680×3360，density 3.5） | 标准2、特大5 | Français浅、Deutsch深，共2条 |

总计 **{flow_count}条完整流程**，唯一结果见 `matrix-results-pura.json` / `matrix-results-compact.json` / `matrix-results-wide.json`。每条实际创建、任务新增/完成/Undo、6小时确认、编辑/取消返回、7小时输入后台恢复、取消、强停重启保存值、UI删除；核对总10小时、任务仅1条、原截止时刻和剩余6小时。小屏及宽屏首条另测带未保存任务草稿删除，无二次放弃对话框。

这些是同一 Phone 系统镜像的三种实际屏幕配置，不是三台真机。DMS 返回的实际视口写在 `runtime-screen-*.json`。主屏矩阵在过程包完成；最新布局修复后，最终包重新检查受影响的小屏德文页面（`label-probe-final.log`及`fixed-small-de-*.jpeg`）、完成宽屏两条完整流程、原屏最终冷启动/空状态/双击导航回归。没有冒充所有组合都在最终SHA重新全量运行。

## 定向修复

1. 标准应用 configuration 跟随系统字号，上限3.2；当前系统最大档实际scale为1.45，不能把配置上限当实测值。
2. 关键短控件最小44vp、任务44vp响应区；符号不随正文放大裁切；补充图标描述、selected/checked语义。
3. 重要名称/任务允许换行；详情标题超过视口32%时随正文滚动，返回与页签仍可操作。
4. 小屏特大德文的页签省略、状态行挤压、设置标题溢出及行动状态窄列，经截图复查发现并修复：页签两行、状态标签明确宽度、标题自适应、状态与校准入口可换行。未改文案含义或颜色体系。
5. 键盘改为resize，避免顶栏被推走；子任务/编辑任务请求输入焦点，focus异常与保存结果隔离。
6. 首页替代加载请求结束当前loading；清单切回Today复位主行动，详情返回清单保留位置。
7. 删除事务成功后允许退出，避免旧草稿返回保护留在已删除详情；失败仍保留原保护。
8. 浅底上8个小字标签改用现有正文色；色板未变，18组抽样文字对比度均≥4.5，见`contrast-final.json`，不等于完整无障碍认证。

冻结检查见`audit.json`：31份service/model/签名等原文件SHA保全，27个业务操作契约保持；加载终态、删除后离开及EntryAbility键盘策略的UI例外均精确限定。九套资源键保持，仅把已有剩余估计提示改为小时单位短标签。

## 原生、键盘和极端状态证据

- 原生基础3/3：`native-final-pura.log`。实际跟随系统字号、触控尺寸、portrait旋转请求后草稿安全和首次Back关键盘；最终仍是竖屏，不算横屏布局通过。
- 真实键盘：创建原生截图，以及名称/备注/任务/剩余工时4/4输入、Back、提交和数据库核对，见`keyboard-results.json`、`keyboard-resize.log`、`hardening-keyboard-*.png`。不是从文字注入成功推断键盘可见。
- 0/1/3/8项目、多完成/逾期/未知/高风险：`edge-results.json`及截图；32节点/30叶、三级树、可视圆圈外8vp命中及Undo：`large-task-results.json`。后续两个键盘用叶子独立写入并核对，无重复。
- 德文/西班牙文小屏特大设置、计划设置、通知设置、数据说明、空表单校验和日期Dialog：`survey-compact-*.log`。界面允许滚动，原生Dialog有退出入口；只读检查，没有改变通知/计划值。
- `back-space-results.json`验证深滚动清单回Today的主行动可见。辅助工具栏名称及系统日期Dialog标题可能省略，但完整名称在正文、完整年月日在选中轮中可读；单行编辑输入可水平滚动，重要展示文字不靠永久截断隐藏。

## 构建与最终安装

全套定向 **237/237，Failure0/Error0**；clean **{clean_time}**；完整debug assembleHap **{build}**；SignHap **{sign}**。最终包实际安装成功见`install-final.log`，SHA256：

`{sha}`

副本：`Dayline-hardening-final-signed.hap`。最后仅更新README/validation记录，未再修改产品代码。较早143E包首次离线安装失败，不能采用当时脚本末尾的成功文案；验证脚本已要求明确的安装成功输出。较早D569包也不再是最终包。

## 数据及环境清理

所有本轮active项目通过App删除；Deadline/任务/提醒状态均0。原八表记录摘要严格保全，原393事件/289归档/13问题未丢失或改写；新增合法操作/删除历史保留。最终历史总数为事件{counts['ddl_sync_events']}、归档{counts['ddl_sync_archive']}、问题{counts['ddl_sync_issues']}。DB8、integrity_check=ok、触发器0，见`cleanup.json`。

原App跟随系统主题/语言、系统字号2/字重1/显示缩放1、通知与逾期临时偏好已恢复。原模拟器config.ini按备份原字节恢复；未重建或替换userdata。清除{cache['owned_artifact_count_removed']}个受限测试缓存/临时布局文件，entry_test已移除。最终空首页、双击创建一次Back回首页、前后台及强停重启通过，见`final-empty.json`、`final-empty-*.jpeg`与`runtime-screen-final-restored.json`。FlClash保留运行。

## 边界和失败记录

最初新Small VM被输入法首次隐私选择阻断，未代替用户接受；最初720×1280实际仅205×365vp，未冒充正常小屏。修正几何后的320×571vp已实际通过。宿主机曾低内存；释放闲置开发进程后继续，不计为App回归。保留所有失败、前置不足、滚动定位失败与修复前图片，不计入通过数量。

尚未做：物理真机、完整屏幕阅读器认证、全横屏布局和客观FPS专项。后台保留未保存输入已验；强停只保证已保存数据，未新增强停草稿持久化。真实账号/AGC/双设备、代理定时提醒送达以及既有发布材料门禁不因此解除，不宣称AppGallery提交GO。

## 最终15项结论

| 项目 | 结论 |
| --- | --- |
| 大字体 | 当前系统标准、中档、特大档通过上述覆盖 |
| 自适应 | 名称/标题换行，长详情标题滚动，状态与入口在窄屏换行 |
| 小屏行动优先 | 仍以唯一首要行动为中心，次要内容按需滚动 |
| 横屏 | 明确portrait，旋转请求后状态安全；不称横屏UI已验 |
| 长文本 | 重要内容可完整查看；辅助省略有正文或原生选中值替代 |
| 键盘 | 五类实际键盘输入已检查，Back先关闭键盘，输入/提交可达 |
| 触控 | 本轮关键入口与44vp任务响应/Undo通过 |
| 对比度 | 深浅18组抽样通过，非全面认证 |
| 状态 | 有文字/勾选状态，不只用颜色 |
| 生命周期 | 后台草稿及保存值冷启保持，编辑返回和清单返回通过 |
| 性能 | 未观察到新的明显阻塞；不报告虚构FPS |
| 测试 | 237主机、原生3、键盘4、完整流程{flow_count}，分别统计 |
| 构建 | clean/完整debug/SignHap成功，最终包已安装回归 |
| 新回归 | 已修复删除退出和窄屏布局等问题，未见已知残留 |
| 本轮阻塞 | 当前覆盖条件下无剩余布局/基础可访问性阻塞 |

**【Dayline Experience Layer 已冻结，并通过 V1.0 Device & Accessibility Hardening。】**
'''
(OUT/'README.md').write_text(report,encoding='utf-8')
root=Path('README.md');body=root.read_text(encoding='utf-8')
marker='### 2026-10-21：Device / Accessibility / Layout Hardening'
assert marker not in body,'Already recorded; do not duplicate history'
summary=f'''- **2026-10-21 Device / Accessibility / Layout Hardening（10月19日开始，当前Phone验收完成，体验继续冻结）**：主屏377×816vp、小屏320×571vp、宽屏480×960vp实际运行；标准/特大四语言主题在主屏和小屏16条，加法语中档及宽屏2条，共{flow_count}条完整流程。真实键盘五场景、原生3/3、32节点/30叶及8项目混合状态通过。去除冗余示例占位/创建说明；修复字号跟随、44热区、长标题/设置标题/页签/状态行溢出、键盘避让/焦点、加载终态/返回位置及删除成功后草稿拦截。最终237/237、clean {clean_time}、完整debug {build}/SignHap {sign}成功；{short} signed已安装并复验。自有业务数据清零，原八表摘要保全，DB8/完整性ok/触发器0，原偏好与显示配置恢复，测试模块/缓存移除。未改数据库/协议/核心规则/通知/身份；云/定时送达和既有发布门禁不变。详见[本轮验证](validation/hardening-2026-10-19/README.md)。'''
task=f'''{marker}

- 状态：完成当前Phone模拟器验收；本轮停止，Experience Layer继续冻结。
- 修改：七个相关页面的适配/触控/可访问性；EntryAbility仅键盘resize策略；App字体跟随profile/portrait配置；九套已有剩余估计单位标签；原生测试与validation。移除核心表单示例和重复说明，不重做视觉体系。
- 验证：237/237、原生基础3/3、四输入键盘4/4加创建键盘实图；{flow_count}条完整流程、三种实际视口、德/西设置Dialog、长文本/层级任务/混合状态；最终clean {clean_time}、完整debug assembleHap {build}、SignHap {sign}及最新signed安装。最终SHA `{sha}`。过程矩阵与最新包定向复验分别记录，不冒充全矩阵均在最终SHA重跑。
- 清理：仅删除本轮自有active数据，保留原393事件/289归档/13问题及合法新增历史；当前业务/任务/提醒0，DB8完整性ok/触发器0；原偏好、字号/字重/缩放、模拟器配置原字节恢复，entry_test及测试缓存移除，最终空首页/双击导航/后台/冷启通过。
- 边界：明确Phone竖屏；旋转只验证状态保全，不称横屏布局通过。未做物理真机或完整屏幕阅读器认证；未新增强停草稿持久化。云/定时送达、release Profile/发布主体/正式政策入口等原门禁不变，非AppGallery提交GO。失败日志及原生日期标题/辅助工具栏省略的替代查看方式如实保留。
- 记录：[完整验证与15项结论](validation/hardening-2026-10-19/README.md)。

'''
change=f'''{marker}

- 去除表单示例/重复教学说明，保留简短标签与单位；系统字号跟随、关键触控区域、长文本和键盘适配，不变更视觉语言。
- 修复真实发现的加载/返回、已删除页面草稿拦截、小屏大字德文标题/页签/状态挤压；保留业务规则和数据库V8。
- 237/237、clean/完整debug/SignHap和最终{short} signed Phone回归通过；三视口{flow_count}条完整流程，已区分过程矩阵与最终包复查。
- 自有数据/缓存/测试模块清理，原历史和偏好/屏幕配置保全。当前覆盖条件下无本轮遗留阻塞，体验继续冻结；未开放云或解除既有发布门禁。

'''
for heading,addition in [('## 当前项目状态',summary+'\n'),('## 最近一次任务记录',task),('## 变更记录',change)]:
 needle=heading+'\n\n';assert body.count(needle)==1,heading
 body=body.replace(needle,needle+addition+'\n',1)
root.write_text(body,encoding='utf-8')
print('README state, latest task, changelog and final validation record updated.')
