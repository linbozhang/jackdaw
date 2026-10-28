# feature-05 任务 1 QA 报告：R1 视口修复 + 交互驱动手册（真机验收）

> 多 Agent 开发循环 · QA（验收工程师）· 2026-10-23
> 验收对象：`loop/interaction-ux` @ `cb9a6661`（diff = `src/input_contexts.rs` +147/-0）
> 契约依据：loop/README.md 交互验收新契约（真机驱动）+ 方案 §R1/§D3 + 任务 1 节
> **结论：PASS**

## 1. 门（单命令逐条，无 `;` 串联）

| 门 | 退出码 | 备注 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | |
| `cargo clippy --workspace -- -D warnings` | 0 | 仅存量 linker_messages 警告（该 lint 明文豁免 -D） |
| `cargo xtask fast` | 0 | 2802 passed / 2 skipped（含 input_contexts 9/9，4 个新单测全过） |
| `cargo xtask integration` | 0 | 4933 passed / 3 skipped |

与程序报告 §3 一致。验收前从当前 commit 重建 `target\debug\jackdaw.exe`（cargo build --bin jackdaw，28s），排除旧二进制。

## 2. 代码审查

- **修复面收敛**：`git diff main..loop/interaction-ux` 仅 `src/input_contexts.rs`，+147/-0；
  排除该文件后 diff 为空。无 T2（工具取消/ActiveTool Reflect）/T3（Add 菜单）改动。
- **抑制语义正确**：`fly_age_frames: Local<u32>` 为会话年龄计数器；fly 上升沿起
  `age < 3` 的帧（edge/edge+1/edge+2）look 置零，第 4 帧起直通；`!fly_active` 帧复位，
  再按下重新抑制（单测 2 直接覆盖）。「按住中途再按下」不存在（同键需先释放，释放帧即复位）；
  焦点丢失结束 fly 后重新进入按新会话处理，语义合理。
- **不误伤**：`move_axes`（WASD/QE）与 `zoom_ticks` 路径一字未动（函数体全文核对），
  单测 4 断言抑制帧内 move_axes.z=1.0、zoom_ticks=2.5。
- **无插桩残留**：src/ 内 `rg "R1DBG|JACKDAW_FLY_GRAB"` 零命中（判别日志只在
  loop/reports 档案里）；无 println/eprintln/warn! 残留。
- **常量注释**：根因（指针栈在 grab 切换瞬间重锚定、10^4–10^6 px 合成 raw delta、
  3 帧窗口覆盖 press 帧/grab 请求帧/grab 在 Last 应用帧）写清并引用档案路径。
- **单测质量**：4 个新单测断言均为精确相等（非弱断言）；含实测巨 delta
  (492988, 690804) 喂入断言置零 + 窗口后 15px 直通。⚪ 建议：单测 4 只验了抑制窗
  第 1 帧的 move/zoom，未遍历全部 3 帧（影响极小）。

## 3. 真机复验（QA 亲测数字；二进制 = 当前 commit 重建）

### 3.1 `r1-drive.ps1 -Drive Full -Repeat 10 -Label qa-full` → `loop/reports/r1-qa-full/`

| 指标 | 实测（×10） | 判定 |
|---|---|---|
| press 旋转跳变（容差 0.005 rad） | dyaw=dpitch=**0.000000 ×10** | PASS |
| 环视（按住拖 20×(15,0)） | dyaw=**0.899999~0.900002**（iter4 记 5.383184 = 0.9+2π 回绕，yaw −2.700→2.683 处）；dpitch=**0.000000 ×10** | PASS |
| W 按住 400ms 位移（理论 4.0） | **3.990~4.636** units（iter8=4.636 偏大为帧时长波动） | PASS |
| pitch 全程 | 恒 −0.463648/−0.463647，无漂移 | PASS |

### 3.2 `r1-drive.ps1 -Drive Press -Repeat 3 -Label qa-press`

press 单步 ×3：dyaw=dpitch=**0.000000 ×3**，全部 press_ok=True。

### 3.3 QA 手动驱动（BRP 通道亲测 + 单次环视交叉确认，`loop/reports/r1-qa-manual/`）

- **亲自 `world.query` 相机 Transform**（brp.ps1 裸调）：返回 7 个相机行；
  唯一 `is_active=true` 且 `Projection=Perspective` 的 3D 视口相机 = **3693v0**，
  translation=(0,4,8)，rotation 四元数 (−0.2298,0,0,0.9732) → yaw=0.000000 /
  pitch=−0.463648（与 camera_system YXZ 提取一致）。
