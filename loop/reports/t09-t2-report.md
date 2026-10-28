# T09-T2 实施报告：可配置生效全链 + 手柄死区

> 任务：`loop/plans/t09-input-actions.md` §二 T2（决策 3-A/4-A/5 已裁）。
> 分支 `loop/t09-actions`（自 main 96656896 拉出），4 文件改动 +220/−14（runtime/schema/schema_values/guards 注册）
> + 新 `tests/guards/game_input.rs`（6 用例）。未 push，未合入（待 QA）。

## 一、交付（三处缺口修复 + 全链测试）

任务书预判的「Vec 列表编辑对 GameInputBinding 的适配缺口」在实做中拆成三个真实缺口，全部修复：

### 1. schema 提取的 crate 过滤把 `GameInputConfig` 整体滤掉（最深一层）

`jackdaw_schema::extract_asset_types` 的 `is_project_crate` 排除一切 `jackdaw_` 前缀
crate——`jackdaw_runtime::game_input::GameInputConfig` 因此进不了工程 schema 的 assets 区，
编辑器 New Asset 列表没有该 kind，`asset.new` 拒绝：**编辑器内重绑定的第一公里断裂**
（真机第一轮即抓到：`nothing registers 'jackdaw_runtime::game_input::GameInputConfig'`）。

修复（`crates/jackdaw_schema/src/lib.rs`，新增 `asset_belongs_to_the_project`）：`jackdaw_runtime`
crate 的 **Asset 且带 `ReflectResource` data** 的类型（ConfigPlugin 配置资产族的判据：
`Asset + Resource`，如 `GameInputConfig`）豁免 crate 过滤进入 New Asset；无 Resource 标记的
Asset（`JackdawScene`，场景文件格式）保持内部（编辑器自己驱动，不该出现在 New Asset）。
root 的 crate 进 `crates` 集合后字段递归描述自动覆盖 `GameActionDef`/`GameInputBinding`
（卡片可编辑的前提）。影响面核对：runtime 全 crate 仅两个 Asset 类型，收窄为 1。

### 2. enum 单字段 tuple variant 的 serde JSON 形态被丢弃（Vec 元素静默消失）

真机第二轮抓到：`asset.set actions` 报告成功但盘上 `{"Key":"ArrowUp"}` / `{"MouseButton":"Left"}`
元素全部消失（Vec 的「不合型元素 drop-with-warning」语义吞掉了它们），只有 struct variant
`GamepadAxis` 存活。根因在 `schema_values::enum_bsn_for_json`：tuple variant 只认
array body（`{"Key":["ArrowUp"]}`），而 serde 标准形态（`"Key": "ArrowUp"` 单值直给）落入
`body.as_object()?` 返回 None。

修复（`src/schema_values.rs`）：variant 恰 1 字段且 body 非 object 时按单元素 tuple 解析——
两种拼写都建出同一 `BsnValue::TupleStruct`；struct/unit variant 形态不受影响。

### 3. T1 的手柄评估腿是死代码（bevy main 无全局 gamepad ButtonInput 资源）

排「手柄 PIE 可达性」（决策 5-A）时发现：bevy main 的 gamepad 管线**不再维护全局
`ButtonInput<GamepadButton>` / `Axis<GamepadAxis>` 资源**——状态移到每个 gamepad 实体的
`Gamepad` 组件（`digital`/`analog` 字段），由 `gamepad_connection_system` /
`gamepad_event_processing_system` 从 `RawGamepadEvent` 流维护。T1 的 `evaluate_actions`
读 `Option<Res<...>>` 永远 None——**手柄绑定从未被评估过**（T1 测试没覆盖该腿所以静默）。

修复（`crates/jackdaw_runtime/src/game_input.rs`）：`evaluate_actions` 的手柄参数改为
`Query<&Gamepad>`——任一手柄的按钮按下即按住动作（any-pad 语义，与 bevy 单 enum 按钮键
一致）；轴取各 pad 中**最大偏转**（多柄冲突取主导）。doc 记档该 bevy 数据模型事实。

### 4. 手柄 PIE 可达性结论链（决策 5-A 裁定：无需协议扩展）

