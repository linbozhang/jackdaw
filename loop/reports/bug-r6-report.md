# R6 程序报告：Scatter placement 坐标无界，远点撑爆稠密网格致编辑器 abort

> 分支 `loop/bug-r6-scatter-far-point`（自 main `8b174e86` 拉）。**未合入 main，待 QA。**
> 证据：`loop/bug-r6/{red,green,fmt,clippy,libtests}.log`。

## 一、数据流（读透后的全链路）

### 1.1 写入路径（谁调 `add_placement`）

```
import operator  terrain.scatter.import (src/terrain/scatter.rs:655)
  └─ scatter_data::stamp (src/terrain/scatter_data.rs:200)      ──┐
stamp operator   存储组重铺 (scatter.rs:1389, 程序化生成点)      ──┼─→ TerrainData::add_placement
adopt operator   Adopt Scatter Group (scatter.rs:2035)            │    (crates/jackdaw_terrain/sidecar.rs)
  └─ scatter_data::adopt (scatter_data.rs:524)                  ──┘     │ placement_slot 算 region 坐标
                                                                          │ 边缘回退（末顶点落回已有 region）
                                                                          │ has_room_for_one_more  ← 修复前唯一闸（总量 1024）
                                                                          │ ensure_region(coord)   ← 远点在这里落 region
navmesh bake (integrations/navmesh/.../bake.rs ×3)、render/scatter.rs ×2、
sidecar 自测 —— 均为测试或小坐标，签名不变即零影响
```

### 1.2 abort 链（票面机理核实，只读未动）

```
add_placement 接受远坐标
  └─ ensure_region(coord≈(3906,3906))            → regions 有了极远一角
      └─ region_bounds() min/max 跨度 ≈3907 个 region
          └─ stored_extent() (region.rs:622)      → 每轴格数 ≈ 3907×256 ≈ 1,000,192
              └─ grid_resolution() (sidecar.rs:1184) = stored_extent.max
                  └─ sync_terrain_surface (src/terrain/mesh.rs:127)
                      └─ store.grid_shape → heightmap →
                         sample_grid_heights_into (region.rs:796)
                            out.reserve(resolution²) ≈ 1e12 × 4B ≈ 4TB → 下一帧分配失败 abort
```

### 1.3 回报面（修复前）

| 路径 | 修复前行为 |
|---|---|
| import（scatter.rs:756-772） | skipped = 提交数 − 存储数，`" ({skipped} fell outside the terrain)"` 已存在；但修复前 skipped 只可能来自满仓（远点总是被接受），远点导入实际是「全收 + 下帧 abort」 |
| stamp operator（scatter.rs:1389-1416） | 只报 `placed {stored}`；其点位由高度图程序化生成、必然在地形内，**不会**触发位置闸，未改（见 D3/偏差） |
| adopt operator（scatter.rs:2049-2056） | 只报 `{adopted} placements now stored`；手摆模型可在世界任意位置 → **真实可静默丢点的路径**，本次对齐 |

## 二、diff 面

| 文件 | 改动 | 性质 |
|---|---|---|
| `crates/jackdaw_terrain/src/sidecar.rs` | +326/−6：`MAX_EXTENT_CELLS_PER_AXIS=4096`、`PlacementRefusal{NoRoom,OutsideExtent}`+Display、`add_placement` 委托新 `try_add_placement`（Result）、`placement_within_extent` 位置闸、测试 7 个 | 核心修复（主战场） |
| `src/terrain/scatter.rs` | +14/−1：adopt 回报语句（`asked` 计数 + `" ({refused} fell outside the terrain)"` 后缀） | 回报面对齐（红线授权范围内，仅回报语句） |
| `loop/plans/bug-r6-scatter-far-point.md` | 方案书入库（R5 惯例） | 文档 |
| 其余 | **零改动**：region.rs / stamp / sync / Y20 文案语义 / buglist / roadmap / progress 均未碰 | — |

## 三、修复设计

**闸门（单咽喉，`try_add_placement` 内、`ensure_region` 之前）**：当一个 placement 需要分配**新 region**（`region(coord).is_none()`，已有 region 直接放行——不扩张 extent）时：

- **有 regions**：按轴算「若接受则 stored_extent 每轴格数」=（跨度 ∪ coord）× region_side，须 ≤ `MAX_EXTENT_CELLS_PER_AXIS`（4096 格）。i128 宽乘防 legacy 极端坐标溢出。
- **空 regions（首点）**：coord 须落在种子窗内——`|coord.x|、|coord.z| ≤ 4096/side − 1`（side=256 时 ±15 region）。种子窗与上限自洽：种子在窗缘时 extent 恰为 4096 格，随后的近点仍可被接受。

**为什么是绝对上限而不是方案书默认的「2 倍跨度」**（D2 口径微调，主控授权「程序可依代码实情微调常数/口径，须写明理由」）：
1. 纯比例口径会**复利**：每次贴窗接受的点把可达半径 ×3，8 个递远点即可从 1 region 爬回百万格——同样的 abort 换了个入场姿势。绝对上限在第一次接受时就封顶总量，是 abort 机理 `reserve(resolution²)` 的精确反量。
2. 「两序远点皆拒、近点皆收」的绿证要求，纯 bbox 比例口径做不到（远点先到会占住包围盒、反手拒掉所有近点）；绝对上限 + 种子窗两序行为一致。
3. 常数依据：新地形 extent = 4 region × 256 = 1024 格/轴（`FRESH_TERRAIN_REGIONS`）；4096 = 4×余量，稠密高度缓冲上界 64 MiB（对照票面 TB 级），远超当前一切合法流（fresh 1024 / import ensure_extent(1024)）。
4. 首点放行语义保留：空文档的**正常**首点（coord 在种子窗内，含一切落在地形网格上的点）照常放行；被拒的只是「首个点就百万单位外」这种本身就是脏数据的情况。

