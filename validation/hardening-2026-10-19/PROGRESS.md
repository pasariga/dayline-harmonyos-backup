# Hardening — 当前 Phone 验收完成，2026-10-21 关闭

## 最终状态（优先于以下进行中历史）

- final-gate.json通过：主屏9、小屏8、宽屏2，共19条完整流程；237/237定向测试，原生3/3、真实键盘四项加创建截图，全部明确区分证据来源。
- 最终产品代码SHA对应signed HAP 78177D15A3B73D0FA527CA2BC8F3C6BBCD76F3A0448F798D8AC7A6B24DCCE0E4；clean1s786ms、完整debug29s021ms、SignHap1s479ms，最新包已安装与受影响小屏/宽屏/原屏空状态回归。
- cleanup.json：业务/任务/提醒0，原八表摘要保全；当前合法历史604事件/500归档/13问题，DB8/完整性ok/触发器0。原偏好与字号/字重/缩放恢复，21个受限缓存清理，entry_test移除。
- screen-restore.json恢复原config字节；runtime-screen-final-restored.json实测1320×2856、377×816vp、density3.5。final-empty.json空启动/双击创建一次Back/后台/强停重启通过。最终App停留空首页，FlClash保留。
- README当前状态/最近任务/变更及本目录README已更新。详细15项结论、过程包与最终包复查区别、失败日志和未验边界见本目录README。本轮结束，不继续新功能或视觉优化。

## 最新续验（2026-10-21 12:17，优先于下方所有旧状态）

- 主屏377×816vp：标准2/特大5四组合8条完整流程＋法语中档3完整流程，共9条；小屏实际320×571vp：标准2/特大5四组合8条；宽屏实际480×960vp：法语浅色2、德文深色5两条，共19条完整流程均通过。所有数据结果在matrix-results-{pura,compact,wide}.json。实际虚拟尺寸有runtime-screen-compact-corrected.json、runtime-screen-wide.json，不是按配置猜测。
- 用户反馈的示例placeholder/冗余创建说明已去除，保留外部标签/单位和细边界，九套remaining_editor_hint仅改成单位短标签。
- 最新真实Bug修复：删除有未保存草稿的Deadline成功后允许直接退出，避免再弹放弃更改留在已删除详情；small normal/large首条及wide两条带草稿删除已实际通过。业务删除事务未改。
- 小屏特大德文视觉复查发现：页签省略、状态标签与数值挤压、设置页标题横向溢出、行动摘要文字被校准按钮挤成窄列。已分别用页签两行、状态标签42%宽、设置标题layoutWeight/不限制两行、行动摘要FlexWrap修复。最新实际图片fixed-small-de-{settings,appearance,planning,notification,plan-labels,action-status}.jpeg，label-probe-final.log通过，已人工看图确认。辅助工具栏标题可省略，完整名称在正文；系统日期Dialog标题可省略，完整年月日轮选择可读。
- **最终产品代码已经冻结，不再做可选UI调整。** 最新全套237/237、clean1s786ms、完整debug assembleHap29s021ms、SignHap1s479ms成功并安装。最新signed SHA **78177D15A3B73D0FA527CA2BC8F3C6BBCD76F3A0448F798D8AC7A6B24DCCE0E4**；验证副本Dayline-hardening-final-signed.hap。此前D569/143E包已过时，README草稿仍有旧SHA，最终必须更新。
- Native基本3/3、键盘4/4＋创建真实键盘、32节点/30叶子三级树/44热区Undo、0/1/3/8混合状态、对比18组均已有实际证据。源码audit31冻结SHA/27业务方法契约通过，DB8/云协议/通知/风险/排期等未改；allowLeave与loading终态是精确UI例外。
- 电脑曾低内存，用户明确允许自行关闭闲置进程但保留FlClash。已停闲置LSP/Hvigor后台；DevEco已退出，FlClash始终保留。Windows曾锁屏，电脑操作停下；Phone HDC继续可靠运行，无需等桌面退出问题回复。没有接受输入法隐私/账号授权。
- **当前Pura仍是wide显示1680×3360 DPI560，HDC5555。所有矩阵结束，正在执行清理session44922。** restore-settings.log已PASS：App跟随系统主题/语言，系统font2/weight1/display1已恢复。cleanup-ui.py正通过App删除原8条自有active测试项目，随后cleanup-check.py核原八表摘要/恢复本轮通知和逾期临时偏好，cleanup-cache.py只删受限hardening缓存。看日志是否成功后再继续，不要另起UI脚本并发。
- **最后必须：** 1)确认cleanup.json、cache-cleanup.json；2)正常stop Pura，screen-profile.py restore恢复pura-screen-original.ini原字节（原1320×2856/DPI560，不能改userdata），再start原Phone；3)默认DEVICEpura/W1320/H2856，runtime-screen.py final-restored --empty；4)final-empty.py验证空首页/双击Add一次Back回首页/前后台/强停重启/无entry_test；5)final-gate.py（要求19条矩阵、237、清理、原显示配置、空状态和最终HAP SHA）＋audit.py；6)更新README三处和本目录README（当前仍草稿旧SHA），明确过程矩阵与最新包定向复验，保留全部失败日志；7)仅在无剩余阻塞后最终15项报告/指定关闭语并停止。
- Emulator CLI instancePath必须deployed父目录；start进程持续运行正常，正常stop后等退出再restore。当前启动session43371。不要Ctrl+C乱关。runtime-screen.py新增--empty参数，清理后不再要求Main测试UUID存在。
- 最终helper：restore-settings.py（已完成）、cleanup-ui.py、cleanup-check.py、cleanup-cache.py、final-empty.py、final-gate.py。它们已写好。final-gate当前应在最终空状态后运行；未具备证据前不要声称通过。