- **PIE = 独立游戏进程**（编辑器 spawn），`maybe_windowless` 只 disable `WinitPlugin`
  （`pie_windowless.rs:57-77`），**`GilrsPlugin` 保留**——手柄由游戏进程 gilrs 直读系统设备，
  不经编辑器输入路由，无捕获/释放语义问题；
- 链路：gilrs → `RawGamepadEvent` message → `gamepad_event_processing_system`（用
  `GamepadSettings` 死区过滤后写入 `Gamepad` 组件）→ 本任务的 `Query<&Gamepad>` 评估；
- headless 合成事件红绿钉死全链（见 §二）；编辑器转发协议（I3）只涉键盘/鼠标，手柄无需扩展。

## 二、红→绿（headless，全部真红真绿）

| # | 用例 | 红 | 绿 |
|---|---|---|---|
| 1 | guards `a_rebinding_file_drives_the_actions_it_names`：真 writer（`write_asset_file`+`ReflectAsset::add`）落盘的重绑定文件驱动动作——文件表赢（ArrowUp 驱动 Move、W 不再、Escape 仍 Pause 并集） | —（首版编译错误修复后红：文件值未注入） | ✅ |
| 2 | guards `bevy_input_types_survive_the_editors_value_model`：`BsnValue::from_reflect` ↔ `bsn_value_to_reflect`+`from_reflect` 无损往返（值模型层） | — | ✅ |
| 3 | guards `a_partial_file_merges_and_carries_its_deadzone`：并集合并 wire 语义（同名覆盖/缺省回落/死区随绑定走） | — | ✅ |
| 4 | guards `the_files_deadzone_reaches_the_engine_gamepad_settings`：**死区链路文件驱动腿**——编辑器保存的 0.5 死区进引擎 `GamepadSettings`（±0.5，唯此一轴显式、其余走引擎默认 0.15） | — | ✅ |
| 5 | guards `the_editors_writer_lands_the_same_form_the_game_reads`：盘上形态（header 全 type_path/LeftStickX 在场）+读回驱动 | — | ✅ |
| 6 | guards `the_runtime_config_assets_reach_the_new_asset_list`：**缺口 1 红绿**——runtime 配置资产过 crate 过滤、绑定 enum 被描述 | `[]`（整体滤掉） | ✅ |
| 7 | 主 crate `a_serde_shaped_single_field_variant_takes_its_value_directly`：**缺口 2 红绿**——serde 直给形态建 tuple variant（wrapped/struct/unit 不受影响） | `None`（被拒） | ✅ |
| 8 | runtime `gamepad_events_reach_the_actions_through_the_component`：**缺口 3 红绿**——合成 `RawGamepadEvent`（gilrs/PIE 转发同流）驱动 Move(0.8 过死区)/Jump(South)；死区内 0.1 无贡献 | main 形态回退模拟红（Res 死读，事件全不到） | ✅ |

- 红证形态说明：#8 用「main 形态 mock」（evaluate_actions 保留新签名但内部换回 `Option<Res>`）
  跑红再还原——main 上该腿无任何测试且 API 已不存在，回退模拟是唯一可行红证（T07-T2 P5 先例）。
- 死区行为腿（引擎过滤而非仅 settings 安装）由 #8 的 0.1-in-deadzone 断言覆盖。

## 三、真机五项清单（QA 补列，一次跑齐）

**环境状况：编辑器全程无冻结（5 轮真机全通，环境窗口良好）**——前两次中断均为脚本/代码
缺口（见 §一 1/2），非环境事件，不触发降级口径。脚本 `loop/qa/t09-t2-live.ps1`（BRP 驱动，
日志 `loop/t09t2-live/`）。工程：`jd new` 新模板工程（path 依赖本分支 runtime），
`H:\workspace_AI\t09t2-live\t09t2-game`（保留供 QA 复跑）。

