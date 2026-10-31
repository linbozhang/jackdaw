# T19 任务 1「负向守卫+探针清源轮」程序报告

> 分支 `loop/t19-graphics`（自 main e86f040b）；任务书 `loop/plans/t19-graphics-parity.md`
> §四-T1（316 行起）+§0 架构事实；主控裁定 8 决策点全按建议（①像素判据=数值主断言+通道内
> 红绿 ②场景级 AA 不加面板行 ③runtime dress 测试锚=T2 域 ④fixture prep=operator 写后存盘
> ⑤GR8 PIE 流送帧探针按方案 ⑥A7 五招自守不前置 ⑦负向格强度=manifest 全清单 diff ⑧book
> 扩节不立新章=T3 域）。**产品代码零改动**（tests 一件+main.rs 一行+qa 脚本一件+报告归档；
> 回滚=删测试文件与脚本）。零场景格式变更、零协议变更、零 fork 改动、零 UI 改动。
> 纪律遵守：全程未设 RUST_BACKTRACE；长命令后台+轮询；门前 df（并按 A6 家族清理了磁盘，
> 见偏差 3）。

## 〇、首步两探针结论（必记项）

### 探针① GR8：PIE 流送帧带 dress 组件——**忠实（按构造成立，两模式各自钉死）**

静态组件链定案（本探针的 headless 半边，方案 T1-1 明列「读 pie_frames.rs 捕获相机的组件链」
为定案手段之一）：

| 模式 | 证据链 | 结论 |
|---|---|---|
| **窗口回退**（游戏有自己的窗口） | 捕获相机=`Camera3d::default()`+**无 RenderLayers**+**无 EnvironmentOptOut**+`ChildOf(rig)` 恒等变换（`crates/jackdaw_runtime/src/pie_frames.rs:188-199`）。`dress_the_cameras` 对**每个** RenderLayers 与默认层相交的 `Camera3d` 逐区 dress——layers 缺席=被 dress（`layers.is_none_or(...)`，`crates/jackdaw_surface/src/environment.rs:503-505`，查询面 `:473`）；新相机无 `UndressedCamera` → 不走 `:516-522` 的早退 → `left_out=default`（零区跳过）全量 dress（fog/ambient/post/AA/阴影，`:538-560`） | 流送帧=与游戏窗口同组件面的相机所绘，**忠实** |
| **无窗模式**（JACKDAW_PIE_WINDOWLESS） | 没有捕获相机：`retarget_cameras` 把游戏**自己的**窗口向相机逐帧改指共享 WindowlessTarget 图像（`crates/jackdaw_runtime/src/pie_windowless.rs:138-152`），readback 直挂该图像（`pie_frames.rs:227-267`） | 流送帧=**游戏本体相机的渲染输出原样**，忠实性按恒等成立 |

两条边界如实记档：①dress 只在 `Environment.dresses_cameras()`（任一组开）时生效
（`crates/jackdaw_scene_types/src/environment.rs:333-338`）——T19 种子（sky+post 双开）恒
dress；②流启动后捕获相机下一帧才被 dress（PostUpdate 每帧跑，一帧延迟，M4 的 settle 纪律
吸收）。**编辑器 ViewportSettings 不存在于游戏进程**（方案事实五②），捕获相机无 opt-out ⇒
场景 AA 落流送帧——正是 M7 三站期望。

**决策 4 两案分流（均记档）**：忠实案（本定案）→ M4 保留 PX 红绿，真机确认=T2 L3 首拍
（N13 绕行+A7 五招届时全量武装）；若 L3 红绿与组件读回矛盾（不忠实案触发条件）→ M4 降级
纯数值轨、GR8 记档（游戏窗口 truth 以 direct run 为准）。T1 结论：**按构造忠实**。

### 探针② 决策 3：fixture 注入形态=**operator 写后存盘，定案 A 案**

