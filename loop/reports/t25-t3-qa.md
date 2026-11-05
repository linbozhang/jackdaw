# T25-T3 终验独立 QA

> QA 起点：`loop/t25-live-tuning` / `f50e15a1`（程序 T3 `1549e081`；此前 T2/T2.5 联合 QA `9af43d44` PASS）。平台 macOS arm64，Rust 1.99.0。QA 只新增本报告与 `loop/reports/t25t3qa_*` 输出，不改产品源、手册、buglist、roadmap、progress 或 T25 驱动脚本。
>
> **裁决：PASS，可放行主控最终闭环；带 C4 已披露的单轮偏差，不是“单次 A–E 零偏差”。** C4 A–E 主跑两条子腿真实 FAIL；经独立 fresh C 窗口重建基线后两条均 PASS。原红证保留，不能用重跑覆盖或抹去。B1 hover tooltip 子腿继续明确 A14-limited/FAIL，不涂绿。

## 1. Diff 面、台账与范围

- `44162952..1549e081` 的产品代码面为零改动：无 `src/`、`crates/`、`integrations/`、Cargo manifest/lock 或测试驱动脚本改动。Book 仅修改既有 `book/src/user-guide/play-in-editor.md` 的 **The stop prompt and live changes** 节；无 `SUMMARY.md`、无新增章节页。其余为 T3 报告、汇总腿/census 日志及 `loop/t25-final/`、`loop/t25-final-c-retry/`、启动失败诊断证据。
- `1549e081..f50e15a1` 仅新增 `loop/progress.md` 一行 T3 程序 closeout/“QA 待派”记录；这与本轮 QA 改动无关。T3 程序提交本身未改 buglist、roadmap、progress。
- 当前 `loop/plans/roadmap-game-dev.md` 的 T25 仍是 `[ ]`。LT10 在 `buglist.md` 已标 `[x]`，LT9、LT8 仍 `[ ]`；buglist 未改。QA 不替主控勾选 roadmap 或结票。

## 2. 13 格矩阵复核

逐读 `loop/reports/t25t3_live_legs.log` 与 `loop/t25-final/console-live.log`，并对照 T2 报告及 `t25-t2-t25-qa.md` 的原 13 格判据和已接受证据面。T2/T2.5 QA 的 D2 修前阻断与 LT10 修后独立三连 PASS 均有保留；T3 的 D2 18 腿汇总与本轮 raw 文档/编辑器日志吻合。

| 格 | QA 判定 | 独立对照要点 |
|---|---|---|
| A1 | PASS | Root x `0.0→2.0`、ledger=1、field marker 6→7；文档/盘/undo 不动，游戏 hazard health `100→85` 但不增账。LT-R1 绿侧与 T2/QA 一致。 |
| A2 | PASS | 同字段重编仍单 entry 且 tray live 值更新；第二实体编辑后 ledger=2、第二行 diff 在档。 |
| A3 | PASS | baseline `(not authored)`、游戏 illuminance=8000；play 窗 Save 写 20 字段整组件 patch、保留 live 值，undo 恰 +1。 |
| A4 | PASS | add/remove 均流送且结构入账；结构行 Revert disabled / Save enabled；移除行 Save 删除 authored patch 并恰 +1 undo。 |
| B1 | PASS（子腿受限） | badge 文本+`jackdaw/pie` 计数、tray row/diff cell 在档。`B1_TOOLTIP_WALKED=FAIL` 如实保留：合成面无 hover（A14），不是 tooltip PASS。 |
| B2 | PASS | play 窗 Revert 将游戏 Root x `3.5→0.0`，ledger -1、marker 消失。 |
| B3 | PASS | per-entry Save 写入 Sun z=3.0，ledger -1、undo 恰 +1。 |
| C1 | PASS | 一条与两条 pending edit 停止均出现正确 prompt 标题，prompt 期间 ledger/document 不动。 |
| C2 | PASS | Apply→文档两值→undo 恰一组→显式 save→reload→replay；游戏 Root x=4.5、Sun z=6.0 与保存值相同。 |
| C3 | PASS | Discard 后 document/disk SHA 恒等、undo 不变、ledger=0、prompt 关闭。 |
| C4 | PASS（fresh C retry；保留主跑两腿 FAIL） | 主 A–E C 窗的 keep+warn 与双 Save/+2 undo 两腿 FAIL；独立 retry 两腿 PASS，raw 细节见 §3。不能描述为主跑一次全绿。 |
| D1 | PASS | stop 后 doc/disk SHA 恒等、ephemeral=0；带 prompt 显式 save 未把 live y=9.0 写盘。 |
| D2 | PASS（18/18） | Path A 全组件 overlay + 单 undo；Path B promote、新 node、ephemeral `31→30`、undo 不变。BSN/盘排除关系内件及逐帧/派生 physics 状态，保留语义组件；reload/replay 后 players=1、health=100、Sun y=6.5，LT10 signature=0。 |

