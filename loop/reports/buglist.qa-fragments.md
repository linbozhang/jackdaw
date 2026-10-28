# buglist.md QA 持有片段（数据恢复 sidecar，非重建全文）

> QA 角色产出，2026-10-24 紧急数据恢复任务。
> **来源与可信度声明**：QA 历轮验收从未完整 Read 过健康版 buglist.md 全文——历轮均为
> Select-String 模式匹配读取，仅持有下列命中片段（**逐字摘自 QA 当时会话的工具输出，可信**）。
> 本文件不是重建全文，是供拼回的精确片段集 + N11/N12 重建底稿（底稿来源已逐段标注）。

## 一、QA 逐字持有的条目片段（可信，直接拼回）

### Y34（T06-T2 验收时读取，仅首行）
```
- [x] **Y34. 发送 `ControlEvent::Stop` 后立即 `kill()`，"优雅停止"契约实际不成立**
```

### W17（T06-T2 验收时读取，首行+备注整段）
```
- [x] **W17. `Val`/`UiRect` 编辑路径不含 PIE Live 预览 tick 的资源守卫**
  （2026-10-26 T06-T2 修复：`val_field.rs::commit_val_to_field` 补资源分流（tick→`resource_field_preview`、commit→`resource_field_commit`，照 `apply_field_value_live` 形状）；实测旧路径的真实缺陷是资源 Val 字段 tick 连资源自身都不写（stale 守卫挡住了跨目标写盘分支）——红 0/2 panic、绿 2/2。提交同 Y34。）
```

### W26（T06-T2 验收时读取，首行+备注整段）
```
- [x] **W26. Job Object 三处 `assert!` 会把"启动失败"变成"编辑器崩溃"**
  （2026-10-26 T06-T2 修复：`PIE_JOB` 改 `LazyLock<Option<Job>>`（init 两处失败 warn+None），`assign_to_process` 失败 warn 继续；正常路径真机回归：kill 编辑器 → my-game.exe 随之死（job object 生效）。降级分支无法真机模拟受限环境，以代码结构（assert 全消）+ 审查覆盖，如实记档。提交同 Y34。）
```

### W9（T07-T1 验收时读取；备注行尾部当时显示截断于 "catalo"，以损坏文件内英文层比对补全）
```
- [x] **W9. JSN→BSN 转换是唯一不走 `write_atomic` 的场景写盘路径**
  `src/jsn_to_bsn.rs:300-301`：裸 `fs::write`，中途崩溃留截断 .bsn；写入内容不带版本 stamp。
  修复方向：改 `write_atomic` 并补 `stamp::with_stamp`。
  > 已修复 160893e6（T04-T1）：commit_conversion 与 convert_catalog_file 改 write_atomic；场景 .bsn 落盘补 with_stamp（catalo[QA 所见截断于此]…
```