## 最新续验状态（2026-10-19 15:55，覆盖下方早期状态）

- 用户最新要求：继续完成，并纠正重复“例如微机原理作业”等教学式占位文字。已删核心表单全部示例placeholder、创建开场/页尾重复说明，保留外部标题/a11y description与细输入边界。剩余估计表单改成有明确小时单位的短标签，九套messages仅改remaining_editor_hint，原文备份messages-*.before.json。
- 主Pura默认字体2与特大5，四locale/theme **8条完整链路通过**；matrix-results-pura.json。237/237主机工作集通过。
- Native基本3/3（native-final-pura.log）通过，明确moduleName:entry，实际字体1.45/max3.200000047，portrait旋转请求保持草稿；确认第一下Back先关键盘。
- 真实键盘创建已由Native草稿截图证实；剩余、任务、编辑名称、备注四字段在正常entry模块经过真实UI路径完成并有PNG，keyboard-resize.log及keyboard-results.json **4/4**。备注长文本需clearText再输入，测试用typedValue作为Back/落库对照；AA测试超时现为90秒，host等待150秒。不要再次用已存在的UX19-Keyboard-Task-Resize名字添加任务。
- 发现并修复默认OFFSET导致详情顶栏被键盘推到状态栏外：EntryAbility成功loadContent后仅追加setKeyboardAvoidMode(RESIZE)，通知/时钟代码原样。EntryAbility.before.ets保留，可精确剥离UI三行比较；核心冻结31份＋EntryAbilityUI限定变化。
- 长列表加子/编辑后找不到输入框，已在两页beginAddChild/beginEditTask请求对应输入焦点，cancel清理focus，全部try/catch隔离，业务方法不变。实际键盘已出现，32节点/30叶、三级树、44热区右侧8vp点中/Undo、原IDs/无重复通过large-task-results.json。
- **8项目混合状态通过**：2完成、2逾期、4未知（包括逾期），高风险组在完成前检查。edge-results.json原先deepList→Back丢主视觉焦点false，已加Index.homeScroller，仅switchHome复位顶端，详情回清单仍保留位置；back-space-results.json两项true。
- 两个临时新VM均无业务数据，Small首次IME授权阻断，未代替用户同意。computer-use激活Primary两次失败，捕获只见桌面；两条异步手工问题已通过commentary撤回，**无需等待用户**。改用**同一原Pura环境更改显示配置**，不复制或修改授权/账号/用户数据。新Small已停止，Large从未启动，保留为几何参考。
- **当前Pura已停机修改几何并重启到compact**：720×1280 DPI360，CLI88724持续运行（正常窗口生命周期）；HDC应仍5555。**原config.ini已备份pura-screen-original.ini，最终必须停机后screen-profile.py restore，原字节恢复再重启！** 只复制hw.lcd.*与isCustomize，身份/SDK/非显示配置不变；不要编辑或删除userdata文件。
- 停机前runtime-screen-before-compact.json：1320×2856、虚拟377×816、density3.5、原Main ID在、DB8/ok。tables-before-compact.json全八表摘要保存，启动compact后须runtime-screen.py after-compact和比较摘要，不能只凭config声称小屏验收。
- 接下来：compact下环境DAYLINE_TEST_TARGET=127.0.0.1:5555 DEVICE=compact WIDTH=720 HEIGHT=1280，先runtime-screen确认并u.restart，再字体2＋四case、字体5＋四case。**不要再用fresh Small VM（10001）**。helper已修复系统Display页面需滚动、首页深滚动找header、完成后Action复位/比例需滚动。
- 然后宽屏参考wide：1440×3040 DPI480，至少正常/大字完整流程＋法/西资源；Pura中档字体3需抽查。补Settings二级/Meta/错误验证/日期时间Dialog、长/多行、手动进度/快速返回。当前主资料库8测试项目均未清理。
- 最后重新test/clean/debug assemble/Sign，最终HAP安装/回归；所有ownIDs在fixtures.json、fixtures-pura.json等文件，后续compact/wide新增分别记录，**同一库须合并所有ownIDs清理**。保留原393事件/289归档/13问题摘要，当前合法历史增加不擦除。恢复原偏好、字体2/粗细1/显示缩放1、显示config原字节、测试模块/缓存清理，README三处及本目录README。尚未完成，不能关闭本轮。

