# R6 QA 报告：Scatter 远点撑爆稠密网格（位置闸）

> 分支 `loop/bug-r6-scatter-far-point`，commit `db31900a`（自 main `8b174e86` 拉）。
> QA 独立亲跑，证据 `loop/bug-r6-qa/`（qa-fmt / qa-clippy / qa-libtests / qa-red-stripped /
> qa-red-extent-blowup / qa-green-restored / r6-console / r6-editor / r6-*.json / r6-live.sh）。
> **总判定：PASS。不合入、不打勾，收尾归主控。**

## 一、逐项判定表

| # | 验收项 | 判定 | 证据（QA 亲跑归档） |
|---|---|---|---|
| 1 | diff 面复核 | **PASS** | `git diff main..loop/bug-r6-scatter-far-point --stat`：恰为程序自报范围——产品代码 2 文件（`crates/jackdaw_terrain/src/sidecar.rs` +326/−6、`src/terrain/scatter.rs` +14/−1）+ 证据 5 日志 + 方案书 + 报告；`region.rs`/`ops.rs`/buglist/roadmap/progress 零改动 |
| 2 | 门禁三连 | **PASS** | fmt exit=0 无输出；clippy exit=0 全文无 error/warning 行；libtests **3104 passed / 0 failed / 59 二进制全 ok**（= 基线 3098 + 新增 6，六条 R6 定向测试逐条核对 ok）。全文唯一 ERROR 行均为测试固件预期日志（bevy_asset loader miss、PIE 构建失败路径测试），与程序报告 §五 一致 |
| 3 | 红绿独立复核 | **PASS** | 方法：工作区摘除位置闸（`try_add_placement` 中删除 `placement_within_extent` 判定，保留 NoRoom）→ 复红 → `git checkout` 还原 → 复绿。详见 §二 |
| 4 | D2 上限正确性专项核验 | **PASS** | 4096 ≥ generate/sculpt 合法链最大 extent（1024），4 倍余量，无阻断。推演见 §三 |
| 5 | 真机腿 | **PASS** | boot 编辑器（bsn_game fixture，Open without setup）→ add terrain → generate → scatter import 注入「2 正常点 + 1 远点」。四断言全命中，详见 §四 |
| 6 | 报告 | 本文档 | — |
| 7 | 证据归档 | 完成 | `loop/bug-r6-qa/` + 本报告在该分支 commit；未合入 main；fixture 无残留（scene.bsn SHA 前后一致、布局文件已删、git status 干净） |

## 二、红绿独立复核（方法与结果如实记档）

**方法**：程序报告 §七 提示的「stash 产品代码保留测试」会连带破坏第 6 条测试（它引用新 API
`try_add_placement`/`PlacementRefusal`），故改用**摘闸法**：直接在工作区 `sidecar.rs` 删除
位置闸三行（`if !self.placement_within_extent(coord) { return Err(OutsideExtent) }`），
NoRoom 判定保留——等价于「修复前」的位置语义（修复前位置无任何闸）。

**红（`qa-red-stripped.log`）**：`cargo test -p jackdaw_terrain --lib sidecar::tests`
→ **111 passed / 4 FAILED**：

- `a_far_point_after_near_ones_is_refused_and_the_extent_stays_bounded` — panicked
  「the far point is refused, not stored」（sidecar.rs:3931）
- `a_far_point_that_arrives_first_is_refused_and_near_ground_still_stores` — panicked
  「the far first point is refused」（:3959）
- `a_point_landing_the_extent_on_the_cap_stores_and_one_past_it_is_refused` — panicked
  「one region past the cap is refused」（:4004）
- `the_two_refusals_are_named_and_both_read_as_none_through_add_placement` —
  `assertion left == right failed: the far point names the extent — left: Ok((RegionCoord
  { x: 3906, z: 3906 }, 0)), right: Err(OutsideExtent)`（远点被接受并分配了票面所述的
  region (3906,3906)）

守卫测试 `a_point_just_past_the_stored_ground_still_claims_the_region_under_it` 与
`a_terrain_at_the_region_cap_keeps_its_no_room_meaning` 摘闸后仍 ok——证明红/绿差异
恰由位置闸产生，且二者的「合法增长/满仓语义」与位置闸无关。

**extent 爆表复现（`qa-red-extent-blowup.log`）**：拒绝断言 panic 在 extent 断言之前，
爆表数值不会打印，故另加一条临时测试（已随还原删除）在摘闸态下直读 `stored_extent`：

```
QA RED REPRO: far point landed=Some((RegionCoord { x: 3906, z: 3906 }, 0))
stored_extent=1000192 x 1000192 cells per axis
(dense buffer would reserve 1000192x1000192x4B = 3 TiB)
```

与票面机理（~1,000,192 格/轴、TB 级 reserve、下一帧 abort）逐位吻合。

**绿（`qa-green-restored.log`）**：`git checkout` 还原后重跑 → **115 passed / 0 failed**，
六条 R6 定向测试全 ok。

