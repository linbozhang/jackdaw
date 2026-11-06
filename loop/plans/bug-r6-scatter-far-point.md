# R6 修复方案：Scatter placement 远点撑爆稠密网格致编辑器 abort（buglist 🔴）

> 立项：2026-11-06（buglist 第 3 票）。基线：main `8b174e86`。libtests 新基线 **3098**。

## 票面（buglist.md:48-51 摘要）

坐标只有 region 总量上限（1024）无位置边界；远坐标分配 region 后 `stored_extent`
包围盒平方化至 ~100 万格/轴，`sync_terrain_surface` 每帧 `sample_grid_heights_into`
的 `reserve(resolution²)` 达 TB 级 → 下一帧分配失败 abort，撤销救不回来。
修复方向：`add_placement` 拒绝超出当前 regions 包围盒合理余量（如 2 倍跨度）的坐标，
import/adopt 报「落在地形外」。

## 策划期核实（2026-11-06 主控亲读）

1. **闸门现状成立**：`sidecar.rs` `add_placement`（~:1420-1441）仅有
   `has_room_for_one_more()`（MAX_REGIONS 总量闸，票面 1024），**无位置边界检查**，
   远坐标直接 `ensure_region(coord)` 落 region。
2. **平方化成立**：`region.rs` `stored_extent()`（~:622-628）由 `region_bounds()`
   （min/max region 坐标，存在且可复用）× region_size 得每轴格数——单个远 region
   即把跨度拉到百万格级。
3. **回报通道现成**：`src/terrain/scatter.rs` import 路径已有
   `" ({skipped} fell outside the terrain)"` 摘要句式可复用/对齐（Y20 是该文案语义
   反转问题，属另一票，本票不改其语义）。

## 修复方案（主控已裁不变量 + 授权程序细化）

**核心不变量 INV1**：任一被接受的 placement 不得把 `stored_extent` 每轴格数推过
既有值的有限倍数（**裁定默认：当前 regions 包围盒各轴跨度的 2 倍余量**；程序可依
代码实情微调常数/口径，须在报告写明理由）。

- **落点=单咽喉** `add_placement`（sidecar.rs）：region 坐标算出后、`ensure_region`
  之前判定；越界 → 拒绝（不分配、不部分写入）。
  - 既有 regions 为空（首点）：放行（首点 bbox=自身一个 region，天然有界）。
  - 拒绝需可区别于「无房间」（`None` 现语义）：返回形态由程序按调用方实情定
    （`Result`/带原因枚举均可），**调用方用户可见面不得静默丢点**——import 路径对齐
    既有 "fell outside the terrain" 回报，operator 路径 toast/warn。
- **回归保护**：`ensure_grid`/`ensure_extent`（generate 链）与 MAX_REGIONS 语义零变化；
  正常近点导入/绘制行为零变化（含 region 边界处的合法跨 region 点）。
- **范围红线**：产品代码只动 `crates/jackdaw_terrain/src/sidecar.rs`（含测试）与
  `src/terrain/scatter.rs`/`src/terrain/ops.rs`（仅调用方回报面，如确需）；
  不碰 `region.rs` 的 extent 计算、不碰 stamp/sync 链、不碰 Y20 文案语义。

## 测试方案（红→绿）

- **红证（sidecar 单测，先于修复归档）**：近点→远点（如相距 10^6 世界单位）顺序
  `add_placement`，断言「远点被拒」——修前远点返回 `Some` 且 `stored_extent` 爆表
  （断言 extent 数值上限，不真分配内存）；反向顺序（远→近）同测。
- **绿证**：上述两序远点皆拒、近点皆收；首点（空 regions）放行；region 边界邻接点
  （恰在余量内/外各一）边界值测试；MAX_REGIONS 满时既有 `None` 语义不回归。
- **真机腿（QA）**：boot 编辑器 → terrain → scatter import（operator/BRP 驱动，
  坐标文件含 1 远点 + N 正常点）：修前=编辑器 abort（红，允许以单测红证为主、
  真机复红可选）；修后=编辑器存活、摘要报「远点落在外」、正常点照常落位
  （world query 断言 placements 计数）+ 现场存活观察数秒（`sync_terrain_surface`
  稳定跑、日志无分配失败）。

## QA 验收要求

门禁三连亲跑（libtests 新基线 3098+新增数·59 二进制口径）/红绿独立复核（方法自选
如实记档）/真机腿 MCP 优先（本机环境情报与 R5 相同：无 jackdaw.toml 走 Open without
setup、A20 popover 教训、`loop/bug-r5-qa/r5-live.sh` 可整体借鉴）/报告
`loop/reports/bug-r6-{report,qa}.md`、证据 `loop/bug-r6*/`；不合入不打勾，收尾归主控。

## 决策点（主控已裁）

- D1 拒绝判定置于 `add_placement` 单咽喉，不在调用方各自查。
- D2 余量默认 2 倍跨度，程序可微调须说明。
- D3 「无房间 None」语义与「越界拒绝」分离或明确复用，报告写明取舍。
- D4 顺带发现新缺陷 → 立票不并修。
