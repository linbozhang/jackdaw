# T18 任务 1「缺口补齐轮」QA 报告

> 分支 `loop/t18-assets`，程序提交 `f9b26b6e`（工作树干净，QA 亲跑基线=该提交）。
> 核实对象：`loop/reports/t18-t1-report.md`；方案 `loop/plans/t18-assets-hotreload.md`
> §四-T1+§五决策表（主控 8 点全裁建议）；buglist A6；AU6 移交出处 `loop/reports/t16-final-qa.md`（§结案：AU6/AU8 记档留 T18）。
> 日期 2026-10-31。QA 口径：只读源码+亲跑门禁（后台+轮询）+覆盖归档日志；勿设
> RUST_BACKTRACE 执行（亲证 `RUST_BACKTRACE=[]`）；buglist/台账/roadmap 未动。

## 0. 裁决

**PASS——放行 T18-T2（真机矩阵轮 M1-M16/L1-L10）。**

依据：①门禁六门+受影响域 4 腿 QA 亲跑全绿（libtests/fast 双 2999，日志覆盖归档+全文复核）；
②AR1-AR4+AU6 五件全部源码级复核通过（信号链/feature 行/反馈锁/双读者/魔数漏斗逐一亲读，
与报告陈述一致，零虚报）；③九件新单测+fs e2e 锚逐件亲跑绿（e2e 锚三连跑 0.96-0.97s 稳）；
④五条偏差全部核实为真且裁定可接受（§3）；⑤fork 零改动亲证（unwrap 原样+fork 树干净）。
报告有两处**表述**不准（§3 附加发现 1/2），不动摇门禁与建设面结论，不构成返工项。

## 1. 门禁（QA 亲跑，覆盖归档 `loop/reports/t18t1_qa_*`）

| 门 | 命令 | 结果 | 证据（QA 覆盖归档） |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0（0 字节=净） | `t18t1_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | ✅ EXIT=0，日志零 error/warning 行 | `t18t1_qa_clippy.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | `t18t1_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib --features dylib` | ✅ **2999 passed / 0 failed**（58 个二进制求和亲算） | `t18t1_qa_libtests.log` |
| fast | `cargo xtask fast`（=fmt+core_deps+git_deps+clippy 同参数+nextest lib dylib，xtask/src/main.rs:35 亲读） | ✅ EXIT=0，**Summary: 2999 tests run: 2999 passed, 0 skipped**；全文扫描仅 3 处失败样词命中均为测试名（`…_not_panicked` 等） | `t18t1_qa_fast.log` |
| 腿 1 asset_formats | `cargo test --test asset_formats` | ✅ 2/2（jpg 装载+teaches 断言） | `t18t1_qa_ar2_formats.log` |
| 腿 2 asset_watch_reload | 同上，**QA 加跑三连**（A6 稳定性） | ✅ 1/1 ×3（0.97/0.96/0.97s） | `t18t1_qa_ar1_watch_reload.log`（三段在档） |
| 腿 3 audio_gate | `cargo test --test audio_gate` | ✅ 7/7 | `t18t1_qa_audio_gate.log` |
| 腿 4 guards asset_lifecycle | `cargo test --test guards asset_lifecycle` | ✅ 5/5（239 filtered out） | `t18t1_qa_asset_lifecycle.log` |
| 定向单测 | `cargo test --lib --features dylib thumbnail::tests` | ✅ **25/25**（22 回归+3 新 AR1） | `t18t1_qa_units_thumbnail.log` |
| 定向单测 | `… asset_failures::` | ✅ 1/1（AR3 三态） | `t18t1_qa_units_ar3.log` |
| 定向单测 | `… file_card::tests` | ✅ 3/3（AR4） | `t18t1_qa_units_ar4.log` |
| 定向单测 | `… audio`（AU6 2 件+同域 3 件） | ✅ 5/5 | `t18t1_qa_units_au6.log` |

磁盘：门前 14Gi free（比程序轮的 27Gi 低，未触 ENOSPC，A6 加重因子在监控下）；门后 11Gi。
全程未设 RUST_BACKTRACE；门禁串行后台+轮询，与编辑器零同窗（QA 未启动编辑器）。
**执行注记**：QA 脚本首版误用 `cargo test --test asset_lifecycle`（无此目标，EXIT=101），
已按 guards 二进制真名重跑覆盖归档——归档日志现为准跑证据。
**进程清理**：结束核 pgrep，无 cargo/rustc 残留。

## 2. AR 逐项源码级复核（亲读+亲跑）

### AR1 内容修改→缩略图/浏览器刷新——通过

