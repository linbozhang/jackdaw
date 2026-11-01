# T22-T1 程序报告：探针+碰撞内核原型轮（决策 1/2 落判）

> 分支 `loop/t22-tilemap`（自 main 79228723）。任务书=`loop/plans/t22-tilemap.md`
> §四-T1 + §0；主控裁定：决策 1=A 路编译探针顺跑留对照+C 路为主（Sprite.rect 自建族）；
> 决策 2=自建 tile-grid 碰撞内核 ~150-200 行纯函数（否决 avian2d）；决策 3=上游内核缓收
> 记 open-challenges；其余按方案。A 路探针在独立分支 `loop/t22-probe-a`
> （commit 4ab99c85，**不合并**，对照留档）。归档=`loop/reports/t22t1_*`。
> 报告日期 2026-11-01。RUST_BACKTRACE 全程未设。

## 一、结论（定案门）

**决策 1=A 路对照证据在案、C 路主线确认；决策 2=碰撞内核原型红绿双证落地。
回落判据均未触发。** 三件主产物：

1. **A 路编译探针（半日定案项）**：`bevy_ecs_tilemap 0.20.0` 对 fork 编译零漂移、
   组件族 Reflect 面全在、headless 结构性 spawn 全绿——对照证据归档，依赖**不进**主线
   （`bevy_ecs_tilemap` 在工作树 Cargo.toml 零出现）。
2. **碰撞内核原型（决策 2 主件）**：新 crate `crates/jackdaw_tilemap_collision`
   （glam-only 引擎无关）——三态语义+点查/区域查/相邻查+轴分离 AABB sweep，
   红证（naive 脚手架，穿墙/落地/触发三行为全红）→绿证（sweep 实现，
   lib 8/8+App 级 3/3）双证在案；绿跑还抓出并修掉一个区域查询越界 panic 真缺陷。
3. **TM5 守卫（A17 防回滑）**：stage 族新测试 2 件全绿——tile=rect 形态保存
   bsn 无 `texture_atlas` 且 rect 往返；对照件（真 atlas 资产）证明守卫有判别力。

## 二、A 路编译探针落判（对照留档，不合并）

探针分支 `loop/t22-probe-a`：根 crate dev-dependency `bevy_ecs_tilemap = "0.20"` +
`tests/bevy_ecs_tilemap_probe.rs` 三测（日志 `t22t1_probe_a_check.log` /
`t22t1_probe_a_spawn.log`）：

| 探针问 | 结果 | 证据 |
|---|---|---|
| registry 0.20.0 对 fork 的编译漂移（方案唯一结构风险，事实一） | **零漂移**：Locking 1 package（`Adding bevy_ecs_tilemap v0.20.0`），bevy fork 全家**零重编**（feature 统一已满足）——`[patch.crates-io]` 重定向对其 `bevy ^0.20` 直接生效 | check 日志全文 |
| 组件族 Reflect 面（事实二：Inspector picker 门） | `TilePos/TileTextureIndex/TileVisible/TileFlip/TileColor` 全部携带 `ReflectComponent`——Inspector 可编辑门、bsn 往返机均开 | 测 1 PASS |
| `TilemapTexture::Single` 柄空间（A17 免疫的 A 路版） | 纯 `Handle<Image>` 变体，`image_handles()` 产出唯一 image 柄，全程无 TextureAtlasLayout | 测 2 PASS |
| headless 结构性 spawn（per-tile 实体模型的量级预演） | map+tile 双实体 headless spawn，`TileStorage::empty/set/get` 索引正确 | 测 3 PASS |

**落判**：A 路编译面成立（T10 avian3d 同型先例复现）。但按主控裁定 C 路为主，
探针依赖**留在探针分支不合并**；对照结论即本节+日志。A 路完整成本（per-tile 实体
膨胀、画布渲染探针、authoring 全新建）仍按方案 §五-决策 1 表，未重估。

## 三、碰撞内核原型（决策 2 主件）

**落点**：新 crate `crates/jackdaw_tilemap_collision`（workspace `crates/*` 自动纳管；
deps 仅 glam 0.33——引擎无关、模板可引用；`[lints] workspace = true`）。

**形态**（src/lib.rs 444 行=303 代码+100 文档+41 空行；分辨率核心 ~90 行）：

- `CollisionMode{Passable,Solid,Trigger}`——三态语义按上游内核
  `setup.rs:77-82` 逐字移植（doc 注明出处），**零上游代码吸收**（决策 3-B）。
