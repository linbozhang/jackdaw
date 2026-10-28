# DX12 Backend 任务报告（程序 / jackdaw loop）

- 分支：`loop/dx12-backend`（自 main 66c35b0a 拉）
- 提交：`91459d34` Default the editor to DX12 on Windows（4 files, +137/-35）
- 状态：**DONE**

## 改动

| 文件 | 改动 |
|---|---|
| `src/render_backend.rs`（新） | 编辑器进程的后端选择：`backends(Option<Backends>) -> Option<Backends>` 纯函数 + `wgpu_settings() -> WgpuSettings` 组装（4 个单测） |
| `src/launch.rs` | RenderPlugin 无条件 `.set(...)`，settings 来自 `render_backend::wgpu_settings()`；LogPlugin 条件块改 `let` shadowing（去掉 debug 下 unused 的 `mut`） |
| `src/lib.rs` | `pub mod render_backend;` |
| `src/render_diagnostics.rs` | `wgpu_settings() -> Option<WgpuSettings>` 重构为 `timestamp_features() -> Option<WgpuFeatures>`（职责收窄，由 render_backend 折叠；`features` 由**覆盖**改为 `|=` 合并，保留 Bevy 默认 features） |

### 后端选择逻辑（`src/render_backend.rs::backends`）

`WGPU_BACKEND` 由 wgpu 原生解析（`Backends::from_env()`）：

| env 状态 | Windows | 非 Windows |
|---|---|---|
| 未设置 | `Backends::DX12`（覆写） | 不覆写（Bevy/wgpu 原默认 `Backends::all()`，行为与改动前完全一致） |
| 设置且解析出 ≥1 个有效后端 | 不覆写——`WgpuSettings::default()` 已应用 env 值，**连同 Bevy 基于 env 推导的 per-backend 调优**（release 下 instance_flags 的 VALIDATION_INDIRECT_CALL 去留、DX12 shader compiler 选择） | 同左 |
| 设置但全部 token 未知（如拼错 `vukan`） | 回退 `Backends::DX12`（wgpu 已 warn；避免空集→无 adapter→启动崩溃） | 不覆写（=原行为：空集导致 GPU not found，非 Windows 语义不变） |

- 仅编辑器进程：注入点在 `launch.rs::run`（编辑器/捆绑扩展二进制的唯一 DefaultPlugins 组装处）。游戏运行时/导出游戏由 scaffold 生成的 `main.rs` 组装自己的 `DefaultPlugins`（经 `maybe_windowless`），不受影响。
- 诊断路径：`JACKDAW_RENDER_DIAGNOSTICS=1` 时 timestamp features 在同一处折叠进 settings（原先单独覆写 RenderPlugin 的逻辑删除）。

### fps_overlay / thumbnail 处置

- `src/fps_overlay.rs:380-382`：`#[cfg(test)]` 内的无后端测试 app（`backends: None` = 不创建渲染器），与编辑器进程无关，**不动**。
- `src/thumbnail.rs:1363`：注释所述为 `tests/util/mod.rs::headless_app()` 的无后端配置；缩略图离屏渲染走编辑器进程内的渲染器实例（编辑器已是 DX12 时同后端），**不需改**；真机验证的默认 DX12 轮截图中场景贴图正常渲染。
- `tests/`、`integrations/*/tests/` 下全部 `WgpuSettings { backends: None }` 均为无后端测试 app，不动。

## 门禁（真实退出码；`&&/||` 分支探针 + 日志独立核验）

> 教训记录：CMD 中 `cmd1 & echo %ERRORLEVEL%` 的 ERRORLEVEL 在行解析期展开（拿到的是上一条命令的码），首轮 clippy/xtask fast 的 "EXIT=0" 是假阳性——实际因 2 个 clippy 错误失败（unused import `WgpuFeatures`；`launch.rs` 的 `mut` 在 debug cfg 下 unused）。修复后改用 `&& echo OK || echo FAIL` 探针 + 日志尾部独立行核验。

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo check -p jackdaw` | CHECK_OK | `loop/dx12_check.log` |
| `cargo fmt --all -- --check` | FMT_OK | `loop/dx12_fmt.log` |
| `cargo clippy --workspace -- -D warnings` | CLIPPY_OK | `loop/dx12_clippy.log` |
| 单测（render_backend，4 个） | TEST_OK（4 passed; 0 failed） | `loop/dx12_unittest.log` |
| `cargo xtask fast` | FAST_OK（2855 passed, 2 skipped, 0 fail） | `loop/dx12_xtask_fast.log` |
| `cargo xtask integration` | INTEGRATION_OK（5005 passed, 3 skipped, 0 fail；首轮 INTEGRATION_FAIL 系残留 jackdaw.exe 进程占用 target\debug\jackdaw.exe 的 os error 32，进程退出后复跑通过，非代码问题） | `loop/dx12_xtask_integration.log` |

## 真机验证（`loop/dx12-verify.ps1`，产物在 `loop/reports/dx12-verify/`）

三轮启动真实编辑器（my-game 工程，BRP 就绪 + 20 帧 + PrintWindow 截图），adapter 行取自 `bevy_render::renderer` 的 `AdapterInfo` INFO 日志：

1. **无 env（默认）**：`AdapterInfo { name: "NVIDIA GeForce RTX 5070", ..., backend: Dx12 }`；截图 `dx12-default.png` 经视觉核验：网格/红蓝轴线/贴图 cube/全部 UI 面板正常，无黑屏花屏。
2. **`WGPU_BACKEND=vulkan`**：`backend: Vulkan, driver: "NVIDIA", driver_info: "591.86"` ——覆盖能力保留。
3. **`WGPU_BACKEND=vukan`（拼错）**：`backend: Dx12` ——未知值回退平台默认（不崩溃）。

lint 修复后重建二进制复跑一轮默认验证：`backend: Dx12`（`loop/dx12_rebuild_verify.log`），提交代码 = 验证代码。

## 兼容性核查（无 BLOCKED）

- Bevy main @ c9c397b `WgpuSettings::default()` 已内建 `Backends::from_env()`；覆写仅发生在「env 未设置/全无效 + Windows」。release 下 VALIDATION_INDIRECT_CALL 的 DX12 去留由 Bevy default 按 all()（含 DX12）计算后原样保留，DX12 路径正确。
- DX12 shader 编译走 Bevy 默认决策（`WGPU_DX12_COMPILER` env → dxcompiler.dll 若在 cwd → FXC）。本机验证 FXC 路径渲染正常；未打包 dxcompiler.dll（与仓库现状一致，非本任务范围）。
- WESL/sparkline/缩略图/sparkline 离屏：真机 DX12 轮全部正常（见截图与三轮 idle+截图流程）。

## Concerns

1. DX12 下编辑器长时间稳定性（驱动层偶发问题）只能靠日常使用观察；三轮短会话 + 截图不构成压力证据。
2. `WGPU_BACKEND` 部分有效值（如 `vulkan,dx12`）遵循 wgpu 原生（两后端并集，adapter 选择交给 wgpu 优先级），未额外干预——与 Bevy 默认行为一致。
3. `loop/` 全部产物（日志/脚本/截图）不入库（.git/info/exclude 已忽略）。