### N10（T06-T3 验收时读取的完整条目——注意当时未勾选；N10 验收通过后程序应已改 [x] 并整理备注，该版本 QA 未见）
```
- [ ] **N10. dirty 场景 + Save 态 play_current 真机冻结编辑器主线程（2026-10-26 T06-T3 矩阵 cell 3 发现）**
  触发：打开已保存场景 → 任意编辑（脏）→ `pie.play_current`（save 策略，默认态）→ play_current 调用正常返回，**下一帧起主线程满 CPU 自旋**（实测 CPU/4s≈5s），BRP 全部无响应，日志停在 `OPERATOR: pie.play_current` 后零输出（保存链最早期）。
  实证（`loop/t06t3_probe_freeze*.log`）：① main 基线（66ef15e8，无 T3 改动）同样冻结=**既有 bug**（T1 的 Save 态 dirty play 真机路径从未跑过，headless guards 全绿）；② clean 场景 play、untitled/dirty + Copy 态 play、Ask→Copy 均不冻；③ connected 后 stop 不冻，但 connecting 窗口内 stop 也触发同款冻结（T3 曾放宽 avail 门后实测 100% 复现，已回退该放宽，connecting-stop 恢复 avail 拒绝+重试语义封路）；④ 保存链单独走（scene.save op）不冻——冻结需要「保存链 + PIE 启动」同帧组合。
  影响面：T1 交付的默认策略（save）在真机上不可用于脏场景 play（用户主路径！）。绕行：先 Ctrl+S 再 Play，或切 play_unsaved_copy。
  修复方向：冻结在 `launch_current_scene → resolve_override_for_launch → save_scenes_before_launch` 之后的同帧 PIE 启动段；重点排查保存后同帧 `spawn_instance`/asset watcher 重扫/编辑器 UI 重建的交互循环。优先级高（默认策略主路径）。
```
N10 修复备注（QA 于 N10 验收前所见版本，当时重复粘贴两遍；N10 验收时 QA 建议清理重复+指引写哈希 6cfb1358——处置后版本 QA 未见）：
```
  （2026-10-26 N10 修复任务备注，待验收：触发面 13 轮真机穷举（QA 4 + 程序 9，含高负载/真门禁负载/connecting-stop/stop 锤变奏）**不可稳定复现**，按降级路径执行静态根因+加固修复：主嫌疑=主线程 `drain_received` 无界 try_recv 循环（积压下消费≤生产则永不 Empty→满 CPU 自旋，三条触发路径的保存链/投影重建/OnEnter 重链都是积压引信；程序 3s 判死窗 vs QA 9s 判活窗解「100% vs 零复现」矛盾）。修法：drain 加 256 帧/4ms 双预算（跨帧消化积压，主线程单帧有界），trait 契约改 bounded batch；守卫测试（洪泛有界+不丢）+ dirty+Save 一步回归 3/3 + 三边界（B2 隔离复测 2/2，首轮 stopped=False 系 QA 脚本 stop 无重试时序）+ stop 锤 3 循环全过。记档：ipc try_recv 部分消息转 INFINITE 阻塞（crate 内部语义，不可加超时，风险低）；connecting-stop 的 accept task detach 泄漏（bevy Task 语义+同步 accept 不可取消，待 ipc 侧可中断 API）。修复 <loop/n10-play-freeze 提交，见 loop/reports/n10-fix-report.md。）
```

### R10（T07-T1 验收时读取；正文行当时截断于 "game_export.r"，尾部以损坏文件英文层比对）
```
- [x] **R10. 导出 staging 硬编码 `assets` 目录，忽略 `jackdaw.toml` 的 `assets_dir` 配置**
    `crates/jackdaw_project_build/src/export.rs:60`（`assets_source: root.join("assets")`），调用方 `src/game_export.r[QA 所见截断]…
    问题：项目可配 `assets_dir = "content"`（`src/project.rs:56-61` `configured_assets_dir`，编辑器资产服务器/索引读的就是配置目录），导出却写死 `…
    后果：自定义目录的项目导出永远报 "no assets directory"；若残留旧 `assets/` 则把非索引目录的旧内容打进发布包且无报错。
  > 已修复 ef353c57（T07-T1）：`plan_export` 内部读 `ProjectManifest::read(root).assets_dir()` 作为 `assets_source`，staged 目录名同步（`ExportPlan::assets_staged_subdir`），签名不变、两调用方零改动（guards: an_assets_dir_override_is_staged_under_its_own_name）。
```

### Y7（T07-T1 验收时读取）
```
- [x] **Y7. 导出 staging 守卫在 Windows 上可被大小写变体绕过**
    `crates/jackdaw_project_build/src/export.rs:246-251`（`Path::starts_with` 逐组件字节比较，大小写敏感；NTFS 大小写不敏感）。
    后果：`jd export --out c:\game\assets`（项目实际 `C:\Game`）守卫放行，`dist.exists()` 命中真实目录后 `remove_dir_all` 删掉真正的 asset[QA 所见截断]…
    修复方向：Windows 上按组件做不区分大小写比较，或两侧 canonicalize 后再比。
  > 已修复 ef353c57（T07-T1）：新增 `path_contains`（Windows 按组件 `eq_ignore_ascii_case`，非 Windows 保持字节比较），`staging_hazard` 两处判定换用；红证确认修复前大小写变体放行且删真 assets（guards: a_case_variant_of_the_output_directory_cannot_bypass_the_guard，红 4 例之一）。
```

