# T18 任务 1「缺口补齐轮」程序报告

> 分支 `loop/t18-assets`（自 main 4e6f747e 拉）；方案 `loop/plans/t18-assets-hotreload.md`
> §四-T1（决策 1/2/3/4/8，主控 8 决策点全按建议裁定）。日期 2026-10-31。
> 红态先归档纪律执行；勿设 RUST_BACKTRACE 口径执行；buglist/台账/roadmap 未动。

## 0. 一句话结论

**T1 全部建设面落地并绿**：探针两件定案（JPG 红绿归档、AR1 事件通路=2-B 共享信号+300ms
settle）、AR1（内容修改→缩略图失效+浏览器刷新）、AR2（workspace jpeg feature）、AR3
（`UntypedAssetLoadFailedEvent` 编辑器接收端，mtime 键 warn 锁）、AR4（文件卡随图片
重载/失败事件重建）、AU6 按决策 1-A 落地（音频提交面魔数校验+拒写）、fs 事件 e2e 锚
一件（真实 watcher→重扫→换值不换柄，3 连跑稳）。quick 门禁全绿：fmt/clippy 全仓
dylib/libtests 2999（=2990+9 新）/xtask fast（2999 passed）/受影响域 5 腿/物理双包
clippy。

## 1. 首步两探针

### 探针① JPG 定案（AR2 钉死）——红绿在案

- 形态：root tests/ 集成 `tests/asset_formats.rs`，真实 `AssetServer`+`ImageLoader`
  链路装 `tests/fixtures/images/probe_1x1.jpg`（773 字节真 JPEG，sips 生成）断
  load_state；另一件 teaches 断言读 workspace `Cargo.toml` 的 bevy features 块，
  只认裸 `"jpeg",` 行（注释行不误匹配）。
- **修前红证**：`loop/reports/t18t1_jpg-probe_red.log` —— 装载以
  `Failed(AssetLoaderError { error: FileTexture(InvalidImageExtension("jpg")) })`
  失败，即 loader 在册但 jpeg feature 未开、扩展名被拒，与方案事实十的静态推断一致
  （AR2 钉死）。teaches 断言同轮红。
- **修后**：workspace `Cargo.toml` bevy features 加 `"jpeg"`（带注释说明导入面邀请
  jpg、模板不带的理由）→ 两件全绿（`t18t1_qa_ar2_formats.log` EXIT=0）。
- Cargo.lock 传播核查：仅 `image` 条目直连新增 `zune-core`+`zune-jpeg` 两行（两者
  本就在链，经 tiff），**零新包、零版本变化**。
- bsn_game fixture：`tests/fixtures/bsn_game` **无 lock 入库**（git ls-files 仅
  Cargo.toml/assets/examples/src），feature 不传播到模板（决策 4：模板只保 wav，
  不同步）——无需刷新任何 lock。模板 teaches `features = ["wav"]` 断言（scaffold
  lib.rs:3749）不受影响（libtests 含 scaffold 全绿为证）。

### 探针② 决策 2 落地形态定案（静态，读码即定）

- `ProjectWindowState::rebuild()` 成本链：`needs_refresh`→`read_the_folder`（一次
  `read_dir`+memoized 的 `AssetKindCache` mtime 检查）→`rebuild_tiles`（despawn+
  重 spawn ≤`MAX_TILES` 个 tile，图片 tile 附带 `TextureInfo::read`）。单次爆发一次
  重建，成本可承受——**无需增量重建**。
- 通路选型：**决策 2-B 主案**（复用 asset_index watcher 单一触发源+顺带加路径粒度）
  全数落地，A 回落未触发。`AssetWatchChanges` 资源（见 §2 AR1）。

## 2. 逐项建设面

### AR1（🔴→吸收落地）外部内容修改→缩略图/浏览器 tile 刷新

- **单一触发源**：`src/asset_index.rs` watcher 事件从 `()` 改为携带
  `event.paths`；`poll_asset_watcher` 排空进新资源
  `AssetWatchChanges { paths, arrival }`（pub(crate) 字段+`take_settled(now)`），
  `AssetScanPending` 行为原样保留。
