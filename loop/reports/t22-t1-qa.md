# T22-T1 QA 报告：探针+碰撞内核原型轮 —— 裁决 PASS（放行 T22-T2）

> 验收对象=`loop/reports/t22-t1-report.md`（分支 `loop/t22-tilemap`，程序提交 3db59ef2，
> 自 main 79228723；基线 ccca1c9e）。方案=`loop/plans/t22-tilemap.md` §四-T1+§五决策表；
> 主控裁定：决策 1=A 路探针顺跑留对照+C 路为主、决策 2=自建 tile-grid 碰撞内核、
> 决策 3=内核缓收（其余按方案）。QA 亲跑日期 2026-11-01。归档=`loop/reports/t22t1_qa_*`
> （七门日志+live 三件+summary 时间线）。RUST_BACKTRACE 全程未设；门链/脚本分窗串行。

## 一、结论

**PASS。** 三主件（A 路对照探针不合并留档 / 碰撞内核红绿双证 / TM5 守卫带判别对照）
全部亲核成立；七门亲跑全绿（日志全文复核，exit 仅辅助）；selftest 3/3+prep 11/11 亲跑
复现；D1-D9 逐条裁定（§六），另 3 条记档级发现（§五 F1-F3），无阻断项。

## 二、门禁表（QA 亲跑终树 3db59ef2；日志全文复核为准）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 零 Diff | t22t1_qa_gates_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 error/warning 行 | t22t1_qa_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0，全文零行 | t22t1_qa_gates_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3037/3037**（=3029+内核 8，拆账见 D8） | t22t1_qa_gates_libtests.log |
| 内核 crate | `cargo nextest run --profile ci -p jackdaw_tilemap_collision` | ✅ **11/11**（lib 8+App 3） | t22t1_qa_gates_kernel.log |
| 受影响域 | `cargo nextest run --profile ci -p jackdaw --test stage 'sprite_' 'tilemap_guard'` | ✅ **65/65**（sprite 四族 drop/gizmo/picking/snap+tilemap_guard 2） | t22t1_qa_gates_targeted.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，fmt/clippy 段零行，lib 段 **3037/3037** | t22t1_qa_gates_fast.log |

- 门禁前 df：72Gi free（A6 纪律）。
- 归档日志逐行扫描：libtests 日志仅 2 处 `panicked` 命中，均为既有测试名
  （`..._inserted_not_panicked`/`..._dropped_not_panicked_on`）的子串，零真警；
  fast/targeted/clippy 三日志零 error/FAILED/Diff 行。
- 程序归档（t22t1_gates_*）与 QA 复跑逐门同形；**F2：程序门禁表无 fast 行**（§五）。
- **live 亲跑**：`t22-live.sh selftest`=3/3（SIZE/CELLS/CENSUS）、`prep`=11/11
  （JD_NEW/REMOTE_INJECT/SHEET/SCENE_2D/TPL_module_physics_*×4/SCAFFOLD_FAMILY/
  TILEMAP_ABSENT/GAME_WARM），EXIT=0（t22t1_qa_live_selftest.log/t22t1_qa_live_prep.log/
  t22t1_qa_live_warmbuild.log）。程序 canonical console 日志已保全（QA 复跑日志另档，
  `loop/t22-live/` 工作树还原干净）。fixture 盘面亲验：scene.bsn 含 rect 形态 hero、
  tiles.png 4×2 八色、remote 两行注入在位。prep 日志 warn 扫描：2 命中均为包名/路径
  子串（`Compiling t22-tilemap`/fixture 路径），零真警。进程清理亲验（无残留）。

## 三、A 路探针复核（不合并裁定核+三结论互证）——全过

1. **不合并+保留**：`loop/t22-probe-a`=4ab99c85，`git merge-base --is-ancestor` 判
   非本支祖先 ✓；diff 面=恰 3 文件（根 Cargo.toml dev-dep `bevy_ecs_tilemap = "0.20"`
   +Cargo.lock +151 行 tests/bevy_ecs_tilemap_probe.rs），无第四文件 ✓。
   **主线零残留**：HEAD 全树 grep `bevy_ecs_tilemap` 零命中；本支 Cargo.lock 增量恰为
   新内核 crate（bevy dev-dep+glam）✓。
