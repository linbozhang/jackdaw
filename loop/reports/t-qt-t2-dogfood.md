# T-QT 任务 2 报告：dogfood 重跑 T02-T1 验收 + 脚本迁移 + manual v2

> 分支 `loop/t02-inspector`，merge main `70bd7976`（QA 驱动工具）后为 `41fede05`，
> merge 无冲突（T-QT 改 remote/ui_probe/test_input/controls；T02-T1 改 commands/inspector/
> scene_io——零文件交集）。
> 验收人：QA（ZCode 子代理，GLM-5.3）。日期：2026-10-25。
> 脚本/产物：`loop/reports/t-qt-t2-qa-*.ps1`、`loop/reports/t-qt-t2-live/`、
> gate 日志 `loop/reports/t-qt-t2-gate-*.log`。

## T02-T1 VERDICT: **PASS**

## 1. 门禁（merge 后合并树独立重跑）

| 门 | 结果 | 数字 | 耗时 |
|---|---|---|---|
| fmt + clippy（`cargo xtask fast` 权威口径） | PASS | exit 0 | 35.1s |
| `cargo xtask fast`（含上面两门+lib） | PASS | **2864 passed / 2 skipped** | 35.1s |
| `cargo xtask integration` | PASS | **5032 passed / 3 skipped** | 306.4s |

- T02-T1 的 8 个新用例全数在 integration 运行中可见并 PASS：
  `field_targeting` ×4（3846-3851 行，含红→绿主用例与 stale-binding 不变量）+
  `three_way_matrix` ×4（3921-3927 行）。
- T-QT 工具用例同场全绿：`controls::ui_probe_click` ×6、`guards::editor_remote` 全列。
- 日志：`loop/reports/t-qt-t2-gate-fast.log` / `-integration.log`。

## 2. 代码审查（T02-T1 commit `dbe4d09f`，16 文件 +766/-11）

- **bound 门透传点完整性**：`rg` 全仓 21 处 `field_edit_commit/preview` 调用点逐一核对——
  三个绑定路径全传 `Some(entity)`：`apply_field_json_with_undo`（reflect_fields.rs:2186）、
  `apply_color_with_undo`（:1881，`_entity` 改名实参化，resource/PIE 路由先于门、顺序不变）、
  `commit_val_to_field`（val_field.rs:389）+ live preview 分支（:398）+ `apply_field_value_live`
  （reflect_fields.rs:2690，拖拽 tick 同受门控）；无绑定路径（asset_row/bindings_card/node_card/
  ops/ui_text_edit/probe_bake/enum/list/commands 单测）全传 `None` 原语义——与方案 §2.3 逐条一致。
- **红→绿用例四要素**（field_targeting.rs:144-166）：B 未被写 / A 严格丢弃 / undo 深度不变 /
  丢弃可闻（线程局部 tracing 断言 const 串 `STALE_FIELD_EDIT_DROPPED`）＋ stale-binding
  不变量（settle 后无 binding 落在选区外，借助新公开 `inspector::field_binding_entity`）＋
  多选多编锁定用例（[A,B] 选区一次提交双写）——四要素+两护角齐备。报告所引红证据
  （"left: 4.0 right: 2.0"）与用例断言文案逐字吻合。
- **warn 三处**（D3，不改行为）：`SetBsnField` 实体不在文档（原静默 return）、
  `field_edit_to_bsn_value` None 的 continue、`apply_json_field_to_ecs` 反序列化/路径两分支
  ——全部一行 `warn!` 带 type_path/entity 上下文。注意点：preview tick 失败路径按帧率重复
  warn 无节流（仅失败路径可达，方案即"一行级不深究"，⚪ 观察）。
- **矩阵 4 格三处一致**（three_way_matrix.rs）：每格断言 ①ECS 即变 ②AST authored ③
  `save_scene`+`scene_open_system` 重载一致；灯①格含 color（Vec2 平面）+illuminance（数值）+
  undo 回默认+undo 条目消费；相机格用 `Camera3d.depth_texture_usages.0`（偏差①合理：面板无
  order/Projection 可编辑行，卡片层抑制）；Transform 锚点格缝合 ①③。