- **settle 窗口**：`asset_index::CHANGE_SETTLE = 300ms`（≥方案要求）。爆发内多次
  push 去重累积，settle 后一次 take——temp-swap 双写=一次刷新。
- **消费端**（`src/thumbnail.rs::respond_to_asset_changes`→纯函数
  `respond_to_changes`）：对每个 settle 后的变更路径，凡「被拍照的文件」（glb/gltf
  经 `is_model_path`；material/prefab 经 `read_asset_kind`+kinds 判定，仅读文档
  扩展名；scene 刻意排除——场景图=保存时视口抓帧）→`Thumbnails::forget(path)`
  （同时清 warned 锁=失败件获新尝试）；并置
  `ProjectWindowState::needs_refresh=true`（tile `applied` 锁靠 rebuild 重 spawn
  重走，`ready()` 以新 mtime 自然 miss→re-render；图片 tile 的 TextureInfo 文本行
  同链刷新）。Project 窗口自家 watcher（Create/Remove/Name）原样保留。
- **单测 3 件**（thumbnail.rs tests）：`pictured_paths_answer_their_extension_or_their_kind`、
  `a_change_event_forgets_the_picture_and_the_next_request_rerenders`（「修改事件→
  forget→request 重排队」方案点名锚）、`a_change_batch_settles_before_it_is_taken`。
- **真机红绿**：M3 两段按方案留给 T2 真机腿（headless 预演=e2e 锚，见下）。

### AR2（🔴→吸收落地）jpeg feature

见 §1 探针①。teaches 断言=`the_workspace_selection_teaches_the_jpeg_feature`。

### AR3（🟡→吸收落地）失败反馈编辑器接收端

- **决策 3-A 探针定案：可达，无需回落。** fork `bevy_asset` 的
  `UntypedAssetLoadFailedEvent` 经 `bevy::asset` 模块重导出（`pub use bevy_asset
  as asset`），`AssetPlugin::build` 无条件 `add_message` 注册；fork 在
  `handle_internal_asset_events` 的 `InternalAssetEvent::Failed` 臂发送（首载与
  重载同一通路）。系统以 `MessageReader` 消费即达。
- 新模块 `src/asset_failures.rs`（约 130 行+单测）：`report_failed_loads` 系统 →
  每路径一次 `warn!`（日志含绝对路径+error+「showing the previous content」）+
  `status_bar::notify_warn`（状态栏 6 秒横幅，文案 `broken.png failed to load;
  showing the previous content`）。锁=`WarnedFailures` 集合，键 **(路径, 当前
  mtime)** ——同文件同时刻只报一次；文件重写（修好或换一种坏）即新键，再坏再报，
  「恢复即清锁」以 mtime 键实现（缩略图失败记账同型）。已入 `EditorPlugin`
  （src/lib.rs）。
- **单测**：`a_failure_warns_once_per_path_and_again_after_the_file_changes`
  ——三态（一次报/重复不报/文件重写后再报）+状态栏文案断言，全绿。

### AR4（🟡→吸收落地）文件卡文本行随重载重建

- `src/inspector/file_card.rs::rebuild_when_the_file_changes`：读
  `MessageReader<AssetEvent<Image>>`（`Modified` 命中当前卡 `AssetPreviewState`
  的 `image_handle`）与 `MessageReader<UntypedAssetLoadFailedEvent>`（asset 相对
  路径命中卡的 `SelectedFile`）→ `InspectorDirty` 一分支（`rebuild_on_preview_
  change` 同型）。事实三的文本行陈旧（Path/Texture 描述/尺寸）修复。
- **单测 3 件**：自有图片重载→脏；他图重载→不动；失败命中→脏。全绿。

### AU6 / AR5（⚪→决策 1-A 探针落地）坏音频导入校验

- **rodio 可达性探针定案：不可达**（fork `bevy_audio` 仅 re-export
  `rodio::{cpal::Sample…, ChannelCount, Sample, SampleRate}`，`Decoder` 不出）→
  按决策 1-A 内置回落=**魔数校验**：`asset_row.rs::audio_file_plausible`（RIFF+
  偏移 8 处 `WAVE` 表单码 / `OggS`；空文件/截断/伪装字节拒绝）。**fork 未动**
  （unwrap 修复否决维持）——游戏进程坏音频 panic 归 book 注记（T3）。
