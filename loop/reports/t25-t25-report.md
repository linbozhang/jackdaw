# T25-T2.5 LT10 小修轮报告

> 分支 `loop/t25-live-tuning`，起始 HEAD `c86b5034`。2026-11-04。执行顺序遵循 T22-T3.5 的红绿纪律：先保留旧红证与中间态，再修 capture filter，最后独立重开复跑。旧的六次 `t25t25_run1`–`run6` 证据未覆盖；新验证归档于 `loop/t25-live/t25t25_run9/`–`run11/`。

## 结论

**LT10 已修复。** Path B 只改变 `promote_ephemeral_to_authored` 的新实体捕获面：复用 `scene_io::should_skip_component`，额外排除确切的 Avian 会话关系组件及确切的逐帧/派生物理状态路径；共享 `scene_io`、Path A、Stop/停止语义均未改。新脚本用正向语义组件、关系内件缺席、逐帧状态缺席和 reload/play 结果共同判定，不再把“没有 `ColliderOf`”当作失败。

| 验收项 | 结果 |
|---|---|
| Path B 关系内件不入 BSN/盘 | run9–run11 三份最终 D2 文档均无 `ColliderOf`、`RigidBodyColliders` |
| 逐帧/派生物理镜像不入 BSN/盘 | run9–run11 三份最终 D2 文档均无 Physics `Position`/`Rotation`/`PreSolveDelta*`、velocity、sleep、AABB、质量派生等状态 |
| 语义组件仍入文档 | Transform、RigidBody、AvianCollider capsule、ColliderDensity、ColliderAabbMargin、CollisionLayers、SleepThreshold 均通过 |
| 真机独立 D2 重验 | run9、run10、run11；每次 18/18 D2 legs PASS，包括保存后重新打开、Play、玩家/健康值与 LT10 错误签名检查 |
| 完整门禁 | fmt EXIT=0；workspace+dylib clippy EXIT=0；physics dual-package clippy EXIT=0；libtests 3091/3091；guards 248/248 |

## 捕获过滤审计

### 排除项及其依据

| 捕获类别 | 确切匹配范围 | 依据与验证 |
|---|---|---|
| Avian 关系内件 | `avian3d::collision::collider::collider_hierarchy::ColliderOf`、`...::RigidBodyColliders`，且反射树仍包含 Entity 时才跳过 | Avian 源码中 `ColliderOf { body: Entity }` 是 `Relationship`，`RigidBodyColliders(Vec<Entity>)` 是自动维护的 relationship target；存的是本会话 bits，重开不能作为文档值恢复。新单测真实建立两者关系并分别验证不入节点；反射检查覆盖直接字段及实际使用的 `Vec<Entity>`。关系过滤只对这两个确切 type path 生效，不会因任意游戏组件含 Entity 就将它过滤。 |
| physics transform mirrors / solver scratch | `Position`、`Rotation`、`PreSolveDeltaPosition`、`PreSolveDeltaRotation` 的确切路径；同时列出短 re-export 与 Avian 实际反射出的 `avian3d::physics_transform::transform::*` 路径 | `Position`/`Rotation` 是 Avian 与 authored `Transform` 同步的物理侧镜像；`PreSolveDelta*` 是位置/旋转求解临时增量。run7 首次重验实证运行时 BSN 路径带 `transform::`，此前仅列短路径会漏过；已补确切嵌套路径及脚本检测，run9–11 的文档均不含这些字段。 |
| 每步积分器状态 | `avian3d::dynamics::integrator::VelocityIntegrationData` | Avian 文档说明其预计算 velocity increments/damping operands 每 timestep 更新、再用于 substeps；只列该组件路径，不用整个 integrator 模块前缀。 |
| collider/ broad-phase 派生状态 | `ColliderAabb`、`EnlargedAabb`、`ColliderTransform` | Avian 源码说明 AABB 从 collider shape 重算，EnlargedAabb 由其派生，ColliderTransform 从 authored Transform 同步；均为重开可重建的瞬态值。 |
| 当前动力学/睡眠/力累积状态 | `LinearVelocity`、`AngularVelocity`、`Sleeping`、`SleepTimer`、`AccumulatedLocalAcceleration` | velocity/sleep timer 是运行时当前值；accumulated acceleration 是 solver 每步排空的累积量，不是 authored 配置。用户要求的 Position/Velocity 类逐帧值不落盘由真实 BSN legs 复核。 |
| collider 派生质量 | `ComputedMass`、`ComputedAngularInertia`、`ComputedCenterOfMass`、`ColliderMassProperties` | Avian 源码将 computed 值定义为从刚体/形状/密度派生；`ColliderMassProperties` 明确为 read-only，手动添加无效并会从 shape+density 重算。 |