T3 主跑的格级判据与 T2/QA 一致；新增偏差集中在 C4 主跑两子腿。T3 的 `D2_*` 汇总行独立计得 **18 个唯一 PASS 腿**，Path B BSN 检查未发现 `ColliderOf`、`RigidBodyColliders`、`PreSolveDelta`、`VelocityIntegrationData`、`SleepTimer` 或派生质量字段。

## 3. C4 主跑偏差与 fresh C retry 裁决

### 主 A–E 跑：失败原样保留

`loop/t25-final/console-live.log` 的 C 窗显示 C4 prompt 与 Review handoff 通过，但：

- `C4_REVERT_KEEPS_ENTRY_FAIL`：post-stop Revert 后 edits `2→1`，不符合预期 keep+warn/count=2。
- `C4_SAVE_TWO_UNDOS_FAIL`：两行 triage 最终清空，但 undo `0→1`，不是每行一条的 `0→2`。

同窗 `loop/t25-final/editor-live-w3.log` 保留 `drain_game_events`、`cleanup_session_on_stop` 及 despawn command 的 `swap_remove` N13 panic。其时间相关性只构成候选解释，不是已证明根因；不能把主跑 FAIL 归咎为已证实 N13 因果。

### retry：独立重建、基线与结果有效

我逐读了 `loop/t25-final-c-retry/` 的原始 console、editor log、walk/click JSON 与 census，不以汇总 PASS 行替代原始证据。

- `console-prep.log` 记录 retry 使用独立输出目录 prep，重写带 `SceneNodeId(7001/7002/7003)` 的 pristine fixture 并保留 pristine 副本；driver 的 prep 源码（`loop/qa/t25-live.sh`）明确每次先重写 scene、重新打开并 settle_save。warm editor 后实际 C 窗是新 editor PID **10376**（`boot-pid.txt` / `EDITOR_READY`），不同于主跑 C 窗 PID 5504；retry 未覆盖 `loop/t25-final/` 原件。
- retry 的 `console-live.log` 先以 C3 重建干净边界：doc/disk SHA 与 undo 恒等、ledger 清零、prompt 关闭；随后再新建两条 C4 entries。故不是沿用上一失败窗口残留账本或 dirty 文档。
- raw `walk-prompt-c4.json.gz` 显示标题 `2 live edits not saved to scene` 与 Review；`c4-revert-click.json` 返回 `clicked:true`，`editor-live-w2.log` 对应 operator 随后记录 `has no live counterpart right now, keeping the entry` warn；console 读回 edits 仍为 2。keep+warn 与按钮执行、状态读回闭合。
- 两份 `c4-save-click*.json` 均命中 Save 按钮；editor log 有两次 `pie.live_edit_save`；console 读回 edits=0、undo `0→2`、`C4_SELF_HEALED_PASS`。tray/prompt 不重现的 leg 通过；raw walk 记录了 handoff tray 与 triage 后状态。
- retry census 单列 `error-handler panics=1 / swap_remove=1`（warm/editor 两窗合计），不并入 A–E。

**独立裁决：C4 偏差非阻断，整体 PASS。** fresh 窗口与基线真实独立，两个失败子腿按相同结构化判据复现为绿，keep+warn、双 Save 各一条 undo、self-heal 均有操作与读回证据。偏差仍是本 QA 的显式限制：主跑并非零偏差，单次 retry 不证明长会话/受污染窗口永远不会再现。保留 N13/LT9 open 与观察，不虚构根因、不扩大修复范围。

## 4. Census 与 warning 归因

QA 对原始 `editor-live-w1..w5.log` 独立计数（归档见 `loop/reports/t25t3qa_census.log`）：

| 窗口 | error-handler panic | `swap_remove` |
|---|---:|---:|
| A / w1 | 3 | 4 |
| B / w2 | 2 | 2 |
| C / w3 | 4 | 5 |
| D / w4 | 1 | 1 |
| E / w5 | 4 | 6 |
| **A–E 合计** | **14** | **18** |

C4 retry 另计 1/1。对 T3 主跑及 retry 原始 editor logs 的 LT10 load-error signature（`does not fit bevy_ecs::entity::Entity` / `ColliderOf` 或 `RigidBodyColliders` construct panic）复核为 **0**；D2 的结构化 `D2_NO_LT10_LOAD_PANIC` 也 PASS。前序 T2 Path B 的旧 LT10 panic 不在 T3 五窗目录/此 N13 合计中，未混算进窗口 E。

抽样归因吻合原件：N13 是 `drain_game_events`/`cleanup_session_on_stop` 等 error-handler 捕获的 `swap_remove` panic；另有层级翻挪产生的 stale `ChildOf` warn、模板未解析 `sounds/ambient.wav` 的 keep-reference warn、preset keymap 重复 chord warn。D2 的通用 `Entity has no BSN representation` 是 from_reflect warning，不匹配 LT10 load/construct signature。`SetComponent|AddComponent`、unknown-field、field-write-skipped 游戏失败 warn shape 均为 0。上述噪音不作为格判据，也不改写票据归因。

