# T25-T3 终验与 book 轮报告

> 分支 `loop/t25-live-tuning`；起始 HEAD `44162952`；2026-11-04；macOS arm64。真机主跑使用 `loop/qa/t25-live.sh prep` + `live`，A–E 五窗自足；终态证据在 `loop/t25-final/`，C4 独立复验在 `loop/t25-final-c-retry/`。归档前缀 `t25t3_*`。`RUST_BACKTRACE` 未设置；prep/gates 窗磁盘可用 21 GiB（高于 15 GiB）；fixture 带 SceneNodeId 7001/7002/7003。

## 结论

13 格均有最终通过证据；其中 C4 首轮全矩阵运行的两个收尾子腿与预期不同，已在全新隔离 C 窗复跑并全部通过，首轮偏差和原始证据均保留。D2 Path A/B 与修后 `save → reload → replay` 收链在 A–E 主跑中 **18/18 PASS**，LT10 专用 load-error signature 为 **0**。B1 的 hover tooltip 子腿仍不可达（A14 工具限制），其余差异面判据全绿，按 T2/T2.5 QA 的 cell 口径列 B1 PASS。

产品源码、Cargo manifest/lock、协议、`scene_io`、buglist、roadmap、progress 与 `loop/qa/t25-live.sh` 均未改。唯一产品面外的内容为本报告、book 扩写及终态 QA 归档。

## 13 格终态矩阵

| 格 | 终态 | 结构化结果 / 证据锚 |
|---|---|---|
| A1 | PASS | Root `Transform.translation.x` 游戏侧 0.0→2.0；`live_edits=1`；字段行 marker 结构计数 6→7；文档/磁盘/undo 不变，构成 LT-R1 绿侧；hazard health 100→85 时 ledger 不增。主跑 `A1_*` 与 `LTR1_GREEN_*`。 |
| A2 | PASS | 同字段重编辑仍一条 entry，tray live 侧更新 2.0→3.5；第二实体 Sun 编辑使 count=2，第二行 `0.0 -> 5.0` 在档。主跑 `A2_*`。 |
| A3 | PASS | 未 authored 的 DirectionalLight 字段 baseline 显 `(not authored)`；游戏值 8000；play 窗逐条 Save 写 20 字段整组件 patch，带 live 值，undo 恰 +1。主跑 `A3_*`。 |
| A4 | PASS | Root add、Sun remove 均流送并入结构账；结构行 Save enabled / Revert disabled；移除行 Save 删除 authored patch 且 undo +1。主跑 `A4_*`。 |
| B1 | PASS（tooltip 子腿 A14 限制） | badge 文本与 `jackdaw/pie` count 联判，tray row/diff cell `baseline -> live` 在档；tooltip walk 子腿 `B1_TOOLTIP_WALKED=FAIL`，因合成面没有 hover，按既定 A14 限制记录，不伪称通过。主跑 `B1_*`。 |
| B2 | PASS | Play 窗 Revert 把游戏侧 Root x 3.5→0.0，ledger 减 1，字段行 marker 消失。主跑 `B2_*`。 |
| B3 | PASS | per-entry Save 写入 Sun z=3.0，ledger 减 1，undo 恰 +1。主跑 `B3_*`。 |
| C1 | PASS | 一条与两条 pending edit 停止均得到正确 StopPrompt 标题；弹窗期间 ledger 不变。主跑 `C1_*`。 |
| C2 | PASS（五点链） | Apply All 后文档字段变、undo 恰 +1（一组）；显式 save 写盘；reload 保留字段；replay 的游戏 BRP Root x=4.5、Sun z=6.0 等于保存值。主跑 `C2_*`。 |
| C3 | PASS | Discard 后 document SHA、disk SHA、undo 深度恒等；ledger 归零，prompt 关闭。主跑 `C3_*`。 |
| C4 | PASS（独立 fresh C 复验） | 主跑 Review→tray、自愈收空均通过；但首轮 post-stop Revert 未走预期 keep+warn，`edits 2→1`，且两行 Save undo `0→1`，故两子腿首轮记 FAIL。另以 `T25_WINDOWS=C` 在独立目录 fresh editor 重跑，Review handoff、Revert 保留 count=2 + warn、两次 Save 后 count=0 / undo `0→2`、tray 自愈全部 PASS。保留两轮，不以复跑覆盖首轮。 |
| D1 | PASS | Stop 后 document/disk SHA 恒等、ephemeral=0；prompt 仍开时显式 scene.save 不写入 live y=9.0，文档仍不变。主跑 `D1_*`。 |
| D2 | PASS（18/18） | Path A 全组件 overlay、单 undo、live y=6.5；Path B ephemeral 31→30、undo 不变（LT5 v1）；Transform/RigidBody/Capsule/ColliderDensity 等语义配置保留；ColliderOf/RigidBodyColliders 与逐帧/派生 physics 状态在 BSN/盘均缺席；save、reload、replay 后玩家=1、health=100、Sun y=6.5；LT10 signature=0。主跑全部 18 个 `D2_*` legs。 |