信号链逐环亲读：`watch_asset_files` 的 notify 回调从发 `()` 改为发 `event.paths`
（src/asset_index.rs:1010-1016）→`poll_asset_watcher` 排空进 `AssetWatchChanges::push`
（路径 contains 去重+`arrival` 记首事件，:838-856）→`take_settled` 以
`CHANGE_SETTLE=300ms` 定批（`mem::take` 单消费清空，:858-872）→
`thumbnail.rs::respond_to_asset_changes`→纯函数 `respond_to_changes`：对批内
`is_pictured_path` 命中者 `thumbnails.forget(path)`（**同时清 warned 失败锁**，
thumbnail.rs:397-400 亲读确认）并无条件置 `project.needs_refresh=true`。
tile 通路闭环亲读：needs_refresh→rebuild 重 spawn（applied=false）→
`update_thumbnail_slots` 的 `thumbnails.request(&slot.path, subject)`（thumbnail.rs:1409）
→缓存 mtime miss→重拍。**方案验收面=glb/gltf/material/prefab 亲核成立**：
`is_pictured_path` 中 `AssetFileKind::Scene => false`，理由（场景图=保存时视口抓帧，
`capture_pending_scene` thumbnail.rs:1285；`Subject::Scene => None` :795）与方案
T1-2 明文「model/material/prefab 路径 forget」一致，测试
`pictured_paths_answer_their_extension_or_their_kind` 断言 scene 拒绝亲跑绿。
定界旁证三事实在本分支仍可复核（红链未被动过）：Project 窗口自家 watcher 仍只吃
Create/Remove/Modify(Name)（project_window.rs:416-418，未动）；tile `applied` 锁仍在
（:1405/:1429）；`forget` 修前唯一调用方=场景截图（现 AR1 消费端 ：179 为新调用方）。
3 单测亲跑绿（units_thumbnail.log）： pictured 判定/「修改事件→forget→request 重排队」
（方案点名锚）/settle 去重定批。
**A6 五纪律在 fs e2e 锚落实亲跑**：tests/asset_watch_reload.rs 自带独立 tempdir、
单触发源（只写 grass.bsn 一文件）、10s 预算、串行；真实 notify watcher→pending→walk→
`reload_in_place`，断柄 id 不变而值 0.2→0.31+mtime 落新（换值不换柄活证）。
QA 三连跑全绿（0.96-0.97s，远低于 10s 预算）。`asset_index::plugin` 转 pub 使锚成立
（tests/asset_watch_reload.rs:49 引用；`PrefabWatcherPlugin` 先例 tests/prefabs/
prefab_lifecycle.rs:689/727/4094 同型亲核）。

### AR2 jpeg feature——通过

- 一行 feature：Cargo.toml bevy features 块 `"jpeg",` 带三行注释（导入面邀请/模板不带的
  理由），亲读。
- teaches 断言亲读：`the_workspace_selection_teaches_the_jpeg_feature` 只认 trim 后
  `starts_with("\"jpeg\",")` 的裸行（asset_formats.rs:127-129），注释行不误匹配；
  亲跑绿。
- 红证形态核：`t18t1_jpg-probe_red.log:14` 失败态 Debug=
  `Failed(AssetLoaderError { … FileTexture(InvalidImageExtension("jpg")) })`——
  loader 在册、扩展名门拒绝，即方案事实十的诚实红（非 MissingAssetLoader 无效红）。
  **小瑕**：该红 log 的断言提示文案为首版措辞（「if this reads as a missing loader…」），
  与现行测试源码提示（「invalid image extension」）不一致；失败因本体清晰，证据有效。
- Cargo.lock 零新包亲核：diff 仅 `image` 条目依赖表 +`zune-core`+`zune-jpeg` 两行；
  两个 `[[package]]` 块在父提交 lock 已存在（:9851/:9857，经 tiff 传入）——零新包、零版本变化。
- probe_1x1.jpg `file` 亲证=真 1×1 baseline JPEG（sips 产物，773 字节）。
- 决策 4-A 边界亲核：`git ls-files tests/fixtures/bsn_game` 仅 Cargo.toml（无 lock 入库）；
  scaffold 双处 wav-only（:2634/:5082）未动——模板不同步落地如实。

### AR3 失败反馈接收端——通过

- 模块亲读（src/asset_failures.rs）：`report_failed_loads` 读
  `MessageReader<UntypedAssetLoadFailedEvent>`→每路径一次 warn（文案含绝对路径+error+
  「showing the previous content」）+`status_bar::notify_warn` 横幅；锁=`WarnedFailures`
  集合，键 (路径， 当前 mtime)。已入 EditorPlugin（src/lib.rs 接线亲读）。