## 二、N11/N12 重建底稿（⚠ 来源=t06-t3-report.md §一 程序报告描述，非 buglist 原文直读；措辞/格式可能与原文有出入，拼回后请用户/T2 实施者校订）

```
- [ ] **N11. Inspector 数值字段的合成输入提交路径不可达（QA 工具缺口）**（2026-10-26 T06-T3 发现）
  触发：ui_drag（scrub 手势不吃合成拖拽）与 ui_input（数值行不提交键入）都到不了字段 commit 路径——QA 无法驱动「Inspector 改 → pending live edit → stop prompt 按钮（Discard/Apply All）」的按钮链。
  处置：补 `field.set` 类 BRP 或修合成输入后收口 T06 矩阵 #7 的按钮半场；语义由 headless live_edits.rs 18 例覆盖（apply_all 恰一条 undo / discard_all 不碰 AST / post-stop apply 走 node_id）。
- [ ] **N12. bevy 原生 BRP 与 jackdaw 方法的实体 id 域互不相通**（2026-10-26 T06-T2 发现、T06-T3 再次撞上）
  形态：world.query/get_components 用 `{index}v{generation}` 字符串且其 world 视图不含 scene_tree 报告的实体；jackdaw/* 用 raw bits u64。跨方法换用需重建映射。
  处置：真机读组件值改走 `jackdaw/entity`（节点 BSN 文本）绕行；统一断言通道记档（T3 工具设计动机之一）。
```

## 三、QA 另持有的一句话级引用（源：loop/plans/t06-play-isolation.md §一 buglist 重叠表，可信但仅一句话）

- Y34：发 Stop 后立即 kill，"优雅停止"契约不成立
- W26：Job Object 三处 assert! 启动失败变编辑器崩溃
- W17：Val/UiRect 编辑路径不含 PIE Live 预览 tick 的资源守卫
- Y37：PIE 每帧对全场实体全量反射 JSON 序列化（性能专项，T06 不吸收）
- Y33：游戏 BRP CORS `*` 任意网页可读写运行中游戏（游戏侧远程安全域）
- Y35：BRP 响应 Content-Length 无上限可 OOM（编辑器 BRP 客户端域）
- R4：远程实体树父子解析与协议失配，层级面板失效（归 T24）
- Y36/W27：键位域（旧链路序列化）
- A1：brush.join 后 recenter 位移不入撤销（已另立项 T03 遗留）

## 四、损坏文件清点（2026-10-24 QA 实测，与任务书预期的差集）

- 在位 53 条：R1-R14（含 Agent 节额外条目 R11-R14）、Y1-Y37、A1、N10；勾 13（R1 R2 R9 R10 Y1 Y2 Y4 Y7 Y8 Y9 Y31 Y34 N10）
- **W1-W28 整组 28 条缺失**（含 7 个勾：期望用户条 19 勾 − 在位 12 勾；已知 W9/W17/W26 三勾，另 4 个勾的条目编号 QA 无法确定）
- **N11/N12 两条缺失**（任务书已知）
- `buglist.recovered.md` 实际不存在（T2 注记称"可删"，恐已删——恢复源又少一个）
- W 组抢救源盘点：loop 文档仅 14 个编号有一句话级引用（W1/W2/W7/W8/W9/W10/W11/W12/W13/W17/W23/W26/W27/W28）；**W3/W4/W5/W6/W14/W15/W16/W18/W19/W20/W21/W22/W24/W25 共 14 条零引用零来源**
- R9 备注按任务书补：`> 已修复 9a80bcbc（T07-T2）`（内容按 T2 报告：自愈根因 bevy eb19a9ea0 + 显式 ScrollPosition + 真机验证）——QA 未读过 T2 报告全文，此行为任务书口径转写