- `TileGrid`：origin/cell_size/width/height，dense 行主序存储；
  world_to_cell（floor 除法）/cell_bounds/cell_center 换算。
- **查询 API（dispatch 三族）**：点查 `mode_at_point`；区域查
  `cells_overlapping`/`solid_cells_overlapping`/`trigger_cells_overlapping`
  （严格相交，边界相触不算）；相邻查 `neighbors`/`neighbor`（四方位，越界=None）。
- **运动分辨率**：`move_probe`——轴分离（先 x 后 y）AABB sweep，对 Solid 格
  夹到最近面并留 `SEPARATION=1e-3` 间隙（静止位置逐位复现，y 稳定断言为逐位相等）；
  blocked 轴速度清零（`hit_wall`）；`is_supported` 脚下支撑闩（x 内缩，
  邻墙顶边不误判为地面）。力（重力/输入）归调用方——内核只解析，确定性可回放。

**红绿单测族**（lib 8 件 + App 级 3 件，`t22t1_kernel_red.log`/`t22t1_kernel_green.log`）：

| 阶段 | 脚手架 | lib | App 级 | 归档 |
|---|---|---|---|---|
| 红 | `move_probe`=naive 积分（无 sweep、grounded 恒 false；临时态，未提交） | 5 绿（纯查询面）/3 红（落地/穿墙/触发） | 0/3 | `t22t1_kernel_red.log`（--no-fail-fast 全量） |
| 绿 | 完整 sweep | **8/8** | **3/3** | `t22t1_kernel_green.log` |

红相判别力：三行为断言（地面站得住/墙挡住/触发区触发）全部只对真 sweep 放行；
绿跑还抓出**一个真内核缺陷**——区域查询对网格外盒子 index 越界 panic
（`first` 未 clamp 到网格上限；触发区走位测试跨出东边界时命中）→已修
（`first/last` 双向 clamp+严格相交复检）。

**App 级探针体**（tests/player_probe_app.rs，bevy dev-dep 无渲染）：Level 资源
+`WalkInput`+`TriggerCensus` 三资源、`apply_inputs→resolve→census_triggers`
链式三系统、单 `PlayerProbe` 实体——三验收断言（落地逐位稳定/墙前 1e-3 驻停+
速度清零/触发 crossing 窗口报告后归零）全绿。**这就是 T2 模板 module
（`{{module_tilemap_collision}}`+`{{module_tilemap_player}}`）的接线形态样张。**

## 四、TM5 守卫测试（A17 防回滑，M14 的 H+FS 半边）

`tests/stage/tilemap_guard.rs`（stage 族挂接，复用 world_app 家族+真 editor 存/开链）：

1. **`the_tile_form_saves_a_rect_and_never_an_atlas`**（PASS）：C 路 tile 形态
   （sheet 柄+`Rect::new(0,0,32,32)`+custom_size 32）spawn→真 `scene_io::save_scene`
   →盘面含 `rect:`、**全文零 `texture_atlas`**；新 editor 重开→rect/custom_size
   逐字段相等+atlas None。
2. **`an_atlas_sprite_is_the_discriminating_control`**（PASS）：真 `sprite_atlas`
   资产（asset.new，T21 SP3 流）+atlas 着装 sprite→盘面**出现** `texture_atlas`
   ——守卫有判别力，非空洞通过。

fork 源码亲证随测试落档：`Sprite.rect` doc「easy one-off alternative to using a
TextureAtlas」（`bevy_sprite/src/sprite.rs:32-37`，方案事实五复核）。M14 的 PX 半边
（画布 tile 像素≠整图）留 T3 L7 真机腿。

## 五、t22-live.sh 骨架+prep 腿

`loop/qa/t22-live.sh`（618 行，t21-live.sh 形态全量复用）：AN2 brp 重试/A9 gbrp
settle/`$PHASE` 日志名/per-phase boot+cleanup trap/warn 扫描
（`tilemap|Tile|UnresolvedTypes|cannot-apply|panicked`）+像素助手族。

- **selftest**（PASS 3 腿）：png 助手在合成 PNG 上自证——尺寸/8 格 8 色
  逐格 md5 判别/census。**格裁剪用 python stdlib 直解**（`png_cells_md5`）：
  T1 探针实证 sips `--cropOffset` 锚点不可靠（A7 家族），格级 census 弃 sips。
