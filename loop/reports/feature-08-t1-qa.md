# 功能 #8 · 任务 1 QA 验收报告：视口画质模型扩展（SMAA / SSAO 质量档 / CAS）

- 验收对象：`loop/graphics-panel` 提交 `9148873d`（基于 main `709c14ca`），diff 4 文件 +354/−16
  （`src/viewport_settings.rs`、`src/viewport_quality.rs`、`tests/viewport/viewport_settings.rs`、`tests/viewport/viewport_quality.rs`）
- 验收人：QA Agent（2026-10-24）。需求口径：`loop/plans/feature-08-graphics-panel.md` 任务 1 节 + §D1/D2；
  程序报告：`loop/reports/feature-08-t1-report.md`
- **VERDICT: PASS**

## 1. 确定性门（每门独立行，探针 + 日志）

| 门 | 命令 | 退出码 | 结果 | 日志 |
|---|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 | 干净 | `loop/qa-t1_fmt.log` |
| clippy（权威口径） | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | 0 | 无警告 | `loop/qa-t1_clippy.log` |
| fast | `cargo xtask fast` | 0 | 2847 passed / 2 skipped | `loop/qa-t1_xtask_fast.log` |
| integration | `cargo xtask integration` | 0 | 4989 passed / 3 skipped | `loop/qa-t1_xtask_integration.log` |

- 权威口径核实：`xtask/src/main.rs` 的 `fast()` 内嵌命令确为 `--all-targets --features dylib -- --deny warnings`（:42-50），与程序报告一致。
- **裸口径（`clippy --workspace -- -D warnings`）在 main 即红的说法：采纳。** 证据：
  - 本分支探针 `cargo clippy -p jackdaw --test component_shape_refresh -- -D warnings`（无 dylib）→
    `error: this lint expectation is unfulfilled`（`tests/component_shape_refresh.rs:1` 的 `#![expect(clippy::print_stdout)]`），
    见 `loop/qa-t1_clippy_bare_probe.log:29-37`；该文件不在本次 diff 中，两分支内容相同；
  - main 上直接复跑（checkout main / worktree 两次尝试）均 exit 101——暴露的是本机环境的另一层失败
    （`multiple input filenames ... build.rs and ';'`，全 workspace 本地 crate 构建传参异常，疑似本机
    cargo/rustc 环境quirk，两分支皆然、与本改动无关），见 `qa-t1_clippy_bare_main3.log`。
  无论哪层先触发，裸口径在 main 上非绿成立，程序按权威口径执行正当。
- 过程记录：integration 第一次运行失败 exit 1，原因是 QA 自己的命令把 `; echo ...` 透传成了 xtask 的
  shard 参数（CMD 中 `;` 非分隔符），非代码问题；纯净重跑后通过（`qa-t1_xtask_integration.log`）。

## 2. 代码审查

### AA 四态（Off/FXAA/SMAA/TAA）
- 互斥由 `AntiAliasing` 单枚举构造保证（`viewport_settings.rs:120-126`；dress 端 `wants_taa/smaa/fxaa`
  三个布尔互斥派生，`viewport_quality.rs:155-157`），无法出现双 AA 组件并存。
- 离开 TAA 清理：`viewport_quality.rs:182-188` 移除 `(TemporalAntiAliasing, TemporalJitter, MipBias)`
  及保管的 `MotionVectorPrepass`；bevy 侧核实 TAA require 列表
  （`bevy_anti_alias/src/taa/mod.rs:114`），Jitter/MipBias 手动清理正确。测试
  `each_anti_aliasing_choice_dresses_the_viewport_camera_alone` 断言 TAA→FXAA 后四者全清。
- SMAA 默认 preset：`Smaa::default()`，bevy 源码核实 `SmaaPreset` 的 `#[default]` 为 `High`
  （`bevy_anti_alias/src/smaa/mod.rs:107-118`），真机 BRP 亦断言 `preset=High`。
- `Msaa::Off` 守卫（`viewport_quality.rs:162-164`）：TAA||SMAA 且非 Off 时插入，防御性单向守卫
  （不恢复），注释言明视口相机 spawn 即 Off（OIT 要求）；测试 `taa_and_smaa_hold_multisampling_off` 钉住。
- ⚪ 既有（非本任务引入）：TAA/SSAO 的 require 链会带来 `DepthPrepass`，离开 TAA/关闭 SSAO 后不清理
  （EffectPrepasses 只保管 normal/motion）——main 上即如此，本任务未改该分支。仅编辑器视口相机
  的性能微损耗（AA=Off/FXAA 且 SSAO off 时多一次 depth pass），无正确性影响，不阻塞。

### SSAO
- diff-才重插：`viewport_quality.rs:190-195`，`ambient_occlusion && ssao.map(quality_level) != Some(wanted)`
  ——开着时仅质量档不同才重插（原位覆盖组件），测试 Ultra→Low 原位更新。
- `NormalPrepass` 回收：走既有 `EffectPrepasses` 保管（:191 标记、:196-201 关闭时随组件移除），
  序列推演（on→换档→off→再 on）状态机正确；测试断言 off 后 SSAO 与 NormalPrepass 双双消失。
- 质量档直译：`ssao_quality_level`（:126-133）Low/Medium/High/Ultra 一一对应 bevy
  `ScreenSpaceAmbientOcclusionQualityLevel`（不含 Custom），无越值。
- preset：四档均 `ssao_quality: High`（quality() 单一来源），旧 preset 识别不破坏（`preset()` 往返）。

### CAS
- 插/删对称（:203-215）：on 且强度 diff → insert `{enabled: true, sharpening_strength, ..default()}`；
  off 且存在 → remove；无 prepass 依赖、无保管负担。测试 0.8→0.25 原位 + off 移除。