所有物理项使用 exact type path，不再按 `avian3d::physics_transform::`、`integrator::` 或 `solver_body::` 整个模块前缀过滤。审计发现 integrator 模块邻近有语义组件 `CustomVelocityIntegration`、`CustomPositionIntegration`；单测证实它们保留。SolverBody 工作结构不是 ReflectComponent，故不把整个 solver module 纳入过滤。反射树对于容器只检查直接 item/key/value；这覆盖本轮实际 Avian 关系形状（`ColliderOf` 直接字段、`RigidBodyColliders(Vec<Entity>)`），未声称支持任意多层嵌套容器。

### 保留项

- `bevy_transform::components::transform::Transform`：authored 姿态，单测及三次真机均保留。
- `avian3d::dynamics::rigid_body::RigidBody`：语义刚体类型，三次真机均保留。
- `jackdaw_avian_integration::AvianCollider(avian3d::...::ColliderConstructor::Capsule { ... })`：authored 碰撞形状，单测/脚本/三次真机均保留。
- `ColliderDensity`、`ColliderAabbMargin`、`CollisionLayers`、`SleepThreshold`：physics 配置值，三次真机均保留。
- `CustomVelocityIntegration`、`CustomPositionIntegration`：自定义积分语义标记，单测保留，证明未用 integrator 模块前缀误删。

### 改动边界

产品代码仅在 `src/pie.rs`：Path B 改用 promote 专用 AST 注册捕获函数，保留旧注册函数的 dead-entity/resource/already-registered guard、node/parent 创建和 per-component upsert，再应用原 save policy + 新过滤。Path A 的 `promote_authored_overlay`、`scene_io/{mod,save}.rs` 和停止逻辑零改动；没有改 Cargo 依赖或 LT9。

## 红绿对照与判据更正

- **原始产品红证仍保留**：`loop/t25-live/editor-live-w2.log` 中 Path B 将 Entity refs 写为 Debug 字符串，load 时出现 `alloc::vec::Vec<bevy_ecs::entity::Entity>[0]: does not fit ...`，随后 `Couldn't create an instance of ... ColliderOf`，PIE `exit status: 101`；原 T2 汇总见 `loop/reports/t25t2_live_legs.log` D2 与 `loop/reports/t25-t2-report.md` §二/§四。
- **旧六次 `LAND_FAIL` 是过时判据，不是产品红**：`loop/reports/t25t25_run1_live.log`–`run6_live.log` 的旧脚本用正向 `grep ColliderOf` 并将“出现”命名为 `D2_PROMOTE_INTERNALS_LAND`。过滤后文档确实不含 `ColliderOf`，于是旧 label 输出 FAIL；逐份核对 run1–run6 的 `d2b-doc`，关系内件与已检查的逐帧字段都缺席，而 Transform、RigidBody、ColliderDensity、ColliderAabbMargin、CollisionLayers、SleepThreshold 与 capsule shape 在。六次日志及文档未修改、未覆盖。
- **run7 诊断迭代**：真机文档暴露 Avian 将 Physics transform 的反射路径写作 `avian3d::physics_transform::transform::Position/Rotation/PreSolveDelta*`；此前 exact list 只写短 re-export path，漏掉真实反射路径。run7 的 `d2b-doc.txt` 因此仍有 4 个 physics-transform 快照，说明它是真正的过滤遗漏；已补确切嵌套路径并由新单测/脚本锁定。run7 的 load/play 实际玩家与健康值均在，`D2_NO_LT10_LOAD_PANIC` 当时被宽泛的 `Entity has no BSN representation` warning 误报；该 warning 可由 Path A 的 reflected overlay 产生，不等于 LT10 的 apply/construct panic。新脚本只匹配具体的 `does not fit bevy_ecs::entity::Entity` 或 `create an instance ... ColliderOf/RigidBodyColliders` 错误；通用 warning 仍保留在 editor log 中供归因。
- **run8**：独立 editor warm-boot 后、D2 selection 前中断，文件保存在 `loop/t25-live/t25t25_run8/` 并标为 partial，不计入三连验收。

