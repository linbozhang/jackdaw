# T09 游戏 Input Action 配置 — 实施方案

> 策划产物（2026-10-28，基于本地 main **9a874945**（T08 闭环点 = P1 第一项基线）全量代码只读调研；
> 不建分支、不改代码）。需求来源：`loop/plans/roadmap-game-dev.md` T09（P1 第二项，T01-T08 已全部闭环）。
> **验收原文**（roadmap 第 21 行，已核实）：「游戏侧动作系统（键盘/鼠标/基础手柄），动作名+绑定+轴+死区+保存。
> **验收=Move/Look/Jump/Interact/Pause 可配置生效；不与编辑器键位混用。**」
> 注意：派发任务书转述为「不与编辑器键位**冲突**」，原文是「不与编辑器键位**混用**」——混用语义更宽
> （既要求冲突消解，也要求两套键位资产/链路不互相污染），本方案以原文为准。
> buglist 输入域直接重叠条目少（W27/Y36 是**编辑器旧键位链路**的债，与游戏侧动作配置不同链）；顺手补齐的
> 是**方案新发现的捕获态鼠标维度缺口**。方案内新发现编号 **I1–I7**（Input，避免与 buglist N 系撞名）。
> 附带前置评估：T08 两项补验条件（progress.md 2026-10-27 条目）建议并入 **T0 轻量前置**（见二、）。

---

## 0. 架构事实（核实结论，方案的地基）

**「游戏输入」在 jackdaw 里=一条已建成的 PIE 转发链 + 零游戏侧动作抽象 + 现成的配置资产机制**。
五条事实决定方案走向：

- **事实一：PIE 输入转发链两侧齐备，「不混用」的键盘维度机制已存在且有测试钉死**。Play 默认
  Embedded 模式（游戏无 OS 窗口，帧流入 Game panel；`PieWindowMode`，`src/pie.rs:642-655`，
  Windowed 是 debug fallback、无输入捕获）。输入路径：
  - 编辑器侧：Game panel 点击/header 按钮激活捕获 `LiveInputCapture`（`src/live_input.rs:27-38`），
    `LiveInputPlugin` 在 Update 链式跑 `collect_forwards → auto_release → apply_release_requests →
    flush_forwards`（`src/live_input.rs:331-348`）；Shift+Esc 硬释放、plain Esc 照常转发（游戏菜单可用）、
    释放路径合成全部 key-up/button-up 不留卡键（模块文档 `src/live_input.rs:1-9`）。
  - 协议：`PieInputEvent`（Key/MouseButton/CursorMoved/MouseMotion/MouseWheel/FocusGained/FocusLost，
    `crates/jackdaw_pie_protocol/src/input.rs:15-38`）走可靠有序通道，bevy 输入类型直接 serde，无损。
  - 游戏侧：`apply_input`（`crates/jackdaw_runtime/src/pie.rs:482-603`，`pie.rs:346` 分发）把事件注入
    虚拟窗口 `PieVirtualWindow` 的标准 bevy 事件流（KeyboardInput/MouseButtonInput/CursorMoved/
    MouseMotion/MouseWheel + picking pointer）——**ButtonInput/UI/picking 全部像真窗口一样工作**；
    Windowed fallback 无虚拟窗口则忽略转发（`pie.rs:489-493`，彼时游戏有真 OS 窗口自己收输入）。
  - 混用消解：捕获态 `disable_keyboard_input_when_typing` 把 `InputSources.keyboard` 置 false
    （`src/keybind_focus.rs:75-90`，:89），编辑器 action 键位全部压制，**已有单测**
    `capture_active_suppresses_action_keybinds`（`:96-122`）。
  - **缺口**：`InputSources { keyboard, mouse }`（`crates/jackdaw_input/src/lib.rs:382-395`）——捕获态
    只关 keyboard，**mouse 维度恒 true**（`evaluate.rs:154-177` 消费），鼠标维度的混用未钉死（I3）。
    **Gamepad 无 `PieInputEvent` 变体**（I4）。
- **事实二：游戏侧零动作抽象、零输入教学**。模板 `lib.rs.template`（T08 后全文 1-165 行）只有
  `spin_cubes`/`falling_cubes` 两个展示系统，无任何 `ButtonInput`/键盘/手柄读取；游戏开发者当前只能
  每游戏裸写 bevy Input 直询。编辑器的 `jackdaw_input` crate 是一个**实体化动作框架**（InputContext/
  Action/Binding + 优先级/consume/TriggerState/ActionValue，`crates/jackdaw_input/src/lib.rs:1-22`），
  但它是编辑器进程内评估的：`Binding` 枚举只有 Keyboard/MouseButton/MouseWheel/MouseMotion 四变体
  **无 gamepad、无死区、无持续轴语义**（`:230-246`）；编辑器键位数据形态 `PresetInput` 同样只有
  Key/MouseButton/Scroll 三变体（`crates/jackdaw_api_internal/src/keymap/types.rs:10-52`），存的是编辑器
  **全局 config 目录** keymap.json（`keymap/persist.rs:232-235`），per-user 不进工程/导出包——两条都不
  能直接当游戏动作表用。
