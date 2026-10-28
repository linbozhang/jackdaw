# T02 任务 1 验收报告（QA，T-QT 工具重跑版）

> 对象：`loop/plans/t02-inspector-loop.md` 任务 T02-T1（程序 commit `dbe4d09f`，
> 基于 main `bc5274ee`；验收在 merge main `70bd7976`（QA 驱动工具）后的 `41fede05` 进行，
> merge 无冲突）。
> 验收人：QA（ZCode 子代理，GLM-5.3）。日期：2026-10-25。
> 驱动方式：新 QA 工具（`loop/qa/manual.md` §7：ui_click/ui_input/ui_tree/camera_state +
> wait idle 手势语义）——原定 SendInput 坐标法废弃。
> **VERDICT: PASS**（详细过程与 dogfood 记录见 `t-qt-t2-dogfood.md`，本文件为 T02-T1 视角结论）。

## 1. 门禁（merge 树独立重跑，全部 PASS）

| 门 | 结果 | 数字 |
|---|---|---|
| fmt / clippy（xtask fast 权威口径） | PASS | exit 0 |
| `cargo xtask fast` | PASS | 2864 passed / 2 skipped（35.1s） |
| `cargo xtask integration` | PASS | 5032 passed / 3 skipped（306.4s），T02-T1 新增 8 用例全数在列 PASS |

## 2. 代码审查（与方案 §2/§3/§4/§6 逐条比对）

- **D1 bound 实体门**：`field_edit_commit/preview` 增 `bound: Option<Entity>` +
  `stale_bound_entity` + const warn 串；三个绑定调用点（文本/数值/颜色 + val live/preview
  + 拖拽 tick）全传 `Some(entity)`；无绑定调用者全 `None` 原语义（方案 §2.3 逐条吻合，
  rg 21 调用点逐一核对）。resource/PIE 路由先于门、不受影响（方案「不做」边界守住）。
- **红→绿用例四要素**齐备（B 未写 / A 严格丢弃 / undo 不变 / 丢弃可闻 const 串）+
  stale-binding 不变量 + 多选多编锁定（方案 §2.4 三用例全落地，报告红证据断言文案吻合）。
- **D3 三 warn**：三个静默丢弃点全部一行 warn 带上下文，零行为变化。⚪ 观察：preview
  tick 失败路径无节流（仅失败路径可达，方案即一行级，不构成缺陷）。
- **D2 矩阵 4 格**：每格 ①ECS ②AST ③save+reopen 三处一致断言；灯①格含 color+illuminance+
  undo 消费；偏差①②（相机格字段、illuminance 代言数值）有 probe 实证支撑，接受。
- **D5 save-skip**：前缀一行 + 真实 type_path 单测，T01 QA ⚪ 收口完成。
- **无任务 2 越界**：无 D4（tooltip/标头）改动；Cargo.toml dev-deps 合规。

## 3. 真机抽验（新工具，my-game 1920x1080，不存盘）

- **§7-3 快速切换 5/5 PASS**：blur 提交+同帧切 B 的真实时序下，**B（切向实体）
  translation.y 五轮全部零污染**（Sun/Cube/Point Light 三实体换向，含正/负/小数值）；
  A 每轮准确落值。stale-drop warn 真机 0 次（丢弃分支由 headless 红绿+不变量+可闻三重
  覆盖；门存在本身封死「写 B」路径）。验收语句「切换实体后不得编辑旧目标」实机成立。
- **§7-2 数值抽验 PASS**：ui_input 单手势（聚焦→全选→'5'→Enter）改 PointLight intensity：
  ECS 100000.0→5.0 + authored bsn `intensity: 5.0`（存盘/重开腿由 headless 矩阵覆盖）。
- 环境保障：跑前/跑后 `my-game/assets/scene.bsn` SHA256 逐字节一致（不存盘策略成立）。

## 4. 遗留与移交

- 真机 §7-6（相机 Projection 字段真机轮）依赖面板可编辑行，随报告偏差① 移交 T02-T2/后续。
- 灯 color 真机闭环（§7-1）属 T02-T2 范围（本轮 §7-2 数值链已实证，color 链 headless 矩阵绿）。
- 工具面两条 ⚪（ui_click 越窗静默落空、ui_tree 过滤语义）见 dogfood 报告 §6，归 T-QT 后续。
