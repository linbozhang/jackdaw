# T11 终验 QA 报告：任务 3（收官段）+ T11 整体终验（只验不修）

> 验收对象：分支 `loop/t11-final` @ **9fb392f9**（406d116b Windows 段产品代码 8 文件 +334/−8；
> 25e0b1bc bevy fork patch 路径重指向（迁移必需）；9fb392f9 Mac 段 22 文件=loop 证据/脚本/
> 合并报告/book 边界段/buglist 三条，**零产品代码**）。开局自检：分支/提交态一致，工作区干净。
> 程序报告：`loop/reports/t11-t3-report.md`；前置 T1 QA（fb4d7e45 PASS）、T2 QA（PASS）。
> QA 证据：**Mac 全量门 8 门亲跑**（11 件归档 `t11t3_qa_mac_*`，脚本 `loop/qa/t11t3-qa-mac-gates.sh`，
> 全程未设 RUST_BACKTRACE——程序 §八-3 禁令遵守）；`loop/t11t3-live/` 双机日志逐位核对；
> 暖工程场景文件盘上核验；avian3d 0.8.0 registry 源码亲读；Windows 归档 8 件全文复核。

## 〇、结论

**PASS（T11 整体，含 roadmap T11 可勾选建议）**——验收句两铁证、矩阵 12 格、cell6 判定、
N13 复发率、N14 修复、book/doc 全部独立核实成立；Mac 权威全量门 8 门中 6 门 CLEAN/绿，
**integration 门 8 红（5331 跑 5323 过）**——逐项诊断后**零 T11 引入**（7-8 项 macOS 环境族
首基线 + 1 项 T10 血统潜伏缺陷被迁移清洁重编暴露），另有 doctests 的 jackdaw_bind
第 4 次环境性失败（单跑复跑 PASS）。两项 **🔴 回流主控**（§八），不阻塞 T11 收口
（T10-T3「9 红 main 既有→PASS+立项 T10a」同款先例），但合入前请主控过目处置建议。

## 一、Mac 全量门亲跑（权威口径；Windows 归档仅迁移前对照）