- **事实三：T08 配置资产机制两侧全链现成，动作表可以零机制建设复用**。`ConfigPlugin::<T>::new(path)`
  一行注入（build 期先插 default 防竞态、资产 walk 后一次/进程覆盖、缺文件 default+恰一条 warn，
  `crates/jackdaw_runtime/src/config.rs:101-135,147-209`）；schema-backed 资产卡片**支持 Vec 列表字段
  编辑**（列表行 + 增删按钮 + enum variant 菜单，`src/inspector/schema_fields.rs:5,69-73,160-246`）——
  「动作名+绑定」的 Vec 结构有现成编辑面；Play（`BEVY_ASSET_ROOT`=项目根）/cargo run/导出 exe 读同一
  文件（「文件即真相」）；dirty 资产卡三腿保护（Play/导出前自动保存+退出对话框）、scene_snapshot 行为
  断言通道（T08-T2 修好接线）全部在位。
- **事实四：手柄零使用、但后端常驻+bevy 原生死区在**。全仓无任何 Gamepad 功能代码（4 处 gamepad 字样
  =UI 图标与 Linux 构建提示：`src/inspector/modifier_display.rs:134`、`build_tools.rs:262` 等）。workspace
  bevy（pin c9c397b）**default features 含 `bevy_gilrs`**（bevy Cargo.toml:190/320）→ 模板游戏子进程经
  scaffold 内嵌 lock 快照同用该树，**gilrs 后端在游戏进程内常驻**——gilrs 独立线程读设备、不依赖窗口
  焦点，Embedded 模式下手柄事件大概率直达游戏进程（多进程读取在 Windows.Gaming.Input 下通常可行，
  **未真机验证，列为 T2 调查项**）。bevy 原生死区：`GamepadSettings`/`AxisSettings`（deadzone bounds）/
  `ButtonSettings`（`bevy_input/src/gamepad.rs:744,828,992`），事件分 Raw 与过滤后两层——死区有现成
  引擎机制，缺的只是作者态配置面。
- **事实五：QA 合成输入可以驱动游戏子进程（测试面大利好，无需 OS SendInput）**。BRP `input.key`/
  `input.text`/`input.motion` 是**进程内合成**（`src/test_input.rs`，SyntheticInput 队列在 `First`
  schedule 播放 write_message，`:73-74`；手册 `loop/qa/manual.md` §3/§7）；`collect_forwards` 在
  `Update` 读同一条编辑器事件流（`MessageReader<KeyboardInput>` 等）——**时序上 First 注入 → Update
  读取转发成立**：合成键盘/鼠标事件经捕获态转发直达游戏虚拟窗口。行为断言走 `jackdaw/scene_snapshot`
  投影（两帧 Transform 差，T08-T2 已实测 gravity 腿精确加倍）。手柄无合成通道（游戏侧 BRP 被
  Y33(CORS)/N12(域不通) 挡），headless 用 Raw 事件注入驱动 bevy 过滤链。

---

## 一、现状与缺陷矩阵

### A. 游戏侧动作系统（验收句主体）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **I1** | 🔴 | **游戏侧零动作抽象**：无「动作名→绑定→轴值→死区」的求值层；模板无输入教学；每游戏裸写 `ButtonInput` 直询，键鼠/手柄/轴各自为政。验收句五动作（Move/Look/Jump/Interact/Pause）在游戏里没有统一读法；T11 玩家控制器、T12 暂停菜单、T17 玩家设置全部需要这一层 | `lib.rs.template:1-165`（零输入）；`crates/jackdaw_input`（编辑器专用，Binding 无 gamepad `:230-246`） |
| **I2** | 🔴 | **动作配置无作者态载体**：无「动作名+绑定+轴+死区」数据结构，游戏侧无法在编辑器配置并保存（改键/调死区只能改代码重编译）。T08 配置资产机制现成但模板没有动作表示例 | 全仓无此类类型；`config.rs:101-135`（机制闲置面）；roadmap T09 验收句 |

### B. 编辑器/游戏输入边界（「不混用」验收句）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **I3** | 🟡 | **捕获态鼠标维度未压制**：`capture.active` 只关 `InputSources.keyboard`，`sources.mouse` 恒 true——捕获中（游戏正在收 RMB/LMB/MMB 转发）编辑器自己的 mouse action bindings 仍评估。实际影响被 UI hover 门部分掩盖（鼠标通常在 Game panel 上），但「不与编辑器键位混用」的鼠标腿未钉死。UI picking 不走 InputSources，关掉 mouse 不影响捕获态点 Stop 按钮/面板 | `keybind_focus.rs:89`（只写 keyboard）；`jackdaw_input/src/lib.rs:382-395`；`evaluate.rs:154-177`（mouse 消费点） |
| **I4** | 🟡 | **手柄链路未验证+死区无配置面**：①`PieInputEvent` 无 gamepad 变体，Embedded 下手柄依赖 gilrs 进程内直读（假设未验证，见事实四）；②死区只有 bevy `GamepadSettings` 代码默认值，无作者态配置（验收句「死区」落空）；③轴（摇杆→Move/Look）无绑定与求值层 | `input.rs:15-38`（无变体）；`gamepad.rs:744/992`（引擎机制在）；全仓零消费 |
| **I5** | ⚪ | **捕获语义的可发现性**：捕获（点击 Game panel）→Shift+Esc 释放的模型已实现且自动释放兜底齐全，但游戏侧无从得知这套模型（模板不教）；游戏若绑 Esc（Pause 常用）与 plain-Esc 转发设计是**正确组合**（Esc 转发给游戏、Shift+Esc 才释放），此边界模板必须写明否则开发者会误以为 Esc 被编辑器吞 | `live_input.rs:1-9,63-65`；模板无说明 |
| **I6** | ⚪ | **改绑定后热生效无机制**：ConfigLoader 一次/进程语义（T08 同款）；Play 中改动作资产→运行中游戏不变，需 stop→play。属设计边界而非缺陷（Live 热调参是 T25 领地），需在 book 钉死预期 | `config.rs:147-209`；roadmap T25 |

