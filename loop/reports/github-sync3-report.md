# GitHub 第三轮同步报告（#802-#818，17 提交）

> 手动触发（定时任务 automation-eb25f968 建立后的立即执行轮）。基线 a83b8dc5 → 合并
> `8cc96c75` → 编译修复 `85705ba3` → 门禁重校准 `6685a995` → 本次收官 commit。
> 裁定原则：上游为主线；场景兼容不约束；不推任何远端。

## 一、增量与 T25 域处置

- 上游 17 提交：#802 **移除 Scene/Live 双模型**、#803 Play 工具栏简化、#804 按需索要运行
  游戏实体、#805 运行时实体与活值流式、#806 Stop 时可选回滚 Play 编辑、#807-#808 Game
  面板状态、#811 地形未存盘编辑在文件变更时保留、#812 地形告警静默+remote 端口隔离、
  #813/#815 prefab 实例存盘语义、#814 Game 面板视图菜单+实例 picker+弹出、#816 jd clean、
  #817 场景 spawn 通知、#818 Game Output 窗口。
- **T25 域处置（按主控裁定执行）**：上游新 Play 模型整体采纳；本地 live 路由/live_edits
  追踪账/StopPrompt/Live Changes 托盘/pie_mirror 随被移除的模型**取代记档**（T25 闭环的
  历史事实不变，能力由上游 #804/#805/#776 通道承继）；`promote_ephemeral_to_authored`
  （Path B Save-to-Scene）为 Inspector 级特性**保留**（LT10 avian 过滤随行）；T25 时代
  guards（play_scene.rs 等）按新模型重锚；book play-in-editor.md 取代注记随合并入库。
- 本地正确性修复全部共存：R1/Y31/Y9/census/physics/R6/settle 双臂/temp_copies/launches。

## 二、门禁终值（亲跑归档 loop/github-sync/sync3-*）

| 门 | 结果 |
|---|---|
| fmt / clippy -D warnings | 双 0 干净 |
| libtests | EXIT=0，**3825 · 70 二进制 · 0 失败**（3876 − 51：live_edits/stop_restore 旧语义测试随取代删除） |
| guards 模块 | **398/398**（383 基线 + T25 重锚净变化 + 上游新增） |
| inspector / operators / prefabs | 235 / 415 / 129 全绿 |
| stage | 628/632：gltf_authoring×3=**A28 并行间歇（单跑 14/14 绿实证）**；`play_revert::a_tab_modified_for_another_reason…`=**A31 新立票（真融合缺陷，见下）** |
| scenes | 318/319：唯一红=A30（维持待裁） |
| viewport | 182/183：唯一红=quality menu（预存基线红） |

## 三、A31（新立票，本轮唯一新增红）

`play_revert` 边界：revert 正确置 dirty=true（插桩实证 was_dirty/holds_mark/reached 全真），
但本地 doc-hash 指纹臂随后帧以「内容==存盘」覆盖回 false——上游旗标语义 vs 本地内容语义
正面冲突。天真修法会打翻 dirty_matrix 十四条锚定裁决 → **立票 A31 交 dirty 语义设计轮**
（与 A30 的「内容 vs 旗标」分歧面一并统一）。插桩已撤，测试如实留红。

## 四、遗留

1. A30（跨页粘贴细胞丢失，T16 域）——维持待裁。
2. **A31（新）**：revert 边界 dirty 保留语义设计轮。
3. A28 族（stage footer/gltf 并行间歇）——维持已知预存。
4. viewport quality menu 预存基线红——维持记档。
5. 上游继续前进中（05cc43c6 之后或有新提交），例行由定时任务 automation-eb25f968（每日
   07:00）按既定政策同步。

## 五、弧线账

| 步骤 | 谁 | 结果 |
|---|---|---|
| fetch/评估/试合并 | 主控 | 32 文件 82 hunk 定型，T25 域政策预置 |
| 82 hunk 解决+合并提交+编译修复 | 程序 agent（静默死亡但全程交付） | `8cc96c75`+`85705ba3` |
| 门禁重校准（部分） | 同 agent（死于收官中途） | `6685a995`+6 文件未提交改动 |
| 遗留改动核验+全量门禁+A31 立票+报告台账 | 主控亲自 | 本次 commit |
