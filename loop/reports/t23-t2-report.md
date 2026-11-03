# T23 任务 2 报告：真机五链矩阵轮（换装→存→重开→导出→重导入×属性）

> 分支 `loop/t23-material`（fast-forward 至 main a058ce58，含 T1 全部建设）；方案
> `loop/plans/t23-material-override.md` §任务拆解 T2 + 矩阵 §二 + 真机腿 §三；T1 基线
> `t23-t1-report.md`/`t23-t1-qa.md`。真机流程脚本 `loop/qa/t23-live.sh`（七相：
> prep/chains/export/broken/rename/reimport/gamebroken；t18 四相形态扩展+A6 五纪律+A9
> 自守+`$PHASE` 日志名），门禁 `loop/qa/t23t2-gates.sh`。运行证据目录
> `loop/t23-live/`（console-*/editor-*/warn-scan-*/shot-*），归档摘要见 §七。
> **真机主链 25/25 腿全 PASS；两铁证①②全部成立；真机新发现 MO8/MO9 两缺陷（只记
> 不修，红证已归档）；M12 零意外 warn。** 门禁见 §六。

## 一、执行摘要

fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t23-materials/t23-materials`（jd new
+jackdaw_remote 注入 t13t3/t15 先例）；GLB fixture=python3 手拼三版轮换
（props.glb/kit.glb：材料 `Rock`/`Trim`+一无名材料；节点 RockA/RockB/TrimC/PlainD；`box`
变体追加 BoxE（穿 Trim→水穿面），`stone` 变体把 `Rock`→`Stone`）；材质三件
`materials/{mossy,wet,deep}.bsn`（Standard 绿/Layered/Water，前两由编辑器 asset.new
写盘=类型头即注册真值，mossy 由 material.create+save+asset.set 绿）。全部断言通道：
R（编辑器 BRP 15703 只读）/G（staged 游戏 BRP 15702，jackdaw_remote 注入）/PX
（jackdaw/screenshot+pixdiff，t19 口径）/盘（场景文档+导出包 SHA/grep）。

**探针期定谳的 BRP 口径**（影响全脚本，已沉淀脚本头注释）：glTF 材质名组件的注册路径
是 `bevy_gltf::assets::GltfMaterialName`（非 bevy::gltf 前缀），它挂在 loader 产出的
**mesh 实体**上（名 `Mesh.Rock`/`Mesh.Trim`；节点实体 RockA 等只带节点 Name）；
BRP 实体参数只收**名字或 `{index}v{generation}` 字符串**（整数 bits 一律
`NoSuchId`）；`MaterialOverrides`/`InstanceMaterialOverrides` 与 Layered/Water 穿组件
可查询；**`ModelMaterial` 未注册 Reflect（BRP 不可见）、
`MeshMaterial3d<StandardMaterial>` 的值反序列化失败（在场可查、柄值不可读）**——
故 Standard 面的穿戴判据=覆盖 map+PX 像素+warn 静默，Layered/Water 面给组件换装
铁证（glTF 模型永不自带这两类组件），全部 give-back 脚都踩在 Layered/Water 持有者上。

## 二、铁证①：五链主干×属性 —— 全部成立（25 腿逐格）

### 铁证① 主干格 M1（L1：place→operator 换装→PX→Save→重开→export→staged G 断柄）

| 格 | 腿 | 结果 | 证据 |
|---|---|---|---|
| M1 放置 | L1_PLACE_PARTS | ✅ | 两模型 6 个带名 mesh 实体+props 根带 `GltfSource` |
| M1 换装写层 | L1_DRESS | ✅ | map=`{"Rock":"materials/mossy.bsn"}`；换装后 warn 零（健康不假报）；PX 像素 diff **2.469%**（>1 判变装） |
| M1 落盘 | L1_DOC_ON_DISK | ✅ | 盘上 t23.bsn 含 `MaterialOverrides`×2+mossy/deep/wet 三路径 |
| M1 重开 | L1_REOPEN | ✅ | 双 map 原样；layered=2/water=1（仍穿装）；PX **0.067%**（<1，视觉不变） |
| M1 导出 | L1_EXPORT | ✅ | staged 树=当前场景 SHA 相等；staged 文档含 patch+三材质文件在树；manifest 列表 |
| M1 staged 穿装 | L1_STAGED_DRESS | ✅ | G：holders=2 且 map 精确回读；layered=2 全在 `Mesh.Rock`（kit）、water=1 在 `Mesh.Trim`（props）——「staged 游戏确实穿对」的真机证据（方案 §0 事实六缺口闭合） |

### 铁证①×属性格（M2/M3/M4/M7）

| 格 | 腿 | 结果 | 证据 |
|---|---|---|---|
| M2 四穿面 | L2_WEAR_FACES | ✅ | props Rock：Standard→**Layered**（layered=2 且 std 面清空）→**Water**（water=2）→回 Standard（water=0）；Trim→Water（water=1）；kit Rock→Layered（layered=2）——组件换装（swap 不是柄写）活证+四穿面柄一致由 export/gamebroken 两态对照（§M10） |
| M3 同名多部件 | L2（含） | ✅ | `name=Rock` 一键换装 props 的 **两块** Rock mesh（layered=2/water=2 成对出现）；kit 列不动 |
| M3 无名材质（MO4） | MO4_REFUSAL | ✅ | 选无名部件+name 空→`cancelled`+警告「that part wears an unnamed material, which no override can address; name= one of the materials the model does name: Rock, Trim」（归档 `t23t2_mo4_refusal_response.json`）；T1 裁定 4-B 的真机形态=断言拒绝（扩大化红证已在 T1 red.log） |
| M4 预制体携带 | M4_PREFAB_INSTANCE | ✅ | pack：`prefabs/props.bsn` 盘上含 `MaterialOverrides`+mossy+deep；packed 实例的 TrimC 经模型层穿 Water（water=1）；实例层赢：TrimC 部件覆盖→实例根 `InstanceMaterialOverrides {"Trim":"materials/wet.bsn"}` 且 layered=1/water=0（实例压模型层）；双胞胎实例：layered=1/water=1（跟随预制体模型层、不吃第一实例的实例层） |
| M7 重导入保留 | M7_REIMPORT | ✅ | props.glb 追加 BoxE→引擎同柄重实例化（`Reloaded models/props.glb`）→named 4+3=7、**BoxE 经幸存覆盖穿上 Water 面**（water=2）、覆盖 map 原样、缩略图重渲染（M13 面）——「改 GLB 不丢覆盖+新部件按名穿装」正主刻画（方案 §0 事实七真机化） |

### 铁证① 横切格（M10/M11/M13）

| 格 | 腿 | 结果 | 证据 |
|---|---|---|---|
| M11 undo | M11_UNDO | ✅ | kit Trim→mossy→undo→map 回单键（组件摘除）→**全程零 warn**（undo 不假报）→redo 复原 |
| M13 缩略图 | M7（含） | ✅ | GLB 重写后 `assets/models` 新 FNV-mtime 缩略图 PNG（t18 AR1 手法） |
| M13 破文件反馈 | M13_BROKEN_FILE | ✅ | deep.bsn 破字节→索引拒绝 warn「materials/deep.bsn no longer holds a type this project knows」×1+覆盖 unresolved warn×1+TrimC 水**面摘除**（give-back 可读）→恢复字节→水面回 1（再穿） |

### 铁证②：结构变化明确报告，不静默丢 —— 红绿成立（M5/M6/M8/M9）

修前红证=T1 归档 `t23t1_red.log`（headless 三红：audit 零 findings/rewrite 不跟随/扩大化活体）；本轮回在真机上判**修后绿**，逐格：

| 格 | 腿 | 结果 | 证据（MO1 双嘴+MO2 审计活体） |
|---|---|---|---|
| M5 失效路径·外部删 | M5_MISSING | ✅ | rm wet.bsn→**恰 1 条** `material override: kit overrides 'Rock' with 'materials/wet.bsn', which names no material the project holds…`（日志嘴）+**状态栏嘴同文**（ui_tree 走查见「material override」字样）+audit 精确四元组 `{component: MaterialOverrides, document: t23.bsn, entity: kit, field: materials, kind: Missing, reference: materials/wet.bsn}`（归档 `t23t2_m5_audit_finding.json`）+kit 的 Layered 面 2→**0**（give-back 可读）+deep 面不动 |
| M5 一次锁 | M5（含） | ✅ | 再等 4s 仍 1 条（重判不重报） |
| M5 恢复自愈 | M5_HEAL | ✅ | 文件回归→Layered 0→**2**（自动重穿，事实四引用表变更触发）+**零新 warn**（锁自清） |
| M5 再失效再报 | M5_SPEAKS_AGAIN | ✅ | 再 rm→新 warn +1（锁清后再说）+Layered 2→0 |
| M6 编辑器改名 | M6_RENAME | ✅ | `file.rename deep.bsn→deep2.bsn`→盘上文档 1 处 `materials/deep2.bsn`（MO3 rewrite 真机）→audit 零→重开 props map `{Rock: mossy, Trim: deep2}`+TrimC 水**面回 1**（穿新路径） |
| M6 活世界刻画 | M6_LIVE_FACE_CHARACTERIZED | ✅ | rename 后**未重开窗口内**：活组件仍拼旧路径 deep.bsn、水面 0（give-back）、+1 unresolved warn——文档层重写不随动活世界（A11 族粘性），重开后文档赢。归档 `t23t2_rename_sticky.log` |
| M8 失效键报告 | M8_STALE_WARN | ✅ | props.glb `Rock`→`Stone`→**恰 1 条** `props overrides a material named 'Rock', which no part of it wears any more…`（stale 键优先口径）；kit 不动（其 glb 未改，Rock 仍匹配） |
| M8 一次锁 | M8（含） | ✅ | 同内容再写→仍 1 条 |
| M8 恢复清锁 | M8_RECOVER | ✅ | 名字回归→水**面回 2**（BoxE+TrimC 再穿）+零新 warn |
| M8 再失效再报 | M8_SPEAKS_AGAIN | ✅ | 再改 Stone→+1 warn |
| M9 审计→修复环 | M9_REBIND | ✅* | audit 归零+重开穿新路径成立（kit map=`{"Rock":"materials/wet2.bsn"}`+layered=2+audit total=0）——*修复写入走「文档外改+重开」通路，见 §四 D2（rebind 算子对 Map 引用失效=MO9） |

**「不静默丢」总格**：M5/M8 的每一个失效（键与路径）都在日志+状态栏双嘴各说一次、进
audit 四元组、且恢复自动重穿——「数据不丢+可发现性补齐」的验收句后半句真机闭环。
**游戏侧边界 M10**：M10_GAME_MISSING ✅——staged 包删 mossy+deep→named=6 不变、
layered=2（wet 持有者仍穿）→**water 面 1→0**（give-back，静默属设计）→**零 panic、
游戏存活（app_info 应答）、游戏日志零 `material override:`**（报告仅编辑器进程，决策
1-A 核心动机的真机验证）。mossy（Standard 面）在游戏侧无独立可读柄（探针口径，§一），
其 give-back 由编辑器侧 M5 型腿+与 export 相的水/layered 对照共同覆盖，报告如实注记。

## 三、真机新发现（MO 系续编，只记不修；红证已归档）

| 编号 | 严重度 | 描述 | 真机证据 | 处置建议 |
|---|---|---|---|---|
| **MO8** | ⚪ | **带覆盖场景每次打开/重实例化会先发一轮瞬时 stale 告警**：场景生成风暴中覆盖组件先于部件到场，报告系统按触发集判「键无人穿」→warn 双嘴各一次；部件到场后锁自清（不再重复），但日志已留痕。每相打开 t23.bsn 的日志均见 2-3 条后自净的 stale 行 | `loop/t23-live/warn-scan-*.txt` 各相头部时间戳组（如 export 相 04:06:04.799 三连）；本报告 §五 M12 归因 | 记档。可选收口：报告系统对「部件计数为 0/在增」的 holder 延迟一帧再判，或 book 注记「打开瞬间的 stale 告警属生成时序，自清」 |
| **MO9** | 🟡 | **`asset.rebind` 对 Map 值引用（MaterialOverrides/InstanceMaterialOverrides.materials）不生效**：MO2 让覆盖路径进审计（Missing 可发现），但 missing_list 的 rebind 重写 `rewrite_ast_reference` 只走 `BsnValue::String`/`List` 字段值——Map 既不在臂内也不在 MO3 的 force 通路（force 只覆盖 audit/rewrite 的扫描-重写层，missing_list 的按字段直改是第三条独立路径）→rebind 应答「the document no longer holds that reference」，文档与活世界均原地不动 | 真机活体：rebind 后 live kit map 仍 `{"Rock":"materials/wet.bsn"}`+audit 仍报同一条+状态栏「no longer holds that reference」。归档 `loop/reports/t23t2_mo9_rebind_map_red.log`+`t23t2_mo9_status_walk.json`（状态栏文本在场） | **T05 修复路的小补**：`rewrite_ast_reference` 的 Struct 臂给 `BsnValue::Map` 加一臂（键匹配 field、值串等于 reference 时替换），~15 行+单测；或 missing_list 对 Map 字段复用 reference_rewrite 的 force 通路。建议并进 T05 域或 T23-T3 收尾，非本任务范围 |

MO9 的发现使 **A11 刻画（rebind 后活世界粘性）在覆盖域被遮蔽**：rebind 根本改不了
Map 引用，粘性无从谈起——如实记档（`t23t2_a11_sticky.log` 已删，避免与 MO9 证据混
淆）；A11 本体（非覆盖域）不受影响，buglist 维持原状。M9 的「audit 归零+重开穿新
路径」改由文档外改+重开通路完成（D2，§四）。

## 四、偏差清单（分级如实）

- **D1（口径新增）真机可读面收窄**：`ModelMaterial` 无 Reflect、Standard 柄值不可
  序列化——方案设想的「G 断部件柄=mossy」改为「组件在场性（Layered/Water）+map 回
  读+PX 像素+M10 对照」。验收力不降：Layered/Water 面是组件换装的结构性铁证（glTF
  永不自带），Standard 面四证据链闭环。已沉淀脚本头注释供后轮复用。
- **D2（通路替代）M9 修复写入走文档外改+重开**：rebind 算子对 Map 引用失效（MO9，
  红证归档）。「audit 归零+重开穿 rebound 路径」的链路结论不受影响；修复路真身待
  MO9 收口后补一轮（建议并 T3）。
- **D3（脚本内迭代，非产品缺陷）**：①BRP 实体参数不接受整数 bits（首版 M4 用 id 传
  参被 `NoSuchId` 拒）→改走 TrimC 部件名通路（同时更稳：pack 后 `entity="props"`
  有实例根/模型根双义性）；②PX 取景首版 `viewport.look_through` 后模型不在框内
  （authored 相机朝向不覆盖摆放点）→改 `view.frame_all`+两侧同选 props 消 selection
  轮廓差（reopen diff 1.058%→0.067%）；③`wear_paths` 需在 rename/rebind 后回落
  `wet2/deep2` 文件头（同类型同注册路径）；④M7 命名部件计数 8→7（无名 mesh 本就不
  挂 GltfMaterialName）。全部为脚本口径修正，产品行为零改动。
- **D4（范围）散布腿未跑真机**：M4 的散布条目带回覆盖（scatter_ops）按方案「抽查一
  腿」以 headless 在库证据兑现（`tests/operators/scatter_ops.rs:455-482` 等三件，
  门禁 stage 全绿含之）；预制体 pack+实例层赢+跟随三面已真机。deviation 记档。
- **D5（预算）Foliage 面记档不跑**：按方案 §二 M2 口径（四穿面取三）。

## 五、M12 warn 扫描归因（词表 `material override:|material.override:|holds no
material|asset load failed|no longer holds a type this project knows|UnresolvedTypes|
cannot-apply|references name files|panicked`，归档 `t23t2_warn_scan_*.txt`）

| 相 | 命中 | 归因 |
|---|---|---|
| chains | 19 | MO8 瞬态（t23.bsn/pref.bsn 每次 open+pack/spawn 重实例化窗口的 stale 自清轮，约 3×5 组）+MO4 拒绝 1（预期）+RUN_OP INFO 行（词表 `material.override` 的点匹配）——零意外 |
| export | 6 | 全为 open 瞬态（MO8）——零意外 |
| broken | 16 | M5 未解决 ×3（rm/heal/re-break 节奏）+M13 索引拒绝 ×1+重开瞬态 ×N+MO9 状态（无 warn，静默）——零意外 |
| rename | 13 | rename 活世界 unresolved +1（M6 刻画的预期形态）+重开瞬态——零意外 |
| reimport | 11 | M8 stale 恰 1×2 轮+加盒/重命名的重实例化瞬态——零意外 |
| gamebroken | 0 | staged 包缺材质：游戏日志零报告（editor-only 设计）+零 panicked |

`UnresolvedTypes`/`holds no material`/`cannot-apply`/`panicked` 全程零命中。

## 六、门禁（产品代码零改动轮；证据=日志全文复核）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零 Diff | `t23t2_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，零 error/warning 行 | `t23t2_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t23t2_gates_clippy_phys.log` |
| libtests | `cargo nextest run --profile ci --workspace --lib` | **3052/3052**（与 T1 基线同数） | `t23t2_gates_libtests.log` |
| 受影响域 | `nextest -p jackdaw --test guards` / `--test stage`（material_overrides/reference_audit/reference_rewrite 家族所在档） | guards **246/246**（250.7s）；stage **572/572**（536.6s） | `t23t2_guards.log`/`t23t2_stage.log` |
| AN2 腿 | `nextest -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1** | `t23t2_an2_scene_load.log` |

**GATES_FAIL=0**（七门全 exit=0 且日志全文零 error/warning/FAILED/Diff 行）。

（本任务改动面=loop/ 下的脚本与报告，产品树零 diff——门禁为 T1 绿态的分支尖复证。）
RUST_BACKTRACE 全程未设；df 门前 79Gi；门链在七相全部结束、编辑器 pkill 后单窗跑。

## 七、产物清单

- `loop/qa/t23-live.sh`（七相真机流程，含探针定谳的 BRP 口径注释）、`loop/qa/t23t2-gates.sh`
- 运行证据 `loop/t23-live/`（console-七相/editor-*全 log/warn-scan-七相/shot-* PNG/g-*.json）
- 归档 `loop/reports/t23t2_*`：warn_scan_×7、px_before/px_after_dressed/px_reopen、
  mo4_refusal_response.json、m5_audit_finding.json、staged_holders/layered/water.json、
  gamebroken_water.json、**mo9_rebind_map_red.log+mo9_status_walk.json（MO9 红证）**、
  rename_sticky.log（M6 活世界刻画）、门禁七 log
- 未动：buglist.md / 台账 / roadmap / 产品代码 / fork / 场景格式 / 协议（MO8/MO9 记档
  待主控裁定吸收面，建议 MO9 并入 T05 域或 T23-T3）

## 八、给 QA 的注意事项

1. **预期 warn 形态**：MO1 双嘴均 `material override: …`；MO4 拒绝走 `warn_caller`
   （op 响应 warnings+日志）；破 .bsn 的可观测是索引行「no longer holds a type this
   project knows」（asset load failed 词表只咬资产服务器面）。M12 词表已含两者。
2. **MO8 瞬态**：复核任何带覆盖场景的日志时，open/pack/重实例化窗口内的 stale 告警
   会自清——判「报了几次」必须用偏移差分（脚本 `mark_log/log_lines_since` 形态），
   不能数全文件。
3. **MO9**：复跑 M9 时 rebind 段预期失败并归档；不要把它当环境问题。修复落地后
   M9_REBIND_MAP_BLIND 腿应翻绿（rebind 后 live map 拼新路径）。
4. **可读面口径**：`ModelMaterial` 与 Standard 柄值 BRP 不可读是本轮回实测结论；
   后轮断言请继续用「Layered/Water 在场性+map+PX」组合，勿再试柄值等值断言。
5. **复跑口径**：每相独立可跑（`bash loop/qa/t23-live.sh <phase>`）；跨相有文档状态
   依赖（chains→export→broken→rename→reimport，gamebroken 依赖 export 的 staged
   树）；全链重跑从 prep 开始。staged 游戏/门禁不得与 watcher 腿同窗。
