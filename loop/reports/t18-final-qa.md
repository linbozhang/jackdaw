# T18 终验 QA 报告：任务 3（收官段）+ T18 整体终验（只验不修）

> 验收对象：分支 `loop/t18-assets` @ **9a7f02b0**（基线 main=e21d4c06；程序提交=T18-T3 收官，
> T2+T2.5 已于 e21d4c06 合入，T2 QA 终轮 PASS 含合并前置见 t18-t2-qa.md §8a/§8b）。程序报告：
> `loop/reports/t18-t3-report.md`。前置：T18-T1 QA PASS（t18-t1-qa.md）、T18-T2 QA 终轮 PASS
> （t18-t2-qa.md §8b，合并前置=missing_list.rs:695 doc 反引号+fast 覆盖归档——QA 本轮在终树
> 亲核反引号在位 ：695 `` `reference_audit`'s `` + fast 3001/3001 亲跑绿，前置兑现）。
> T3 diff 亲核（numstat 全件）：**产品面=book 六文件（新章 assets.md 216 行+SUMMARY 挂目+
> prefabs/audio/materials 三交叉引用+open-challenges 条目改写）+loop/plans/t16-audio.md（AU6
> 结案回写）+loop 工具与归档 52 件**——`src/`、`crates/`、模板、fork、协议、场景格式零改动
> （commit 全件无该域路径）；fork 树干净亲证（pinned rev 9cb82e77e）；工作树除 QA 归档外零触碰。
> buglist/台账/roadmap 零触碰（A6/A7/A9/A10/A11 均维持未勾选=正确；roadmap 第 32 行未勾=留主控；
> 台账最后一行=T18-T1 DONE，T2/T2.5/T3 行留主控合入时写）。
> QA 手段：**Mac 全量门亲跑**（串行后台链+轮询，全程未设 RUST_BACKTRACE，门链独窗，门前 df
> 17Gi）+**关键格证据原文全读**（console 91 行/editor 日志 237 行/summary/warn 空件语义/m13
> audit/m9-ar3/m10-thumbnail/m12-storm 空件+**9/9 截图亲览**）+book 新章九节逐节对锚源码+
> UI 名现场核对+clippy 双包/doctests 采信归档抽核（0 warning 行+bind dyld 第 11 次目击签名+
> 单包复跑绿+mtime 顺序可追）。
> QA 归档 `loop/reports/t18t3_qa_*`（门禁九件亲跑覆盖归档：fmt/libtests/fast/audio_gate/
> save_store/integration/a6_isolated/doc/scaffold_e2e）+`t18t3_qa_integration-signal_cap_red.log`
> （harness cap 旁证轮）+`t18final_qa_*` 三件（bsn_game 首探/bsn_game_run 绿证/gates_progress）。

## 〇、结论

**PASS（T18-T3 收官 + T18 整体，含 roadmap T18 可勾选建议）**——全量门 QA 独立复现与程序轮
逐位吻合：integration **5456 跑 5455 过+唯一红=A6 已知件**（QA 终轮亲跑同签名三试
`prefab_lifecycle.rs:714 watcher reloaded prefab; v2 should be in world. Got ["v1"]`=buglist
原签名；另有 harness cap 被杀旁证轮 4976 跑 4975 过同样唯一红=A6，两轮互证「红跟随二进制内
并行负载」定案形态；隔离 1/1 绿 4.18s）；fast/libtests 双通道 **3001**、**teaches 91**
（scaffold 包 91/0 亲点）、audio_gate **7/7**、save_store **19/19**、fmt/clippy 归档零红、
docs **17 条 warning=T17 归档同数同族**零新增、scaffold_e2e **1/1**；**heavy 档 bsn_game_run
3/3 QA 补腿亲跑**（§二-2，T17 先例）。T3 真机复跑 15 判定 **14 PASS/唯一 FAIL=L7_M9_BAD_PNG
板面恢复半格=AR9 已知红**（四面绿含 AR10 引擎面 Reloaded=1，与 T2.5 §9.6 归档形态逐位同形）
亲读复核成立；三目标格（M3/M8 三面同腿、M10 坏 GLB、M12+AU6 拒写门）console/editor/截图三层
证据全读亲览与报告陈述一致、零虚报；warn 扫描 4/2/1/0 意外=0 与 QA 手数编辑器日志逐条吻合。
book 新章九节+SUMMARY+四处交叉引用全落且事实面对得上源码（UI 名防杜撰全数亲核）；**AU6 结案
回写在案且与 T18 实际落地一致**（一处「两轮/三轮」措辞级时滞记 §六-1）；验收句「外部改资产
视口+Inspector+缩略图正确更新；坏文件不崩不丢引用」逐词证据在案（§四，铁证①限定注记=无
meta 主流链如实）；AR1-AR11 结案清单全绿（§五，AR9 另立渲染侧、AR12=A11 独立票）。
**偏差 0 🔴 + 0 🟡 + 6 ⚪（§六）**——全部为措辞/记档精度/QA 侧基建级，不动摇裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 9a7f02b0；门链独窗，未设 RUST_BACKTRACE）