- **save-skip**（D5）：`SKIP_COMPONENT_PREFIXES` 增 `"jackdaw_camera::"` + 真实
  `type_path()` 单测（防字符串拼错）——照方案 §6 一行级。
- **无任务 2 越界**：commit 不含 category_strip.rs / layout.rs / jackdaw_api_internal 的
  inspector.rs——无 D4（tooltip/标头）内容。Cargo.toml +5 行为 tracing/tracing-subscriber
  dev-deps（可闻用例所需），合规。

## 3. 真机抽验（新工具 dogfood，my-game，1920x1080，BRP 15807）

> 驱动全部经 `ui_click`/`ui_input`（manual §7）；数据断言全部 `world.query`（ECS 真值）。
> 不存盘策略：跑前/跑后 `assets/scene.bsn` SHA256 **逐字节一致**（4F55D81E…17DB）。

### §7-3 快速切换（D1 竞态，blur 提交+切换同帧的真实用户时序）

构造：ui_click 选 A（outliner 行）→ 展开卡片 → `ui_input`（commit=**none**）向 A 的
translation.y **打字不提交** → **紧接** ui_click B 行（同一手势队列连播，无 wait 间隔）——
B 行点击抢走焦点，数值控件 blur 提交 is_final ValueChange 与选区切到 B 同帧，即方案 §2.2
「blur 触发源」的实机形态。五轮换向（Sun/Cube/Point Light 三实体）：

| 轮 | 编辑 | 切到 | B 前后（translation.y） | A 前后 | 判定 |
|---|---|---|---|---|---|
| 1 | Sun.y='7.5' | Cube | 3.178415 → 3.178415 | 6.618198 → **7.5** | PASS |
| 2 | Cube.y='3.25' | Sun | 7.5 → 7.5 | 3.178415 → **3.25** | PASS |
| 3 | Sun.y='9.5' | Point Light | 5.346088 → 5.346088 | 7.5 → **9.5** | PASS |
| 4 | Cube.y='-4.75' | Point Light | 5.346088 → 5.346088 | 3.25 → **-4.75** | PASS |
| 5 | Point Light.y='6.125' | Cube | -4.75 → -4.75 | 5.346088 → **6.125** | PASS |

**结论：5/5 B 零污染**（含正负值、小数、三种实体）；A 每轮准确拿到自己的编辑（blur 提交
在真实时序下均落在「选区仍含 A」的窗口内，属合法多目标提交）。stale-drop warn 真机 0 次
——门的**丢弃**分支本轮实机时序未触发（如实记录）；该分支由 headless 红绿用例+不变量+
可闻用例三重钉死（§2），且门的存在保证即使时序翻转也只可能丢弃、不可能写 B。

### §7-2 数值链路抽验（PointLight intensity）

`ui_input`（click 聚焦→Ctrl+A→'5'→Enter，单手势一次往返）对 intensity 输入：
ECS **100000.0 → 5.0**（world.query）；authored bsn `intensity: 5.0,`（jackdaw/entity）。
双腿实证（存盘/重开腿由 headless 矩阵灯②格覆盖，真机不存盘）。

### camera_state 工具抽测

merge 后构建上 `jackdaw/camera_state` 正常应答（yaw/pitch/translation/perspective，
与 T-QT-T1 轮值同构）——新工具在 T02 分支 merge 树上无回归。

## 4. dogfood 效率记录（新旧对比）

- **定性**：旧法（uitext.ps1 world.query 文本+坐标 JSON 人工对位 → input.pointer 坐标点击 →
  `-Milliseconds` 赌帧）**根本无法驱动本次场景**——「聚焦→改文本→同帧提交」链路旧工具没有
  聚焦编排能力，X/Y/Z 数值行的定位也需人眼算坐标；新法 ui_tree 按 kind/rect 结构化发现 +
  ui_click 按实体 + ui_input 单队列手势（聚焦/全选/打字/提交一气呵成）+ 手势感知 wait idle，
  定位与提交全在编辑器内完成，脚本零坐标数学。本轮 5+5 轮全部数据级断言可复核。