主跑 13 格原始逐腿记录：`loop/reports/t25t3_live_legs.log`；D2 专项原件为 `loop/t25-final/` 下 `d2a-doc.txt`、`d2b-doc.txt`、盘快照、selection/walk、`editor-live-w5.log`。大于 500 KiB 的 walk JSON 已无损 gzip（`.json.gz`）。

### D2 三腿收链与 LT10 判据

- `D2_DISK_HAS_PLAYER=PASS`，同时盘上关系内件和逐帧/派生字段排除腿 PASS。
- reload 后 replay 的 `D2_REPLAY_PLAYER_IN_GAME=PASS`、`D2_REPLAY_HEALTH_PRESENT=PASS`、`D2_REPLAY_SUN_Y=PASS`（Sun y=6.5）。
- `D2_NO_LT10_LOAD_PANIC=PASS`，明确 signature 为 0；T3 D2 18 个结构化腿全 PASS。
- D2 editor log 仍有 N13 panic 和通用 `Entity has no BSN representation` warning；后者不是 LT10 signature（与 T2.5/QA 判据一致），并已保留原始日志用于归因。

## Census、偏差与票据

### N13 / LT9 归因

A–E 主跑 census：**error-handler panics=14、`swap_remove` signature=18**，逐窗明细在 `loop/reports/t25t3_census.txt` / `loop/t25-final/census-live.txt`。

| 窗 | error-handler panics | `swap_remove` signature |
|---|---:|---:|
| A / editor w1 | 3 | 4 |
| B / editor w2 | 2 | 2 |
| C / editor w3 | 4 | 5 |
| D / editor w4 | 1 | 1 |
| E / editor w5 | 4 | 6 |
| **合计** | **14** | **18** |

SetComponent/AddComponent、unknown-field、field-write-skipped warn shape 均为 0。独立 C 复验 census 为 1/1（包含 warm editor 和 C editor），不并入 A–E 主跑数字。

A 窗的 `jackdaw/pie` projection telemetry 在 cycle 1 为 `authored=3, ephemeral=31`，Review replay 后读到 `authored=13, ephemeral=21`。本轮 `ROUTE_FALL_THROUGH` / retry guard 触发次数为 0，所有 routed edit/add/remove 面腿通过；这不是已证明的路由红，但属于 LT9 继续开放的观测，不能据此宣称长会话问题已修或已消失。

C4 首轮的 Revert/undo 两子腿失败，与同一 editor log 中 `cleanup_session_on_stop` 及 despawn command 的 N13 panic 同窗出现；fresh C 复验两腿转绿。记录为 N13 时序相关候选，不将相关性写成已证明根因，也不以其掩盖首轮失败。无产品修复扩大范围。

### LT5–LT10 处置建议（供主控收账）