| 半边 | 证据 | 结果 |
|---|---|---|
| **盘面（headless 常驻断言）** | `tests/viewport/graphics_prefs_clean.rs::the_prep_chain_authors_an_environment_through_the_operators`：`selection.select name=valley` → `component.add`（Entity 参数带 Entity PropertyValue）→ `environment.set sky.enabled=true post.enabled=true post.exposure=13 post.bloom_intensity=0.8 post.antialiasing=Smaa` → `scene.save` → 文档带 Environment → 重开读回逐字段相等 | **绿**（现状直绿） |
| **真机（seed 相）** | `loop/qa/t19-live.sh seed`：fixture 注入+锁刷新+暖编（PREP_OK）→ 编辑器开 scene.bsn → 同一 operator 链（BRP 面）→ `scene.save` → 文档 SHA 前后变化+完整 Environment 块落盘 → BRP 组件读回精确（`exposure:13.0, bloom_intensity:0.800000011920929(f32), antialiasing:"Smaa", enabled:true`+sky enabled）→ 视口 High 档预设 | **PASS**（SEED_OPCHAIN） |

种子后的文档即 T2 全矩阵共享 fixture：`scene.bsn` SHA
`655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9`。seed 相幂等守卫实测
通过（二跑「已带种子→跳过写→只验证」）。B 案（手写文档）留作受阻回落，不动。两笔 QA 纪律
从本探针沉淀进脚本注释：**entity 参数按名传**（`resolve_entity_params`：String→按名、
Int→按 id，`src/boot_ops.rs:480-499`——裸 id 字符串不解析）；**f32 读回断言带 epsilon**
（0.8 种子读回 `0.800000011920929`，首拍假红见偏差 2）。

## 一、GR2 负向守卫（tests/viewport/graphics_prefs_clean.rs，两测现状直绿）

新文件 242 行（fmt 后），挂进 `tests/viewport/main.rs` 一行。既有锚
`graphics_panel.rs:245-249`（面板 A 区控件→零 undo）的**盘面扩展**：把覆盖面从「面板控件
路径」扩到「operator 家族全量×用户路径×存盘字节」。

### 守卫 1：`the_viewport_preferences_leave_the_scene_document_untouched`

- **流程**：tempdir 工程+开场景（文档带 Environment+Camera3d）→ 首次 save 取基准字节 →
  **全套 viewport.* operator ×17 调用**（`run_op_clause_as_user` 用户路径——每次调用都申请
  history entry，`allows_undo=false` 的语义在最强路径下被检验；
  `crates/jackdaw_api_internal/src/operator.rs:661` 快照门=`creates_history_entry && allows_undo`）
  → `scene.save` → 字节相等+undo 栈零增量。
- **红绿自证（验收标准的「断言消息自证覆盖面」落实为三重）**：
  1. `assert_the_settings_moved`：17 项逐字段断言（preset 双跑+quality.set 五参+8 个 show
     flag+ssao on/quality+sharpen on/strength+realtime/stats/graph），每条消息点名产生它的
     operator——**operators 没跑则守卫没有前提**；
  2. **clobber 技巧**：二次 save 前把盘上文档写坏（`// clobbered\n`），scene.save 必须真写
     回——**save 静默没发生=红**（防「字节相等」因没写而平凡绿）；
  3. undo 断言消息自带前后计数（"went from N entries to M"）。
- **结果：现状直绿**（产品无改动的活证）。undo 栈实测零增量（scene open/save 同窗零污染）。

### 守卫 2：`the_prep_chain_authors_an_environment_through_the_operators`

探针②的盘面半边（见上），兼作 B 区写入链的 dogfood：`component.add` 一条 undo（其文档
语义「Pushes a single undoable history entry」实证）、`environment.set` 五字段一次调用、
`scene.save` 后重开读回 exposure 13.0/bloom 0.8/Smaa 逐字段相等。

## 二、像素助手入库（loop/qa/t19-live.sh，新 763 行）

t16-live.sh 骨架（leg/summary/cleanup trap/$PHASE 日志名/gbrp 重试/export_wait/staged 形态
原样）+T18 像素手艺搬运+feature-08 pixdiff 语义 python3 纯 stdlib 化：