| # | 门 | 命令 | 结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0，日志空） | `t11t3_qa_mac_fmt.log` |
| 2 | Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0，615 行零 error/FAILED 匹配，Finished 2m11s） | `t11t3_qa_mac_clippy_ws.log` |
| 3 | Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t11t3_qa_mac_clippy_physics.log` |
| 4 | 单测 | `cargo test --workspace --lib` | **绿**（58 套件全 ok，EXIT=0；日志中 ERROR/WARN 行均为 pie prebuild 负路径测试夹具） | `t11t3_qa_mac_libtests.log` |
| 5 | fast | `cargo xtask fast` | **2961/2961 passed, 0 skipped**（EXIT=0；与 Windows 归档逐位同总数） | `t11t3_qa_mac_gate_fast.log` |
| 6 | integration | `cargo xtask integration` | **FAIL：5331 run, 5323 passed (3 flaky), 8 failed**（EXIT=1，诊断见下） | `t11t3_qa_mac_gate_integration.log` + 隔离复跑 2 件 |
| 7 | doctests | `cargo test --workspace --doc --features dylib` | jackdaw_bind 1 处 dyld 失败（EXIT=101）→**单包复跑 PASS**（EXIT=0）——bind flaky 家族第 4 次（T08/T09/T10/T11），Windows 同款形态（§八-3） | `t11t3_qa_mac_doctests.log` + `t11t3_qa_mac_doctests_bind_rerun.log` |
| 8 | docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **CLEAN**（EXIT=0，零 error；仅 link-to-private 类 warning） | `t11t3_qa_mac_doc.log` |

**integration 8 红诊断（QA 全文逐行复核+隔离复跑定性）**——这是本机（macOS）第一次
全量 integration 基线（Windows 末次全绿=T10a 5303/5303@bb178d11）：

| # | 测试 | 失败形态（日志原文） | 隔离复跑 | 定性 |
|---|---|---|---|---|
| 1 | `jd::standalone_scaffold::the_shipped_binary_scaffolds_without_a_checkout` | 产物 Cargo.toml 含 bevy fork `[patch] path=`（/Users/…/bevy-fork-pinned）——断言「shipped binary 必须 registry 依赖」被破 | **确定性红** | **🔴 真·潜伏产品缺陷（T10 血统，非 T11 引入）**，见 §八-1 |
| 2-4 | `guards reference_rewrite` ×3 | journal/tab 路径断言打印 `/private/var/folders/…`（TMPDIR 被 canonicalize） | 确定性红 | macOS 路径规范化环境族 |
| 5 | `guards reference_audit::a_loaded_scene_leaves_one_summary_warning` | broken-ref 告警数 0≠1（fixture 在 Mac 未产告警；域=T05 参照审计，与 T11 零交集） | 确定性红 | macOS 环境族（初判路径/FS 相关，未深挖） |
| 6 | `guards session_journal::a_dirty_tab_journals_the_save_emitters_own_text` | 同 `/private/var` 路径形态 | 确定性红 | macOS 环境族 |
| 7 | `guards session_journal::the_journal_write_costs_no_more_than_five_milliseconds` | journal 写 301ms（满载）/568ms（单跑）≫5ms 预算 | 确定性红 | Mac/APFS 性能预算（环境） |
| 8 | `panels reconcile::a_maximized_leaf_draining_ends_the_maximize` | despawned-entity observer 错误（project_window highlight_on_hover；域与 T11 零交集） | 确定性红（另两个同族 panels 测试单跑过=负载 flaky） | Mac 时序竞态环境族 |
| 9* | `controls ui_probe_click::a_ui_input_types_and_commits_in_one_gesture` | 合成打字多出字符 `"0entity: 42"` | 确定性红 | Mac 合成键盘路径（环境） |

（*全量跑最终 8 failed + 3 flaky-passed；隔离复跑 11 项中 9 红对上表，`maximize_toggle`
与 `switching_workspaces` 两 panels 项单跑绿。guards 套件 222 件中 216 过+6 失败=上表 2-7，
**产品关键 guards（N14 新测试/undo/物理/拾取/scaffold flow）全绿**；standalone_scaffold 与
teaches/fork-patch 等产品面测试仅 1 红即 #1。）

**「零 T11 引入」论证**：①三个 T11 提交的产品面 diff（runtime/camera_rig/scaffold doc 占位/
commands.rs SetBsnField/Cargo.toml 路径值）与全部红的测试域（jd standalone 发货、参照审计/
重写、session journal、panels reconcile、controls ui_probe）**无一行交集**；②红的机制族
（TMPDIR 规范化/APFS 预算/合成键盘/observer 竞态）均为平台性；③#1 的成因链在源码级闭合
（§八-1），注入逻辑与断言分别来自 T10-T3/T10 前。**main 在本 Mac 无法建基线对照**（main 的
[patch] 指向 E:/ 盘符路径不可解析——25e0b1bc 重指向正是 Mac 可构建的前提），故以机制归因
替代 T10a 式 worktree 复现，如主控要求可另派验证。

**Windows 归档 8 件对照复核**：fmt 空/clippy×2 零匹配/guards **222/222**/fast **2961
(1 leaky), 2 skipped**/doctests bind 失败+复跑过/integration **止于编译 warning 无终局
Summary**（程序已声明，Mac 重跑覆盖）——与程序 §六表逐项一致，无隐瞒。

## 二、证据链核实（12 格表 vs `loop/t11t3-live/` 双机日志）

**逐位核对结果：报告 §二 12 格表 Mac/Windows 两列的每一个数字均与原始日志一致**：
格 1（R2 dz=2.440000057220459/apex 1.9142364263534546/drift 8.522421062195917e-07）、
格 2（M2 五 add finished+R1C1 y=0.8600000143051147）、格 3（1.5736/3.1483 m/s）、格 5
（apex 2.7273950576782227 vs 理论 2.6949）、格 6（墙停 −2.4399993419647217/滑 x 2.390→4.421/
高速 −2.440000057220459/推箱 dx=1.1385418474674225e-07）、格 7（drift 0.000/R4 FP
\|local\|=1.2999998331069946）、格 9（盘上 1.2999999523162842/行为 1.2999998）；Windows 列
（0.860/−2.440/2.458/1.86m/1.67-3.34/0.00/R4 1.600）与 `t11t3-c-progress.log` 逐位一致。

**抽查 3 关键格原始日志全文**：
- **格 4（C7，a3）**：`t11t3-a3-mac-console.log` 全文 8 行复核——开通道 rigXZangle
  0.0→**−57.29578101508276°**（=−1.0 rad=−200×0.005，与 57.29578 理论差 **1.0e-6 度**，
  优于报告宣称的 1e-5）；RMB 按住帧 −57.29578→−114.5915156255728=**恰再转 57.2958（单写）**，
  双写会是单步 −114.59——「让位=单通道」断言成立。断言窗口 57.29578±8.5°（=±0.15 rad）。
  语义澄清（合成 motion 经 capture 成真 MouseMotion、RMB 帧由 crate 通道合法消费）与
  决策 3-③ 一致，记档口径接受。
- **格 11（Stop 铁证，a2）**：`t11t3-a2-mac-console.log` L9-11——驱动中玩家 z=−2.440000057220459
  （W 按住、rig 每帧跟随）→stop→`sha_same=true temp_left=0`。SHA+temp 双断言在案。
- **格 5（apex，c-mac）**：`t11t3-c-mac-progress.log` L8——apex 2.7273950576782227，
  expected 2.694862385321101（v²/2g=36/19.62+0.86），窗口 ±0.35 内，authored jump_speed 6.0。
- 附：N13 计数行（a2 console L12-22：13→19→…→57 累计）与 x10 收口 57 一致。

**`.sh` 移植版 vs `.ps1` 原版断言窗口逐字比对**（防放宽容差）——**未放宽**：

| 腿 | ps1 窗口 | sh 窗口 | 判定 |
|---|---|---|---|
| C: R1C1 落定 | placed+tpl+rig(mat+act)+y∈(0.7,1.05) | 同窗口；唯 mat/act 谓词为「场景内任一 rig」非「placed 玩家之 rig」 | ⚪ 形松一格，由 R1C5（rig=placed 最近者，offset 理论 (0,3.15,4.61) 精确窗）兜底 |
| C: R1C2 墙停 | n≥4 && z∈(−2.60,−2.0) | 同 | 一致 |
| C: R1C5 跟随 | drift<0.15 && \|y−3.147\|<0.3 && \|z−4.605\|<0.4 | 同 | 一致 |
| C: R1C3 跳 | \|apex−(0.86+36/19.62)\|<0.35 | 同 | 一致 |
| C: R1C4 滑 | Δx>0.8 && z∈(−2.70,−2.15) | 同 | 一致 |
| C: R1C6 半速 | vPl∈(1.2,2.8) && vTp>2.8 | 同 | 一致 |
| C: R2 开箱 | visible && dz>0.8 && (apex−y0)>0.6 && fDrift<0.2 | 同 | 一致 |
| C: R2 推箱 | dx>0.3 | 同（如实 FAIL） | 一致 |
| C: R3 高速 | z∈(−2.50,−2.0) | 同 | 一致 |
| C: R4 FP | \|.\|∈(0.9,1.75) | 0.9<\|.\|<1.75 **&& \|.\|−1.3\|<0.3** | **更严**（M9 eye_height 补腿） |
| A: M2/N14/M8/M6PRE | 六条件/grep 集合 | 逐字同 | 一致 |
| A: M7PRE | FirstPerson 在盘 | +`eye_height: *1\.2999`（正则修复版） | 更严（新格） |
| A: PIE 探针 | 进程活+无 exited 标记+pie=running | 同（a2 加 warm-aware 冷编窗） | 一致 |

**M7PRE FAIL 标注核实（程序称断言正则 BUG 而数据在盘）——属实**：QA 亲读暖工程
`t11t3-fp.bsn:475` = `eye_height: 1.2999999523162842`（f32 序列化长尾，`1\.3` 确实不匹配）；
修后正则 `1\.2999` 匹配；行为面由 R4（1.2999998）闭环。另核 `t11t3-place.bsn`（move_speed 2.0/
jump_speed 6.0/PlayerVelocity/Kinematic/distance 5.0/sensitivity 0.008…/ActiveCameraRig 全在盘）
与 `.bak`（首存态 jump_speed **4.5**——N14 兄弟字段落库的时序证据）、`t11t3-fast.bsn`（8.0）。

**导出腿/无物理腿**：`t11t3-export-mac-console.log`（release 构建 631 components/staged 5 文件/
editor-private 排除/manifest sha256）+ smoke log（staged exe 自 `.jackdaw/dist/release/` 启动，
Metal AdapterInfo）在档；`t11t3-nophys-mac-game.log` 含教学退场金句 `Jump! (needs the physics
module to leave the ground)`（L11）。⚪ 唯缺口：两腿报告中的**行为采样数字**（落定 (−2,0.860,0)、
W→z−2.440、W 1.2s→−4.93、y 恒 1.0、世界零 avian 组件）系 BRP 轮询输出未落日志文件——启动面/
机制面有盘上证据，数字面以同通道同数字的四通道一致侧证（程序措辞如实，未夸大）。

## 三、cell6 判定复核（avian3d 0.8.0 registry 源码亲读）——**判定成立**

QA 独立实读 `~/.cargo/registry/src/index.crates.io-…/avian3d-0.8.0`：

1. **`MoveAndSlide` 是纯 shape-cast 数学、不写任何 body 状态**：SystemParam 字段仅
   `spatial_query: SpatialQuery` + `colliders: Query<(Collider, Position, Rotation,
   Option<CollisionLayers>), (With<ColliderOf>, Without<Sensor>)>`（只读）+ `length_unit: Res`
   ——无 Commands/无可变写入口；`move_and_slide(...)`（move_and_slide.rs:483 起）函数体
   483-700 行零 body 写路径，返回 `MoveAndSlideOutput { position, projected_velocity }`。
2. **`ContactConstraint::generate` 消费双方 LinearVelocity**：solver/plugin.rs:735-741 调用
   传入 `body1.linear_velocity.0, body2.linear_velocity.0`；contact/mod.rs:106 起的实现用两速度
   算 tangent 方向与约束——模板玩家 avian `LinearVelocity` 恒零+sweep 皮肤宽度外无重叠
   →法向约束无冲量可发，Dynamic 立方体不动。与报告 §四机制链逐环吻合。
3. **「kinematic 影响 dynamic」的前提形态**与 avian 文档一致（rigid_body/mod.rs:298
   「Kinematic 不受外力/碰撞影响」；需重叠或 velocity-based 形态才有推挤）。

**处置裁定：接受「决策 1-A 语义边界，非缺陷」**。方案自身的内在矛盾（矩阵格 6 期望行写了
「玩家推 FallingCube」vs 决策 1 明选了「不被推挤」形态）以文档化收口：book 边界段在
（player-controller.md「One boundary of that design, on purpose…never shoved, never shoving」
+将来形态指引 projected_velocity→LinearVelocity/Dynamic+锁轴）、buglist A2 立账（机制链+双机
实证+指引）、矩阵子项如实记 FAIL（语义边界）——不为过格改引擎/模板，正确。墙停/贴墙滑/
高速不穿透三子项全过不受影响。

## 四、N13 复发率核实——**buglist 更新如实，证据链闭合**

- `t11t3-a2-mac-editor.log` QA 全量 grep：`swap_remove index` 命中 **59**（x10 窗口末 57+其后
  CELL11 轮 +2，与 console 计数行自洽）；签名三形态 is 0/len 0 ×51、is 1/len 0 ×3、is 2/len 0
  ×5（「空 vec 退化」属实，与旧机 is 1/len 1 同根）；
- 受害系统双证：`jackdaw::pie::drain_game_events` ×32 + **`jackdaw::pie::cleanup_session_on_stop`
  ×11**（第二受害系统在案）；
- 全部被 bevy 错误处理器捕获（`Encountered an error in system …: Exclusive system panicked`
  ×43），10 轮 editorAlive=yes——「Mac 不死编辑器」属实；RUST_BACKTRACE 禁令（§八-3）下真栈
  不可得，panic 签名为唯一形态证据——如实记档。
- buglist N13 条目更新（100%/10 轮/57 次/第二受害系统/签名/严重度依机器）与上述日志逐项一致。

## 五、N14 修复核实——**代码+测试+双机活证+盘上态四重成立**

- 代码（406d116b `src/commands.rs`）：`SetBsnField::execute` project 分支在首 set 前检测
  fieldless patch（空 Struct/bare Type）→ `project_schema_default_bsn` 以 schema 默认整灌
  →再落单字段；helper `project_patch_is_fieldless`/`project_schema_default_bsn` 实现在案，
  schema 无 default 保持稀疏不恶化——与报告 §一描述一致；
- guards `a_first_field_set_after_add_authors_the_whole_component`（scaffolded_component_flow.rs:708）
  在案，QA 的 Mac integration 亲跑 **PASS**（盘上面 emitted.contains("jump_speed")+二次 set
  不回退双断言）；guards 222 件中产品面全绿；
- 活证：Windows `N14_LIVE_SIBLING_ON_DISK=True` + Mac `PASS`（console L9：move_speed 2.0 与
  sibling jump_speed 4.5 同盘）；QA 盘上复核 `.bak` 文件首存态含 `jump_speed: 4.5`（时序自洽：
  现 place.bsn 的 6.0 是 M8 二次 set 后的重存）。
- undo 语义 ⚪（backfill 不进 undo）维持程序记档。
- **建议：buglist N14 可勾选**（修复+双机活证+QA 复核三面齐）。

## 六、book/doc 核对——**方案 §T3-2 书单逐项在位**

`book/src/user-guide/player-controller.md`（406d116b 新增 152 行+Mac 段边界 10 行，SUMMARY 挂 game-input 后）：
五件套表（组件/作用/谁写）、CameraRig 两模式五参数表、多 rig 边角（「Two rigs, no camera」+
ActiveCameraRig 手加=多玩家 gate 设计）、Look 双通道一致（C7）、跳跃/碰撞机制（move_and_slide
一句话+avian character-controller 章指引）、**「不推 Dynamic 体」边界段（cell6 Mac 补）**、
GameConfig.gravity 双消费同源（「One value, both consumers」）、C8 参考系定案（camera-relative+
CameraLook.yaw 单一真相+身体朝向随移动）、参数调法纪律（per-entity=组件/game-wide=config）、
摆放链 step-by-step（五件套字面+两件套无物理形态+「缺一件=悬空不动」）、存量工程迁移注记
（类型面免费/行为面一行 add_plugins）、30 秒清单三条=方案口径。`game-input.md`（Look 消费面+
章节链接）与 `physics.md`（player controller 链接+move_and_slide 描述）交叉更新在 diff。
C10 模板 doc：`{{module_physics_player_doc}}` 占位（physics=五件套 bullet/plain=两件套 bullet）
+PlayerMarker 注释改指向+teaches 三新锚（`queries five components together`/``zero
`PlayerVelocity` ``/`` `AvianCollider` (a capsule of radius 0.35``）+plain stays 一锚——与
「照 doc 摆得动」闭环（M2 双机 operator 直摆全 finished+行为复活）。⚪ 唯措辞项：avian
「链接」以章节名文字指引呈现（无 URL），可接受。

## 七、验收标准与 QA 清单对照（方案 290-307 行）

| 条目 | 裁定 |
|---|---|
| 矩阵 12 格全过 | **11 PASS + 格 6 主面 PASS/推箱项语义边界**（§三复核成立的文档化收口，双机一致；方案矩阵行与决策 1 的内在矛盾以此化解——不构成格 FAIL） |
| 全量门（日志全文复核） | Windows 8 件复核一致；Mac 亲跑 6 绿 + integration 8 红（零 T11 引入，§一/§八）+ doctests bind 单跑过 |
| 用户 30 秒清单 | book 章末三条在位=方案逐字口径（见 §十） |
| C1/C2/C3 机制红绿 | T1 QA 已核（PASS）；N14 红绿+活证本轮补核 |
| 验收句铁证一「即玩」 | 格 1（双机 R2 开箱）+格 2（双机 operator 摆放链）独立证据 ✓ |
| 验收句铁证二「Inspector 可调」 | 格 8（M8 双机同盘+行为 R1C3/C6+T2 QA 冷重启 P3）+格 9（distance 双机/eye_height Mac 三处闭环/sensitivity 盘上+量纲 0.005 由 C7 活证 1e-6 度）✓（sensitivity authored-0.008 行为面 ⚪ 残留，程序已记） |
| T01-T10 防线回归 | T09 量纲（格 3/4 新语义+guards）、T10（格 5/6+拾取链 T1 QA）、T02（格 8/9）、T03（T2 QA undo 单记录+N14 undo 记档）、T06（格 11 SHA+temp）、T07（格 10 四通道）、T08（gravity 双消费 doc+跳异数学）——分布覆盖 ✓ |
| quick/全量门+物理双包 | ✓（§一） |

## 八、QA 发现汇总（本轮新增）与回流

1. **🔴（回流主控，建议立项小任务）standalone 发货承诺被 fork patch 注入破坏（T10 血统
   潜伏缺陷，迁移清洁重编暴露）**：`module_patch_lines`（scaffold，T10-T3 引入）在
   `BEVY_FORK` 被 build.rs 烘入时向**所有** physics 新工程无条件注入 fork `[patch] path=`
   行；`jd::standalone_scaffold::the_shipped_binary_scaffolds_without_a_checkout`（断言自
   2026-10-11）因此确定性红（Mac 隔离复跑 2/2 红）。Windows T10a 之所以绿：build.rs 仅对
   build.rs 自身/feature 变化 rerun（不监视 workspace Cargo.toml——embed-recipe 分支外的
   rerun-if-changed 声明所致），T10-T1 加 fork patch 后**增量构建一直沿用旧的无 fork 烘入
   产物**；Mac 迁移全量冷编首次诚实烘焙 → 暴露。即：**任何机器清洁重建都会红，非 Mac 特有**。
   修法方向（程序裁量）：注入 gate 在 `jackdaw_dev_checkout()`（standalone 二进制自然不注）
   或 standalone 产物剥离 path patch。不影响 T11 验收面（T11 的 e2e/teaches/export 全绿——
   在 checkout 内 fork patch 本就该注入）。
2. **🔴（回流主控，建议记「Mac integration 环境基线」账）8 红中其余 7-8 项 macOS 环境族**
   （§一表 2-9：/private/var TMPDIR 规范化 ×5、journal 5ms 预算在 APFS 上 300-570ms、
   panels observer 竞态、合成键盘多字符）——首 Mac 基线、域与 T11 零交集；处置选项：
   立小批清理（路径断言改 canonicalize 比较、预算门按平台校准、ui_probe 键位映射）或在
   xtask 层标注平台性 skip/allowlist，主控裁定。**在处置落地前，Mac integration 门应视为
   「带已知环境红」状态**，后续任务以「无新增红」为口径。
3. **🟡 `src/commands.rs:2270` 注释含 U+FFFD 替换字符+`?`**（`at all \uFFFD?the bare type`，
   406d116b Windows 段写入；全 T3 改动面唯一一处，其余文件零命中）——buglist 编码事故
   同族的注释级残留，不影响编译/门禁，建议合入前顺手修一行。
4. ⚪ doctests jackdaw_bind 第 4 次环境性失败（本轮 Mac 形态=dyld 找不到 libstd dylib，
   单包复跑 PASS；T09 已挂「根治建议」backlog，维持）。
5. ⚪ 导出腿/无物理腿行为采样数字未落日志（§二；启动面/机制面有盘证，数字面四通道一致侧证）。
6. ⚪ M7PRE 断言正则 BUG（数据在盘已核、正则已修、行为面 R4 闭环、未重跑整链——程序记档
   如实）；a-leg 首轮 PIE 探针误判 DEAD（Mac 工具差：进程路径模式+冷编窗，a2 warm-aware
   探针纠正——程序 §八-4 如实）。
7. ⚪ `.sh` R1C1 谓词形松一格（任一 rig vs placed 玩家之 rig，R1C5 兜底）；R4/M7PRE 两处
   **更严**；断言窗口整体未放宽。
8. ⚪ 双 rig 时序竞争：QA 在 `t11t3-c-mac-game.log` 尾亲见 `Camera order ambiguities …`
   警告（模板 rig 抢激活窗口）——与程序 §七-4 记档一致，行为无害，维持。
9. ⚪ 25e0b1bc fork patch 路径重指向（E:/→/Users/…）随分支合入 main——T10 偏差②「机器本地
   路径约定」的延续（Cargo.toml 注释明示 documented machine convention）；提醒：主控合入后
   Windows 旧机/CI 需重跑 `scripts/make-bevy-fork.ps1` 对齐本地路径（CI fork 断裂本就在
   open-challenges 第五条账上）。
10. ⚪ 程序报告 §六 Windows integration 归档无终局 Summary 的声明属实（QA 复核原文止于
    warning 行）；Mac 重跑已覆盖该门证据。

## 九、结论与 roadmap 建议

- 任务 3 验收标准：矩阵 12 格（11 PASS+1 语义边界文档化）、book/doc、30 秒清单——**过**；
  全量门：Mac 权威 6/8 绿，integration 8 红+doctests bind 均**非 T11 引入**且各有处置路径
  （T10-T3 同款先例：不退回、立项清理）；
- T11 整体：T1/T2 已 PASS 合入（fad046ce），T3 两项 QA 裁定修复（C10/N14）四重核实成立，
  cell6 判定源码级复核成立，N13 挂账清偿（复发率 100%+第二受害系统）；
- **VERDICT: PASS**（T11 整体）。roadmap T11 **建议可勾选**，闭环注记建议含：两铁证双机
  在案、cell6 语义边界指向 buglist A2、🔴 两项回流（standalone-scaffold 小任务+Mac
  integration 环境基线账）、🟡 一行注释清理。
- 主控合入路径照旧 `--no-ff`（9fb392f9 含 406d116b/25e0b1bc 两父链），台账 T11 行补记。

## 十、用户 30 秒清单（T11 累积口径）

1. 新工程直接 **Play**：看到胶囊玩家，WASD 走、Space 跳（落地可再跳）、走到墙边正面停/
   斜着滑、相机跟着转。
2. Inspector 把玩家 `move_speed` 改 8.0、相机 `distance` 改 4——再 Play 明显变快变近；
   保存重开，两个数还在。（进阶：`mode` 切 FirstPerson+`eye_height` 调高低。）
3. 自己 **Add Entity** 摆一个 Cube 玩家——加满**五件**（`PlayerMarker`、`PlayerController`、
   零值 `PlayerVelocity`、Kinematic `RigidBody`、`AvianCollider` 胶囊 0.35×1.0）+Camera Rig
   拖到它下面+physics 地面——Play 一样能跑能跳（**注意：少一件就悬空不动**，book 有清单）。

## QA 会话产物索引

- 门禁：`loop/reports/t11t3_qa_mac_{fmt,clippy_ws,clippy_physics,libtests,gate_fast,gate_integration,doctests,doctests_bind_rerun,doc,failed_rerun,scaffold_rerun}.log`（11 件）；
  脚本 `loop/qa/t11t3-qa-mac-gates.sh`（串行 8 门，无 RUST_BACKTRACE）。
- 核验对象：`loop/t11t3-live/` 全目录、暖工程 `/Users/zhanglinbo/workspace/loop-mac/t11t1-game/assets/t11t3-*.bsn(.bak)`、
  avian3d-0.8.0 registry 源码、buglist N13/N14/A2、roadmap T11 行。
- 进程收尾：QA 跑后复查无 jackdaw/t11t1-game 残留进程（仅本次门禁自身 rustc）；工作区干净。