2. **三结论与源码/日志互证**：
   - **编译零漂移**：check 日志 `Locking 1 package`+`Adding/Downloaded/Checking
     bevy_ecs_tilemap v0.20.0`，**bevy fork 全家零 Compiling 行**（patch 重定向直接生效，
     feature 统一已满足）——依赖本体两轮编译零 error/warning ✓（T10 avian3d 同型先例复现）。
   - **五组件 ReflectComponent 全在**：探针测 1 经 AppTypeRegistry 逐 TypeId 断言
     TilePos/TileTextureIndex/TileVisible/TileFlip/TileColor 五件 `ReflectComponent`
     非空（Inspector picker 门+bsn 往返机）——spawn 日志 3/3 PASS ✓。
   - **TilemapTexture::Single 纯 Image 柄**：探针测 2 模式匹配 Single 变体+
     `image_handles()` 恰 1 柄+全程不命名 TextureAtlasLayout（A17 免疫的 A 路版）✓。
3. **F1（记档）**：归档 check 日志是**首轮红**（EXIT=101：4 个 error 全在探针自己的
   测试代码——`ImagePlugin` 路径/`TileStorage` 字段访问/`Option<&Entity>`，即探针
   作者对 0.20.0 API 的预期适配错，非依赖漂移）；终态绿证=spawn 日志（编译+3/3，
   EXIT=0）。报告 §二表「check 日志全文」引注未注明首轮红形态，偏差表 D5 亦未列——
   结论不受影响（依赖本体两轮干净），记档级报告缺口。

## 四、碰撞内核审查（建设主件，源码全读+红绿亲核）——全过

`crates/jackdaw_tilemap_collision`：Cargo.toml deps 仅 glam（bevy 仅 dev-dep）+
`[lints] workspace=true`，引擎无关 ✓。

1. **行数账（D1）**：非测试段恰 444 行=**303 代码+100 文档+41 空行**（逐行计数复核，
   与报告一字不差）；分辨率核心 ~90 行实测成立（sweep_axis 51+move_probe 27+
   is_supported 7）；差额=dispatch 明确要求的三族查询 API+Aabb/Direction 辅助面，
   语义面零超纲 → D1 同意记档。
2. **三态语义对照（决策 3-B）**：上游 `nightly-2026-10-27` `setup.rs:77-82` 亲读——
   `CollisionMode{Solid, Trigger, #[default] Passable}`+derive
   `(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)`；内核移植件变体集/默认态/
   derive 列表逐项一致（枚举序 Passable 提前，`#[default]` 语义同），doc 注明出处，
   零上游代码吸收 ✓。引注 `setup.rs:77-82` 经 grep 实测**精确**（77=enum 声明行，
   82=闭括号行）。
3. **查询 API 正确性**（逐函数源码核）：
   - `world_to_cell` floor 除法（负坐标正确 floor 出界，测 1 断言 (-0.5,-0.5)→(-1,-1)）；
   - 点查 `mode_at_point`=world_to_cell+in_bounds→Option ✓；
   - 区域查 `cells_overlapping`：`first`/`last` **双向 clamp 到 [ZERO, grid_max]**+
     严格相交复检（边界相触不算，与 Aabb::intersects 语义一致）；clamp 后
     index ≤ w·h−1 可证，`modes[index]` 无越界面；行主序迭代器游标推进正确；
   - 相邻查 `neighbor`/`neighbors` 四方位 [E,N,W,S] 序、越界 None ✓。
4. **OOB 真缺陷（D7）结构亲证**：未 clamp 的 `first` 在盒子 min 跨出东边界时
   world_to_cell 产出 x=9>grid_max=7 → `modes[1*8+9=17]` 对 16 元 vec 越界 panic；
   触发走位测试（150 步×1.6px 止于 x=304，盒 [296,312) vs 256px 宽网格）**每轮绿跑
   都跨该边界**=永久回归格，且 `last` clamp 同时消除了 y=0 行的静默错读变体
   （phantom 索引 8/9 落进下一行数据）——修复面完整 ✓。
5. **SEPARATION=1e-3 逐位复现**：静止时每步 resolved 起点=start+delta 后 `max(face)`
   其中 face=底面+half+SEP 为同一算式——逐位同一值，测 6/App 测 1 以
   `assert_eq!`（逐位相等）断言 3 步静止 ✓；is_supported 脚下盒 x 双侧内缩 SEP+
   y 深度 2·SEP，几何亲证「驻墙时邻墙顶边不误判为地面」（驻墙位 feet.max.x=
   墙面−2·SEP，严格相交判 false）✓；静止体永不与 Solid 相交的负向断言三处齐备。
6. **红绿双证亲核**：红证 22:35 先于绿证 22:41 归档（先红后绿纪律 ✓）；红日志形态
   自洽——`sweep_axis is never used` 死代码警告（naive 脚手架态）+lib 5 绿/3 红
   （三验收行为全红）+App 0/3+`--no-fail-fast` 双 target 全量，EXIT=101；绿日志
   lib 8/8+App 3/3，EXIT=0。naive 脚手架未入库 ✓（HEAD 无痕迹）。