| 票 | 建议裁定 | T3 素材 |
|---|---|---|
| LT5 | 保持 open / 低优先级 | Path B 在 v1 仍不可撤销；D2 undo 深度不变是真机事实。book 已明确提醒先备份/使用 disposable scene。 |
| LT6 | 保持 open / 低优先级 | 缺 `ReflectDefault` 且无 baseline 时，Revert 保留 entry 并 warn；保持当前稀疏边界，不扩修复面。依据 plan §0 与 T2 事实五。 |
| LT7 | 保持 open / 低优先级 | A14 下 `ui_tree` 不暴露 Display；badge 判据用计数面 + 文本联合，不把单一 walk 当可见性证明。 |
| LT8 | 保持 open / 低优先级 | badge 是计数器，点击不打开 tray；明确 Stop→Review 是验证过的 tray handoff。仅 book 记边界，不改 UI。 |
| LT9 | 保持 open / 中优先级 | 无代码触碰；A–E 与 guard 保持短窗自守，guard 本轮 0 次。projection authored 3→13 的观测转交主控，不作修复结论。 |
| LT10 | 维持已修 / 主控收票 | T2.5 联合 QA PASS 后，T3 D2 再次 18/18，具体 LT10 signature=0。主控完成最终 ledger/roadmap closeout。 |

核对 `buglist.md` 当前只列有 LT8、LT9、LT10；未找到 LT5–LT7 的独立条目。本表按计划/T2 报告补充处置素材，不代主控新增或修改 buglist、roadmap、progress。

## Book、文档与门禁

- 扩写既有 `book/src/user-guide/play-in-editor.md` 的 **The stop prompt and live changes** 节；未新建章节页、未改 `SUMMARY.md`。覆盖 diff、Inspector marker、tray 与三键 prompt、Review handoff、有限白名单三层边界、结构行 Save/Revert、Path A/B、LT5/LT9/N13 注记、显式 Apply/Save/Save to Scene gate 与 30 秒检查清单。
- `mdbook` 不在本机 PATH，未能执行 `mdbook build`。文件级链接检查覆盖 PIE 页和 `SUMMARY.md` 的 44 个本地链接/锚点，0 个缺失；现有 PIE→Configuration、Run targets、Debugging Errors 链接和 SUMMARY 的 PIE 条目均在。`git diff --check` 通过；SUMMARY 未改。
- gates 在 live editor 窗关闭后独立执行；磁盘 21 Gi，`RUST_BACKTRACE=<unset>`。

| 门禁 | T3 结果 | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0，零输出 | `loop/t25-final/t25t3_gates_fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，0 warnings | `loop/t25-final/t25t3_gates_clippy_ws.log` |
| physics 双包 clippy | EXIT=0，0 warnings | `loop/t25-final/t25t3_gates_clippy_physics.log` |
| `cargo test --workspace --lib` | **3091/3091**（T3 本轮实跑；与 T2.5 基线相同，不能仅借用 T2.5 证明） | `loop/t25-final/t25t3_gates_libtests.log` |
| `cargo test -p jackdaw --test guards` | **248/248** | `loop/t25-final/t25t3_guards.log` |
| 真机前 `cargo build --features dylib` | EXIT=0；用于解决本机 stale editor/dylib mismatch | `loop/t25-final/t25t3_build_prelive.log` |

## 偏差与收尾交接

1. 首次 `live` 尝试的 editor 启动遇本机 `dyld: Symbol not found`（旧 `target/debug/jackdaw` 与 `libjackdaw_dylib.dylib` 不匹配），没有进入矩阵。失败原件保留在 `loop/t25t3_preflight_fail/`；独立 `cargo build --features dylib` 后重新 prep，以新 `loop/t25-final/` 完整跑完 A–E。
2. B1 tooltip 子腿因无合成 hover 保留 A14 注记，不阻塞 cell。
3. C4 首跑两腿 FAIL、独立 C fresh-window 重跑全绿；首跑原件未覆盖，复验位于 `loop/t25-final-c-retry/` 与 `loop/reports/t25t3_c4_retry.log`。主控收官时应保留这项时序偏差，而不是只引用绿色重跑。
4. A 窗 projection 数量上涨和 N13 census 继续支持 LT9/N13 留档；LT9、N13、A7/A9/A10/A14、Path B undoability 均未改。
5. Fixture `scene.bsn` 与 `.pristine` 最终 `cmp=0`；`buglist.md` / roadmap / progress 未改；无产品源码改动。

原始证据目录 `loop/t25-final/`（A–E）和 `loop/t25-final-c-retry/`（C3/C4）；启动失败诊断 `loop/t25t3_preflight_fail/`。报告、book 与 `t25t3_*` 汇总日志待同分支提交。