- **prep**（本轮实跑）：`jd new`（须 `DYLD_LIBRARY_PATH`，首轮探明）→
  jackdaw_remote 两行 sed 注入（t21 已证形态）→`tiles.png` 4×2 八格八色 sheet
  生成→2D 场景 fixture（Scene2dRoot+Camera2d+**C 路 tile 形态 hero**：sheet 柄+
  rect 格 0）→**模板完整性预检**（`{{module_physics_*}}` 家族四锚在位+
  scaffold `module_physics_*` 函数族在位+`{{module_tilemap_collision}}`
  **预期缺席**（T2 前出现即漂移报警））→fixture 暖编。结果见 §六末行。
- **T3 stubs**：palette/draw/erase/fill/layers/undo/save/stop/run/pie/export/flow
  十二相按 L 腿命名占位（每相独立 boot/cleanup）。

## 六、门禁结果（终树；日志全文捕获于 loop/reports/t22t1_*，exit 仅辅助）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 | t22t1_gates_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0（全文 0 error/0 warning 行） | t22t1_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | t22t1_gates_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3037/3037**（=主线 3029+内核 lib 8；主线自 T21-T1 记录的 3025 后 +4，属 T21 收官 carry 漂移，见偏差 D8） | t22t1_gates_libtests.log |
| 内核 crate | `cargo nextest run --profile ci -p jackdaw_tilemap_collision` | ✅ **11/11**（lib 8+App 3） | t22t1_gates_kernel.log |
| 受影响域 | `cargo nextest run --profile ci -p jackdaw --test stage 'sprite_' 'tilemap_guard'` | ✅ **65/65**（sprite 四族+tilemap_guard 2 件全绿） | t22t1_gates_targeted.log |

> 门禁纪律注记：clippy_ws 首轮红（守卫测试 6 处：缺 `OperatorResultExt` 导入/
> `Name` 遮蔽/缺 `Anchor` 导入/借用冲突/doc_markdown×2）+targeted 首轮红
> （nextest filter 语法误用）——修后**覆盖归档日志**重跑，复跑 EXIT=0 全文零行。
> prep 首轮两红（jd 缺 DYLD env；与门链并发触发 split-runtime dylib 竞态 +
> 陈旧 jd 符号失配，T12-T3「门链单独跑」教训复训）——串行+硬化后 canonical
> 全绿（§七）。
> **prep 实跑结果**：见 `loop/t22-live/console-prep.log` 与 §七。

## 七、prep 实跑账（本轮，canonical run）

- `bash loop/qa/t22-live.sh selftest`：3/3 PASS（SIZE/CELLS/CENSUS）。
- `bash loop/qa/t22-live.sh prep`：**11/11 PASS**——`PREP_JD_NEW` /
  `PREP_REMOTE_INJECT` / `PREP_SHEET` / `PREP_SCENE_2D` / `TPL_module_physics_*`
  ×4 / `TPL_SCAFFOLD_FAMILY` / `TPL_TILEMAP_ABSENT` / `PREP_GAME_WARM`。
  fixture=`/Users/zhanglinbo/workspace/loop-mac/t22-tilemap/t22-tilemap`
  （scene.bsn 含 Scene2dRoot+rect 形态 hero；tiles.png 4×2 八色 sheet；
  remote 注入 Cargo.toml+main.rs 各一行；暖编过）。
- prep 起点磁盘面 73Gi free（A6 纪律行随脚本落）。
- 环境事实（脚本已自愈硬化）：①`jd` 在依赖图变更后（本分支加了 workspace
  成员）会因陈旧 dylib 符号不匹配直接 abort——prep 现按 t21 形态先
  `cargo build -p jackdaw -p jd` 再用；②sips `--cropOffset` 锚点不可靠
  （探针实证，A7 家族）——格级像素 census 定版 python stdlib（`png_cells_md5`）。

## 八、T2 交接

1. **组件族落点已具备承接面**：内核 crate 的 `CollisionMode`/查询面语义即 T2
   `TileCollisionMode`（per-layer 组件）与图层模式行的数据源；`TileGrid` 构造
   函数（origin/cell_size/w/h）与编辑器 `TilemapLayer`（cell_size/columns/rows/
   image 柄）的映射在 `TileGrid::new` 一行。
2. **游戏侧接线形态已钉**：`tests/player_probe_app.rs` 三系统链即
   `{{module_tilemap_collision}}`+`{{module_tilemap_player}}` 的样张；
   决策 6 正式定案（模板 module vs fixture 注入）待 T2 落地面裁定。
3. **TM5 守卫已生效**：T2 的 tile 生成代码落地面直接被
   `tilemap_guard::the_tile_form_saves_a_rect_and_never_an_atlas` 覆盖——生成
   rect 形态即绿，滑回 atlas 柄即红（对照件机制已验）。