- 决策 3-A 探针定案亲核：fork `bevy_internal/src/lib.rs:28` `pub use bevy_asset as asset`
  + `bevy_asset/src/lib.rs:421` `add_message::<UntypedAssetLoadFailedEvent>()`（AssetPlugin
  无条件注册）+ `event.rs:28` pub struct → `bevy::asset::UntypedAssetLoadFailedEvent`
  可达，**回落未触发**；产品 `use` 编译绿即活证。
- 三态单测亲跑绿（units_ar3.log）：一次报（含状态栏文案断言）/同 (path,mtime) 重复不报/
  文件重写后再报。

### AR4 文件卡双读者——通过

- 亲读（src/inspector/file_card.rs::rebuild_when_the_file_changes）：读者一
  `AssetEvent<Image>::Modified` 命中当前卡 `AssetPreviewState` 的绘制柄 id；读者二
  `UntypedAssetLoadFailedEvent` 命中卡的 assets 相对路径 → 单分支 `InspectorDirty`。
  落点合理性核：`AssetWatchChanges::take_settled` 是 mem::take 单消费——文件卡若也吃
  批路径会与浏览器刷新争批，取 Image Modified 精确命中是正确取舍（偏差③核实成立）。
- 3 单测亲跑绿（units_ar4.log）：自有图重载→脏；他图重载→不动；失败命中→脏。

### AU6 坏音频魔数校验（决策 1-A）——通过

- 魔数亲读（src/inspector/asset_row.rs::audio_file_plausible）：`OggS` 前缀，或
  len≥12 且 `RIFF`+偏移 8 `WAVE`；空/截断/伪装拒。**fork unwrap 未动亲证**：
  fork `bevy_audio/src/audio_source.rs` `Decodable::decoder` 仍 `.build().unwrap()`；
  `git -C bevy-fork-pinned status` 干净（pinned rev 9cb82e77e）——决策 1-A 边界（不动
  fork）如实；游戏进程 panic 残留归 book 注记（T3），与 t16-final-qa 移交口径闭合。
- 漏斗接入亲核：picker 列表选择（:739）与 Browse/native 对话（:804/:835）两路共漏斗
  `commit_asset_row`，音频行（`bevy::audio::AudioSource` type_path 判定）提交非空路径前
  校验，坏文件 notify_warn+writer hook 不执行（字段不动）；Clear（""）免检。
  file_card 无音频导入动作亲核（grep 零命中）——asset_row 即唯一写入面，报告注记如实。
- 2 单测亲跑绿（units_au6.log）：六态魔数；拒写+状态栏点名+好文件放行+Clear 免检三段。

## 3. 偏差 5 条裁定（逐条核实）+ QA 附加发现

| # | 偏差 | 核实 | 裁定建议 |
|---|---|---|---|
| ① | 探针首版红因无效（缺 ImagePlugin→MissingAssetLoader），判无效未入库；补装后得诚实红归档 | 归档红证 :14 为 `InvalidImageExtension("jpg")`（诚实红实锤）；红 log 断言提示文案是首版措辞（措辞瑕，证据本体有效） | **接受**。诚实归档纪律执行到位；无需补跑。红证唯一性以归档文件为准 |
| ② | AR1 消费端放 thumbnail.rs 而非扩 Project 窗口 watcher | 决策 2-B 本就是「复用 asset_index 信号」；被拍照判定是缩略图域知识；`take_settled` 单消费（mem::take）决定了只能一个消费端——Project 窗口自家 watcher 原样保留（:416-418 亲读） | **接受**。语义=决策 2-B 全数落地，方案 §四-T1-2 的「或共享信号」分支 |
| ③ | AR4 取 Image Modified+失败事件而非 AssetWatchChanges | 同②的单消费约束；Modified 精确命中绘制柄更准；场景/材质卡不在事实三范围 | **接受**。范围注记如实；M1/M3 真机腿顺带验卡面 |
| ④ | AR3 锁键 (path,mtime) 而非「warned 集合+恢复清锁」 | 恢复无消息可观测（引擎对恢复不发事件），mtime 键让「修好后再坏」必再报且零记账——**严格优于方案原议**（原议的「恢复即清」不可实现）；与缩略图失败记账同型 | **接受**。三态单测亲跑绿 |
| ⑤ | `asset_index::plugin` pub(crate)→pub | tests/asset_watch_reload.rs:49 真需要；`PrefabWatcherPlugin` pub 先例同型（prefab_lifecycle.rs 三处） | **接受**。边界最小性另见附加发现 3 |

**QA 附加发现（不动裁决，供修正口径与后续记档）**：

