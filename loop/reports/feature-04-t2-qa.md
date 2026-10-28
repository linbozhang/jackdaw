# 功能 #4 任务 2 QA 验收报告：depgraph 过滤、着色、反查 UI

> 多 Agent 开发循环 · QA（独立第三方）· 2026-10-22
> 对象：分支 `loop/system-graph`，commit `88968fcf`（基于 main `f3e08b88`）
> 方式：逐条亲自核实（diff 通读 + 仓库既有范式对照 + bevy@main 源码求证 + 四门亲跑）

## 结论

**VERDICT: PASS**。四门全 0；规格逐条 ✅（含上轮交底两条）；无 🔴/🟡；3 条 ⚪（不阻塞）。

## 一、确定性门（亲跑，退出码）

| 门 | 退出码 | 计数 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | 无 diff |
| `cargo clippy --workspace -- -D warnings` | 0 | 无 error/warning（Finished） |
| `cargo xtask fast` | 0 | 2796 passed / 2 skipped |
| `cargo xtask integration` | 0 | 4927 passed / 3 skipped |

与程序报告声称一致。11 个新测试（`remote::debug::depgraph::tests::*`）在两门中均实际运行且 PASS（fast 第 613–623 号，integration 同名 11 条），非仅声称。

## 二、规格符合性（逐条）

1. **交底①（picker 排除空串+去重）✅**：`access_component_options` 用 `BTreeSet` 且只收 `!component.is_empty()`；测试 `access_options_exclude_empty_components_and_dedup` 构造含 `("", unbounded)` 条目的 reply，断言候选恰为两个真实类型名（去重+排空双验）。
2. **交底②（exclusive/unbounded 恒命中，双入口同判定）✅**：`access_matches` 对 `system.exclusive` 与任一 `kind == ACCESS_UNBOUNDED` 条目短路返回 true；测试 `unbounded_and_exclusive_match_any_component`（2 任意组件 × unbounded/exclusive 双系统）真实且 PASS。**双入口同一判定**：`matches_filter` 的 Manual 臂直接调 `access_matches`、Selection 臂调 `matches_any` 而 `matches_any` 内部即 `access_matches`——三路汇于同一函数，OR 入口的恒命中由结构保证（OR 路径另由 `selection_filter_matches_any_component` 独立测试）。
3. **手选 AND / 反查 OR ✅**：Manual=`components.iter().all(access_matches)`（`manual_filter_requires_every_component`：双组件全中才中、缺一不中、空过滤全中）；Selection=`matches_any`（任一中即中）。符合主控裁定。
4. **短名兜底 ✅**：`short_name_fallback_matches_across_namespaces` 跨名字空间正例（`sky::physics::Transform` vs `bevy_transform::...::Transform`）+ 短名不匹配反例（`Name` 不中）；`style::short_type_name`（style.rs:15，自带泛型剥离测试）。
5. **着色 ✅**：命中 `ACCENT_BLUE@0.28` / 非命中 `COMPONENT_CARD_BG@0.35` / 无过滤=默认 `COMPONENT_CARD_BG` 三态各有测试（`node_color_highlights_hits_and_dims_misses`、`node_color_defaults_without_filter` 回归锚点）；徽标为 `GraphNodeSpec.subtitle` 文本（`R3 W1`/`ALL`/`EXCL`），非颜色；歧义红边框逻辑在 `spawn_graph_positioned` 内未动；`filter.is_changed()` 已加入 rebuild 触发条件（与 `selected.is_changed()` 并列）。
6. **反查链路两级取值顺序 ✅**：`apply_selection_filter` 先 `RemoteSelection.selected` + `RemoteSceneCache.entities`（`selection_components`，键=reflect type_path），空则 `local_selection_components`（本地 `Selection.entities` archetype 走 `Components::get_info().name()`，与访问表同源）；两空态测试 `selection_components_empty_without_selection_or_entity`（None + 实体不在 cache/despawned）；两链皆空 no-op 不炸。
7. **降级 ✅**：`access_reported == false`（含 reply 为 None）时过滤行替换为 muted 提示、`filtering` 强制 false（色回默认）、徽标隐藏（`access_data.then(...)`）、meta 行追加 `, access data unavailable`；无 panic 路径。
8. **无任务 3 越界 ✅**：diff 恰 5 文件（depgraph/graph/mod/relationships/schedules）；schedules.rs 仅加 3 个 kind 常量，`system_box` 未动；无 book/、无 roadmap 改动。