### C. 测试与断言面

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **I7** | ⚪ | **手柄无合成注入通道**：键盘/鼠标合成输入→capture→游戏的链路成立（事实五），手柄无对应工具；物理手柄依赖 QA 机器有无设备。headless 可用 Raw 事件注入驱动 bevy 过滤链测死区数学；真机手柄格按 MCP 优先评估补通道（决策 5） | `test_input.rs`（无 gamepad）；Y33/N12（游戏侧 BRP 两道坎，t08 方案 §一.C 已知） |
| — | ✅ | **正向资产（不用重建）**：PIE 输入转发全链（协议/注入/捕获/自动释放）；键盘混用消解 gate+单测；`ConfigPlugin` 一行注入；schema 卡片 Vec 列表编辑+enum 菜单；dirty 资产三腿保护；`asset.*` 九 op 全套 BRP 可驱；`jackdaw/pie`/`scene_snapshot`/`jackdaw/export`/`jackdaw/wait`；MCP 25 工具含 `input.key`/`input.motion`/`ui_tree`/`ui_click`；bevy gilrs+GamepadSettings 引擎机制 | 事实一/三/四/五 |

**统计：🔴 2（I1、I2）｜🟡 2（I3、I4）｜⚪ 3（I5、I6、I7）｜✅ PIE 转发链+配置资产机制+合成输入链三块地基**

### buglist 重叠表（输入/键位/手柄/焦点域全量扫描）

| 条目 | 一句话 | T09 处置 |
|---|---|---|
| **W27** | 旧键位链路对表外按键序列化丢数据（`key_from_display_name("???")`→None 静默回默认） | **不吸收**：编辑器旧 keybinds 链路的债；T09 游戏动作配置走配置资产新链路（bevy 原生类型字段反射序列化，不经 display_name 往返），不受此缺陷影响。备注维持 |
| **Y36** | 旧版键位文件把全部默认绑定一起落盘，默认键位变更无法触达老用户 | **不吸收但吸收其教训**：编辑器旧链路的债；T09 动作资产若也全量落盘会有同款病——决策 1-A 修正为「加载时并集合并」（表内覆盖代码默认、缺失条目回落代码默认），结构上治同款病 |
| Y14 | `LastPressedPanel` 幽灵面板影响键位可用性 | 不吸收（编辑器面板焦点域，与游戏输入无交集） |
| Y37 | PIE 每帧全量反射 JSON 序列化（性能） | 不吸收；T09 行为断言依赖该投影流，知悉其性能账 |
| N11 | Inspector 合成提交工具缺口 | 不吸收（T06 尾巴②已排期；T09 卡片编辑走 `asset.set` op，无需 UI 合成输入） |
| N12/Y33 | BRP 实体域不通/游戏侧 BRP CORS | 不吸收；游戏侧断言继续走投影域（`scene_snapshot`）+行为断言，按域选方法知悉（T08 同款裁定） |
| R13 | 视口右键旋转延迟（用户亲测） | 不吸收（视口相机域，非游戏输入） |

> 如实报告：与「游戏输入」直接重叠的 buglist 条目为零——该域从未建设过（事实二）；T09 的缺陷主体是
> 本方案新发现的 I1-I7。W27/Y36 的**教训**（全量落盘病、display-name 往返丢数据病）已内化进决策 1。

---

## 二、分任务拆解（T0 前置 + T1/T2/T3）

### T0「T08 两项补验条件执行」（前置，轻量 QA 性，非代码任务）

**背景**（progress.md 2026-10-27 T08-T3 条目）：终验时环境事件（编辑器加载停 4-15min）致两项降级，
落账为「并入 T09 前置或用户 30 秒清单」：①机器空窗补跑 `loop/qa/t08-t3-qa.ps1`（脚本已在库，覆盖
C2 重启一致/C7 导出腿的独立抽验）；②T08-T3 评审②主路径（PIE stop 后资产卡关卡行为修复效果）补验。

**执行方式**：T09-T1 开工**前**、在 main 工作区（未叠加 T09 改动）跑：①整脚本一遍，PASS 标准沿用
t08-t3-qa.md 的口径；②补验腿=dirty 资产卡 → play_current → stop → 资产卡仍开且值未变（对应
57aa302d 的 `drop_a_file_the_selection_left` 修复）。两腿各自留档（日志入 `loop/reports/`）。
**失败处置**：若补跑 FAIL，按 T08 遗留缺陷回流处理（不并入 T09 代码任务，单独回流修复轮），T09 是否
继续由主控裁定。**耗时预估**：30-60 分钟（机器空窗即可），不建分支零代码。

### T1「游戏动作系统核心 + 模板教学 + 混用消解补齐」（I1+I2+I3+I5；决策 1/2/3/6）

**目标**：游戏获得「动作定义（配置资产）→ 注入（ConfigPlugin）→ 求值（InputActions 系统）→ 消费
（模板示例）」完整链；模板开箱即有 Move/Look/Jump/Interact/Pause 五动作默认绑定与可观察行为；捕获态
鼠标维度补压制，「不混用」两维度（键盘/鼠标）都钉死。