## 真机 D2 三连结果

脚本以 `T25_WINDOWS=E` 对现有 fixture 连续启动三个新的编辑器 D2 窗口；每个 run 均用 BSN `x: -2.0` 候选定位 player，运行 Path A + Path B，保存后 `scene.open reload` 并再次 Play。每份证据分开记录 `console-live.log`、`editor-live-w*.log`、`census-live.txt`、`d2b-doc.txt` 与 selection/walk JSON。

| Run | D2 legs | 关键结果 | N13 census（单列，不算 LT10） |
|---|---:|---|---|
| run9 | 18/18 PASS | ephemeral 31→30；undo 1→1；Transform/RigidBody/Capsule/Density 配置入文档；关系与逐帧值不在文档/磁盘；reload 后 players=1、health=100、Sun y=6.5；LT10 load-error signature=0 | error-handler panics=4，swap_remove=6 |
| run10 | 18/18 PASS | 同上；reload 后 players=1、health=100、Sun y=6.5；LT10 load-error signature=0 | error-handler panics=4，swap_remove=6 |
| run11 | 18/18 PASS | 同上；reload 后 players=1、health=100、Sun y=6.5；LT10 load-error signature=0 | error-handler panics=3，swap_remove=5 |

这三轮仍有旧 N13 `swap_remove`/error-handler 噪音（各轮 census 单独归档），但没有 LT10 `Entity` apply/ColliderOf construct 错误；游戏侧玩家及健康值均实际应答。三轮结束后 fixture 与 `.pristine` 字节一致。

摘要：`loop/reports/t25t25_run9_live.log`、`run10_live.log`、`run11_live.log`。逐轮原始证据分别在 `loop/t25-live/t25t25_run9/`、`run10/`、`run11/`。

## 门禁与测试

最终门禁日志在 `loop/t25-live/t25t25_fixed/gates/`，编辑器 build 在 `loop/t25-live/t25t25_fixed/build-editor.log`。

| 命令 | 结果 |
|---|---|
| `cargo fmt --all -- --check` | EXIT=0，日志零字节 |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，28 行编译/检查输出，0 warning/error |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，18 行编译/检查输出，0 warning/error |
| `cargo test --workspace --lib` | **3091/3091**；T25-T2 基线 3087 + 本轮 4 个 promote tests |
| `cargo test -p jackdaw --test guards` | **248/248** |
| `cargo build --features dylib` | EXIT=0，构建用于真机 D2 的 editor binary |

新增四个单测名：`promoted_relationship_internals_do_not_land_in_the_document`、`promoted_per_frame_physics_mirrors_do_not_land_in_the_document`、`promoted_semantic_components_all_land_in_the_document`、`the_entity_walk_is_scoped_to_known_avian_relationships`。

首次 gate 试跑中 clippy 曾暴露“直接引用 Avian 但 editor crate 无直接依赖”和 doc-markdown lint；已改为 exact type-path + reflection 判断并格式化文档。该次诊断日志保留在 `loop/t25-live/t25t25_gate_attempt1/`；上述最终门禁表只引用后续完整绿跑 `t25t25_fixed/gates/`。

## 归档清单与偏差

- 保留了原 T2 红证、旧六次 `t25t25_run1`–`run6` 试跑证据、部分落在根目录的工作树输出（归档为 `t25t25_preexisting_*`），以及 run7 的 per-frame 诊断和 run8 partial；没有覆盖或删除旧证据。
- 新 D2 判据将旧 `D2_PROMOTE_INTERNALS_LAND` 改为 `D2_PROMOTE_INTERNALS_EXCLUDED`，并新增 `D2_PROMOTE_SEMANTIC_COMPONENTS`、`D2_PROMOTE_PER_FRAME_EXCLUDED`、磁盘侧对应判据和明确 LT10 load-error 检查。
- 本轮只解决 LT10；LT9 未改。N13 与 D2 无关，仍按每轮 census 如实记录。