## 三、偏差抽验

1. **`commands.queue(apply_selection_filter)` ✅ 正确**：bevy@main（c9c397b）`system_param.rs:1005-1027` 证实 `&'_ mut World` 参数注册 write_all、与其他 SystemParam 冲突（B0008），bevy 官方建议原文即 "Using a `Commands` parameter instead of `&mut World` to defer changes"；仓库 40+ 处 `commands.queue(|world: &mut World|` 同款既有模式。延迟闭包内只读资源后写 `AccessFilter`，触发 change detection → 下帧 rebuild，链路正确。
2. **`node_color(filtering, hit)` 双参与 `spawn_graph` 加 `node_colors` 参数 ✅ 均为方案允许**：后者是 D4-2 明列两小改法之一（"给 spawn_graph 加 colors 参数"）；前者偏离草图单参签名，但正是 D4-3 三态语义（无过滤=默认）的可单测化表达，回归锚点因此成立——判定为合理实现期收敛，非违规格。

## 四、代码质量

- 纯函数隔离达标：`access_matches`/`matches_any`/`matches_filter`/`access_component_options`/`node_color`/`access_badge`/`selection_components` 全部纯函数且全有单测；`local_selection_components` 依赖 `&World` 属合理例外。
- `depgraph.rs`/`graph.rs` 全文 **0 个 `.unwrap()`、0 个 `#[allow]`**。
- chips/picker 与 `queries.rs` 范式逐点一致（toggle 关已开 picker、空候选不开、marker 门控 select 写入、`try_despawn`、`EditorEntity`+`BlocksCameraInput`、chip `retain` 移除）；`AccessFilterPicker` vs `FilterPicker` 双 marker 互不串写。
- kind 全部走 `ACCESS_READ/WRITE/UNBOUNDED` 常量，过滤/徽标逻辑零魔法字符串。

## 五、发现（分级）

- ⚪ [程序] 未连接（reply == None）时过滤行提示 "requires a newer jackdaw_remote"——真实原因是未连接，措辞略失真（meta 行同时显示 "no schedules" 可辨）。程序报告偏差 5 已主动上报；建议改为按 `reply.is_some()` 区分两态，或维持现状待任务 3 降级提示行一并处理。
- ⚪ [程序] `access_matches` 对空串过滤组件在 exclusive 判断**之前**返回 false（空串连 exclusive 系统也不命中）——UI 无法引入空串（picker 候选排空、chips 源于候选/快照键），纯防御性选择，语义自洽（空=无操作），无需改。
- ⚪ [既有] `tests/component_shape_refresh.rs` 在无 dylib feature 的裸 `clippy --all-targets` 下 `unfulfilled-lint-expectations`——不在本 diff、不受官方两门影响，与程序报告判断一致，建议后续单独小修。

## 六、给主控 / 任务 3 的 concerns

1. 人工 QA 全套（过滤高亮、From selection 实机、老版本降级驱动、游戏侧帧尖刺 <5ms 门槛）按方案留任务 3，本 QA 仅覆盖 headless 可验证面。
2. 程序报告自报的三条遗留（断连后禁用态短暂滞后但 no-op 安全、本地兜底短名可能多亮、大图徽标性能开关备而未用）核实属实，风险评级同意（均保守方向、无误命中）。
3. ⚪-1 的未连接措辞问题建议并入任务 3 降级提示行一并裁决。