1. **报告 §3 warn 归因行不准确**：称 libtests 日志含本任务新增 `asset load failed:` 一族
   ——QA 实测本轮归档 log **0 条**，程序自己的归档 log 同样 0 条（git show 亲核）。原因：
   AR3 单测以 `run_system_once`+状态断言验证（StatusNotice/WarnedFailures），不经日志。
   **零意外 warn 反而更干净**，但 T2 M15 的「预期列」口径应理解为**编辑器进程真机日志**
   的签名（坏文件真机腿才会出），headless 门禁日志里不会出现。
2. **报告 §3「唯一 ERROR 行=PIE 故意坏构建」不准确**：本轮 libtests 107 条 ERROR，
   QA 逐族归因全部为既有故意场景/无头环境噪声（bevy_asset no-loader/unapproved=无头
   测试 app 的故意失败件；PIE SIGKILL+E0560=故意坏构建；save not-a-directory=故意；
   feathers 嵌入图标/字体+extract ClearColor+RenderApp/CompressedImageFormatSupport=
   无头噪声；keymap chords=既有）。**零新失败签名，结论不变，表述以本报告为准。**
3. **`AssetWatchChanges` pub 面略宽**：`take_settled` pub 而 tests/ 零外部使用（e2e 锚
   只需 `plugin`+`AssetIndex` pub）——单消费契约存在外部误用面（外部抢 take 会饿死
   浏览器刷新）。非缺陷；建议后续触碰 asset_index 时收窄 pub(crate)，本轮不动。
4. **缩略图回归数**：实测模块 25 件（22 回归+3 新）全绿；方案写「19 件」为方案时点枚举，
   超集成立，验收线满足。
5. guards 腿归档日志为 QA 按 guards 二进制真名重跑的覆盖版（程序原档跑的是全 guards
   二进制 5 件同绿，形态差异无实质）。

## 4. T18-T2 放行建议与真机矩阵交接口径

- **M3/M4/M8（AR1 红绿两段）**：红段**不可也不必**在本分支复现（复现需 revert 修）——
  红证=方案事实四②+事实六静态链+本报告 §2 三事实源码亲核（Project watcher 排除
  Modify(Data)/applied 锁/forget 修前零调用方），已归档在案；绿段真机必断：
  外部改 .glb/.material.bsn 后盘上 `.jackdaw/thumbnails/` 出现**新 mtime 文件名 PNG**
  +像素 diff+浏览器 tile 换图。**真机若见陈旧 tile 即 FAIL**（排查顺序：settle 300ms
  →截图时窗→FSEvents 延迟），不赌时序不重试（A6 纪律④）。
- **M2（JPG）**：编辑器装载面已由腿 1 绿（真 JPEG+真 AssetServer 链路）；拖放→参考图
  板→文件卡全链未跑真机，按 L2 走。压缩管线注记照程序报告 §5-5（jpg=raw，既有注释）。
- **M9/M10（坏文件+AR3）**：状态栏横幅文案 `… failed to load; showing the previous
  content`+日志签名 `asset load failed:`（**仅编辑器真机日志会出现**，见附加发现 1）
  记入 M15 warn 扫描预期列；AU6 拒写文案 `…is not a sound file the editor can decode…`
  仅状态栏、非日志 warn，同记预期列。
- **M12/L8（AU6 红绿对照）**：口径=「修前」指 **pick 面**可写坏引用（决策 1-A 修后
  拒写）+场景已挂坏音频的 play panic 风暴**仍在**（fork unwrap 未动，诚实注记）；编辑器
  存活由 error_handler 兜底为现状实证。红绿对照按程序报告 §5-4 执行，勿把「修后无 panic」
  误写成验收预期——修的是写入口，不是 play 面。
- **A6 纪律延续**：单触发源/settle≥2s/预算 10s 超时即 FAIL/与门禁不同窗/门前清磁盘
  （本机磁盘 11-14Gi 起，建议 T2 门前再清一轮）。
- AR6（外部改名边界）/AR7（导入缓存孤儿）/AR8（首载坏刻画）按方案记档格执行，不立新缺陷。

## 5. 产物

- QA 门禁与定向单测归档：`loop/reports/t18t1_qa_{fmt,clippy,clippy_physics,libtests,fast,
  ar2_formats,ar1_watch_reload,audio_gate,asset_lifecycle,gates_progress}.log`（覆盖归档）
  + `t18t1_qa_units_{thumbnail,ar3,ar4,au6}.log`（QA 新增）。
- 程序证据复核引用：`t18t1_jpg-probe_red.log`（InvalidImageExtension 形态亲核）。
- 本报告未动任何产品代码/buglist/台账/roadmap；覆盖归档的日志与本报告待主控随 T18-T1
  收尾一并入库（QA 不自行 commit）。
