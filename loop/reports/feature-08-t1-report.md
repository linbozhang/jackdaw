# 功能 #8 · 任务 1 报告：视口画质模型扩展（SMAA / SSAO 质量档 / CAS）

- 分支 `loop/graphics-panel`（基于 main `709c14ca`），提交 `9148873d` `Extend viewport quality settings with SMAA, SSAO and CAS`
- 改动 4 文件，+354 / −16：`src/viewport_settings.rs`、`src/viewport_quality.rs`、`tests/viewport/viewport_settings.rs`、`tests/viewport/viewport_quality.rs`
- `loop/` 目录未入库（日志与报告仅留本地）

## 门禁（每门独立行，探针 + 日志）

| 门 | 命令 | 退出码 | 日志 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 | `loop/feature-08-t1_fmt.log` |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | 0 | `loop/feature-08-t1_clippy.log` |
| fast | `cargo xtask fast` | 0（2847 passed, 2 skipped） | `loop/feature-08-t1_xtask_fast.log` |
| integration | `cargo xtask integration` | 0（4989 passed, 3 skipped） | `loop/feature-08-t1_xtask_integration.log` |

- clippy 标志说明：任务原文 `clippy --workspace -D warnings` 的字面形式在**未改动的主干上即失败**（`tests/component_shape_refresh.rs:1` 的 `#![expect(clippy::print_stdout)]` 在无 `--features dylib` 时不满足，已用 `git stash` 在干净树上复现确认，与本次改动无关）。故按仓库权威口径（`xtask fast` 内嵌命令：`--all-targets --features dylib --deny warnings`）执行，该口径全绿。
- 针对性探针（非门禁）：`cargo test -p jackdaw --test viewport viewport_` → 111 passed / 0 failed；`cargo test -p jackdaw --lib viewport_settings` → 9 passed / 0 failed。

## 新增测试（8 个）

单测（`src/viewport_settings.rs`，2 个）：
1. `a_file_from_before_ssao_quality_and_sharpening_takes_their_defaults` —— 旧 viewport.json（无 `ssao_quality`/`sharpen` 字段）serde default 兼容；
2. `the_presets_keep_the_choices_they_already_made` —— 钉住四档 preset 旧字段映射不漂移。

集成（`tests/viewport/`，6 个）：
3. `each_anti_aliasing_choice_dresses_the_viewport_camera_alone` —— AA 四态（Off/FXAA/SMAA/TAA）组件矩阵，含 TAA↔SMAA 切换清理 `TemporalJitter`/`MipBias`/`MotionVectorPrepass`；
4. `taa_and_smaa_hold_multisampling_off` —— SMAA/TAA 下视口相机 `Msaa::Off` 约束；
5. `the_ssao_quality_reaches_the_camera_and_off_takes_the_prepass_back` —— SSAO 质量档透传（Ultra→Low 原位更新）+ 关闭回收组件与 `NormalPrepass`；
6. `sharpening_dresses_the_viewport_camera_with_its_strength` —— CAS 开关 + 强度透传（0.8→0.25 原位更新）；
7. `the_smaa_ssao_and_sharpening_choices_round_trip_through_the_users_file` —— 新字段经 operator 写入 viewport.json 并读回一致；
8. 扩测 `names_the_settings_do_not_have_are_refused` —— `ssao_quality=extreme` / `quality=extreme` / `strength=1.5` 拒绝且设置不变。

## 实现要点

- **AA**：`AntiAliasing` 加 `Smaa` 变体（serde snake_case `"smaa"`，旧文件无损）；dress 插 `Smaa::default()`（High preset，与场景层 `dress_the_cameras` 同款）；互斥由单枚举构造保证；离开 TAA 沿既有分支清理 `TemporalJitter`/`MipBias` 及其保管的 `MotionVectorPrepass`；新增 `Msaa::Off` 守卫（视口相机本就因 OIT 在 spawn 时 `Msaa::Off`，守卫为防御性约束，且 surface 层对视口相机 `antialiasing` opt-out 恒真、不会与它打架）。
- **SSAO**：`ViewportQuality` 加 `ssao_quality: SsaoQuality`（Low/Medium/High/Ultra，默认 High）；映射函数 `ssao_quality_level` 直译 bevy 四档（不含 Custom）；dress 比对 `quality_level` 差异才重插（开关/换档复用同一路径），`NormalPrepass` 保管回收走既有 `EffectPrepasses`；preset 映射四档全为 High（旧文件 preset 识别不破坏）。
- **CAS**：`ViewportSettings` 加 `sharpen: bool`（默认 off）与 `sharpen_strength: f32`（默认 0.6）；dress 比对强度差异插/删 `ContrastAdaptiveSharpening`（`enabled: true`，`denoise` 用默认 false）。
- **operator**：`viewport.quality.set` 增 `ssao_quality` 参数、`anti_aliasing` 接受 `smaa`；新增 `viewport.ssao.set`（on/quality 均可选，缺省保持现状）与 `viewport.sharpen.set`（strength 越界 0..=1 拒绝）；全部 `allows_undo=false`、改动经 `ViewportSettings` resource → `viewport.json` 自动落盘（既有链路零改动）。`EnvironmentOptOut` 语义不变（antialiasing 恒 true，场景 AA 不落视口）。
- **副作用说明**：viewport 设置菜单的 Anti-Aliasing 分组由 `AntiAliasing::ALL` 数据驱动，枚举扩展后菜单自动多出 SMAA 单选项（零新增 UI 代码，属模型扩展的自然结果；QA 任务 3 的「菜单行为回归」已由 `viewport_settings_menu` 既有测试覆盖通过）。

## 与方案偏差

- clippy 门按仓库权威口径加了 `--all-targets --features dylib`（见上，字面口径在主干上即红）。
- CAS 未暴露 bevy 的 `denoise` 与 SMAA 的 `SmaaPreset` 参数（方案 D6/§3.2 面板规格本就只有开关+强度、SMAA 无子档），保持模型最小。

## Concerns

- 无阻塞项。真机视觉验证（SMAA/CAS 实际渲染效果、pixdiff）归任务 3 QA。