- 接入点：`commit_asset_row`（picker 列表选择与 Browse 两路共同漏斗）——音频行
  （`AudioSource` 类型）提交非空路径前校验，坏文件 `notify_warn`（点名路径）+
  **拒写引用**（writer hook 不执行、字段不动）；清空（""）不校验。file_card 无
  音频导入动作（grep 零命中），asset_row 即音频引用唯一写入面，如实注记。
- **单测 2 件**：`audio_plausibility_reads_the_leading_bytes`（六态）、
  `committing_an_audio_field_refuses_a_file_that_is_not_a_sound`（拒写+状态栏+
  好文件放行+Clear 免检）。全绿。

### headless 锚（方案 §四-T1-7）

1. **真实 fs 事件 e2e**：`tests/asset_watch_reload.rs`（独立二进制=integration
   档，A6 纪律：独立 tempdir、单触发源、10s 预算、串行跑）。链路=真实 notify
   watcher→`AssetScanPending`→walk→`reload_in_place`：外部原地重写
   grass.bsn（0.2→0.31），断**柄 id 不变而值已更新**（换值不换柄活证）+mtime 落
   新。三连跑 0.90/0.92/0.93s 全绿。为此 `asset_index::plugin` 转 pub
   （`PrefabWatcherPlugin` 先例）。
2. AR1 缓存失效单测：§2 内 3 件。
3. AR3 warn 锁单测：§2 内 1 件。

## 3. 门禁（quick 四门+受影响域，日志全文复核）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 | `t18t1_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，零 error 行 | `t18t1_qa_clippy.log`（中途 3 轮 doc-markdown/redundant-closure 修正后覆盖归档） |
| 单测 | `cargo test --workspace --lib --features dylib` | ✅ **2999 passed / 0 failed**（=2990+9 新） | `t18t1_qa_libtests.log`（全文复核：唯一 ERROR 行=PIE 测试故意坏构建场景，既有归因） |
| fast | `cargo xtask fast` | ✅ EXIT=0，**2999 tests run: 2999 passed, 0 skipped**（日志全文零 error/FAILED/Diff） | `t18t1_qa_fast.log` |
| 物理双包 clippy | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | `t18t1_qa_clippy_physics.log` |
| 受影响域集成 | asset_formats / asset_watch_reload / audio_gate / guards::asset_lifecycle | ✅ 四腿全 EXIT=0 | `t18t1_qa_*.log` + `t18t1_qa_gates_progress.log` |
| warn 归因 | libtests 日志扫描 `thumbnail\|Failed to\|failed to\|UnresolvedTypes\|cannot-apply` | 仅既有 headless 环境告警（RenderApp/CompressedImageFormatSupport）+keymap/live_edits 既有条目；**本任务新增 warn 仅 AR3 的 `asset load failed:` 一族（设计内）** | `t18t1_qa_libtests.log` |

磁盘：门前 27Gi free。全程未设 RUST_BACKTRACE。长命令后台+轮询执行，门与编辑器
无同窗。

## 4. 偏差清单（如实）

1. **探针①形态修正**：首版探针 app 缺 `ImagePlugin`（红因=`MissingAssetLoader`
   对整个 Image 类型，非扩展名门），判为无效红；补 `ImagePlugin`+仓内先例的显式
   `register_asset_loader(ImageLoader::new(NONE))`（material_assets.rs 测试同款）
   后得到**诚实红** `InvalidImageExtension("jpg")` 并归档。红证以归档文件为准，
   首轮无效红未入库。
2. **AR1 消费端落点微调**：方案写「Project 窗口 watcher 事件面扩 Modify(Data)」，
   实际按决策 2-B 把消费系统放 `thumbnail.rs`（被拍照文件的判定是缩略图域知识；
   `capture_pending_scene` 观察者本就双向耦合先例），Project 窗口自家 watcher
   未动。语义=方案验收面全数达成。