对照程序自带红证（`loop/bug-r6/red.log`，3 FAILED 于 ：3845/:3873/:3918）与绿证
（`green.log`，6 passed）：行号差异系第 6 条测试后加入所致，内容一致，采信。

## 三、D2 上限正确性专项核验（推演专节）

**命题**：4096 格/轴是否 ≥ 最大合法 dense grid 的 extent（即 generate/sculpt 合法地形
永远不会被新闸误拒）？

**源码事实链（全部亲读核实）**：

1. `RegionSize::DEFAULT = RegionSize(256)`（region.rs:128）。生产文档创建路径唯一：
   `RegionTerrainData::default()` → `TerrainRegions::new(RegionSize::DEFAULT)`
   （sidecar.rs:1170）。全仓其余 `RegionSize::new(...)` 调用均位于测试代码。
2. `MAX_REGIONS = 32*32 = 1024`（region.rs:40）是 region **数量**上限，不是位置边界。
3. `ensure_grid(resolution)`（region.rs:639）：自 (0,0) 起铺 `span×span` 正方形
   （span = ceil(res/side)），`held + wanted > 1024` 时整体拒绝——**不越 (0,0) 象限，
   不产负坐标 region**。
4. **generate 链的 region 分配点仅两处**：`terrain_generate`（ops.rs:250）与 terrain
   import（import.rs:613），均只在空文档（`grid_resolution()==0`）时
   `ensure_extent(FRESH_TERRAIN_REGIONS × 256)` = `ensure_extent(1024)` → 4×4 regions
   @ (0..4)² → **stored_extent = (3+1−0)×256 = 1024 格/轴**。
5. **sculpt/paint/erode 链零隐式分配**：写路径 `write_grid_heights/write_grid_control`
   使用文档自身 `grid_resolution()`（= 存量 extent max，sidecar.rs:1278-1286），re-ensure
   不自扩张；brush/erode 操作不新建 region（sculpt.rs 测试注释 "nothing allocates
   implicitly" 与代码一致）。
6. scatter 的 `add_placement` 是唯一能把 extent 推过 1024 的生产路径——修复后它自身封顶
   4096。理论形态「1024 regions 全铺 @256 侧 = 8192 格/轴」需要某处以 resolution 8192
   调 `ensure_grid`，grep 全查生产代码无此调用（唯一 `ensure_extent` 调用传 1024），
   **不可通过合法流到达**。
7. `stored_extent()` 公式 `(hi+1−min(lo,0))×side`；闸门 reach 公式
   `(max(hi,at)−min(lo,at)+1)×side`。lo≥0 时两式同为 `(hi+1−lo)×side`；lo<0 时同为
   `(hi+1−lo)×side`——**接受瞬间的 would-be extent 与之后真实 extent 逐项等价，无口径漂移**。
8. 种子窗自洽：窗 = 4096/256 − 1 = 15 region。首点在窗缘 (±15,±15) 时 extent =
   16×256 = **恰 4096**，与上限严丝合缝；此后近点仍可接受直至贴上限
   （定向测试 3 实证 extent=4096 时收、超一 region 拒）。
9. i128 宽乘：i32 全域跨度（~2^33）× u32 side（~2^31）≈ 2^64 量级，i128 无溢出，
   legacy 极端坐标下闸门自安全。
10. 阈值性质：4096²×4B = 64 MiB 稠密缓冲上界；即使贴上限再 +1 region（4352 格），
    reserve ≈ 72 MiB 亦远非 abort（abort 需 ~1e6 格/轴）。上限是 4 倍于合法链上限的
    保守护栏，不是贴脸阈值。

**结论**：**最大合法 generate/sculpt extent = 1024 格/轴；4096 ≥ 1024，PASS，无阻断。**
且闸门仅在「需分配新 region」时生效——`placement_within_extent` 首行对已有 region
短路放行，合法地形既有 ground 上的 placement（含 region 边界合法跨 region 点）永不被拒。

**headless 佐证**（QA libtests 亲跑日志内核对，全绿）：
`allocating_past_the_cap_is_refused_whole`（ensure_grid(32) side=1 恰满 MAX_REGIONS、
ensure_grid(33) 整体拒绝）、`the_cap_refusal_names_what_it_refused`、
`an_empty_document_has_no_stored_extent`、`a_region_far_from_the_origin_widens_the_terrain_to_reach_it`
（ensure_region 直连路径语义不变）。

**边界说明（不阻断）**：legacy 密网格文档迁移 `from_legacy_v1` 可产出 >4096 格/轴的
存量文档（如 resolution 8192 → extent 8192）。该路径不属于 generate/sculpt 合法链；
且此类文档上既有 ground 的 placement 仍全部放行，仅新 region 声明被拒——行为合理，
不构成误拒。见 §五偏差 4。

## 四、真机腿（MCP/BRP 驱动，形态如实记档）

驱动形态：bash+curl+jq 直连 BRP（`loop/bug-r6-qa/r6-live.sh`，复刻 r5-live.sh 模式；
无 jackdaw.toml fixture 走 **Open without setup** 真实路径，ui_click 点开）。