**改动面预估**：
1. **runtime 动作求值层（`crates/jackdaw_runtime` 新模块 `game_input.rs`）**：
   a) 数据类型（`Asset + Resource + Reflect + Clone + Default` 双 derive，对齐 `GameConfig` 模式）：
      `GameInputConfig { actions: Vec<GameActionDef> }`；`GameActionDef { name: String,
      kind: GameActionKind（Button/Axis2D/Delta2D）, bindings: Vec<GameInputBinding> }`；
      `GameInputBinding` 为 enum：`Key(KeyCode)` / `MouseButton(MouseButton)` /
      `MouseMotion`（Look 用） / `GamepadButton(GamepadButton)` /
      `GamepadAxis { axis: GamepadAxis, deadzone: f32 }`——**bevy 原生类型字段**（workspace bevy 开
      `serialize`，类型安全、schema 卡片渲染 variant 菜单，不经 display-name 往返=避开 W27 病）；
   b) 求值系统 `InputActionsPlugin`（挂 `Update`）：读 `GameInputConfig` Resource（ConfigPlugin 注入
      后）+ `ButtonInput<KeyCode>`/`ButtonInput<MouseButton>`/`MouseMotion` 累计/
      `ButtonInput<GamepadButton>`/`Axis<GamepadAxis>`，产出 `GameActions` Resource
      （`HashMap<String, GameActionState>`：pressed/just_pressed/just_released/value: Vec2——Axis2D 多键
      合成、Delta2D 累计鼠标 motion 与手柄轴、死区过滤在轴读数处应用并同步写入 bevy
      `GamepadSettings`，见决策 4）；**加载时并集合并**：代码内默认动作表（`Default` 实现，五动作）
      与资产文件求并集——文件覆盖同名动作，文件缺的动作回落代码默认（治 Y36 同款「全量落盘病」，
      决策 1 修正项）；
   c) runtime 零新依赖，纯 bevy_input 既有类型；
2. **模板教学面（`lib.rs.template`）**：
   a) 注册 `GameInputConfig`（`init_asset` + `register_asset_reflect` + `ConfigPlugin::<GameInputConfig>
      ::new("input-actions.bsn")` 三行，与 GameConfig 并排）；**默认绑定表写在类型 `Default` 里**
      （文件缺省时游戏照跑）：Move=KeyW/A/S/D+左摇杆、Look=MouseMotion+右摇杆、Jump=Space+South、
      Interact=KeyE+East、Pause=Escape+Start（Esc 与捕获释放 Shift+Esc 是正确组合，注释写明）；
   b) 消费示例系统（对齐 FallingCube 风格，约 15 行）：`PlayerMarker` 实体——`Move` 的 Axis2D 驱动
      XZ 平移、`Look` 的 Delta2D 驱动 Y 旋转、`Jump`/`Interact` just_pressed 计数进 Resource（可断言）、
      `Pause` 切换 `GamePaused` Resource（时间缩放或日志可见）；doc 注释补「# Input actions」一节：
      编辑器打开 `input-actions.bsn` 卡片改绑定 → Save → Play 生效；捕获模型（点击 Game panel 捕获、
      Shift+Esc 释放）一并写明（I5）；
3. **混用消解补齐（I3，一行级）**：`disable_keyboard_input_when_typing`（`keybind_focus.rs:89`）的
   赋值扩为 `sources.mouse = ... && !capture.active` 同步关鼠标；单测扩一腿（mouse false 断言）；确认
   UI picking 不受影响（evaluate 只 gate action bindings，UI 点击走 picking 事件流）——捕获态点
   Stop 按钮/Game panel 的编辑器 UI 仍可用；
4. **编辑器侧零改动验证**：schema-backed 卡片对 `Vec<GameActionDef>` 的列表编辑（增删行+enum 菜单）
   来自既有机制，T1 真机证明一次全链即可。

**验收标准（可执行可复现）**：
- [ ] headless 红→绿①（求值层）：无 `InputActionsPlugin` 的 App 上 `GameActions` 不存在（红半）；
  注册后注入 `GameInputConfig`（Move 绑 KeyW）+ `ButtonInput<KeyCode>` press KeyW → `GameActions`
  读 Move.value == (0,1)；改绑 KeyCode::ArrowUp（另一配置值）→ 同输入下 Move 无、ArrowUp 有——
  **「可配置生效」的机制层红绿**；
- [ ] headless 红→绿②（并集合并）：资产文件只含 Move 一条 → `GameActions` 含全部五动作（其余四条
  来自代码默认），Move 用文件值其余用默认值；文件含全部 → 全文件值（Y36 病的反证用例）；
- [ ] headless（手柄腿机制）：`write_message(RawGamepadAxisChangedEvent)` 驱动 bevy 过滤链 →
  死区内原始值被滤为 0、死区外线性缩放（bevy AxisSettings 语义）；`GamepadButton` press → 动作
  just_pressed（GamepadPlugin headless 可跑，事件注入模式）；
- [ ] headless（I3）：capture.active → `InputSources.mouse == false`；UI picking 事件（PointerInput）
  照常（不受 InputSources gate 的影响断言）；
- [ ] 模板：scaffold 测试族扩展（含 GameInputConfig/InputActionsPlugin/五动作默认表，实编 cargo
  check 先例）；