| 助手 | 形态 | 自证 |
|---|---|---|
| `png_pixels_md5` / `png_decode_rgb` | t18 :272-311 原样搬运（五滤行全解，RGBA/LA/G 灰度扩展到 RGB 再求 md5） | selftest：同内容 md5 稳定、异色 md5 相异 |
| `crop_md5 <png> <x> <y> <w> <h>` | t18 固定矩形版**参数化**（t19 各通道裁剪矩形由腿传入） | selftest：矩形内稳定、跨界相异（合成 128x64 红底绿象限图） |
| `pixdiff <a> <b> [tol]` | pixdiff.ps1 语义 python 版：逐像素通道和差>tol 计 changed%、mean channel diff；尺寸不匹配自红 | selftest：同图 0.00%、红绿互补 100.00%（mean 113.333） |
| `settle_pixels [s]` | GR4 纪律入脚本（AA/画质切换后 settle≥2s+首拍丢弃由腿执行；screenshot 内置 SETTLE_FRAMES=90 是底线不是方案） | 脚本注释钉死 |
| `shot <name> [kind]` | **A7 五招自守**：①每次唯一 `request` 键（PendingWaits 防陈旧帧，server.rs:1798-1836）②rm -f 先行 ③落盘 size>0 才算 ④判红必过 `confirm_red`（见下）⑤`screencapture -x` 降级 | t16 shot 形态扩展 |
| `confirm_red <name> <kind> <before> <after>` | **flake 探针（非判据）**：「无变化」判红前拍两张同态新帧——两张互等且等于 after 才认真红；否则判 flake/stale（返回 1 让腿重读修正帧） | 决策 6-A 落库 |
| `manifest_diff <before> <after>` | 决策 5-C：export-manifest 全清单 SHA-256 diff（T07 字段现成），空输出=零 diff；M10 的强度形态 | 兼容 files/entries 与 path/name/sha256/sha/hash 拼写 |
| `gr6_spot_check` | **GR6 抽查腿脚本位预留**（T2 A 区腿时落 assertions：Sun/Point Shadows 像素红绿+shadow resource 数值半；真踩 R12 形态→GR 系记档不修） | 占位注释带断言草图 |

`selftest` 相=助手库验收证据（合成 PNG、无编辑器无 GPU），**全绿**
（`loop/reports/t19t1_selftest.log`）。`prep`/`seed` 相=本报告探针②的真机载体；
editor/game/export 三相为 T2 骨架（腿位按方案 §三 注明）。

## 三、门禁（日志全文复核；归档 loop/reports/t19t1_*）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（首轮 1 处 Diff 即 fmt 后过） | — |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN，0 warning/error**（2m11s） | t19t1_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN**（`--deny warnings` exit 0；磁盘恢复后复跑 Finished 无告警） | t19t1_gates.log |
| 单测 | `cargo test --workspace --lib` | **3001 passed，0 failed（exit 0）**——与任务书预期 3001 恰合 | t19t1_libtests.log |
| 集成·viewport | `cargo test -p jackdaw --test viewport` | **166/167 passed；1 failed=既有 flake（A/B 定证非 T19 引入，见下）。graphics_panel 8 件全绿回归+新守卫 2 件在全量跑中绿** | t19t1_gates.log + t19t1_viewport_flake.log |
| 集成·surface | `cargo test -p jackdaw_surface` | **全绿（52+0，dress 测试族含 AA/MSAA 替换与还原四件全过）** | t19t1_gates.log |
| AN2 腿 | `cargo nextest run -p jackdaw_runtime --features animation --test animation_scene_load`（T15 转活先例维持） | **1 passed** | t19t1_gates.log |

（首轮 libtests 起撞磁盘满（偏差 3），清理后**重跑覆盖**归档日志——README 门禁证据标准。）