## 5. Book、链接与技术准确性

- 扩写只落在既有 PIE 节；对照源码确认：游戏 `With<Transform>` 及 DerivedFaceMesh/FrameCaptureCamera 排除、projection/save/resource 三层过滤、badge 为计数且 Review/重开 handoff、结构增删的 Save/Revert 行态、Path A 单 undo、Path B v1 不可撤销，以及 Path B 的 Avian session relationship/per-frame/derived-state 精确过滤均与现有实现和 T3/T2.5 证据一致。
- 文案明确“当前内建过滤，不是用户可配白名单”；显式 Save/Apply 与磁盘 Save 分开；停止后无 live entity 的 Revert 可 warn 并留 entry；LT8 badge 不开 tray、LT9 仍 open 且只给 workaround。30 秒清单未把 LT9、tooltip、Path B undo 性能写成已解决或保证行为。现有 Configuration、Run targets、Debugging Errors 交叉链接无误。
- 独立文件级 checker 覆盖 `SUMMARY.md` + PIE 页共 44 个本地链接目标（其中 1 个 fragment），0 断链；摘要输出在 `loop/reports/t25t3qa_links.log`。`SUMMARY.md` 未改。`command -v mdbook` 无结果，本机未安装/不在 PATH 的报告事实成立，未安装工具或运行构建。
- **Whitespace 勘误：**针对 book 页、T3 报告与 census 汇总文件的 `git diff --check` 为 0；archive 全量 `44162952..1549e081` 检查返回 2，来源是生成/原样保留的 `LIVE done`、`PHASE_DONE` 等 stdout 行尾空格及被捕获文档/日志 EOF 空行；T3 artifact 细项在 `loop/reports/t25t3qa_diffcheck.log`。`1549e081..f50e15a1` ledger diff 检查为 0。故 T3 报告的宽泛“`git diff --check` 通过”仅适用于正文/实质文件，不能用于声称整个新增原始证据归档无空白差异。本 QA 提交的原始 cargo test stdout 也各有一条 EOF 空行，`t25t3qa_diffcheck.log` 忠实包含被检查输出的行尾空格，因此 staged 全 QA artifact 检查同样会标记这些捕获件；报告/手册正文无空白问题。未重排或改写任何 raw stdout；此为非阻断归档格式偏差。

## 6. 门禁独立亲跑

开始前 `df -h .` 可用 **24 GiB**（高于 15 GiB 线），`RUST_BACKTRACE` 未设置。fmt、clippy 与测试运行于 live editor 关闭后的独立 QA 门禁窗；全流程 exit 0，完整 stdout/stderr 均存档：

| 命令 | 独立 QA 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0，0 bytes | `loop/reports/t25t3qa_fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，0 warning/error | `loop/reports/t25t3qa_clippy_ws.log` |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，0 warning/error | `loop/reports/t25t3qa_clippy_physics.log` |
| `cargo test --workspace --lib` | 59 suites，**3091 passed / 0 failed** | `loop/reports/t25t3qa_libtests.log` |
| `cargo test -p jackdaw --test guards` | **248 passed / 0 failed**（181.70 s） | `loop/reports/t25t3qa_guards.log` |

程序报告中的 fmt/workspace+dylib clippy/physics clippy/libtests 3091/guards 248 结果获独立重跑支持；真机与门禁窗分离。QA 未重跑 editor dylib build（T3 该 build 有独立归档，QA 本轮产品代码零改动）。

## 7. LT 素材与最终交接

| 票 | QA 素材/处置建议（不代主控改票） |
|---|---|
| LT5 | 保持 open/低优先级。Path B v1 不可撤销是真机/源码事实；book 已提示 disposable scene/backup。 |
| LT6 | 保持 open/低优先级。无默认 baseline 时 stop 后 Revert 可保留 entry 并 warn；book 对该可见边界给出 Save/Apply/Discard 替代法。 |
| LT7 | 保持 open/低优先级。A14 不支持 hover/Display 强证明；tooltip 子腿仍 FAIL 注记，badge 判据用 count+文本，不夸大可见性。 |
| LT8 | 保持 open/低优先级。badge 只是 count、点击不展开；手册推荐 stop→Review handoff，语义一致。 |
| LT9 | **继续 open/中优先级**。长会话 stale projection 未修；手册标为 open limitation，仅给 stop/restart workaround。 |
| LT10 | 已具备结票证据。T2.5 改动边界/测试、联合 QA 的 3 次 fresh D2 18/18、T3 D2 18/18 与 LT10 signature=0 相互闭合；buglist 已 `[x]`，建议主控维持已修并正式收票。 |

**最终：PASS 放行 T25-T3 QA。** 交主控执行票据/roadmap/分支收官；必须保留 C4 主跑两腿 FAIL + fresh C 两腿 PASS、B1 tooltip A14-limited、LT9 open 三项事实。QA 未勾选 T25 roadmap 或改动其他状态文件。