- 手动序列（SendInput）：聚焦→光标窗口中心 (691,411)→jiggle→RMB 按住 500ms→
  读相机（**dyaw=0.000000 dpitch=0.000000**）→拖 20×(15,0)→读相机
  （**dyaw=0.900000 dpitch=0.000000**）→松开。GetCursorPos 探针全程钉在 (691,411)
  （Locked grab 的 ClipCursor 生效，OS 光标不动、raw delta 驱动环视——行为符合设计），
  GetForegroundWindow 全程 = jackdaw 窗口。
- **截图证据**：`qa-manual2-window.png`（PrintWindow 全窗，空场景网格 + 视口相机）；
  `r1-qa-full/full-01.png`（第 1 轮环视后：视口视角相对正视偏转 ≈45–50°，与
  yaw −0.9 rad ≈ −51.6° 吻合）。

### 3.4 驱动侧 flake 记录（非产品缺陷）

手动第一次尝试 look_ok=False（dyaw 恒 0，fly 未触发，OS 光标自由漂移）——
与 manual.md §4 已记载的 flake 模式（hover 注册/焦点类偶发）一致；同结构加探针
重跑即稳定通过。3.1/3.2 的 13 轮脚本驱动无一次 flake。

## 4. 判别档案抽查（数据可信，非编造）

- `r1-disc-pm-none/editor-stderr.log`：真实 `[R1DBG]` 帧日志与程序报告 §1 表格
  **逐数字吻合**——iter1 FLY_EDGE 37028.78 → edge+2 (492988, 690804) len=848673.88；
  iter2 36935.50 / 441904.56 / 329593.66。注入值确为 15px/步（脚本源码核对）。
- **GRAB_APPLY 时序**：日志中 GRAB_APPLY 帧号 = edge+1（1311→1312、1383→1384）；
  bevy_winit 源码 `lib.rs:160-163` 证实 `changed_cursor_options` 注册在 **Last**——
  「edge+1 Last 才 ClipCursor、合成 delta 最早 edge+2 被读到」成立，N=3 有据。
- `r1-fixed-final/metrics.csv`：press 0.000000×10、look 0.9×10（iter4 5.383184 回绕
  已核实 = 0.9+2π）、move 3.995~4.166，与程序报告 §4 一致。
- Locked 组 18/18 干净、pm-none 2/2 巨 delta 的汇总与各 `r1-disc-*/metrics.csv` +
  stderr 相符（pm-none metrics.csv 仅 1 行完整 press 记录，iter2 的巨 delta 证据在
  stderr 日志中——归档完整性小瑕疵，不影响结论）。

## 5. 无越界

- diff 仅 `src/input_contexts.rs`；无 CONTRIBUTING.md / tool_ops / measure_tool /
  entity_ops 等改动；ActiveTool/EditMode Reflect 注册未做（报告 §6.3 已声明留 T2）。
- `loop/` 不入 git：`.git/info/exclude:7` 忽略，`git ls-files loop/` 为空，
  工作树 clean。

## 6. 发现（分级）

| 级别 | 责任方 | 问题 |
|---|---|---|
| ⚪ | 程序 | 报告 §4 W 位移区间写 3.995~4.172，档案 fixed-final 实际最大 4.166（转写小误，结论无影响；QA 实测宽至 4.636） |
| ⚪ | QA 基建 | 手动驱动存在偶发 fly 未触发 flake（1/15 次，3.4 节）；manual.md §4 已记载成因，建议后续在脚本按下前加 hover 预检 |
| ⚪ | 档案 | `r1-disc-pm-none/metrics.csv` 缺 iter2 完整行（证据在 stderr 日志，可追溯） |
| ⚪ | 环境（记录） | 本机 fixture `my-game` PIE 后台预构建必失败（rustc 1.96 不受支持），所有 run（含程序档案）均有该 ERROR，与本任务无关、不阻塞 |

## 7. 结论

**PASS**。四门全过；修复面收敛、语义正确、单测扎实；QA 真机亲测 13+1 轮
press 跳变恒 0、环视精确 0.9 rad、W 位移 ≈4.0；判别档案数据与代码注释的因果链
逐项有据；无越界改动。R4 手册 + loop/qa 脚本链（brp/input/screenshot/r1-drive）
验收可用，T2/T3 可复用。