### 既有 flake 发现（不修，报主控裁定）：`viewport_settings_menu::a_preset_picked_in_the_quality_menu_holds_and_the_menu_shows_it`

- **形态**：全量 `--test viewport` 二进制并行跑下 `viewport_settings_menu.rs:192` 断言
  `the defaults are the High preset` 红（`selected(HIGH)` 为假）；单测隔离跑**绿**。
- **A/B 定证**：把新模块 `graphics_prefs_clean` 从 main.rs 摘除后全量重跑——**同样 1 failed
  （164/165 passed）**。该二进制的产品代码与 main 全同（T19 零产品改动），故 **flake 预存
  于 main，非 T19 引入**；证据链归档 `t19t1_viewport_flake.log`（含 panic 消息）。
- **机理候选**（未修，供主控/后续票参考）：并行测试共享每进程 `JACKDAW_CONFIG_DIR` 的
  `viewport.json`——任一未覆盖 `ViewportSettingsFile.path` 的测试写共享文件，恰好撞上本测
  启动读档窗口，默认 High 档被并发写入的 preset 覆盖；或纯 UI 时序（菜单行 settle 在
  CPU 争用下滞后）。同域既有测试 `viewport_settings::changing_viewport_settings_leaves_the
  _saved_scene_unchanged` 在本轮全量跑绿（flake 非全域性）。
- **处置**：按「只记不修」纪律不动；候选 buglist W 条目（测试基建域），主控裁定吸收面。

### 新守卫与既有测试的重叠面（如实声明）

诊断中发现既有 `tests/viewport/viewport_settings.rs:166
changing_viewport_settings_leaves_the_saved_scene_unchanged` 已覆盖守卫 1 的一个子集
（preset low+8 show flags+realtime/stats→save→字节相等）。新守卫的**增量**：①operator 家族
补齐（`viewport.quality.set` 单选五参/`viewport.ssao.set`/`viewport.sharpen.set`/
`viewport.stats.graph.toggle` 既有测试未跑）；②undo 栈零增量断言（既有测试无）；③用户路径
`run_op_clause_as_user`（每次调用申请 history entry——`allows_undo=false` 在最强路径下被
检验，既有测试走静默 `run`）；④clobber 重写证明（防 save 静默不发生的平凡绿）；⑤
settings-moved 逐字段自证；⑥文档带 Environment+Camera3d（dressing 目标在场）。既有测试
保留不动，二者互补。

## 四、偏差清单（如实分级）

| # | 级 | 偏差 | 处置 |
|---|---|---|---|
| 1 | S | GR8 探针的「真机流送帧红绿对照」半边未在 T1 跑，顺延 T2 L3 首拍 | 方案 T1-1 文本允许「headless 或真机单腿定案」，静态组件链已两模式钉死且给出不忠实案的触发条件与回落；真机腿需 PIE+N13 100% panic 绕行+A7 五招全量武装（T2 机器），提前单跑=双重 flake 暴露零新判定 |
| 2 | S | seed 首拍假红：断言 jq `==0.8` 撞 f32 读回 `0.800000011920929` | **链本身首拍即成功写对文档**（假红在验证器不在链）；epsilon 修正后重跑 PASS。红证归档 `t19t1_seed_attempt1_false-red.log`（含正确落盘的文档全文=决策 3 真机证据） |
| 3 | S | 门禁首轮 libtests 起 `No space left on device`（磁盘 100%，fixture 暖编 target 18G+.jackdaw/target 6.6G 吃满）；重跑中途再撞一次（重复测试二进制累积），再清 workspace `target/debug/incremental`（9.5G 纯缓存） | A6 家族纪律：先清已闭环 T18 fixture 的 17G 构建缓存（证据已在 loop/t18-live/ 归档）、再清 t19 fixture 两个 target 缓存+workspace incremental 缓存；种籽文档与注入面无损。暖编状态牺牲→**T2 先重跑 `prep` 相**（幂等守卫原样）。门禁重跑覆盖归档日志 |
| 4 | 备注 | t19 fixture 含 avian 物理模块（`jd new` 默认模块面），比 t16 fixture 重 | 不影响 T1 断言；T2 游戏腿编译体积更大，预算列入 prep 相冷编 |
| 5 | 备注 | seed 相「High 档资源面」探针行首拍用了组件查询（资源查询才对），已修正脚本 | 资源面真实读回属 L1/T2 的 opt-in 前提确认；本相 preset operator 调用成功即够 |

