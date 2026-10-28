# DX12 Backend 任务 QA 验收报告（验收 / jackdaw loop）

- 验收对象：`loop/dx12-backend` @ `91459d34`（基于 main 66c35b0a，4 files, +137/-35）
- 验收人：QA agent（真机契约，独立复跑）
- 结论：**PASS**

## 门禁（QA 独立复跑，真实退出码探针 `&& echo OK || echo FAIL`）

| 门 | 结果 | 备注 |
|---|---|---|
| `cargo fmt --all -- --check` | FMT_OK | |
| `cargo clippy --workspace -- -D warnings` | CLIPPY_OK | 残留 warning 为 build script 的 linker stderr 噪音（rust-lld 忽略 `-fuse-ld=lld`），非 clippy lint |
| `cargo xtask fast` | FAST_OK | 2855 passed / 2 skipped / 0 failed（`loop/qa_xtask_fast.log`）；含 `render_backend` 全部 4 个单测 PASS |
| `cargo xtask integration` | 引用程序日志 + 尾部抽查 | `loop/dx12_xtask_integration.log` 尾部核实 5005 passed / 3 skipped，与程序报告一致（契约允许，改动面小） |

## 代码审查

- **选择逻辑正确**：`render_backend.rs::backends` 三态分发——env 有效（Some 且非空集）→ 返回 `None` 不覆写；env 未设置 / 全未知（None / Some(empty)）→ Windows `Some(DX12)`、其它平台 `None`（不覆写，行为同改动前）。已对照 Bevy 源码核实（checkout `c9c397b` = Cargo.lock 实际 rev，`crates/bevy_render/src/settings.rs:84` `Some(Backends::from_env().unwrap_or(Backends::all()))`）：env 有效时 `WgpuSettings::default()` 确已应用 env 及其衍生调优，不覆写是正确做法；程序报告的 Bevy 行为声称属实。
- **注入点仅编辑器进程**：`launch.rs::run()` 是编辑器 DefaultPlugins 唯一组装处，RenderPlugin 在此无条件 `.set`；scaffold 生成的游戏 `main.rs` / 游戏运行时不在 diff 内，未受影响。
- **单测**：4 个，覆盖 env 解析形状 / 平台默认 / 有效值不覆写 / 拼错回退；`cfg!(windows)` 使平台断言在两平台各自生效，xtask fast 中全 PASS。
- **无越界**：分支 diff 仅 4 文件（launch.rs / lib.rs / render_backend.rs / render_diagnostics.rs）；`render_diagnostics` 收窄为 `timestamp_features()` 并以 `|=` 合并进 default features（保留 Bevy 默认，行为改进）。
- **loop/ 不入库**：`.git/info/exclude:7` 忽略 `loop/`，`git check-ignore` 核实。工作区另有未提交 `.gitignore`（`+.mimosa/`）与未跟踪 `buglist.md`，均未混入分支 diff，与本任务无关。

## 真机验证（QA 独立复跑，复用已审阅的 `loop/dx12-verify.ps1`；产物 `loop/reports/dx12-verify/`，程序旧产物已归档至 `dx12-verify-prog/`）

构建：QA 自建 plain debug 二进制（`cargo build -p jackdaw`，BUILD_OK，mtime 22:17:12 后三轮启动均用该二进制）。每轮：真实启动编辑器（my-game）→ BRP 等 idle + 20 帧 → PrintWindow 截图 → 取 stderr 原始 `AdapterInfo` 行。

| 轮 | env | AdapterInfo backend | 截图视觉核验 |
|---|---|---|---|
| dx12-default | 无 | **Dx12**（RTX 5070, driver 32.0.15.9186） | 正常：网格地面、红/蓝轴线、棋盘格贴图几何体、全 UI 面板（Outliner 17 实体/Components/底部日志），无黑屏花屏 |
| vulkan-override | `WGPU_BACKEND=vulkan` | **Vulkan**（driver "NVIDIA", 591.86） | 正常（同上要素齐全） |
| typo-fallback | `WGPU_BACKEND=vukan` | **Dx12**（回退，编辑器正常启动不崩溃） | 正常（同上要素齐全） |

三轮 stderr 原始日志均经独立 grep 核验（非仅脚本 SUMMARY）。

## 发现（均不阻塞）

1. ⚪ **release + 拼错 env 组合下 VALIDATION_INDIRECT_CALL 被移除**：Bevy `default()` 先按 `Some(empty)` 计算 instance_flags 并移除该 flag（settings.rs:130-138），jackdaw 随后才覆写 backends=DX12，此时 DX12 运行于缺该 flag 的状态（wgpu 注释称 DX12 验证路径需要它）。仅「release 构建 + 用户拼错 env」异常路径触发，且属容错回退场景，无功能危害；完美修复需复制 Bevy 内部调优逻辑，不值得。记录备查。
2. ⚪ **拼错 env 时游戏侧 schema extractor 子进程仍失败**：typo 轮 stderr 出现 `project schema extraction skipped: extractor failed: ... Unable to find a GPU!`（extractor 继承拼错 env、按 wgpu 原生语义空集无 adapter）。改动前编辑器主进程在同场景同样失败，**非回归**；且仅 schema extraction 降级（WARN，编辑器可用、截图正常），符合「仅编辑器进程」的范围界定。default / vulkan 轮 extractor 均 0 失败行，行为自洽。
3. ✅ 程序报告的关键声称（Bevy default 内建 from_env、rev c9c397b、门禁数字、真机三态）逐项核实属实；报告质量高。