- [ ] 真机（BRP 全链，MCP 优先）：模板工程 → `pie.play_current` → `jackdaw/pie` running → 合成
  `input.key key=W` 按住 400ms（捕获态自动激活或 `call_operator` pie.play_input_toggle 先激活）→
  `scene_snapshot` 两帧差：PlayerMarker 沿 +Z 位移与配置 move 速率一致 → `input.key key=Escape` →
  Pause 断言（时间缩放后 FallingCube 位移停止/或 Resource 投影）——**合成输入→capture→游戏→行为
  断言的端到端首证**（事实五链路实测）；
- [ ] 真机（不混用·键盘）：捕获态合成 `input.key key=F5`（编辑器 Play 键位）→ `jackdaw/status` 或
  探针断言编辑器键位无动作（无新 play/无 fly）且游戏收到该键（Look/动作无扰动断言）；未捕获态
  F5 正常触发 play_current（回归）。

**测试设计**：runtime `game_input.rs` 内嵌单测（求值/并集/死区三组）+ guards 新
`tests/guards/game_input.rs`（编辑器 emit 资产形态↔runtime 读往返，复用 T08 config_injection 模式）；
真机脚本沉淀 `loop/qa/t09-input-play.ps1`。**buglist 吸收**：无打钩（I 系新发现）。

### T2「可配置生效全链 + 手柄与死区真机面」（I4+I7；决策 4/5）

**目标**：验收句「可配置生效」的三态铁证（改绑定→重启/Play/导出一致）+「基础手柄」的真机闭环
（或结构化兜底）+死区可配置生效的直接证据。

**改动面预估**：
1. **改键三态链（纯验证，零新代码）**：`asset.set` 改 `input-actions.bsn` 的 Move 绑定（W→ArrowUp）→
   `asset.save` → 盘上 bsn 文本断言 → `pie.play_current` → 合成 ArrowUp → PlayerMarker 位移方向
   断言（+X 而非 +Z）→ stop → 改回 → 再 Play 行为随文件变（注入真的在读文件）；
2. **手柄 PIE 可达性调查（决策 5-A，先行）**：真机连手柄（用户环境有则用，无则借/或 xviaz 虚拟手柄
   驱动一次性验证）→ Embedded Play → 观察 `GameActions` 是否收到手柄输入（行为断言）。结论二选一：
   - gilrs 直读成立 → 手柄链零协议改动，book 记录该边界（编辑器与游戏同时读设备，事件双达但编辑器
     无 gamepad 消费=无混用）；
   - 不成立 → **协议扩展兜底**：`PieInputEvent` 尾部加 `Gamepad { event: ... }` 变体（serde enum
     加法，旧序兼容）+ 编辑器侧 gilrs 事件转发（`collect_forwards` 扩）+ runtime `apply_input` 扩
     ——改动面约 3 文件，行为对齐键鼠转发；
3. **QA 手柄合成通道（MCP 优先，决策 5-B）**：无论 2 结论如何，若 QA 机器无手柄，补
   `PieInputEvent` 合成通道的价值在「手柄格可自动化」——按 MCP 优先流程走小任务立项：编辑器侧
   BRP `input.gamepad`（写入转发队列，`test_input.rs` 扩）→ capture 链 → 游戏。工具本身过门禁+测试；
   若主控裁定不立项，手柄真机格降级为「headless 机制层+用户 30 秒清单」（物理手柄手测）；
4. **死区可配置生效**：headless 数学用例（T1 已有）+ 有设备/合成通道时：死区 0.5 → 摇杆推 30%
   → Move 无位移；死区 0.1 → 同推力有位移（两次行为对比断言）；
5. **导出腿**：`game.export` → dist 内 `assets/input-actions.bsn` 值=编辑值 + manifest 含该文件
   （T07 工具复用，配置资产天然进包=决策 1 红利）。

**验收标准**：
- [ ] 真机：改键→Play 行为变（2.1 的方向断言红绿）；改回→恢复；
- [ ] 真机：改绑定重启编辑器 → `asset.get` 同值 → Play 行为同值（三态①②）；导出 dist 值一致
  （三态③）——三态各有独立断言（文件+行为+dist）；
- [ ] 手柄：调查结论留档（成立/不成立+证据）；成立则真机摇杆驱动 Move+死区对比两格过；不成立则
  协议扩展实现+同两格过（合成通道驱动）；
- [ ] headless：死区数学（Raw 注入→滤后值）红线用例；
- [ ] 缺文件兜底：删 `input-actions.bsn` → Play 仍跑（代码默认五动作）+ 恰一条 warn + 行为=默认
  绑定（合成 W 位移）——「缺配置不是错误」语义对齐 T08。

**测试设计**：真机脚本 `loop/qa/t09-rebind.ps1`/`t09-gamepad.ps1`；协议扩展（若做）加 runtime 单测
（变体往返 serde + 注入行为）。**buglist 吸收**：无。

### T3「验收矩阵 + 文档收尾」（I5+I6 文档面+全任务终验）

**目标**：验收句「Move/Look/Jump/Interact/Pause 可配置生效；不与编辑器键位混用」的终验矩阵
（全 BRP/MCP 驱动）；book 输入节；边界钉死；roadmap 勾选。