### serde 兼容
- `ViewportQuality`/`ViewportSettings` 均 container 级 `#[serde(default)]`（:211/:241），
  旧 viewport.json（无 `ssao_quality`/`sharpen`/`sharpen_strength`）→ High/false/0.6；
  单测 `a_file_from_before_ssao_quality_and_sharpening_takes_their_defaults` 钉住。
- 新字段往返：`the_smaa_ssao_and_sharpening_choices_round_trip_through_the_users_file`
  （operator 写 viewport.json → load 读回全等，含 anti_aliasing=smaa / ssao_quality=medium / sharpen 0.75）。
- `AntiAliasing` serde snake_case，`"smaa"` 新变体对旧文件无损。

### operator
- `viewport.quality.set`：`anti_aliasing` 接受 `smaa`（错误文案同步更新）、新增 `ssao_quality`；
  多参数原子性成立（局部 `quality` 最后统一提交，坏参数 Cancelled 不留半截改动）。
- 新 `viewport.ssao.set`（on/quality 均可选、缺省保持现状）与 `viewport.sharpen.set`
  （strength 越界 0..=1 拒绝）：坏值在写 settings 前 Cancelled；`names_the_settings_do_not_have_are_refused`
  扩测断言 `ssao_quality=extreme`/`quality=extreme`/`strength=1.5` 均拒绝且 `settings == before`。
- undo 契约：全部 `allows_undo = false`，与既有 `viewport.*` 家族一致。
- `EnvironmentOptOut` 未动：`environment_opt_out`（:93-102）与 main 逐字节一致，`antialiasing: true` 恒真
  （场景 AA 不落视口的既有分界保持）。
- ⚪ 既有（框架级）：bool/float 参数的类型坏值（如 `on="maybe"`）经 `as_bool` 返回 None 静默忽略
  （与「未传」不可区分），非本任务引入；可识别的字符串枚举坏值与数值越界均正确拒绝。

### 测试质量（8 新增/扩展）
断言矩阵完整：AA 四态互斥、TAA 清理（Jitter/MipBias/MotionVectorPrepass）、Msaa::Off、SSAO 质量透传
+ prepass 回收、CAS 强度透传、文件往返、旧文件 default、preset 钉住、坏参数拒绝。preset 钉住测试只抽查
Low/Full 两档旧字段（未逐一断言四档 ssao_quality），但 quality() 单一来源，风险可忽略。

### 无任务 2/3 越界
- diff 仅上述 4 文件：无 `graphics_panel.rs`、无 `builtin_extensions.rs` 窗口注册、无 book/README 文档。
- 设置菜单自动多出的 SMAA 选项：`viewport_settings_menu.rs:277-284` 的 Anti-Aliasing 分组由
  `AntiAliasing::ALL.map(...)` 数据驱动，该文件零改动（diff 核实 MENU_UNCHANGED），无手写 UI 代码——
  程序报告声明属实，属模型扩展的自然结果。
- `loop/` 不入库：`git ls-files loop/` 为空（.git/info/exclude 本地忽略）。

## 3. 真机抽查（BRP，1 项 + 顺带 SSAO）

脚本 `loop/qa/f8-t1-brp.ps1`（plain 构建 `cargo build -p jackdaw`，exe 08:49 重链含本分支代码），
my-game 工程启动编辑器（BRP 15703），对视口相机实体（active+Perspective，entity=3707v0）
经 `jackdaw/call_operator` 切换并 `world.get_components` 断言。日志 `loop/qa-t1_brp_spot_check.log`：

| 步骤 | 断言结果 |
|---|---|
| 默认/切 fxaa | 仅 `Fxaa` 在，`Smaa`/`TemporalAntiAliasing` 不在 |
| 切 smaa | `Smaa` 在且 `preset=High`；`Fxaa`/`TAA`/`TemporalJitter`/`MipBias` 全清 |
| 切 taa | `TAA`+`TemporalJitter`+`MipBias` 在；`Smaa` 消失 |
| `viewport.ssao.set on=true quality=ultra` | `SSAO.quality_level=Ultra` + `NormalPrepass` 在 |
| `viewport.ssao.set on=false` | `SSAO` 与 `NormalPrepass` 双双回收 |

`F8_T1_BRP_SPOT_CHECK_PASS`；结束后恢复 fxaa 默认并关编辑器（用户 viewport.json 不受残留影响）。

## 4. 发现

| 级别 | 责任方 | 问题 |
|---|---|---|
| ⚪ | 既有（main） | 离开 TAA/关闭 SSAO 后 `DepthPrepass` 不回收（bevy require 链带入，EffectPrepasses 只保管 normal/motion）；仅编辑器视口性能微损耗，无正确性影响，可入 backlog |
| ⚪ | 框架既有 | operator bool/float 参数类型坏值经 `as_bool`/`as_float` 静默忽略（None 与「未传」不可区分）；字符串枚举坏值与数值越界的拒绝路径本任务均已覆盖 |
| ⚪ | 程序（设计取舍） | 方案 §3.1 曾软性提议「Full 档 = SSAO High + 锐化 0.6」；实现中 preset（ViewportQuality）不含 sharpen（在 ViewportSettings 层），切 preset 不重置锐化。规格表 §3.2/D6 未将 sharpen 绑入 preset，保持「只增不改」原则，判定可接受，记录供任务 2 知晓 |

无 🔴/🟡。

## 5. 结论

门禁四门全绿；模型/实现/测试与方案任务 1 范围一致、无越界；真机 BRP 抽查通过。**PASS**，可进入任务 2（Graphics 面板 UI）。