## 五、GR3/GR7 book 注记草稿（随 T3 落盘，本轮只备稿）

**GR3（场景级 AA 无面板行——注记进 graphics-panel.md「Play 与导出」节）**：
> 场景级抗锯齿（AA/MSAA）不在 Graphics 面板上：Scene 区只承载 Post Processing、Tonemapper、
> Exposure 与 Bloom。要给场景作者 AA，走 Inspector 的 Environment 组件（或
> `environment.set post.antialiasing`），它在游戏运行与导出里生效；编辑器视口按设计永远
> 不吃场景 AA（视口用自己的质量档，见下）。把 AA 面板化是面板 backlog 的一项
> （open-challenges 一句话：Graphics 面板 Scene 区补 AA/MSAA 行）。

**GR7（开箱无 Environment——注记进同节）**：
> 新工程的场景没有 Environment 实体：Scene 区会显示空态提示，四个通道（编辑器视口、Play、
> direct run、导出）都按引擎默认画质跑——这是开箱一致性的对照态，不是缺陷。在场景根上加
> Environment 组件后，同一份画质数据才会随场景存盘并走进游戏。

（终稿归 T3：落 `book/src/user-guide/graphics-panel.md` 扩两节，不另立新章——决策 8。）

## 六、给 QA（T2 真机矩阵轮）的注意事项

1. **先重跑 `prep` 相**：磁盘清理牺牲了暖编（偏差 3）；注入已在（grep 守卫跳过 sed），
   `cargo build` 冷编 ~10 分钟预算单列；编辑器首开 PIE 前会重建 `.jackdaw/target`。
2. **seed 相幂等**：文档已带种子（SHA `655892c6…`），seed 相跳过写、只做读回验证；要换种子
   值先手工清掉 `scene.bsn` 的 Environment 块或删行 `exposure` 触发重写。
3. **entity 参数按名传**（探针②沉淀）：`component.add {"entity":"Root",...}`；裸 id 字符串
   不解析（`resolve_entity_params`：String→按名、Int→按 id，boot_ops.rs:480-499）。
4. **f32 读回带 epsilon**（偏差 2）：种子值断言一律 `abs(diff)<0.001`，别写 `==0.8`。
5. **像素判据分工**（决策 1）：编辑器视口=`shot`+`pixdiff` % 形态（渲染目标直拍尺寸稳定）；
   游戏窗口=`screencapture`+`crop_md5` 变/不变（chrome 噪声用裁剪隔离）。判红必过
   `confirm_red`（A7 相邻两拍 flake 探针）；AA/画质切换后 `settle_pixels 3`+首拍丢弃。
6. **M10 强度**：`manifest_diff` 全清单 diff（决策 5-C）——改 A 区前后各导一次，diff 空输出
   即包面不变；manifest 结构意外时回落 scene.bsn SHA 单点对比（A 案）。
7. **L3 PIE 腿**：N13 绕行纪律照旧（编辑器存活+panic 后重试读回）；流送帧按 GR8 定案保
   PX 红绿，若与组件读回矛盾→M4 降级数值轨+GR8 记档。
8. **磁盘**：门前 df；fixture 的 `target/` 与 `.jackdaw/target/` 是吃盘大户（24G 量级），
   腿间清理按 A6 单触发源纪律。
9. **GR6 抽查**：A 区腿顺带跑 `gr6_spot_check` 位（Sun/Point Shadows 像素红绿+shadow
   resource 数值半）；像素侧 flat 而数值侧动= R12 形态，记 GR 红证不修。