**拒绝语义（D3 取舍：显式复用 + 可区分并存）**：
- `add_placement` 签名不变（`Option`），两种拒绝都归 `None`——**显式复用**，全部既有调用方（scatter_data stamp/adopt、navmesh bake、既有测试的 `.expect()`）零改动、零行为漂移。
- 新增 `try_add_placement -> Result<_, PlacementRefusal>`：需要区分的调用方走它；`NoRoom` = 满仓（原 `None` 语义原样），`OutsideExtent` = 越界。判定顺序：满仓先于越界（满仓+越界双重病理时报 NoRoom，保持既有满仓行为字节不变）。
- 用户可见面不静默：import 路径复用既有 `fell outside` 摘要（skipped 现在真的会因越界 >0）；**adopt 路径补上同句式后缀**（真实可达的静默丢点路径）；stamp operator 程序化点位不可能越界，未加死分支（见偏差 §六）。

## 四、测试清单（红→绿）

定向测试 6 个（`sidecar.rs` 测试模块，前 5 个红绿同文、只引用修复前 API）：

| 测试 | 断言 | 修复前 | 修复后 |
|---|---|---|---|
| `a_far_point_after_near_ones_is_refused_and_the_extent_stays_bounded` | 近点收；远点(1e6,1e6)拒；extent ≤4096/轴；region 数不增 | 🔴 FAILED（远点 Some） | ✅ |
| `a_far_point_that_arrives_first_is_refused_and_near_ground_still_stores` | 远点先到拒、零分配；近点照收；extent 有界 | 🔴 FAILED | ✅ |
| `a_point_landing_the_extent_on_the_cap_stores_and_one_past_it_is_refused` | 恰在上限内（extent=4096）收；超一 region 拒且 extent 不动 | 🔴 FAILED | ✅ |
| `a_point_just_past_the_stored_ground_still_claims_the_region_under_it` | 贴边一点照常领相邻 region（合法增长不回归） | ✅（守卫） | ✅ |
| `a_terrain_at_the_region_cap_keeps_its_no_room_meaning` | 满仓时已有 region 照存、需新地拒（原 None 语义不回归） | ✅（守卫） | ✅ |
| `the_two_refusals_are_named_and_both_read_as_none_through_add_placement`（随修复加入，D3） | `OutsideExtent`/`NoRoom` 各归各位；`add_placement` 对两者仍答 `None` | —（新 API） | ✅ |

- 红证：`loop/bug-r6/red.log`（3 FAILED / 2 passed，失败行如实：3845「the far point is refused, not stored」、3873「the far first point is refused」、3918「one region past the cap is refused」）。extent 断言用数值上限，未真分配大内存。
- 绿证：`loop/bug-r6/green.log`（fmt 归一后重跑，6 passed）。

## 五、门禁（QA 请以日志全文复核为准，exit code 仅辅助）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | exit=0，无输出 | `loop/bug-r6/fmt.log` |
| `cargo clippy --workspace -- -D warnings` | exit=0，全文无 error/warning 行 | `loop/bug-r6/clippy.log` |
| `cargo test --workspace --lib` | **3104 passed / 0 failed / 59 二进制全部 ok**，exit=0（= 基线 3098 + 新增 6）；全文唯一 `ERROR` 行是某测试固件预期内的日志输出（`jackdaw::pie: PIE: game build of my-game failed`，测 PIE 构建失败路径），非门禁失败 | `loop/bug-r6/libtests.log` |

## 六、偏差与如实记录

1. **D2 口径从「2 倍跨度」改为「绝对上限 4096 格 + 首点种子窗」**：理由见 §三。这是本票最大的口径偏移，请主控复核。
2. **stamp operator 回报面未加 skipped 后缀**：其点位由 `jackdaw_terrain::scatter` 从高度图生成、必然在地形内，越界拒绝在该路径不可达；加后缀是死分支。红线要求「回报面如确需」才动——此处判为不需。满仓拒绝在该路径本就不显示 skipped，属既有行为（Y20 文案语义域），未碰。
3. **红线内文件集之外零改动**；`src/terrain/scatter.rs` 只动了 adopt 的回报语句（+`asked` 计数一行，为算 refused 所必需的最小 diff）。
4. **顺带发现、未修（交主控立票裁量）**：
   - a) `stored_extent()`（region.rs:626）自身在 legacy 极端 region 坐标（min/max 跨 i32 全域）时 i64 乘法可溢出（debug panic/release 回绕）——本次在 sidecar 闸门里用 i128 自保，但 region.rs 原函数未动（红线）。
   - b) import 摘要的 `fell outside the terrain` 对「满仓」拒绝也用同一句（既有语义，Y20 域）。
   - c) seed 窗缘（coord ±15）首点放行后，随后负方向近点会被上限拒绝（extent 已 4096）——有界但方向不对称；绝对上限口径的固有性质，实际影响需 QA 真机腿观察。
5. 真机腿（boot 编辑器 + 含远点坐标文件的 scatter import + 存活观察）按方案书归 QA。

## 七、给 QA 的验收提示

- 单测腿：复跑 §四 6 个定向测试；独立复红可 `git stash` 产品代码保留测试（测试只依赖修复前 API，stash 后 3 个拒绝断言应红）。
- 真机腿：坐标文件 = N 正常点 + 1 远点（如 1e6）。修后期望：编辑器存活、摘要 `imported {N} into '...' (1 fell outside the terrain)`、world query 断言 placements 计数 = N、`sync_terrain_surface` 稳定跑数秒无分配失败日志。