**改动面预估**：
1. **真机验收矩阵**（截图+日志留档 `loop/reports/`，模板工程 fixture）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 默认动作表 | 新工程 `asset.get input-actions`（或新建卡片）→ 五动作默认绑定在（含键盘+鼠标+手柄三类绑定源） |
| 2 | **键盘改键生效** | Move 改绑 ArrowUp（`asset.set`+save）→ Play → 合成 ArrowUp → 位移方向断言（T2 链复跑一格） |
| 3 | **鼠标绑定生效** | Jump 改绑 MouseButton::Left → Play → 合成 LMB press → Jump 计数 Resource 断言（投影/行为） |
| 4 | **Look 生效** | 合成 `input.motion dx=200` → PlayerMarker Y 旋转变化量断言（两帧快照差） |
| 5 | **Interact/Pause 生效** | 合成 KeyE → Interact 计数；Escape → GamePaused 翻转 + FallingCube 停止位移（时间缩放行为断言） |
| 6 | **手柄+死区** | 有设备/合成通道：摇杆驱动 Move + 死区 0.5/0.1 对比断言；无设备：headless 机制层证据+用户清单降级（如实记档） |
| 7 | **三态①重启** | 改绑定 → kill/重开编辑器 → `asset.get` 同值 → Play 行为同值 |
| 8 | **三态③导出** | dirty 卡+`game.export` → dist `input-actions.bsn` 值=编辑值 + manifest 含该文件 |
| 9 | **不混用·捕获态** | capture 中合成 F5/WASD/RMB → 编辑器键位零动作（status/探针）+ 游戏收到（行为断言）；鼠标维度 I3 修复后 mouse bindings 同断言 |
| 10 | **不混用·未捕获态** | Play 运行中（未捕获）合成 WASD → 编辑器视口 fly 激活（BRP 断言 fly 态，T01 纪律：必须确认激活）+ 游戏 PlayerMarker 位移为零 |
| 11 | 缺文件兜底 | 删资产 → Play 跑在代码默认上 + 恰一条 warn |
| 12 | Stop 铁证回归 | T06 Stop 链复跑：scene SHA/资产文件 SHA 不变、temp 清理——动作链零污染 |

2. **book 文档**：新节「Game input」（或并入 game-parameters 节扩为 Game config）：动作资产工作流
   （New Asset→卡片改绑定→Save→Play）、五动作默认表导览、捕获模型（Game panel 点击/Shift+Esc/plain
   Esc 归游戏）、手柄边界（gilrs 直读结论 or 协议转发说明）、死区语义（bevy AxisSettings 线性缩放）、
   「改绑定 stop→play 生效」边界（I6，热生效挂 T25）、并集合并语义（文件覆盖+默认回落，Y36 教训）；
3. **工具面核对（MCP 优先评估结论）**：现有 25 工具+22 BRP 方法**基本足够**——`asset.*`（改配置）、
   `input.key`/`input.motion`（合成键鼠→capture→游戏）、`jackdaw/pie`/`scene_snapshot`（行为断言）、
   `jackdaw/export`（三态③）。**唯一缺口=手柄合成**（I7）按 T2-3 流程裁定量；不硬耗；
4. buglist 核对（无打钩预期）、roadmap T09 勾选、台账记行（含 T0 补验结果）。

**验收标准**：
- [ ] 矩阵 12 格全过（无设备降级格如实标注，不虚报）；
- [ ] 全量门按 2026-10-25 升级版门禁证据标准（日志全文复核、重跑覆盖归档）；
- [ ] 用户 30 秒清单：①模板工程 Play → 点 Game panel 里画面 → WASD 走、鼠标转、Space 跳、Esc 暂停
  （FallingCube 停）；②把 Move 的 W 改成方向键上（卡片编辑）→ Save → 再 Play → 方向键走 W 不走；
  ③手柄（若有）：摇杆走、推一点点不动（死区）、Start 暂停。

**QA 清单（放行标准，全任务）**：
- [ ] T0 两补验腿留档（PASS 或回流处置）；T1/T2/T3 各自验收全绿；I1/I2 各有机制层红→绿；
- [ ] 「可配置生效」铁证：至少一个动作的改绑定在「编辑器改→文件→行为」三点闭环（格 2 红绿），
  且五动作各有生效证据（格 2-6）；
- [ ] 「不混用」铁证：捕获态编辑器零动作+游戏收到（格 9）、未捕获态编辑器动作+游戏零输入（格 10）
  双向都钉死；I3 修复有 mouse 维度断言；
- [ ] T01/T06/T07/T08 既有防线回归：fly 断言纪律（格 10）、Stop 铁证（格 12）、导出 manifest（格 8）、
  dirty 资产三腿（格 8 前置）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **动作配置载体形态** | A=**配置资产同族**（`GameInputConfig`: Asset+Resource 双 derive，assets 下 `input-actions.bsn`，`ConfigPlugin` 一行注入）：复用面最大——New Asset/卡片（Vec 列表+enum 菜单现成）/asset.* op/dirty 三腿保护/write_atomic/T05 rename/导出全包免费；「文件即真相」→重启+Play+导出三态一致是结构保证；**修正项=加载时并集合并**（文件条目覆盖代码默认、缺失回落默认），治 Y36 的「全量落盘后默认变更触达不了老文件」病。B=专用输入映射系统（编辑器新面板+专用格式+独立保存链）：编辑体验可定制（录制控件/冲突检测）但需重建保存/undo/导出全链，改动面数倍，且 T17 游戏内设置还要二次桥接。C=代码硬编码（无配置）：验收句直接落空 | **A 为主**；B 的录制控件/冲突检测作为增强挂 backlog（资产卡片先行，门槛由模板默认值+book 降）；游戏内重绑定归 T17（决策 3） |