| 项 | 内容 | 结果 |
|---|---|---|
| ①改绑三态 | `asset.new`（New Asset 列表出现 "Game Input Config"）→ `asset.set actions`（serde JSON：方向键+左摇杆 0.5 死区+LMB Jump）→ `asset.save` 盘上完整形态 → Play → **ArrowUp 按住 dz=−11.9 驱动 PlayerMarker；W 按住 dz=0（文件表赢了）** | **PASS** |
| ②capture 生命周期 | `pie.play_input_toggle` 激活→转发通；**Shift+Esc 真弦**（input.key 合成走 collect_forwards 释放分支）→ArrowUp 不动（dz=0）；再 toggle→又动（dz=−11.9） | **PASS** |
| ③手柄 PIE 可达性 | 本机 `Win32_GamePad` **0 设备**（无实体手柄）；机制级证据链齐（§一-4 结论链+§二 #8 合成事件红绿+窗口期 5 轮 PIE 进程稳定） | **PASS（机制）/实体腿挂账**（无硬件） |
| ④PlayerMarker 行为断言 | `scene_snapshot` 两帧差（投影 20 实体，按初始位 (-2,0.5,0) 定位 marker；基线静止帧对照） | **PASS** |
| ⑤I3 mouse 事件级抽验 | capture 激活下 `input.motion dx=240`（24 帧合成 MouseMotion 流）→游戏 Look 驱动 PlayerMarker yaw，**delta=−0.932**（=sin(240px×0.01×N/2) 量纲精确吻合）；键盘腿同链已通 | **PASS** |

## 四、门禁（quick 四门，归档 `loop/t09t2_*`）

| 门 | 结果 | 归档 |
|---|---|---|
| fmt | clean（一次 `cargo fmt` 后 0 diff） | `t09t2_fmt.log` |
| clippy workspace all-targets `-D warnings` | clean（修 2 处 doc-markdown backticks 后过） | `t09t2_clippy.log` |
| 单测 | 主 crate lib **1176/0**（+1 enum 形态）、guards **210/0**（+6 game_input）、runtime **38/0**（+1 合成事件）、scaffold **82/0**、schema 等其余全绿 | `t09t2_lib.log`/`t09t2_guards.log`/`t09t2_crates.log` |
| 集成（nextest，T08 同款排除集） | **5235 passed / 0 failed**（2 skipped 既有 ignore，347s） | `t09t2_integration.log` |

真机归档：`loop/t09t2-live/`（editor-std*、`loop/qa/t09-t2-live.ps1` 逐轮输出在
`H:\workspace_AI\t09t2_*.log` 之外未另存——脚本 stdout 即五项判定行，QA 复跑脚本可得）。

## 五、偏差与记档

1. **三个缺口都是任务书「适配缺口」的子层**：预判的「Vec 列表编辑适配」实为
   schema crate 过滤（更前置）+ enum serde 形态（更深层）两处；另发现 T1 手柄评估腿死代码
   （bevy main 数据模型变化，T1 报告 §二记档了 GamepadSettings 组件化但漏了读侧资源不存在）。
   三处均有独立红绿。
2. **③实体手柄腿挂账**：本机无手柄（0 设备）。合成事件链（与 gilrs 同一流）已红绿钉死，
   windowless 保留 GilrsPlugin 有代码实证；接实体手柄复验挂 open-challenges/环境恢复后。
3. **`asset.new` 的 schema watcher 时序**：schema 刷新可晚于 idle（T08 QA ⚪ 教训重演），
   脚本侧以轮询吸收；「idle 放行≠kinds 就位」建议记 buglist backlog（编辑器侧可考虑
   启动时对现有 schema.json 做一次初始刷新——watch_project_schema 只监听变化）。
4. **guards 测试的 editor 侧注册**：`editor_saves_rebinding` 在 editor_test_app 里
   `init_asset::<GameInputConfig>()`（编辑器 world 无该类型注册），与模板游戏侧注册同构；
   真机 PIE 下类型注册来自游戏进程 schema，两侧路径不同但 writer/read 形态同一（本测试钉形态）。
5. **I3 mouse 腿的量纲验证**：yaw delta −0.932 与 240px×0.01×~24 帧的合成角精确吻合，
   非仅「非零」的弱断言。

## 六、buglist

无打钩项（本轮新发现均为任务内缺口，非 I/W 系遗留；watcher 时序 ⚪ 见 §五-3 建议）。
