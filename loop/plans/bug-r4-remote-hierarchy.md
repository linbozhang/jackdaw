# R4 修复方案：远程实体树父子解析与协议格式失配（buglist 🔴）

> 立项：2026-11-06（Mac 2 迁移落地后首个 buglist 任务；主控按契约「逐条复现→修复→打勾」从 🔴 段顶部选题）。
> 基线：main `5406f839`（T25 收官 + 迁移指南）。工作树另有一项环境落地改动（Cargo.toml 10 行
> patch 路径 Mac1→Mac2，属迁移手册第三节步骤 1，预热构建通过后单独提交 main，不入本任务分支）。

## 票面（buglist.md:37-41，原文引用）

**R4. 远程实体树父子解析与协议格式失配，远程层级面板整体失效**
- `src/remote/entity_browser.rs:92-97`（`extract_parent` 用 `as_u64()`）。
- 生产端 `crates/jackdaw_pie_protocol/src/snapshot.rs` 序列化的 `ChildOf` 是实体文本形式
  （如 `"0v1"`）或 `[bits]` 数组，`as_u64()` 均返回 `None`；协议 crate 专门提供了
  `entity_bits()`（`src/pie_projection.rs:79` 用的就是它），此处没用。
- 后果：`jackdaw/scene_snapshot` 拉回的所有实体被判为根、`has_children` 恒 false、
  懒展开永不填充，远程层级树退化为平铺列表。
- 修复方向：改用 `jackdaw_pie_protocol::snapshot::entity_bits(&value)`。

## 策划期核实（2026-11-06 主控亲读，逐条代码级）

1. **票面成立**：`extract_parent`（entity_browser.rs:92-97）仍为
   `.and_then(serde_json::Value::as_u64)`，当前 main 未被后续 T 系列顺带修复。
2. **entity_bits 可用且形态全覆盖**：协议 crate `pub mod snapshot`（lib.rs:5），
   `pub fn entity_bits`（snapshot.rs:31-39）支持 Number(u64)/String(实体文本
   `parse::<Entity>`)/Array(首字段)/Object(首值) 四形态；自身单测
   `an_entity_is_read_from_its_text_or_its_bits` 锁定三形态 + 负例。
3. **消费面=单函数 4 个调用点**：`:322`（根过滤）、`:393`/`:415`（children_of 构建）、
   `:423`（根判定）全部经由 `extract_parent`——单点替换即全修，无需触 UI 层。
4. **同型误用全仓扫描=仅此一处**：`grep 'hierarchy::ChildOf' -A2 | grep as_u64` 全仓唯一命中
   即本票；`src/remote/debug/relationships.rs:63` 已用 `entity_bits` 解析同款值（正确先例）。
5. **调用约定**：编辑器侧既有 3 处全限定调用先例（pie_projection.rs:79、
   remote/debug/queries.rs:138、relationships.rs:63）——本修复沿用全限定风格，不新增 use 行。
6. **依赖已就位**：编辑器 crate Cargo.toml:139 已依赖 `jackdaw_pie_protocol`；
   `RemoteEntity` 来自 `jackdaw_remote::scene_snapshot`（协议 crate re-export），
   修复不改变任何类型签名。

## 修复方案

`src/remote/entity_browser.rs` `extract_parent` 单行替换：

```rust
fn extract_parent(entity: &RemoteEntity) -> Option<u64> {
    entity
        .components
        .get("bevy_ecs::hierarchy::ChildOf")
        .and_then(jackdaw_pie_protocol::snapshot::entity_bits)
}
```

范围红线：只动 `src/remote/entity_browser.rs`（含新增测试模块）；不碰协议 crate、
不碰 producer 面（`scene_snapshot` 序列化）、不碰 UI 树组件。

## 测试方案（红→绿）

`entity_browser.rs` 当前无测试锚，新增 `#[cfg(test)] mod tests`（文件底部）：

- **红证（文本形态）**：`ChildOf = serde_json::to_value(Entity::from_raw_u32(5).unwrap())`
  （与协议测试同款构造，产物为实体文本形式）→ `extract_parent` 应返回 `Some(bits)`；
  修前行为 `None`（= bug 复现，先于修复归档）。
- **数组形态**：`json!([text])` → `Some(bits)`；修前 `None`。
- **数值形态（回归锚，修前即绿）**：`json!(bits)` → `Some(bits)`，保证修复不丢旧能力。
- **负例**：`json!("not an entity")` → `None`（不把垃圾值误判成父实体）。
- 组合断言：`has_children` 判定链用最小 HashMap 手工组装 RemoteEntity（child 指向 parent）
  验证 `extract_parent(child) == Some(parent.entity)`——直锁票面「恒 false」症状。

## QA 验收要求

1. **门禁**（日志全文复核制，exit code 仅辅助）：
   - `cargo fmt --all -- --check`
   - `cargo clippy --workspace -- -D warnings`
   - `cargo test --workspace --lib`（基线 3091，本任务 +新增测试数）
   - 任务相关：无其他 crate 改动，protocol crate 测试不强制；`cargo test -p jackdaw entity_browser` 定向为程序自检项。
2. **红绿三方一致**：程序红证归档（修前 None 截图/日志）→ 修复 → 绿；QA 独立复跑红绿
   （checkout 修前 commit 复红一次，或采信程序归档+源码级亲读判定，QA 自选并如实记档）。
3. **真机腿（MCP 优先原则，交互/面板类任务必做）**：
   - boot 编辑器（fixture 工程）→ boot 游戏（或 PIE，需含父子层级实体的场景）→
     remote 连接建立 → 打开远程层级面板；
   - 断言：树出现非平铺结构（子行挂在父行下 / `has_children` 行可展开且展开后填充子行）；
     用 `ui_tree` / BRP 结构化工具（loop/qa/manual.md §7），坐标注入仅作兜底；
   - 与修前对照：平铺列表（可选，独立复红成本高时以单测红证为准，如实记档）。
   - 真机腿若受本机环境阻塞：报主控裁定，不得静默降级。
4. **报告落盘**：`loop/reports/bug-r4-report.md`、`loop/reports/bug-r4-qa.md`；
   真机证据归档 `loop/` 下任务目录。

## 决策点（主控已裁）

- D1 修复形态=全限定单行（沿用 relationships.rs:63 先例），不引入 use 行、不做 trait/包装。
- D2 测试放 `entity_browser.rs` 文件内 `#[cfg(test)]`（该文件首个测试锚），不另建 tests/ 文件。
- D3 不顺带修其它 buglist 票（范围纪律）；真机腿若顺带发现新缺陷 → 按惯例立票（A 系）不并修。
- D4 Cargo.toml 路径对齐属迁移落地，独立提交 main（先于本任务分支），commit message 说明来源。

## 任务拆分

- T1 程序：红证归档 → 单行修复 + 测试模块 → 门禁自检 → 报告。
- T2 QA：门禁亲跑 + 红绿复核 + 真机腿 → PASS 后主控合入（`--no-ff`）→ buglist `[x]`
  （附修复说明与提交号，格式参照 R9/R10 已勾条目）→ 台账记一行。

修复循环上限 5 轮（契约）；单轮不过门禁即返工，超限升级用户裁决。