3. **AR4 信号选择**：方案给「决策 2 的变更信号 **或** AR3 事件」两案，实现取
   `AssetEvent<Image>::Modified`（精确命中卡的绘制柄，避免 `AssetWatchChanges`
   单消费点与浏览器刷新争夺路径批）+ AR3 失败事件双读者。场景/材质卡的内容变化
   面不在事实三引用范围，未扩。
4. **AR3 锁键形态**：方案建议「warned 集合+文件恢复后清锁」；实现为 (路径，mtime)
   键集合——恢复无消息可观测，mtime 键让「修好后再坏」必再报且无需恢复记账。
5. **`asset_index::plugin` 可见性 pub(crate)→pub**：fs e2e 锚（integration 档）
   需要，`PrefabWatcherPlugin` 先例同型。
6. 其余零偏差：fork 零改动；场景格式/协议零变更；模板/bsn_game 未动（决策 4-A）。

## 5. 给 QA / T2 的注意事项

1. **AR1 红绿两段**在 M3/M4/M8 真机腿执行：改 .glb/.material.bsn 前（tile 陈旧红证
   已不可能复现于本分支——修已落地，红证以方案事实六静态链+本报告为准）→改后断
   `Thumbnails::forget` 生效=盘上 `.jackdaw/thumbnails/` 新 mtime 文件名 PNG+像素
   diff。若真机仍见陈旧 tile，优先查 settle（300ms）与截图时窗。
2. **A6 纪律**：`asset_watch_reload` 已按五纪律跑（独立 tempdir/单触发源/10s
   预算）；真机 watcher 腿延续同口径，腿内 settle≥2s。
3. **AR3 warn 扫描归因**：`asset load failed:` 与状态栏文案 `…failed to load;
   showing the previous content` 是**设计内信号**；M15 的 warn 扫描表把该签名记
   预期列。AU6 拒写的状态栏文案 `…is not a sound file the editor can decode…`
   同理（仅状态栏，非日志 warn）。
4. **M12 坏音频腿**：AU6 探针拦的是「写引用」时刻；场景里**已挂**的坏音频 play
   panic 风暴仍在（fork unwrap 未动，决策 1-A 诚实注记），红绿对照腿照方案 L8：
   修前 panic 日志在案、修后（指 pick 面）无新引用可写。编辑器存活由 error_handler
   兜底为现状实证。
5. **M2 JPG 腿**：编辑器侧装载已通（feature 落地）；拖放后参考图板/文件卡链路
   未跑过真机，按 L2 全链走。若 `.jpg` 导入后进压缩管线出问题，注意 launch.rs
   的 `default_compressed_image_processor_extensions` 只列 png（jpg=raw，
   既有注释自证），异常才立 AR9。
6. **bsn_game fixture**：无 lock 入库，无刷新面；scaffold 模板未动。
7. T16 移交闭环件：AU6 处置证据（本报告 §2 AU6 节）供 T3 回写 T16 结案清单与
   buglist 打钩。

## 6. 产物与证据索引

- 代码：`Cargo.toml`（+jpeg）、`src/asset_index.rs`（watcher 路径+`AssetWatchChanges`
  +`CHANGE_SETTLE`）、`src/thumbnail.rs`（响应系统+3 测试）、`src/asset_failures.rs`
  （新，AR3）、`src/inspector/file_card.rs`（AR4+3 测试）、`src/inspector/asset_row.rs`
  （AU6+2 测试）、`src/lib.rs`（接线）、`tests/asset_formats.rs`、
  `tests/asset_watch_reload.rs`、`tests/fixtures/images/probe_1x1.jpg`。
- 红证：`loop/reports/t18t1_jpg-probe_red.log`。
- 门禁：`loop/reports/t18t1_qa_{fmt,clippy,libtests,fast,ar2_formats,ar1_watch_reload,
  audio_gate,asset_lifecycle,clippy_physics}.log` + `t18t1_qa_gates_progress.log`。
- 新测试合计：lib +9（thumbnail 3、asset_failures 1、file_card 3、asset_row 2）；
  integration 二进制 2 个（asset_formats 2 件、asset_watch_reload 1 件）。