| 2 | **游戏侧求值层位置** | A=**runtime 通用 `InputActionsPlugin`**（求值 `GameInputConfig`→`GameActions` Resource，模板/游戏读状态不碰 bevy Input 细节）：教学一行接线、键鼠手柄轴死区统一在一处、T11/T12/T17 直接消费；与 `ConfigPlugin` 同居 runtime=同一依赖零新增。B=只给数据层（配置资产存着，求值各游戏自写）：机制最小但每游戏重写求值=I1 没治。C=复用/扩展编辑器 `jackdaw_input` crate（游戏进程内 add_plugins）：框架成熟，但 Binding 无 gamepad/死区/持续轴语义要扩枚举+评估逻辑，且该 crate 的演进主权在编辑器（context 优先级/consume 等编辑器概念对游戏是负担）——跨界耦合后编辑器改动作框架会波及已发布游戏 | **A**；C 不做（演进主权分离：编辑器动作框架服务编辑器，游戏动作系统服务游戏，数据格式互不依赖）；若未来两框架趋同由引擎侧统一（挂 open-challenges 一句话） |
| 3 | **重绑定位置（编辑器内 vs 游戏内）** | A=**首版编辑器内**（资产卡片+`asset.set`，保存→stop→play 生效）：零新 UI、BRP 可驱（QA 面好）、三态一致走 T08 已验链；缺点=「按键捕获」式录制控件没有（卡片里手选 enum variant）。B=游戏内重绑定 UI（Pause 菜单 Settings→Controls，运行时录制+写回资产）：玩家侧终局形态，但需要游戏侧 UI（T12 才建 UI 能力）+写回链（游戏写文件=新链路，与「编辑器是作者态入口」的架构方向相逆） | **A 首版**；B 挂 T17「玩家设置」（彼时有 UI 能力+存档面，写回走「存档建议→编辑器采纳」或运行时覆盖层，届时再裁）；A 的录制控件体验缺口在 book/Try it 用模板默认值+卡片 enum 菜单压低门槛 |
| 4 | **死区层位置** | A=**配置死区→写入 bevy `GamepadSettings`**（注入时按绑定表的 deadzone 值 set per-axis `AxisSettings`，引擎层统一滤）：用 bevy 原生机制，`GamepadAxisChangedEvent`/`Axis<GamepadAxis>` 读到的已是滤后值，语义标准（deadzone+livezone 线性缩放）、与未来任何读轴的代码一致；缺点=bevy 的 per-axis 设置是按 (gamepad, axis) 键——per-action 不同死区同轴会打架（首版不做 per-action 差异死区）。B=求值层自读 Raw 轴+自滤（per-action 死区自由）：表达力强但重造 bevy 已有的过滤轮子，且 ButtonInput/GamepadAxisChanged 两套读数不一致（一处滤一处不滤）埋混乱 | **A**；per-action 死区差异挂 backlog（真实需求出现时在求值层加「动作级死区覆盖」读 raw 值，接口留好：绑定表字段已 per-binding） |
| 5 | **手柄 PIE 可达性路线** | A=**验证先行+协议兜底**（T2 真机/虚拟设备验证 gilrs 直读；不通则 `PieInputEvent` 尾加 Gamepad 变体+编辑器转发+runtime 注入三处扩）：直读成立=零协议改动最小面；不成立=兜底改动面约 3 文件且行为对齐键鼠（serde enum 尾部加变体，同仓同版本构建无协议漂移风险）。B=直接做协议扩展（不赌直读）：面大一点但确定性高、且**顺手给了 QA 合成手柄通道**（编辑器侧注入→转发→游戏，I7 的解）。C=只赌 gilrs 直读：最省但 Embedded 手柄被证伪时 T2 返工 | **A**，但把「QA 手柄合成通道」独立按 MCP 优先流程裁量（T2-3）：无论直读结论，若 QA 机器无物理手柄，通道本身值得立项（手柄格自动化的唯一结构化路径）；C 否决 |
| 6 | **捕获态鼠标压制（I3 修法）** | A=**capture.active 同关 `sources.mouse`**（`keybind_focus.rs:89` 一处赋值扩腿+单测）：与 keyboard 同语义，action mouse bindings 全压制；UI picking 走事件流不经 InputSources，捕获态点 Stop/面板不受影响（需断言钉死）。B=维持现状（hover 门事实上遮蔽）：理论混用面留存（无 hover 门的 mouse binding），验收句「不混用」鼠标腿无断言支撑 | **A**（一行级+两断言：mouse bindings 压制、PointerInput 照常）；B 不取（验收句要求两维度都有证据） |