4. **调色板渲染形态样张（决策 4 三案）与 rect 双端像素探针（M14 PX 半边）
   未在本轮 dispatch 口径内**——移交 T2 落地面/T3 L2+L7（见偏差 D3/D4）。
5. **A 路对照**：探针分支 `loop/t22-probe-a` 不合并；若 T2/T3 实现误引入
   `bevy_ecs_tilemap`，`grep bevy_ecs_tilemap Cargo.toml` 即红。

## 九、偏差清单

| # | 偏差 | 处置 |
|---|---|---|
| D1 | 内核 303 代码行 vs 方案估 150-200 | 如实记档：方案估只含分辨率核心（实测 ~90 行）；差额=dispatch 明确要求的三族查询 API+Aabb/Direction 辅助面。零裁剪需求——语义面无一超纲 |
| D2 | 方案 T1-1①「rect 裁剪双端像素探针」未跑 | dispatch 执行要点未含真机项；其 headless/FS 半边已由 TM5 守卫（§四）落地；像素半边移交 T3 L2/L7（M14 PX） |
| D3 | 方案 T1-1③ 调色板渲染形态三案样张（决策 4）未跑 | dispatch 执行要点未含；决策 4 移交 T2 落地面（A 主选维持） |
| D4 | 方案 T1-3 决策 6 两形态 demo 未跑 | 同上口径；App 级原型（§三）已给出接线形态样张，决策 6 正式定案移交 T2 |
| D5 | clippy_ws/targeted 首轮红（守卫测试 6 lint+1 借用+filter 语法） | 已修+覆盖归档日志重跑（§六注记） |
| D6 | prep 首轮红：jd 缺 DYLD_LIBRARY_PATH；与门链并发→dylib 竞态；依赖图变更后陈旧 jd 符号失配；sips cropOffset 锚点不可靠 | 均已修入脚本并硬化（§五/§七）；格裁剪定版 python stdlib（A7 家族自守的顺带收获） |
| D7 | 内核绿跑抓出区域查询越界 panic（真缺陷） | 已修（clamp）+守红绿在案（§三）；触发走位测试即为回归格 |
| D8 | libtests 3037 ≠ dispatch 口径「3002+新增」 | 3037=主线 3029+内核 8；主线自 T21-T1 记录 3025 后 +4（T21 收官 carry 合入的测试增量），非本轮引入 |
| D9 | A 路探针分支保留未合并 | dispatch 允许「独立分支」隔离；对照证据=§二+两日志，依赖树零残留 |

## 十、给 QA 的注意事项

1. **零 fork 变更、零 buglist/台账/roadmap 触碰**（纪律）；本轮唯一新依赖面=
   `crates/jackdaw_tilemap_collision`（glam-only，workspace 成员），无 Cargo 结构
   动作（`[patch]`/workspace members glob 未动）。
2. **A 路对照分支 `loop/t22-probe-a` 在本地存在**——QA 复核勿合并；主线依赖树
   `grep bevy_ecs_tilemap Cargo.toml` 应零命中。
3. **内核红绿复核入口**：`cargo nextest run --profile ci -p jackdaw_tilemap_collision`
   （11 件）；红证=`loop/reports/t22t1_kernel_red.log`（naive 脚手架为临时态、
   未入库，绿证=`t22t1_kernel_green.log`）。触发走位测试（跨网格东边界）是
   D7 缺陷的永久回归格。
4. **TM5 守卫在 stage 族**：`cargo nextest run -p jackdaw --test stage tilemap_guard`
   两件；QA 真机轮（T3 L7）做 M14 的 PX 半边时，headless 半边已在案，勿重复建设。
5. **t22-live.sh 用法**：逐相单独跑（`selftest`/`prep` 现用，余 T3 占位）；
   prep 自带 editor/jd 暖编（依赖图变更后陈旧 jd 会 abort，脚本已自愈）；
   脚本与编辑器/游戏/门链**不同窗并发**（本轮 dylib 竞态实证）。
   fixture=`/Users/zhanglinbo/workspace/loop-mac/t22-tilemap/t22-tilemap`。
6. **prep 的模板预检语义**：`TPL_TILEMAP_ABSENT` 是**预期通过**项
   （`{{module_tilemap_collision}}` 在 T2 落地前出现=漂移报警）；T2 落地后该腿
   需翻转为存在断言。
7. libtests 基线口径：本分支起 **3037**（含内核 8）；后续轮次的增量按此基线计。
