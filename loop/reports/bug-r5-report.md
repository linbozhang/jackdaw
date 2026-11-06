# R5 程序报告：空地形上点 Erode 直接 panic

> 2026-11-06，程序 agent。分支 `loop/bug-r5-erode-empty-terrain`（自 main `958dfa28` 拉）。
> 方案书：`loop/plans/bug-r5-erode-empty-terrain.md`（双层修复 D1+D2，主控已裁）。
> **未合入 main，待 QA。**

## 票面与根因

`terrain_erode`（src/terrain/ops.rs）读出 `grid_resolution()` 后直接调 kernel；
kernel `hydraulic_erosion`（crates/jackdaw_terrain/src/erosion.rs:75）迭代体内
`rng.random_range(1.0..(res - 2) as f32)` 对 resolution 0–3 为反/空区间，rand panic：
`panicked at crates/jackdaw_terrain/src/erosion.rs:75:29: cannot sample empty range`。
面板 Erode 按钮只有 `has_selected_terrain` 门槛，空地形（未生成，resolution==0）可直达。
触发条件是 `iterations > 0` 且 resolution < 4，与地形是否为空无关。

## 修复（双层）

- **D1 op 层拒绝**（src/terrain/ops.rs `terrain_erode`）：签名新增 `mut commands: Commands`；
  `resolution < 4` 构造拒绝消息 → `warn!` + `commands.queue(toast_terrain_notice)` + `return None`
  —— 严格沿用 `terrain_generate` 的 refused 分支形态（ops.rs:247-260）。**不写 undo、不置 dirty、
  不写 heights、不重建。** 文案（英文，沿用 `RegionCapError` house 句式）：
  `this terrain's grid is {resolution} vertices a side and erosion needs at least 4; nothing was eroded and no ground was changed`
- **D2 kernel 早退**（erosion.rs `hydraulic_erosion` 开头）：`if resolution < 4 { return; }`，
  注释说明「无内部可侵蚀：droplet 生成区间为空/反区间，梯度读会越过网格」——兜底保护未来调用方。
- op doc 注释补一句拒绝行为说明。

## diff 面

| 文件 | 改动 | 行数 |
|---|---|---|
| `src/terrain/ops.rs` | op 拒绝分支 + `Commands` 参数 + doc 一句 + 1 条 op 测试 | +65 |
| `crates/jackdaw_terrain/src/erosion.rs` | kernel 早退 + 注释 + 2 条 kernel 测试 + 1 个测试参数 helper | +59 |

未触碰 panel.rs / generate / quantize / brush / UI 机制 / buglist / roadmap / progress。

## 测试清单（红→绿）

**kernel 级**（erosion.rs `#[cfg(test)]`，既有锚内新增）：
- `grids_below_four_vertices_a_side_are_refused_without_touching_heights`：
  res 0/1/2/3 + `iterations>0`（16 滴）不 panic 且 heights 全不变。修前 panic（红证）。
- `a_well_sized_grid_is_eroded_into_finite_heights`：res 64 斜面正常侵蚀，heights 变化且逐元素有限（回归锚）。

**op 级**（ops.rs `#[cfg(test)]`，现成 `World::run_system_cached_with` harness，entity_ops/hierarchy 先例同款）：
- `eroding_an_empty_terrain_is_refused_without_undo_or_dirty`：空地形（res 0）Erode →
  返回 None（拒绝）+ `undo_stack` 空 + `rebuild_all` 不置位 + store 分辨率仍 0（无写入）。
  修前同样 panic（红证，panic 源头同为 erosion.rs:75）。tests/ 集成 harness 未动（红线）。

**红证归档**：`loop/bug-r5/red.log`，双腿齐全，panic 原文：
`panicked at crates/jackdaw_terrain/src/erosion.rs:75:29: cannot sample empty range`。
**绿证归档**：`loop/bug-r5/green.log`：kernel 4/4、op（terrain::ops 全模块）4/4。

## 门禁三连（2026-11-06 本机，日志全文复核）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | 干净（无 diff，exit 0） | `loop/bug-r5/gates-fmt.log`（0 字节） |
| `cargo clippy --workspace -- -D warnings` | 干净（Finished，无 error/warning 诊断） | `loop/bug-r5/gates-clippy.log` |
| `cargo test --workspace --lib` | **3098 passed / 0 failed，59 个测试二进制** | `loop/bug-r5/gates-test.log` |

**测试数拆账**：3098 = 基线 3095（R4 后，59 二进制口径）+ **3**（kernel 2 + op 1），二进制数 59 不变。
日志复核：无真实 FAILED / 编译 error；grep 命中的 "failed"/"ERROR" 均为测试名子串与负路径场景测试的
预期日志输出（baseline 同款）。

## 偏差与如实记档

1. **red.log 录制过程**：前两次运行因 shell `&&` 链在失败的 kernel 腿后短路、op 腿未跑
   （kernel 红证本身已成立）；随后一次 op 腿因测试写法编译错（`run_system_cached_with` 返回
   `Result` 需 `.expect` 解包）未构成有效红证。最终 red.log 以「重跑 kernel 腿覆盖 + op 腿追加」
   产出，现为干净双腿红证（上表 panic 原文即出自该文件）。中间态残页未留存（已被覆盖，契约按
   「覆盖归档」执行）。
2. **toast 文案**：QA 真机腿需确认 toast 实际出现（headless 测试中 `toast_terrain_notice`
   无字体即 no-op，测试只能断言拒绝行为本身）。
3. **真机腿（QA）**：boot 编辑器 → 建 Terrain → 不生成直接点 Erode（或经 operator `terrain.erode`，
   效力等同）：修前=panic（本报告红证等价复现于 kernel/op 两层测试），修后=不 panic + toast + undo 栈
   无新记录。此项由 QA 按方案书执行。
4. **新缺陷**：本次未发现需立票的新缺陷（kernel 早退使 op 层的垃圾-undo 病灶同被堵死，双层互保）。

## 状态

分支 `loop/bug-r5-erode-empty-terrain` 已 commit；**未合入 main**；buglist 打勾、roadmap/progress
未动，收尾归主控。待 QA 验收（`loop/reports/bug-r5-qa.md`）。
