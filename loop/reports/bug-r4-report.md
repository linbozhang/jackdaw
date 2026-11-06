# R4 程序报告：远程实体树父子解析与协议格式失配（buglist 🔴）

> 任务：T1 程序腿（红证 → 单行修复 + 测试模块 → 门禁自检）。
> 分支：`loop/bug-r4-remote-hierarchy`（自 main `9c80f5a8` 拉）。方案书：`loop/plans/bug-r4-remote-hierarchy.md`。
> 结论：**未合入 main，待 QA**（T2：门禁亲跑 + 红绿复核 + 真机腿）。

## 票面与根因（引方案书）

`src/remote/entity_browser.rs` 的 `extract_parent` 用 `serde_json::Value::as_u64` 解析
`ChildOf`，而生产端 `crates/jackdaw_pie_protocol/src/snapshot.rs` 序列化的 `ChildOf` 是
实体文本形式（`"5v0"`）或 `[bits]` 数组，`as_u64()` 均返回 `None`。后果：`jackdaw/scene_snapshot`
拉回的所有实体被判为根、`has_children` 恒 false、懒展开永不填充，远程层级树退化为平铺列表。
协议 crate 已提供 `entity_bits()` 覆盖全部四形态（`src/remote/debug/relationships.rs:63` 是正确先例）。

## diff 面清单

仅 1 个文件，`git diff --stat`：`src/remote/entity_browser.rs | 59 insertions(+), 1 deletion(-)`。

1. **修复（1 行替换，`extract_parent`，entity_browser.rs:96）**：
   - 修前：`.and_then(serde_json::Value::as_u64)`
   - 修后：`.and_then(jackdaw_pie_protocol::snapshot::entity_bits)`
   - 形态=方案书 D1：全限定单行，沿用 `relationships.rs:63` 先例，不新增 use 行。
   - 该函数 4 个调用点（:322 根过滤、:393/:415 children_of 构建、:423 根判定）全部经由
     此单点，无需触 UI 层；类型签名未变。
2. **新增测试模块（文件底部 `#[cfg(test)] mod tests`，58 行）**：该文件首个测试锚（D2）。

未触碰：协议 crate、scene_snapshot producer、UI 树组件、`buglist.md`、`loop/plans/roadmap-game-dev.md`、`loop/progress.md`。符合范围红线。

## 新增测试清单（4 条，构造参照协议 crate 同款先例 `an_entity_is_read_from_its_text_or_its_bits`）

| 测试 | 构造 | 断言 | 修前 | 修后 |
|---|---|---|---|---|
| `extract_parent_reads_the_text_form_bevy_writes_for_child_of` | `ChildOf = serde_json::to_value(Entity::from_raw_u32(5).unwrap())`（实体文本形式；兼作票面组合断言：child 指向 parent，直锁根判定/has_children 链） | `Some(parent.to_bits())` | ❌ 红（`None`） | ✅ |
| `extract_parent_reads_the_array_form_of_a_tuple_component` | `json!([text])`（tuple struct 数组形式） | `Some(bits)` | ❌ 红（`None`） | ✅ |
| `extract_parent_still_reads_bare_bits` | `json!(bits)`（数值形式，回归锚） | `Some(bits)` | ✅ 绿 | ✅ |
| `extract_parent_rejects_a_garbage_value` | `json!("not an entity")`（负例） | `None` | ✅ 绿 | ✅ |

辅助构造：`remote_entity_with` 组装最小 `RemoteEntity`（仅 `ChildOf` 一个组件，`scene_node_id: None`）。

## 红证（先于修复归档）

`cargo test -p jackdaw entity_browser`（修前，完整日志归档 `loop/bug-r4/red.log`，PIPE_EXIT=101）：

```
test remote::entity_browser::tests::extract_parent_reads_the_text_form_bevy_writes_for_child_of ... FAILED
test remote::entity_browser::tests::extract_parent_reads_the_array_form_of_a_tuple_component ... FAILED
---- ... stdout ----
assertion `left == right` failed
  left: None
 right: Some(4294967290)
test result: FAILED. 2 passed; 2 failed; ...
```

即：文本/数组两形态返回 `None`（bug 复现，正是票面症状），数值形态与负例维持绿（回归锚有效）。
红证 4 条测试与修后同源码同构造，QA 可 checkout 修前 commit 复红独立验证。

## 绿证（修复后）

`cargo test -p jackdaw entity_browser`（修后，完整日志归档 `loop/bug-r4/green.log`，PIPE_EXIT=0）：
`test result: ok. 4 passed; 0 failed; ...`（jackdaw lib 二进制 1277 测试 = 1273 基线 + 4）。

## 门禁三连自检（日志全文复核制，exit code 仅辅助）

| 门 | 命令 | exit | 关键日志行 | 日志全文复核 | 归档 |
|---|---|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | （无 Diff 输出） | ✅ 首轮抓到新增测试 2 处长行 Diff，`cargo fmt --all` 修正后重跑覆盖归档，末轮无 Diff | `loop/bug-r4/fmt.log` |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | `Finished dev profile ... in 2m 24s` | ✅ 逐行审：无真实 error/warning 行（grep 命中均为 crate 名含 "error" 子串：quick-error / proc-macro-error / thiserror） | `loop/bug-r4/clippy.log` |
| 单测 | `cargo test --workspace --lib` | 0 | `test result: ok. 3095 passed; 0 failed`（合计） | ✅ 59 个测试二进制（=基线 59），3095 passed / 0 failed（=基线 3091 + 新增 4），无 FAILED/panicked/error 行，全部 `0 failed` | `loop/bug-r4/libtests.log` |

单测数字核对：3091（基线）+ 4（本任务新增）= **3095**，精确吻合。

## 偏差记录（如实）

1. **fmt 门一轮返工**：首轮 `--check` 抓到新增测试模块 2 处长行超宽（.Diff），rustfmt 修正后
   重跑覆盖归档通过。属新增代码排版，非方案/修复形态偏差。
2. 其余无偏差：修复形态严格按方案书 D1；测试锚按 D2 放文件内；组合断言（方案书测试方案第 5 条）
   并入文本形态测试（同一测试内 child→parent 组装断言 `extract_parent(child) == Some(parent.entity)`），
   未单列第 5 个测试。
3. 任务相关门（方案书 QA 验收 1）：协议 crate 测试不强制（未触碰），定向测试已跑归档。

## 交付物索引

- 分支：`loop/bug-r4-remote-hierarchy`（不含 main 合并；commit 见分支最新提交）
- 代码：`src/remote/entity_browser.rs`（1 行修复 + 58 行测试模块）
- 证据：`loop/bug-r4/{red,green,fmt,clippy,libtests}.log`
- 本报告：`loop/reports/bug-r4-report.md`

**状态：未合入 main，待 QA（T2）亲跑门禁 + 红绿复核 + 真机腿。**