小定案（主控可否决）：方案内编号 I1-I7；模板示例实体命名 `PlayerMarker`（区别 T11 将来的真玩家）；
动作资产默认路径 `input-actions.bsn`（与 `game-config.bsn` 并列，`DEFAULT_CONFIG_PATH` 家族语义）；
`GameActions`/`GameInputConfig` 命名入 `jackdaw_runtime::prelude`（对齐 ConfigLoader 家族）；
五动作默认绑定表如 T1-2a 所列（WASD+左摇杆/鼠标+右摇杆/Space+South/KeyE+East/Escape+Start）。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| schema 卡片对 `Vec<GameActionDef>`（列表行内 enum variant 菜单）渲染深度未实测——嵌套两层 Vec+enum 可能渲染不出或体验差 | T1 首批真机走查（卡片打开/增删行/改 variant）；若渲染不可用，回落形态=键名字符串字段（`PresetInput` 同款 `String` 存名，schema 渲染纯文本行）——保底路径写明，程序先试 enum 再回落并说明 |
| `GamepadPlugin` headless 可跑性（Raw 事件注入→过滤链在哪个 schedule、测试里 pump 几帧） | bevy 模式成熟（事件驱动）；T1 手柄腿单测先行验证，不行则死区数学用纯函数抽测（AxisSettings 变换函数直调） |
| gilrs 直读假设未验证（Windows.Gaming.Input 多进程读取） | T2 调查先行+协议扩展兜底（决策 5）；调查需要的手柄设备提前向用户报备（借用或虚拟驱动 viGEm，一次性） |
| 并集合并语义边角（文件动作 kind 与默认不同/同名绑定重复/文件含未知动作名） | 规则写死：文件同名覆盖（kind 用文件的）、重复绑定保留首个+warn、未知动作名照载（消费方找不到读者=无人读，不报错）——headless 用例钉死三条 |
| `PieInputEvent` 加变体（若走协议扩展）的兼容面 | serde enum 尾部加法+同仓同版本构建（编辑器与游戏同 checkout 构建，无跨版本对话）；变体加法进 guards 往返用例；PIE 协议版本注释更新 |
| 求值时序：PIE 注入事件（Update 期 collect→flush→游戏进程收到）→游戏下一帧 PreUpdate ButtonInput 更新→Update 求值——首帧延迟与 repeat 语义 | 一帧延迟与真窗口一致（winit 事件本就跨帧）；just_pressed/just_released 以 ButtonInput 为准天然正确；headless 用例覆盖「press→value 立即可读」的帧边界 |
| 模板变长（InputConfig+PlayerMarker+五动作表）影响 scaffold 基线与新用户体验 | scaffold 测试族同步扩；模板 doc 结构化（Try it/Input actions/Tuning parameters 三节）；PlayerMarker 系统 ~15 行上限 |
| T0 补验若 FAIL（T08 遗留缺陷回流）冲击 T09 排期 | T0 失败≠T09 停摆：按回流单独立修复轮，T09-T1 可先行（改动面不相交：T08 残留=PIE stop 关卡/环境劣化，T09=模板+runtime 加法），主控裁量 |
| 回滚 | T1/T2/T3 独立成分支段：T1=runtime 新模块+模板扩展+一行 mouse 压制（revert 即回无动作系统现状，零格式变更——资产文件是用户数据、schema kind 自动消失）；T2 若含协议扩展=serde 加法（revert 后旧文件不残留）；T3=纯矩阵+文档。全程零场景格式变更、零既有协议破坏——与 T05-T08 同款最大回滚保险 |

---

## 五、与 T01-T08 已建设施的衔接

1. **T06（PIE 换把/捕获链/Stop 铁证）=T09 的运行地基**：输入转发链（live_input/apply_input/PieInputEvent）
   是 T06 期建成的设施，T09 零改动复用（唯一动点=I3 一行+可选 gamepad 变体）；三态策略（Save/Ask/Copy）
   对动作资产的保护由 T08 dirty 资产三腿免费覆盖；Stop 铁证链在矩阵格 12 回归。
2. **T08（配置资产机制）=T09 的载体地基**：`ConfigPlugin` 一行注入、schema 卡片 Vec 编辑、dirty 三腿、
   `scene_snapshot` 行为断言、三态矩阵方法学全部直接复用——T09 是该模式从「标量参数」到「结构化动作表」
   的第一次推广，验证其表达力边界（嵌套 Vec+enum）；并集合并规则治 Y36 同款病，反哺 book 语义。
3. **T01（视口导航/输入方法论）**：格 10 未捕获态断言复用其「必须确认 fly 激活」纪律（BRP 断言 fly 态，
   不以零变化冒充）；幅度闸/输入注入探针经验沿用。
4. **T-QT/MCP 工具层**：`input.key`/`input.motion`/`ui_tree`/`ui_click`/`wait idle`/25 工具直接构成
   T09 验收驱动面；事实五链路（First 注入→Update 转发）让**合成输入驱动游戏子进程**成为常规能力
   （比 T08 的行为断言更进一步——T08 只读行为，T09 可注入输入）；手柄合成通道是唯一缺口（决策 5）。
5. **T07（导出/manifest）**：动作资产天然进包（过滤名单不含 .bsn 正本）；格 8 复用 `jackdaw/export`+
   manifest 断言。
6. **对 T10-T20 的奠基**：T11 玩家控制器=在 `GameActions` 上建移动/跳跃/碰撞消费层（T09 给
   `PlayerMarker` 骨架，T11 扩真控制器+CameraRig）；T12 暂停菜单消费 Pause 动作+UI 焦点；T17 玩家
   设置=游戏内重绑定+存档面（决策 3-B 领地）；T20 示例游戏端到端消费全链。「不混用」结论对
   T11-T20 全部 Play 验收复用。
7. **分支与行号基线**：本方案行号基于 main 9a874945（T08 闭环点）。T09 从 main 拉
   `loop/t09-input-actions`（三任务分段续用同分支族，T06/T08 先例）；行号按符号名重定位（矩阵证据
   均已给符号名）。T0 在 main 工作区执行、不建分支。