7. **App 级探针体**（player_probe_app.rs 188 行）：Level/WalkInput/TriggerCensus
   三资源+`apply_inputs→resolve→census_triggers` 链式三系统+单 PlayerProbe 实体，
   三断言（落地逐位稳定/墙面 1e-3 驻停+速度清零+触发 crossing 窗口报告后归零，
   附每帧「墙永不使体相叠」不变式）全绿——确为 T2 模板 module 接线样张 ✓。

## 五、TM5 守卫+prep 脚本复核——全过

1. **TM5 两件亲跑绿**（本 QA targeted 门 65/65 内含，逐测 PASS 行在案）+源码全读：
   - 正件：C 路 tile 形态（sheet 柄+`Rect::new(0,0,32,32)`+custom_size 32）→真
     `scene_io::save_scene`→盘面含 `rect:` 且**全文零 `texture_atlas`**→新 editor
     重开 rect/custom_size 逐字段相等+atlas None ✓；
   - 对照件：真 `asset.new` sprite_atlas 资产（T21 SP3 流）着装 sprite→盘面**出现**
     `texture_atlas`——守卫判别力实证，非空洞通过 ✓；
   - fork 文档引注亲证：`bevy-fork-pinned/crates/bevy_sprite/src/sprite.rs:32-37`
     「An optional rectangle…easy one-off alternative to using a [`TextureAtlas`]」
     逐字在位 ✓。M14 PX 半边（画布 tile 像素≠整图）留 T3 L7——测试 doc 与报告口径
     一致 ✓。
2. **prep 脚本（618 行）**：
   - **TPL_TILEMAP_ABSENT 预期缺席腿**设计亲核：模板文件 grep 到
     `{{module_tilemap_collision}}` 即 FAIL+漂移报警文案、缺席即 PASS——T2 落地后
     须翻转为存在断言（报告 §十-6 已自注，进 §七交接硬要求）✓；
   - **环境教训自愈硬化**亲核：`cargo build -p jackdaw -p jd` 先行（依赖图变更后
     陈旧 jd 符号失配 abort 的教训；warmbuild 日志见真实重编链）+格级 census 定版
     python stdlib `png_cells_md5`（sips `--cropOffset` 锚点不可靠，A7 家族；selftest
     CELLS 腿即其 8 格 8 色 md5 判别自证）✓；
   - 结构：AN2 brp 8 连重试/A9 gbrp settle/`$PHASE` 日志名/per-phase boot+cleanup
     trap/Recovered Work 弹窗自愈/warn 扫描面（含 TileBrush/tile_size 豁免）+A7
     五招 shot+12 个 T3 stub 按 L 腿命名——t21 形态全量复用 ✓；
   - **F3（记档）**：fixture sheet 用**八色**（每格独色），方案 §三写「四色」——
     判别力只强不弱（每 tile index 唯一色），良性偏离，无需回改。
   - 澄清（非偏差）：方案「launcher Template::TwoD 出」——`jd new` 实无模板旗
     （help 实证），2D 味经 fixture scene 文件落地即 T21 同款唯一通路；游戏 main 用
     默认模板+module 占位符族，2D 玩家 module 是决策 6 的 T2 落地面，口径自洽。

## 六、偏差 D1-D9 裁定建议（QA 意见）