流程：boot（pid 3754，1920x1080）→ `entity.add.terrain` → `terrain.generate`
（fresh 4×4 regions，extent 1024）→ 写布局文件（项目内 `assets/r6-qa-scatter.json`）→
`terrain.scatter.import {path, terrain:"Terrain", group:"r6probe"}`，内容 = 2 正常点
（(10,10)、(500,500)）+ 1 远点（(1,000,000, 1,000,000)）。

| 断言 | 结果 | 证据 |
|---|---|---|
| ① 编辑器存活 | **命中** | import 后立即 alive；3 轮 `wait until=idle` 存活观察（约 12s，修前 abort 落在下一帧）；RSS 744,976 → 747,872 KB（+2.9MB，无爆量）；编辑器日志 `panicked\|abort\|allocation failed` 计数 = **0**；FINAL_ALIVE（teardown 主动杀前） |
| ② 远点被拒且用户可见回报 | **命中** | `call_operator` 应答 reports：`terrain.scatter: imported 2 into 'r6probe' (1 fell outside the terrain)`（`r6-import-probe.json`）；编辑器日志 INFO 同文（`r6-editor.log`）；**ui_tree 全量 walk 命中可见 text 节点**：`{"entity":8589930764,"kind":"text","text":"imported 2 into 'r6probe' (1 fell outside the terrain)","rect":[1677,555,235,11]}`（Scatter 面板摘要行） |
| ③ 正常点照常落位 | **命中** | 摘要计数 `imported 2`（= 3 提交 − 1 拒）；far-only 二次导入 `imported 0 into 'r6probe2' (1 fell outside the terrain)`（负方向远点同拒） |
| ④ 回归锚（近点行为修前修后一致） | **命中** | 修后：`imported 2 into 'r6qa-near'`（无 note，`r6-import-near.json`）；修前行为=近点接受：程序红证与 QA 摘闸红跑中守卫测试 `a_point_just_past_the_stored_ground_still_claims_the_region_under_it` 均绿（摘闸态即修复前语义，近点接受、region 正常增长） |

附带观察：假资产名 `a.glb` 触发的 asset load 失败 WARN（"its placements draw nothing"）
为渲染层对缺失资产的既有优雅降级，与位置闸无关。

收尾：scene.bsn SHA256 前后一致（不存盘策略）；两份布局文件已删；`git status` 对
fixture 干净。

## 五、偏差清单

1. **D2 口径偏移（主控已裁接受，QA 复核通过）**：「2 倍跨度」→「绝对上限 4096 格/轴 +
   空文档首点种子窗」。QA 复核意见：**正确且必要**。复利论证成立（纯比例口径下每次贴窗
   接受把可达半径 ×3，递远点序列可爬回同一 abort）；绿证的「两序远点皆拒、近点皆收」
   只有硬上限能做到（bbox 比例口径下远点先到会占住包围盒反手拒掉近点）；4096 ≥ 合法链
   上限 1024 有 4 倍余量（§三推演）。
2. **stamp operator 未加 skipped 后缀**（程序判死分支）：复核同意——stamp 点位由
   高度图程序化生成、必然在地形内，位置闸在该路径不可达；加后缀确为死代码。
3. **`src/terrain/scatter.rs` 最小 diff**：亲读确认只动 adopt 回报语句 + `asked` 计数
   一行（为算 refused 所必需），红线授权范围内。
4. **legacy 密网格文档**（`from_legacy_v1`，extent 可 >4096）：非 generate/sculpt 合法链；
   既有 ground placement 不受影响，仅新 region 声明被拒。行为合理，不阻断；主控如认
   需要可另行立票。

## 六、程序顺带发现 a/b/c 的复核意见

| 项 | 程序描述 | QA 复核 |
|---|---|---|
| a | `region.rs` `stored_extent()` 自身在 legacy 极端坐标（min/max 跨 i32 全域）时 i64 乘法可溢出（debug panic / release 回绕）；本次闸门用 i128 自保，原函数未动（红线） | **核实成立**。span 公式为 i64 运算，i32 全域跨度 +1 后 × side 可超 i64。修复未扩大该暴露面（闸门先行拦截可承受的新 region），原函数属红线禁改。建议主控立票（低优先：需 legacy 极端坐标文档才可达） |
| b | import 摘要对「满仓」拒绝也用 `fell outside the terrain` 同句 | **核实成立**（skipped = 提交数 − 存储数，来源不分 NoRoom/OutsideExtent）。属 Y20 文案语义域，本票红线明确不改其语义。同意维持，Y20 处置 |
| c | 种子窗缘（首点 ±15）放行后，负方向近点会被上限拒（extent 已 4096），方向不对称 | **核实成立**（首点 (15,15) 后负方向一点 reach=(16+16)×256=8192>4096）。绝对上限口径的固有性质；触发条件苛刻（用户首个点恰落窗缘再反向铺点），本票真机腿未触发（首点在正常地形网格内）。建议主控裁量是否立票（低优先） |

## 七、结论

七项验收全 PASS，无阻断项。修复正确、最小、红绿闭环、真机四断言全命中，D2 口径偏移
经专项推演核验成立。

**不合入、不打勾，收尾归主控。**