当前日期2026-10-19。用户要求见附件3817b8ba；最新补充明确反对重复教学式占位文字。本轮不再重构信息架构/颜色/核心规则。

## 已完成与当前代码

- 初始基线：主Pura业务0，事件393、归档289、问题13；八表摘要和原偏好保存在本目录，源码SHA基线source-before.json。正常用户数据不可删，合法历史不可擦。
- 新增AppScope字体followSystem配置（原来默认不跟随），最大cap3.2；实际标准/大/特大字号需分别测试，5档预计1.45，以原生数值为准。入口声明portrait，不设计横屏。
- Index只改最近有效刷新finally结束loading，避免初次加载被前台刷新接替后一直loading。其余业务操作原样。
- 七个UI页面短按钮min44；核心任务44响应区/checked角色；More有任务上下文；页签selected；符号按钮padding0/maxFontScale1防裁切；重要项目/任务名称允许全显示。
- 最新补充：移除创建/编辑/任务/工时/备注的示例placeholder及创建页重复开场/页尾文字；输入保留外部标题/无障碍description和轻量可编辑边界，不是重新设计。
- 现有浅底色上的强调色小字对比度约4.24；8处按钮改用现有text_body，不改任何颜色资源/体系。contrast-before.json及contrast-label-fixes.json。
- 长名字大字时Detail标题超过视口32%则随内容滚动，返回/页签仍固定；正常字号正常屏原结构不变。该最新fallback的实际验收正在进行。
- 全services/models/EntryAbility/签名等冻结32份；27业务方法保持；仅Index loading finally条件放宽（UI）。audit.py已通过。

## 实际通过

- 主机全套237/237，test-working-result.txt；这是工作过程测试，最后还须重新test/clean/完整assemble/Sign。
- Pura标准字体index2，中文浅色/深色、English浅色、Deutsch深色 **4条完整流程通过**。matrix-results.json，matrix-pura-normal.log；实际创建、加任务、完成/Undo、6小时、改名返回/取消草稿、7小时输入后台同PID保留、强停重启6小时/1任务/原截止保持，再通过UI删除每个case。
- 系统字体标准2、其余字体粗细1/显示缩放1原值已保存；当前准备字体5大字4条矩阵。