- **耗时感**：环境摩擦（启动方式、工程门槛、窗口尺寸对齐——见 §6 教训）占了本轮大头墙钟；
  工具调用面本身极快：一轮切换 = 4 个 BRP 往返（约 2-3s），§7-2 一次 ui_input 往返。
  重试型 Brp-Call 全程零 keep-alive 卡顿（上轮 ⚪ 未复现，防御已标准化进脚本模板）。
- **净结论**：新工具把「不可驱动」变成「可脚本化」，dogfood 目的达成；工具面缺的是
  越界告警（见发现 1），结构发现面（折叠卡片的零尺寸子树）已可工作。

## 5. 脚本迁移（loop/qa，不入 git）

- `uitext.ps1` 头部加 **deprecated** 注记（被 `ui_tree` 取代，仅旧构建对照用）；
- `manual.md` 升 **v2**：§0 脚本清单带 v2 状态列（brp.ps1 保留基础设施但 Get-FlyCamera/
  Get-YawPitch 标注被 camera_state 取代；input.ps1 保留=真输入栈唯一手段；历史驱动脚本标注
  「方法已被 §7 取代，勿仿写」）；新增 **§7.5 真机沉淀**（窗口尺寸/控件本体/折叠卡/实体
  格式/过滤语义/禁触标题栏/直连派生/临时工程门槛八条，全部本轮实证）；
- qt 脚本模板：`t-qt-t2-qa-live.ps1` 的 `Brp-Call`（catch→250ms 退避重试）为标准模板，
  手册 §0 已注明 qt-*.ps1 必须带重试（上轮 ⚪ 落实）；本轮 t-qt-t2 系列脚本全部内置。

## 6. 发现

- ⚪ [T-QT 工具] `ui_click`/`ui_input` 在目标点越出窗口可拾取区时**静默落空**（返回
  `clicked:true` 但 picking 无命中）：默认 1280x720 窗口下 Inspector 输入列部分越界，
  打字零效果；`JACKDAW_WINDOW_SIZE=1920x1080` 后同一步骤立即生效（两轮 switch 输出对照）。
  建议 ui_probe 对 aim 点超窗给 INVALID_PARAMS 或 warning。
- ⚪ [环境/编辑器待查] 对 y=0 顶部条节点（如 [1142,0,46,34]）的合成点击**两次复现窗口缩为
  16x16**（GetWindowRect 实测 L=0 T=0 R=16 B=16，iconic=False），根因未查（自定义标题栏
  命中测试疑似）。与 T02-T1 diff 无关；手册已加「禁触 y<40」规约。
- ⚪ [工具] `ui_tree` 无过滤仅返回浅根；text 过滤返回命中子树的根而非文本本体，调用方需
  walk children（方法论已写入手册 §7.5）。
- ⚪ [工具] bevy BRP（world.*）实体格式 "NvM" 与 jackdaw BRP raw bits 不同构，跨方法换用
  需重建映射（手册已记，数据断言建议 world.query 全量表）。
- ✅ 正向：五轮切换+数值抽验全部数据级断言（world.query 真值）；不存盘策略 SHA256 双向
  校验通过；merge 树上门禁+新工具用例同场全绿。

## 7. 环境注记

- 上轮「harness 无法派生窗口进程」结论已过时：本轮 `cmd /c`（PATH 前缀 deps+toolchain lib，
  launch4 模式）+ 输出重定向 + 后台派生直接成功（dylib-host exe 三次稳定启动）；
  explorer ShellExecute 与 schtasks /IT 在本会话均失效（bat 未执行/返回 255），未再依赖。
- my-game 仅新增 `screenshots/tqt2-*.png`（BRP 截图落档），scene.bsn 与其余文件零改动。