门前 df 17Gi（≥10Gi 线）；门后 14Gi→bsn_game 补腿重建后一度 3Gi→QA 清可再生缓存
（target/bsn_game_run 12G+target/debug/incremental 9.2G，T3 报告偏差 6 同款处置）→21Gi。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（3s，0 字节） | `t18t3_qa_fmt.log` |
| 2 | 单测 | `cargo test --workspace --lib --features dylib` | **EXIT=0；3001 passed / 0 failed**（58 个 test result 行求和亲算）；**scaffold 包 `91 passed` 亲点**（`new_game_project_teaches_the_audio_pattern` 等在档）——teaches 91 计数器与 T17-T2 一致零扰动 | `t18t3_qa_libtests.log` |
| 3 | fast | `cargo xtask fast` | **EXIT=0；Summary 3001 tests run: 3001 passed, 0 skipped（82.9s）**；全文 error 词扫描全部为 PASS 行测试名（假阳性族），0 FAILED | `t18t3_qa_fast.log` |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（11.8s） | `t18t3_qa_audio_gate.log`（QA 新增档） |
| 5 | save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（0.115s） | `t18t3_qa_save_store.log`（QA 新增档） |
| 6 | **integration** | `cargo xtask integration` | **Summary [2890.8s] 5456 run：5455 passed (36 slow)，1 failed，0 skipped**——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload` 三试全败（28.8s），panic 同签名 `:714 watcher reloaded prefab; v2 should be in world. Got ["v1"]`=**buglist A6 原签名**；零其他红。计数 5456 与 T17 时代 5440 之差=T18 新增集成件自然增长，failed=1 与 T17 终树「5439/5440 唯一红=A6」完全同构 | `t18t3_qa_integration.log` |
| 7 | A6 隔离 | `cargo test -p jackdaw --test prefabs prefab_file_change_triggers_reload` | **1/1 PASS（4.18s，100 filtered out）**——「红跟随二进制内并行负载」定案口径在终树复现，与程序归档（4.07s）同形互证 | `t18t3_qa_a6_isolated.log` |
| 8 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**（37.3s）；warning 面 **17 条=存量私项链接族**（程序归档 17 条+T17 归档 17 条同数同族，本轮零 src/ 改动=预存树态） | `t18t3_qa_doc.log` |
| 9 | scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **PASS 1/1**（154.0s）EXIT=0 | `t18t3_qa_scaffold_e2e.log` |
| 10 | heavy 补腿 | `cargo nextest run --profile ci -p jackdaw --test bsn_game_run` | **3/3 PASS（149-151s 慢档）**——含 `a_save_survives_the_fixture_restart`；integration 门 `-E not(binary(bsn_game_run)|…)` 结构性排除亲读于门命令行，T18 全弧未跑过此件，QA 按 T17 先例补齐终树绿证（前置=fixture 本地锁刷新，§六-3） | `t18final_qa_bsn_game_run.log` |

**clippy 双包/doctests（采信归档抽核）**：`t18t3_qa_clippy.log`（全仓 -D warnings，Finished
1m10s，`warning` 计 0）/`t18t3_qa_clippy_physics.log`（Finished 34.3s 零 warning 行）抽核通过
+fast 内含同参数 clippy 三重覆盖；`t18t3_qa_doctests.log` 主跑仅 `-p jackdaw_bind --doc` 处
dyld rpath 家族失败（`libstd-614bb9b33bbc23af.dylib not loaded`，**第 11 次目击**，T15 定案
环境票）+`t18t3_qa_doctests_bind_rerun.log` 单包复跑 **1 passed**（1.76s merge）——双日志
mtime 顺序可追（16:18→16:22），采信。

**旁证轮（harness 1h wall cap）**：QA 第一条门链在 integration 中段被 SIGTERM（T17 QA §六-5
同款）——被杀时已跑 **4976/5456：4975 passed，1 failed=同一 A6 同签名三试**（480 not run due
to signal）。该轮与终轮两轮独立互证：integration 的唯一红恒为 A6、终树零其他红。全文保全
`t18t3_qa_integration-signal_cap_red.log`（613KB）。

**程序归档交叉复核**：`t18t3_qa_fmt.log` 0 字节、`t18t3_console-assets.log` VERDICT 行
14/15、summary 文件逐字节同、warn-lines 与 m12-storm 两空件语义=零意外零 panic 的最强形态、
m9-ar3 单行 AR3 签名、m10-thumbnail 恰 2 行写 off、m13-audit count=0——与 t18-t3-report
§〇/§三/§四门禁表逐项一致，无隐瞒。

## 二、唯一预期红双件口径核 + heavy 档补腿定性（之外零红）

1. **真机 M9=AR9 板面半格、integration=A6——双件口径核成立，之外 QA 亲证零红。**
   - **M9 四面绿+半格红逐行亲读**（console:41-51+editor 日志）：存活 ✅（M16 BRP+pid）；旧内容
     保持 ✅（board-region md5 good=broken=36591fe7…）；AR3 反馈 ✅（恰 1 行
     `jackdaw::asset_failures: asset load failed: …/board.png (…Invalid PNG signature…)
     -- showing the previous content`，逐字=asset_failures.rs:80 双形态）；**AR10 引擎面 ✅**
     （修复写盘窗口 `Reloaded matrix/board.png`=1，editor:152）；红=板面恢复（fixed md5 仍
     36591fe7…，want ≠broken≠good）→ **AR9 已知渲染侧缺陷的红证持续**，与 T2.5 §9.6
     归档形态逐位同形，非新缺陷。**截图亲览**：m9-board-good/broken/fixed 三窗板面同为蓝色
     （旧图恒显）=AR9 红证目视实锤。
   - **integration=A6**：终轮+被杀旁证轮+隔离绿三面互证（§一-6/7）。
   - 两红之外，15 判定真机相+九门+heavy 腿 QA 全数亲见零第三红。
2. **bsn_game heavy 档补腿（QA 亲跑 3/3）**：integration 门结构性排除 heavy 档（`-E
   not(binary(bsn_game_run)|…)` 亲读），T18 全弧（T1/T2/T2.5/T3）无一轮跑过 bsn_game_run，
   而 T2.5 改动过 jackdaw_runtime（游戏二进制依赖图内）。首跑败于 **fixture 本地 Cargo.lock
   过期**（`--locked` 拒绝更新；lock 为 git-ignored 本地件，Oct 30 23:09 旧于 T18-T1 的 jpeg
   feature 行）——**这正是方案 §四-T1-3 脚注预见的「bsn_game fixture 的 Cargo.lock 若受
   feature 传播影响则刷新」**，因无门覆盖而漏刷；QA 按脚注刷新本地锁（`cargo metadata
   --offline`，仅 zune-core+zune-jpeg 两包入闭包，备份在 /tmp/bsn_lock_backup.lock；**仓库
   零足迹**——该文件 git-ignored 亲证）→ 3/3 绿。T17 QA 偏差 4 的建议（触碰
   runtime/模板/工作区 manifest 的弧线宜将 heavy 档列入收官门）在 T18 应验，再次入册（§六-3）。
3. **jpeg 闭包传播勘定（新证据，QA 勘定非缺陷）**：T18-T1 的 workspace bevy `"jpeg"` 经
   `workspace = true` 继承链（jackdaw_api/api_internal/commands/feathers/input/localization/
   panels/widgets 家族）进入 bsn_game fixture 的**有效闭包**（cargo tree -i zune-jpeg 亲证
   激活路径）——即 fixture/生成游戏的**有效依赖闭包**已含 jpeg 解码。三点定性：①声明面
   （模板 Cargo.toml 只写 `["wav"]`，scaffold `dependency_with_features` 独立 git 行亲读
   :45-57、:2634/:5082 两处+teaches 钉死）不受影响——决策 4-A 的字面与 teaches 锚全部成立；
   ②闭包级 file_watcher 早在 T18 之前就在游戏 fixture 闭包内（备份锁 `notify-debouncer-full`
   在案）——jpeg 是同一既有传播族的新增量，非新缺陷、非新机理；③mp3/flac 仍零入闭包
   （symphonia=0）——book「MP3/FLAC 未启用」句保持为真。book §五类格式表的 JPG 模板边界句
   在声明面为真；有效闭包面该句的「游戏侧需自加 jpeg」实操指引变为不必要（但无害）——
   一句话 nuance 建议主控合入时自裁（§六-4）。

## 三、book 核对（方案 §四-T3-2 九节书单+SUMMARY+交叉引用+T2/T2.5 QA 交接）

`book/src/user-guide/assets.md`（216 行新章）逐节亲读，事实面逐条对锚源码（QA 亲验）：

| 书单项 | 源码/证据对照（QA 亲核） | 判 |
|---|---|---|
| 1 The five families（五类格式面表+导入导览+**JPG 边界如实**（编辑器 jpeg 已开全通/模板只保 wav+自加 `"jpeg"` 指引）+mp3/flac 未启用） | 扩展名族=asset_ingest classify+pick filter 面；`Cargo.toml:240 "jpeg"` 带三行注释（与书口径同源）；scaffold :2634/:5082 wav-only；模板 jpg 闭包 nuance 见 §二-3 | ✅ |
| 2 Import options（纹理 Compressed/Original 两态+`.meta` 语义+「survives an external rewrite」+sRGB 文件名启发式+模型 `.meta` LOD+无通用 import 面板如实） | file_card Import 行+texture.import op 写 meta+sRGB 启发式（texture_import.rs:35-53 方案事实十一）；M7 真机往返（shot-m7-card-compressed+console L6 PASS） | ✅ |
| 3 Hot reload 四层链（引擎同柄重载 `Reloaded` 铁证行/视口按类跟随（模型整实例重建+authored 变换保持）/材质走索引 walk 换值不换柄+unsaved 门/Project 窗+缩略图随变更路径刷新+prefab debounce+开页文档外部改动提示；**hot_reload 撞名注记**（File 菜单 Hot Reload=扩展 dylib，资产热重载无开关恒开）；**游戏侧 dormant**（模板不 watch+dev 手开 file_watcher 的路）） | CHANGE_SETTLE=300ms（asset_index.rs:837）；`Reloaded matrix/hero.glb` 在 editor:44/49；fork spawner Modified 语义（方案事实二）；File 菜单 Hot Reload 开关=lib.rs:2374-2377 亲读+hot_reload.rs 扩展 dylib（事实七）；模板无 file_watcher=事实八+§二-3 闭包 nuance | ✅ |
| 4 Thumbnails（mtime 键语义「stale thumbnail is never served」+**AR1 修复后行为**（watcher 报变更路径→失效→重渲染）+失败一 warn 写 off、改文件获新尝试+`.jackdaw/thumbnails` 可清） | thumbnail.rs:24-29/247 mtime 键 doc；respond_to_asset_changes→forget+needs_refresh（T1 QA §2 亲读链）；失败 mtime 记账 :211-216；M3/M4 真机新 mtime PNG+像素 md5（console:7/:27） | ✅ |
| 5 When a file is broken（引擎保旧值+**失败反馈双形态逐字**（log `asset load failed: … -- showing the previous content`+横幅 `<path> failed to load; showing the previous content`）+每版本一次锁+恢复无锁+**AU6 拒写门逐字**（`… is not a sound file the editor can decode; the reference was not written`+游戏进程 play 面崩溃边界如实）+**AR9 注记**（经 Compressed 重载过的纹理可见面停在首载内容=渲染侧已知缺陷；无 meta 主流链正常跟随；toggle 回 Original 或删 `.meta` 恢复）） | asset_failures.rs:80/:88 逐字；asset_row.rs:525 逐字；fork unwrap 未动=T16 回写+book「crash of that process」如实；AR9 注记与 T2.5 §8a-2 裁定逐点对应（含 M12 窗口板面 teal 的佐证观察 §六-6） | ✅ |
| 6 Renaming and moving（编辑器内=引用跟随；**外部改名=设计边界**（watcher 不猜同一性→audit 报 Missing→Missing References+Rebind 兜底）「designed boundary, not a gap」） | follow_a_move/file_ops（事实十五）+T05 决策②；reference_audit.rs:650 `Missing References` label+asset-references.md 指路；M14 检测半格 T2 绿+rebind 半格=A11 票（§8b 口径） | ✅ |
| 7 The 30-second check（六步：看 tile→外改 .glb 三面自变→改材质→写坏图片存活+旧图+横幅点名→恢复跟随→picker 拒垃圾音频；**AR9 勿演示注记收尾**（「Keep the demo on textures without import options」）） | 与 T2-T2.5 QA 交接（§8a-2 AR9 限定+§8-3 修正式）逐条对应；六步与 M3/M4/M9/M12 真机腿一一映射；「修好即恢复」限定在无 meta 图=正向演示面（T3 报告 §一-7） | ✅ |

**SUMMARY+交叉引用**：`SUMMARY.md:23` 挂目于 Asset References（:22）与 Resources（:24）之间
=资产题簇相邻（方案原话「prefabs/audio 之间」的跨度内；程序 §一如实披露实际位，§六-5）✅；
四处交叉引用逐一亲读：`prefabs.md:164`（External edits 节尾指路）、`audio.md:173`（**mp3/flac
表行**改写+指路）、`audio.md:193`（**Broken file (loud) 段改写**：picker 第一道门=拒写门，
过时话「forgiving decode is future work」已删）、`materials-textures.md:135`（gotchas 增
「saved material 不跟外改」条+指路）、`open-challenges.md:101-112`（**Asset import 条目按
T18 后现状改写**：共同格式族已入库+出链+open tails=FBX/USD、sRGB 显式开关、纹理翻转、
mp3/flac 解码、游戏侧 dev 热重载模块、**压缩纹理滞后面（AR9）**）✅。

**UI 名现场核对（防杜撰）**：`Add > Reference Image`＝Add 菜单行 `EntityAddImageOp::LABEL`
（entity_ops.rs:2785，add_entity_picker.rs:71 经 CreationTaxonomy 亲读）✅；`New Material`
＝material_browser.rs:1089 ✅；`Place GLTF`＝entity_ops.rs:2442 ✅；Project 窗 **New Asset**
菜单＝new_asset.rs:23/76（label `New Asset...`）✅；音频行 **Pick**/**Browse**＝
asset_row.rs:100/:44（`Browse...`）✅；**File > Hot Reload** 开关＝lib.rs:2374-2377 ✅；
**Missing References**/Rebind＝reference_audit.rs:650 ✅。程序自报的初稿两处杜撰勘正
（Add > Model→Reference Image 等）核为成立；章内出链目标
（materials-textures/audio/prefabs/asset-references/SUMMARY）全存在亲验 ✅。

**AR7 book 注记缺口**：方案 §一-AR7 处置列注记「book 注记『清 .jackdaw/imported 安全』」
未落章（book 只有 `.jackdaw/thumbnails` 可清句，grep 全 book 零 `imported` 命中）——⚪ 记
§六-2（AR7 本身记档不修，注记缺失不动摇任何验收面）。

## 四、验收句逐词+关键格三格复核（证据原文全读+9/9 截图亲览）

roadmap 第 32 行验收原文（逐字在案）：「PNG/JPG/GLTF(GLB)/材质/音频优先；导入选项/预览刷新/
重导入/失败反馈。验收=外部改资产视口+Inspector+缩略图正确更新；坏文件不崩不丢引用。」

### 铁证①「外部改资产→视口+Inspector+缩略图正确更新」——成立（限定注记=无 meta 主流链）

| 验收词 | 证据（QA 亲读/亲览/亲跑） |
|---|---|
| 外部改资产 | FS 脚本写盘驱动（box_glb/png_write/file_break 全在 t18-live.sh 亲读；编辑器只被动响应）——M3 双盒改写/M1 红→蓝 PNG/M4 base_color/M5 wav 内容全部脚本外部写 |
| 视口 | M3：Box 计数 1→**2**（console:5）+m3-hero-one/two 亲览（单白盒→双盒，红参考板保持）；M1：全帧像素 md5 red=5339…≠blue=1d11…（console:17） |
| Inspector | M8 单腿内文件卡 Path 行（ui_tree walk `hero.glb`+`Path` 双命中，脚本 :763-766 亲读）+M1 文件卡（shot-m1-file-card）+M4 材质卡（T2 亲看 #0DFF0D 沿用；本轮 console:28 hex 盲软检查注记如实不参与判定） |
| 缩略图 | M3：**新 mtime PNG** `bde84cd9…-18e38af96cec9db7.png`+像素 md5 fa93ba8c…（console:7，AR1 绿证）；M4：材质 tile 新 mtime+md5（console:27） |
| 正确更新/三面同腿 | **L3_M8_THREE_FACES_PASS**（console:11）：单腿内三断互不依赖手工刷新（视口 PX/卡 ui_tree/缩略图新文件+像素），m8=true 独立于 M3 ok 判定 |
| **限定注记** | 带 texture.import meta 的纹理外改视口板可停首载内容=AR9（§二-1）；铁证①「全绿」适用面=**无 meta 主流链**——T2 QA §三口径+book §5/§7 注记+30 秒勿演示注记三处落账亲读 ✅ |

### 铁证②「坏文件不崩不丢引用」——成立

- **不崩**：M10 坏窗存活（console:54 `editor alive after bad glb`）+AR8 首载坏 place 不 spawn
  （boxes=2 不变+thumbnail 写 off 恰 2 行 console:59=m10-thumbnail-lines.log 亲读
  broken_first.glb 两行）+修好 2 盒重生（editor:194 Reloaded）；M11 索引拒读 1 行保旧值
  （console:63=editor:198）；M12 坏 wav+两次重开真读 **panic=0**（console:66-69+
  editor 日志 237 行全文零 `panicked at` QA 亲扫+m12-storm-sample.log **0 字节**=零风暴
  最强形态）；M16 每坏窗 BRP 应答+pid 一致（console:42/54/62）。
- **不丢引用**：M13 场景 SHA `d22caf81…` 坏文件梯全程不变（console:85）+`jackdaw/audit`
  count=0「no broken references」（m13-audit.json 亲读）+Board/Song 实体在+重开 9 实体
  （editor:214）；AU6 拒写门=**横幅逐字+文档 grep 硬断言**（console:79-80
  `the picker refused the garbage wav`+`AudioPlayer<…>("sounds/blip.wav")` 在；
  m12-after-refusal 亲览：橙色横幅 `sounds/aaa_bad.wav is not a sound file th…`+Inspector
  字段仍 `blip.wav`）；引用存路径串=坏文件往返零写入（editor:141-146/160-163 失败行与
  SHA 链互证）。
- **「修好→恢复」半格**：M10/M11/M12 修复腿全绿；M9 板面恢复半格红=AR9（§二-1），验收句
  字面（不崩不丢引用）不涉——T2 QA §三口径沿用。
- **M15 warn 扫描**：`asset_load_failed=4 thumbnail_writeoff=2 index_refusal=1
  playface_panics=0 unexpected=0`（console:89）——QA 手数编辑器日志逐条吻合（AR3 4 行
  :145/:162/:173/:217+thumbnail 写 off 2 行:177/:184+索引拒读 1 行:198+panic 0；余下
  keymap chords/unsaved-reread/relationship 三族=归因过滤器良性族，脚本 :1177-1180 亲读）；
  warn-lines-assets.log **0 字节**=意外为零的最强形态 ✅。

### 其余验收词（优先级清单）

- **PNG/JPG**：PNG 全链 M1 PASS；JPG 绿链 loader 失败行=0（console:23）+板生成（shot
  m2-jpg-plate）——AR2 修复后全通，红证=T1 归档 InvalidImageExtension 诚实红。
- **GLTF(GLB)**：place+`.meta` LOD+三面热重载+坏文件双态全过（M3/M8/M10）。
- **材质**：换值不换柄活证=M4 tile 换图+浏览器列表原样+editor:104 `reloaded 1`；「材质不走
  AssetServer」设计如实入书。
- **音频**：M5 Reloaded 好/坏探针各 1+零 panic（console:35-38）；AU6 拒写门三度真机绿
  （T2 两轮+T3 本轮）。
- **导入选项**：M7 Compress→`.meta` 落盘→外改后选项仍生效（console:34 PASS）+模型 LOD meta
  （方案事实九②，book §2 如实）。
- **重导入**：索引域（M4/M11 walk+unsaved 门）+引擎域（M5 Reloaded 链）双通道 ✅。

## 五、QA 放行清单对照（方案验收标准+各任务 QA 裁决链）

| 条目 | 终态 |
|---|---|
| **T1 验收（AR1-AR4+AU5 落地+headless 三锚）** | ✅ QA PASS（t18-t1-qa.md：门禁亲跑+AR 逐项源码级复核+九件新单测亲跑绿） |
| **T2 验收（M1-M16/L1-L10 真机矩阵）** | ✅ QA 终轮 PASS（t18-t2-qa.md §8b：AR10/AR9/AR11 三件落判+合并前置落地后放行；前置本轮终树亲核兑现） |
| **T2.5 小修轮** | ✅（AR10 读时复验+AR9 判别复探另立+AR11 三轮定稿；§8a 复验三件两落一打回→§8b 点验转 PASS） |
| **T3 验收（14 格终态复跑+重点腿+book+全量门+AU6 回写）** | ✅ 本轮（§一/§三/§四：assets 相 15 判定 14/1亲读复核+三目标格三层证据全读+book 九节+九门亲跑+AU6 回写核） |
| **AR1 🔴 缩略图/浏览器不吃内容修改** | **已修结案（吸收）**：AssetWatchChanges 信号链（300ms settle+路径粒度 forget+needs_refresh）；真机绿=M3/M4/M8 新 mtime tile+像素 md5（console:7/:27） |
| **AR2 🔴 JPG 无解码器** | **已修结案（吸收）**：workspace features 一行+teaches 钉死；M2 真机绿；Cargo.lock 零新包（T1 QA 亲核） |
| **AR3 🟡 失败无作者态反馈** | **已修结案（吸收）**：asset_failures.rs 双形态+（path,mtime）锁；M9 warn×1 亲读（editor:145-146 逐字） |
| **AR4 🟡 文件卡文本行陈旧** | **已修结案（吸收）**：file_card 双读者→InspectorDirty；M1/M3 卡面跟随 |
| **AR5/AU6 ⚪ 坏音频 unwrap panic** | **结案（决策 1-A）**：picker 魔数校验+拒写引用（真机三度绿）；fork unwrap 维持（fork 纪律）+游戏进程 play 面边界如实（book+T16 回写双落账）；编辑器 panic 风暴三轮未复现=诚实注记非验收预期（§六-1 措辞时滞） |
| **AR6 ⚪ 外部改名不跟随** | **设计边界结案**：M14 检测半格绿（audit 报 Missing）；rebind 半格红=AR11→已修/AR12→A11 独立票（下两行）；book §6「designed boundary」如实 |
| **AR7 ⚪ 导入缓存孤儿** | **记档不修（方案口径）**；book 注记缺口 ⚪（§六-2） |
| **AR8 ⚪ 首载坏刻画** | **刻画腿结案**：M10 AR8 腿绿（place 不 spawn+写 off 2 行+存活），无新缺陷 |
| **AR9 🟡→🔴建议 meta 纹理 GPU 面冻结** | **另立渲染侧缺陷结案（T2.5 §8a-2 裁定）**：读取层排除（fresh_processed 五单测）+渲染面定位论证闭合；M9 板面半格红归它持续红证；book+30 秒勿演示注记落账；**buglist 立票留主控合入**（T3 报告 §六-7 口径，本轮零触碰=正确） |
| **AR10 🔴 读取层陈旧缓存** | **已修结案（吸收）**：fresh_processed() 读时复验（单元 5/5+真机 M9 引擎面 Reloaded=1 两轮一致） |
| **AR11 🟡 TupleStruct rebind 匹配** | **已修结案（三轮定稿）**：matcher 放宽+audit 真拼写测试助手；§8b 点验 2/2 亲跑 |
| **AR12 世界侧粘性** | **=buglist A11 独立票**（主控裁定不追入本轮）：归档三件×票面一致性核 ✅（§8b-2）；A11 未勾选=正确，独立小任务 |
| **关联票纪律** | A6（维持「已定案环境票」放行口径，本轮 QA 两轮复现同签名+隔离绿再证）/A7（不前置，脚本 `$PHASE` 日志名+软检查不参与判定教训延续）/A9（自守，settle+idle 探针）/A10（无 PIE 主链零暴露）/A11（独立票未动）——**全部未打钩=正确** ✅ |
| **buglist/roadmap/台账纪律** | T3 提交触碰零 buglist/台账/roadmap（numstat 亲核）；roadmap 第 32 行未勾（留主控）；台账无 T2/T2.5/T3 行（留主控）；buglist AU6/AU8 零条目亲证（grep EXIT=1）✅ |

## 六、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 事实 | 处置 |
|---|---|---|---|
| 1 | **AU6 回写轮数时滞**：t16-audio.md AU6 条目写「T18 **两轮**真机（T2 五窗+QA 亲跑）均未复现 play 面 panic 风暴」，而 T3 终态=第三轮复跑（console:66-67 panic=0「noted honestly」）；T3 提交信息自称「across three live rounds」、报告 §二括注「+本轮第三轮」 | 回写文本写于第三轮复跑之前未随终态刷新；实质（未复现+诚实注记+非验收预期+fork 维持+游戏进程边界）四处全数成立 | 措辞级勘误随本报告入档；建议主控合入时把「两轮」改「三轮」（一处 token，改后无需复验） |
| 2 | **AR7 book 注记未落**：方案 AR7 处置注记「book 注记『清 .jackdaw/imported 安全』」，book 章 grep 零命中 | AR7 本身记档不修、低频低危；thumbnails 缓存可清句在章，imported 缓存句缺 | 一句话级；主控合入时顺手补或接受（不动摇任何验收面） |
| 3 | **heavy 档全弧未跑+fixture 本地锁过期**：integration 门结构性排除 bsn_game_run（命令行亲读），T18 四轮无一跑过；QA 补跑首败=fixture 本地 Cargo.lock（git-ignored 本地件）过期于 T18-T1 jpeg 行——方案 T1-3 脚注预见的效果无门覆盖而漏刷 | QA 刷新本地锁（备份 /tmp/bsn_lock_backup.lock，仓库零足迹）→ **3/3 绿终树补腿**；T17 QA 偏差 4 建议再次应验 | 已由 QA 闭合；建议入册：后续触碰 runtime/工作区 manifest 的弧线，收官门含 bsn_game_run |
| 4 | **jpeg 闭包传播 nuance**：T18-T1 jpeg 经 workspace 继承（jackdaw_api 家族）进入游戏 fixture 有效闭包（zune-core/zune-jpeg 入锁）——book JPG 模板边界句在声明面为真、有效闭包面「自加 jpeg」指引不必要；同族 file_watcher 传播 T18 前已存在（备份锁 notify-debouncer 在案），非 T18 新机理 | 声明面 teaches/scaffold 锚全部成立；mp3/flac 仍零入闭包 | ⚪ 记档；主控可裁在 book §1 补一句 nuance 或维持声明面口径（验收句游戏侧不在字面） |
| 5 | **QA 第一门链被 harness 1h wall cap SIGKILL**（integration 中段，480 not run due to signal）：被杀轮 4976 run 4975 passed 1 failed=同一 A6 同签名 | 与 T17 QA §六-5 同款基建注记；被杀轮全文保全作旁证 | 与终轮两轮互证后第二链跑完全程 |
| 6 | **M12 窗口板面 teal 佐证观察**：m12 两张截图板面显 teal（M9 修复内容），而 M9 三窗恒蓝=AR9 红 | M12 腿含 scene.save+scene.open 重开（editor:207-226）——新鲜装载路径重建板面，AR9 的冻结面=同柄原地重载路径（其裁定范围即如此）；红判定在 M9 窗口内的判别协议下做出，无矛盾 | 佐证 AR9 范围限定，不立新缺陷；建议 A9/AR9 修复红绿脚本可加「重开即跟」对照腿 |

**未动面**：`src/`（编辑器）、`crates/`（产品）、fork（pinned rev 亲证干净）、协议、场景格式、
模板/fixture 入库件——T3 零改动（T18 全弧产品面=T1 的编辑器五件+feature 行+T2.5 的
runtime texture_import+missing_list+tests，T3 纯 book+loop）；buglist/台账/roadmap 本轮未写
（主控合入时落笔）；工作树仅 QA 归档 12 件变更/新增+本报告（`git status` 全量亲录）。

## 七、最终裁决与 roadmap 建议

- **T18-T3 验收标准（方案 §四-T3）**：14 格终态复跑+重点腿（assets 相 15 判定 14 PASS，三
  目标格全在且证据原文全读亲览，M13 SHA 链/M15 warn 扫描/M16 存活随相附带全绿；唯一 FAIL=
  AR9 已知红非新缺陷）✅；book 新章九节+SUMMARY+交叉引用 ✅（§三）；AU6 结案回写 ✅（§五，
  一处措辞时滞 §六-1）；buglist/台账/roadmap 留主控 ✅；终验门全量日志 QA 亲跑复现 ✅（§一）。
- **T18 整体（T1/T2/T2.5/T3）**：验收句逐词全数在案（§四）；铁证①单腿三断独立+铁证②
  SHA/audit/组件 grep 三面独立成立；AR1-AR11+AU6 结案清单全绿（§五）；门禁双轮吻合
  （fast/libtests 3001+teaches 91、integration 5455/5456 唯一红=A6 定案口径 QA 两轮复现同
  签名+隔离绿、heavy 档 bsn_game_run 3/3 补腿）；T1/T2/T2.5 三轮 QA 裁决链闭环（PASS→PASS
  （含返工两轮）→T3 终验）。
- **VERDICT: PASS——T18 整体闭环。roadmap T18（第 32 行）建议可勾选**，闭环注记建议含：
  验收句逐词证据（三面同腿 witness+坏文件双态+SHA/audit 铁证）；AR 终态（AR1-AR4/AR10/AR11
  修+A5/AU6 决策 1-A 结案+AR6 边界+AR7/AR8 记档+AR9 另立渲染侧票随合入立账+A11=AR12 独立票）；
  integration 5455/5456 唯一红=A6（QA 两轮复现同签名+隔离绿，定案口径）+heavy 档 bsn_game_run
  3/3 QA 补腿（fixture 本地锁刷新一次性）；book 九节新章+四处交叉引用+AU6 回写；⚪ 偏差六项
  不阻塞（AU6 回写「两轮」→「三轮」一处勘误随合入落笔）。
- **主控合入路径**：照旧 `--no-ff`（T3 单提交 9a7f02b0 随 T2/T2.5 之后）；主控落笔面=T3 报告
  §六-7 清单（roadmap 勾选+收官行、台账 T18 行、buglist 如实记档：AR9 渲染侧票+AR7/AR8 ⚪
  记档+AU6 处置已回写核对、A6/A7/A9/A10/A11 不打钩）+本报告 §六-1 的「两轮→三轮」一处勘误
  +§六-2 可选 AR7 book 句+§六-4 可选 JPG 闭包 nuance 句。

## 八、用户 30 秒清单（book §The 30-second check 的实机版，T3 真机腿一一对映）

1. **看 tile**：开一个带模型/材质/参考图的工程（新工程模板自带）——Project 窗三类 tile 在。
2. **外改 .glb**：外部工具改模型的 `.glb` 并保存——一拍之内：视口实例重建、文件卡跟随、
   tile 渲出新形状（铁证①三面同腿真机形）。
3. **改材质**：改 `.material.bsn` 的 `base_color`——tile、浏览器和每个用它的面换新。
4. **写坏图片**：用垃圾字节覆写一张在用图片——编辑器不死、板面保持旧图、状态栏点名：
   `… failed to load; showing the previous content`。
5. **恢复**：写回好字节——重载跟上修复（无 meta 图=正向演示面）。
6. **拒垃圾音频**：给音频行 Pick 一个坏 `.wav`——picker 拒绝并警告，引用一字不写。
   *（演示勿用带 Compressed `.meta` 的纹理：其可见面是唯一已知滞后角=AR9，见书内注记。）*

## QA 会话产物索引

- 门禁九门+heavy 补腿+旁证轮：`loop/reports/t18t3_qa_{fmt,libtests,fast,audio_gate,
  save_store,integration,a6_isolated,doc,scaffold_e2e}.log`（亲跑覆盖/新增归档）+
  `t18t3_qa_integration-signal_cap_red.log`（harness cap 旁证轮全文）+
  `t18final_qa_{bsn_game,bsn_game_run,gates_progress}.log`（heavy 腿首探/绿证/门链时间线）。
- 核验对象：`loop/reports/t18-t3-report.md`+归档 t18t3_* 26 件（console/editor/summary/warn
  两空件/m13-audit/m9-ar3/m10-thumbnail/m12-storm 空件+截图 9 张全览）+T1/T2/T2.5 报告与 QA
  （含 §8a/§8b）+`loop/reports/t16-final-qa.md`（移交出处）+`loop/plans/t16-audio.md` AU6
  条目（回写核对对象）+buglist A6/A7/A9/A10/A11+roadmap 第 30/32 行；book 六文件+
  源码对照点（asset_failures/asset_row:525/asset_index:837/thumbnail/Cargo.toml:240/
  scaffold:2634/:5082/add_entity_picker/entity_ops/material_browser/new_asset/lib.rs:2374/
  reference_audit:650/missing_list.rs:695）；t18-live.sh 关键段（M3/M8 三面腿/M15 归因过滤
  器/retrigger 预案）；修复 diff 面（`git show 9a7f02b0 --numstat` 全件+T2.5 两提交）；
  fork 树（干净+9cb82e77e）；bsn_game fixture 闭包勘定三件（备份锁/cargo tree/diff）。
- 进程收尾：QA 复查零 jackdaw/nextest/cargo 残留进程；fork 零触碰；`JACKDAW_SAVE_DIR`/环境
  零残留；df=21Gi（清 target/bsn_game_run 12G+incremental 9.2G 后）；门链独窗；
  RUST_BACKTRACE 全程未设；工作树除 QA 归档外零触碰（fixture 本地锁=git-ignored 本地件，
  已在 §六-3 披露）。

—— QA agent（loop 自动化终验），2026-10-31