## 当前设备/数据

- HDC Pura 127.0.0.1:5555，1320×2856/DPI560=377vp。当前App语言Deutsch、深色，系统字体准备5（以pura-large-system-font.json确认）。
- 原生entry_test当前已卸载，前次0/3记录native-hardening-initial-failed.log保留；原因包括非常规foreground回调测试前置/无UI与3.2浮点精确比较。Native测试已改为正常Home前后台/id定位/浮点容差，尚需重新打包运行。
- Pura仍有自有主夹具 `9638609c-bbd9-4a7b-915a-95455548e808` / `UX19-Mathematik-Pruefung-Abschlussprojekt-langer-Titel`，总10、自动2任务、备注300字符。本轮matrix case正常通过后经App删除；失败case0曾由App删除后重跑。所有已知IDs由fixtures-pura.json及fixtures.json保存，最后需要合并清理保全。
- 两个临时模拟器已创建、尚未启动：Dayline Hardening Small（720×1280,DPI360=320vp）与Large（1440×3040,DPI480=480vp）。都在LocalAppData/Huawei/Emulator/deployed，镜像用现有HarmonyOS6.1.1(24)。不要触碰Mate/Pura原设备数据。
- Emulator CLI-start的instancePath是**deployed父目录**，不是具体设备目录；后者失败。当前Pura由exec60725启动，该进程会在窗口关闭前持续运行，不要Ctrl+C误关设备。

## 接下来必做

1. Pura字体5的四语言/主题完整矩阵（当前运行），大字长名fallback、真实软键盘五场景、字体3中档、法/西长资源和Meta/Settings/Date-Time/Dialog。
2. 修正后的Native3项重新验证（先在普通App中正常启动并让数据库完成加载，再安装并执行测试；不要再次在runner冷启动中反复直接调用onForeground）。需记录实际scale、portrait旋转请求只保证数据/草稿安全，不称横屏通过。
3. 主机停止时不要擦库；启动Small后检查实际HDC目标及尺寸，环境DAYLINE_TEST_TARGET/WIDTH/HEIGHT/DEVICE对应；harness.py默认Pura参数。Small至少默认和大字×四locale/theme全流程；Large至少完整流程和两字号/法语抽查。
4. 0/1/3/8 Deadline、多完成/逾期/未知/高风险，长任务树/多行/300备注、触控边缘/More/撤销；全自有UI数据，不写业务SQL造假。
5. 最后所有修复后重新test、clean、完整debug assembleHap/SignHap，最终signed安装/回归；清自有业务/偏好/测试模块/临时layout，保留原历史摘要，DB8/integrity/0触发器，恢复系统字体2/粗细1/显示缩放1及App原偏好。
6. README当前状态/最近任务/变更和本目录README。不得提前写通过；不进入新功能。

## 工具注意

- **只允许一个设备UI自动化脚本运行**。不要矩阵运行时并发dumpLayout、点击或Sky操作，会导致空JSON/测试前置紊乱。只读日志、源码、DB/包元数据可独立进行。
- `ui.py tap`第2参数有空格必须整体引号，否则被错当scroll开关；失败证据保留。
- 从Scroll页面边缘滑动，避免在TextArea里反复滚动备注而不是页面；tap(scroll=True)会先确认按钮不在屏幕底端裁切处。
- `tap(task title)`可能点到顶部不可点击的NextStep文本；完成操作用已观察的完成按钮或任务checkbox id/实际响应区，不把定位失败算业务失败。
- PowerShell不支持C风格\"转义。复杂脚本写UTF8文件；中文不要经PS heredoc管入Python。所有Python调用设置PYTHONUTF8=1。
- Keyboard可见性不能从HDC输入推断；需直接Sky点按Emulator窗口并实际看见键盘，Phone截图保存证据。computer-use技能已读，Windows必须sky，不接受隐私/账号授权。
- 已有矩阵脚本harness.py/matrix.py，直接重跑相同tag前必须经App删除该tag残留，不能重复创建同名导致错误。
