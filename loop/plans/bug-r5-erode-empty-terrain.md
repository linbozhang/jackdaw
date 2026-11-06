# R5 修复方案：空地形上点 Erode 直接 panic（buglist 🔴）

> 立项：2026-11-06（buglist 阶段第 2 票，紧随 R4 闭环）。基线：main `958dfa28`。
> libtests 新基线 3095（R4 后）。

## 票面（buglist.md:43-46，原文引用）

**R5. 空地形上点 Erode 直接 panic**
- `crates/jackdaw_terrain/src/erosion.rs:75` + `src/terrain/ops.rs:308-312`（`terrain_erode`）。
- 问题：`rng.random_range(1.0..(res - 2) as f32)` 对 resolution 0–3 为空/反区间，rand panic
  （`terrain_generate` 在 ops.rs:246-251 有空地形分支，erode 没有）；面板 Erode 按钮
  （`src/terrain/panel.rs:2449-2456`）只有 `has_selected_terrain` 门槛，UI 可直接触达。
- 修复方向：kernel 开头 `if resolution < 4 { return; }`，或 op 里拒绝 `grid_resolution() < 4`。

## 策划期核实（2026-11-06 主控亲读，逐条代码级）

1. **kernel panic 面成立**：`hydraulic_erosion`（erosion.rs:62 起）迭代体内
   `rng.random_range(1.0..(res - 2) as f32)`——res=0/1 反区间、res=2/3 空区间，rand 均 panic；
   只要 `iterations > 0` 且分辨率 <4 即触发，与地形是否为空无关。
2. **op 层零守卫成立**：`terrain_erode`（ops.rs:308+）读
   `resolution = data.document().grid_resolution()` 后直接调 kernel，无任何前置判断；
   空地形（未 sculpt）文档 `grid_resolution()==0`（`terrain_generate` 的
   `if data.document().grid_resolution() == 0` 分支即此含义，ops.rs:246-251）。
3. **UI 触达成立**：Erode 按钮（panel.rs:2449-2456）`call_operator(TerrainErodeOp::ID)`，
   选中任意 Terrain 实体即可点，无分辨率/has-data 门槛。
4. **策划期新增发现（比票面多一层）**：若只做 kernel 静默 `return`，op 层会继续走完——
   `new_heights == old_heights` 仍然 `set_heights` + `dirty.rebuild_all = true` +
   `history.push_executed(SetTerrainHeights::whole(...))`，产生**新旧全等的垃圾 undo 记录**
   （Y1 家族同款「无意义撤销记录」病灶）+ 一次无谓全网格重建。

## 修复方案（双层，主控已裁）

- **D1 主修复=op 层拒绝**（`src/terrain/ops.rs` `terrain_erode` 开头）：
  `if resolution < 4` → toast 提示（沿用 `terrain_generate` 的 refused 分支 +
  `toast_terrain_notice` 先例）并 `return None`——**不写 undo、不标 dirty、不重建**。
  提示文案诚实：「地形分辨率过低（<4），无法侵蚀」级；英文与既有 toast 文风一致。
- **D2 兜底=kernel 早退**（`crates/jackdaw_terrain/src/erosion.rs` kernel 开头）：
  `if resolution < 4 { return; }` + 注释说明梯度读越界/区间构造的下限——保护未来调用方
  （票面修复方向第一 clause 原样落地）。
- **范围红线**：只动 `src/terrain/ops.rs`、`crates/jackdaw_terrain/src/erosion.rs`
  （含各自测试模块）；不碰 panel、不碰 generate、不碰 quantize/brush 等相邻面。

## 测试方案（红→绿）

- **kernel 级**（erosion.rs 测试模块；若该文件无测试锚则新建 `#[cfg(test)]`）：
  - 红证：`hydraulic_erosion(&mut heights, 0..=3 各一， params with iterations>0)` 修前 panic
    （红证以定向测试输出归档；`#[should_panic]` 不适合做红证归档形态，直接跑并在日志留
    panic 输出即可）；修后全不 panic 且 heights 未被改动。
  - 回归锚：resolution≥4（如 64）正常侵蚀，heights 发生变化（或至少不 panic 且逐元素有限）。
- **op 级**：若 `src/terrain/` 或 tests/ 有 operator 测试锚（stage/单元 harness），加
  「空地形 Erode → 拒绝 + 无 undo 记录 + dirty 不置位」断言；若无现成 harness，
  以 kernel 测试 + 真机腿覆盖，如实记档（不得为凑测试引入不受测代码）。
- **真机腿（QA）**：boot 编辑器 → 建 Terrain 实体（Add 菜单/脚手架）→ **不生成、直接点
  Erode**：修前=编辑器 panic（红）；修后=不 panic + toast 出现（ui_tree 断言）+ undo 栈
  无新记录（BRP/ operator 面查询）。红证复现允许经 operator 调用（`terrain.erode`）替代
  按钮点击——同一 operator 入口，效力等同（如实记档所选形态）。

## QA 验收要求

1. 门禁三连亲跑+日志全文复核：fmt / `cargo clippy --workspace -- -D warnings` /
   `cargo test --workspace --lib`（新基线 3095+新增测试数；R4 后 59 二进制口径）。
2. 红绿独立复核（方法自选如实记档，参照 R4 QA 惯例）。
3. 真机腿按上述 MCP 优先形态执行；环境阻塞报主控，不得静默降级。
4. 报告：`loop/reports/bug-r5-report.md` / `bug-r5-qa.md`，证据归档 `loop/bug-r5*/`。
5. 不合入、不打勾、不动 roadmap/progress——收尾归主控。

## 决策点（主控已裁）

- D1 双层守卫（op 拒绝+toast 为主、kernel 早退为兜底），拒绝面不做 UI 按钮置灰
  （gate 变更属面板改动，超票面范围；toast 反馈已够）。
- D2 toast 文案走 `toast_terrain_notice` 既有通道，不新增 UI 机制。
- D3 顺带发现新缺陷 → 立票不并修。