| # | 偏差 | QA 裁定建议 |
|---|---|---|
| D1 | 内核 303 代码行 vs 方案估 150-200 | **同意记档**。303 行逐行复核精确；方案估只对应分辨率核心（实测 ~90 行）；差额=dispatch 要求的三族查询 API+辅助面，零超纲（§四-1） |
| D2 | 方案 T1-1①「rect 裁剪双端像素探针」未跑 | **同意移交，附硬约束**：headless/FS 半边已由 TM5 守卫落地属实；但 rect 裁剪像素行为是路线 C **唯一引擎假设**（方案 §六风险表「低-中」），至今零像素证据——M14 PX 半边**必须落在 T3 L2/L7，不得滑出 T3**；若 T2 调色板/画布工作先触 canvas 渲染，鼓励首步顺手补一拍最小 PX 探针 |
| D3 | 调色板渲染形态三案样张（决策 4）未跑 | **同意移交 T2 落地面**（决策 4-A 主选维持）；T2 落地时以真机观感回调 B 案浮点不变 |
| D4 | 决策 6 两形态 demo 未跑 | **同意移交 T2**；App 级原型即接线样张（§四-7），正式定案随 T2 模板 module 落地做 |
| D5 | clippy_ws/targeted 首轮红 | **同意结案**。按门禁证据标准「修完重跑覆盖归档日志」执行（归档=复跑后 EXIT=0 全文零行）；首轮细节因覆盖不可回溯属契约预期，非违规（T21-T1 D6 同判） |
| D6 | prep 首轮红（jd DYLD/并发 dylib 竞态/陈旧符号/sips 锚点） | **同意结案**。四项全部硬化入脚本（§五-2）；canonical run 11/11 绿+QA 复跑 11/11 绿双证；「脚本与门链不同窗」教训已写入脚本头注与报告 §十-5 |
| D7 | 区域查询越界 panic（真缺陷） | **同意结案**。缺陷真实性结构亲证+修复面完整（双向 clamp+严格复检）+触发走位测试=每轮绿跑必经的永久回归格（§四-4）——「红绿抓真缺陷」的样本质量高于预期 |
| D8 | libtests 3037 ≠ dispatch「3002+新增」 | **认可**。3037=3029+内核 8；3029=T21 收官提交 765c363d 门禁记录（fast 同 3029），非本轮引入；QA 亲跑恰 3037/fast lib 段亦 3037 互证。**采纳报告 §十-7：基线自本分支起 3037** |
| D9 | probe-a 分支保留未合并 | **同意**。隔离面恰 3 文件+主线零残留亲证（§三-1）；对照证据=报告 §二+两日志在案，`grep bevy_ecs_tilemap Cargo.toml` 即红的红线成立 |

## 七、QA 发现清单（记档级，无阻断）与放行建议

**发现：**

| # | 发现 | 建议 |
|---|---|---|
| F1 | A 路 check 归档日志为首轮红（探针测试代码 4 个 API 适配 error；依赖本体两轮干净），报告 §二未注明、D5 未列 | 记档；绿证以 spawn 日志为准；后续探针类日志归档注明轮次形态 |
| F2 | 程序门禁表无 fast 行（本轮新增 workspace 成员 crate，属「跨 crate 面大」应跑档） | 记档；QA 已补跑全绿（3037/3037），T2 程序门禁表补 fast 行 |
| F3 | fixture sheet 八色 vs 方案「四色」 | 记档；判别力增强，无需动作 |

**裁决 PASS，放行 T22-T2（建设轮），交接清单：**

1. **组件族+内核对接**：`TileCollisionMode`（per-layer 组件）以内核 `CollisionMode`
   为语义源；`TileGrid::new(origin, cell_size, w, h)` 一行对接编辑器
   TilemapLayer（cell_size/columns/rows/image 柄）——报告 §八-1 认可。
2. **游戏侧接线**：`tests/player_probe_app.rs` 三系统链即
   `{{module_tilemap_collision}}`+`{{module_tilemap_player}}` 样张；决策 6 随落地定案。
3. **TM5 守卫已生效**：T2 tile 生成代码直接被
   `the_tile_form_saves_a_rect_and_never_an_atlas` 覆盖（对照件机制已验）——生成
   rect 即绿、滑回 atlas 柄即红。
4. **TPL_TILEMAP_ABSENT 翻转为存在断言**是 T2 的必做随行件（否则 prep 腿自相矛盾）。
5. **红线**：`bevy_ecs_tilemap` 不得进主线依赖树（grep 即红）；probe-a 分支保留勿删。
6. **门禁基线**：libtests=3037（含内核 8）；fast 行进程序门禁表（F2）。
7. **风险在案**：D2 硬约束——rect 像素半边 T3 L2/L7 必落；决策 4-A 观感回落 B 案
   浮点不变；A7/A9/A10 自守按脚本现成形态走。

## 八、证据索引

- QA 门禁：`loop/reports/t22t1_qa_gates_{fmt,clippy_ws,clippy_phys,libtests,kernel,targeted,fast}.log`
  + `t22t1_qa_gates_summary.txt`（时间线）
- QA live：`loop/reports/t22t1_qa_live_{selftest,prep,warmbuild}.log`
- 程序归档（复核对象）：`loop/reports/t22t1_gates_*`、`t22t1_kernel_{red,green}.log`、
  `t22t1_probe_a_{check,spawn}.log`、`loop/t22-live/console-{prep,selftest}.log`（canonical，已保全）
- 上游对照：`git show nightly-2026-10-27:crates/jackdaw_tilemap/src/setup.rs`（77-82 行）
- fork 对照：`/Users/zhanglinbo/workspace/bevy-fork-pinned/crates/bevy_sprite/src/sprite.rs`（32-37 行）
