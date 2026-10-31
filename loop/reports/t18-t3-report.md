# T18 任务 3「终验 + book 章 + AU6 结案」程序报告

> 分支 `loop/t18-assets`（`git merge main` 快进到 e21d4c06，T2+T2.5 已在；T3 零 src/、零
> crates/ 产品改动）；方案 `loop/plans/t18-assets-hotreload.md` §四-T3。真机 macOS arm64，
> fixture `/Users/zhanglinbo/workspace/loop-mac/t18-assets/t18-assets`（BRP 15703），全程未设
> RUST_BACKTRACE，编辑器二进制先 `cargo build --bin jackdaw` 重链（T2.5 教训执行）。
> **判语：book 资产新章落地（含 T2 QA 交接的 AR9 限定与 30 秒清单修正全部入章）；AU6 按
> T16 移交口径结案回写；关键格终态复跑 assets 相 15 判定 14 PASS、唯一 FAIL=AR9 已知红
> （T2.5 §9.6 同形，四面绿含 AR10 引擎面）；全量九门绿——integration 5455/5456 唯一红=
> A6 已知件（隔离 1/1 绿），0 新增红。** buglist/台账/roadmap 未动（主控合入时落笔）；
> A10/A11 票无动作。日期 2026-10-31。

## 〇、最终判定汇总

```
真机（prep+assets 相，15:38-15:52）: L3_M3_GLB=PASS L3_M8_THREE_FACES=PASS
  L7_M10_BAD_GLB=PASS L8_M12_BAD_AUDIO=PASS L8_AU6_PICK_GATE=PASS
  M13_INTEGRITY=PASS M15_WARN_SCAN=PASS（意外=0）+同相 M1/M2/M4/M5/M7/M11 全 PASS；
  唯一 FAIL=L7_M9_BAD_PNG（板面恢复半格=AR9 已知红，非新缺陷）
门禁（终树）: fmt ✅ / clippy 全仓 ✅ / clippy 物理双包 ✅ / libtests 3001/0 ✅
  / fast 3001/3001 ✅ / integration 5455/5456（唯一红=A6，隔离 1/1 绿）✅
  / doctests（bind dyld 第 11 次目击→单包复跑绿）✅ / docs EXIT=0 ✅ / scaffold_e2e 1/1 ✅
```

归档：`loop/reports/t18t3_*`（26 件：真机 console/editor/summary/warn/m13-audit/m9-ar3/
m10-thumbnail/m12-storm 空件 + 截图 9 张 + 九门日志 + A6 隔离件）。

## 一、book 新章（方案 §四-T3-2 全项 + T2/T2.5 QA 交接）

**`book/src/user-guide/assets.md`**（新章，SUMMARY 排 Asset References 与 Resources 之间——
prefabs/audio 跨度内、资产题簇相邻），九节：

1. **The five families**——五类格式面表（Images png/jpg/jpeg/webp/bmp/tga/ktx2、Models
   gltf/glb、Materials `.material.bsn`、Audio ogg/oga/wav、Definitions）；**JPG 边界如实**
   （编辑器 jpeg feature 已开=导入/显示/缩略图/热重载全通；**游戏模板只保 wav**，游戏侧
   装 jpg 需自加 `"jpeg"`——AR2 决策 4-A 原文）+mp3/flac 未启用。
2. **Import options**——纹理 Compressed/Original 两态+`.meta` 语义+「重导入仍尊重选项」+
   sRGB 文件名启发式（`_albedo/_normal`）；模型 `.meta` LOD；「无通用 import 面板」如实。
3. **Hot reload: edit the file, watch the editor follow**——**四层链**：引擎同柄重载
   （`Reloaded` 行=铁证行）/视口按类跟随（图换像素、glTF 整实例重建、authored 变换保持）/
   材质走索引 walk 换值不换柄（材质不走 AssetServer 的设计如实+unsaved 门）/Project 窗+
   缩略图随变更路径刷新+prefab debounce 重载+开页文档外部改动提示；**hot_reload 撞名注记**
   （File 菜单 Hot Reload=扩展 dylib，资产热重载无开关恒开）；**游戏侧 dormant**（模板无
   file_watcher=发货克制设计态；dev 手开 feature 的路在）。
4. **Thumbnails**——mtime 键语义（陈旧缩略图永不误用）+**AR1 修复后行为**（watcher 报告
   变更路径→缓存失效→tile 重渲染）+失败一 warn 写 off、改文件获新尝试+`.jackdaw/
   thumbnails` 可清。
5. **When a file is broken**——引擎保旧值（重载失败不删旧资产+引用是路径串+文档字节不动）
   +**失败反馈双形态**（日志 `asset load failed: … -- showing the previous content` 逐字+
   状态栏横幅 `<path> failed to load; showing the previous content`）+每 (path,mtime) 一次
   锁+恢复无锁可清+**AU6 拒写门**（`… is not a sound file the editor can decode; the
   reference was not written` 逐字+游戏进程 play 面崩溃边界如实）+**AR9 注记**（经
   Compressed 重载过的纹理可见面停在首载内容=已知渲染侧缺陷；无 meta 主流链正常跟随；
   演示勿用带 meta 纹理）。
6. **Renaming and moving**——编辑器内=引用跟随（T05 面）；**外部改名=设计边界**（watcher
   不猜同一性→audit 报 Missing→Missing References **Rebind** 兜底）——asset-references
   指路。
7. **The 30-second check**——六步（开工程看 tile→外改 .glb 三面自变→外改材质→写坏图片
   →编辑器不死+旧图保持+横幅点名→恢复跟随→picker 拒垃圾音频）；**AR9 勿演示注记**收尾
   （按 T2-QA §8a-2 限定与 §8-3 修正式撰写；AR10 已修故「修好即恢复」对无 meta 图恢复
   为正向演示面）。

交叉引用落地：`SUMMARY.md` 挂目；`prefabs.md`（External edits 节尾指路 assets.md）；
`audio.md`（**Broken file (loud) 段改写**：picker 第一道门=T18 拒写门，删「forgiving
decode is future work」过时话；**mp3/flac 表行**指路 assets.md）；`materials-textures.md`
（gotchas 增「saved material 不跟外改」条+指路）；`open-challenges.md`（**「Asset import
beyond GLTF」条目按 T18 后现状改写**：共同格式族已入库，open tails=sRGB 显式开关/纹理
翻转/mp3-flac 解码/游戏侧 dev 热重载模块/压缩纹理面滞后——决策 6-B/8-B 的一句话记账）。
出链七目标逐一核实存在；UI 名现场核对（`Add > Reference Image`=entity.add.image label、
`New Material`=material.create label、Place GLTF=operator label——防杜撰，偏差 7）。

## 二、AU6 结案回写（方案点名 T3 义务）

**位置：`loop/plans/t16-audio.md` §缺陷矩阵 AU6 条目（处置列）**。回写内容：

- ~~记档不修~~ → **已结案（T18-T3 处置回写 2026-10-31）**；
- **决策 1-A 探针形态落地**：编辑器侧导入校验（`asset_row` 音频 pick 提交前魔数校验
  RIFF/OggS），坏文件状态栏 warn+**拒写引用**（横幅文案逐字在案，T18 真机 M12 绿证——
  本轮第三度复现：`t18t3_shot-m12-after-refusal.png` 橙色横幅+字段仍 blip.wav）；
- **fork `unwrap()` 维持不动**（fork 纪律）⇒ 游戏进程 play 面对坏字节仍会崩——book 注记
  的已知边界；编辑器进程 panic 被 error_handler 兜住，且 T18 两轮真机（T2 五窗+QA 亲跑
  +本轮第三轮）均未复现 play 面 panic 风暴（如实注记，非验收预期）。

**buglist 核验**：根 `buglist.md` grep AU6/AU8/音频=零条目（AU 系编号只存在于 t16 方案与
roadmap 收官行）——无对应条目，**buglist 零动作**（任务口径亦如此）。t16-t3-report.md 的
移交措辞（§一-7「AU6 现状如实」）为历史记录不改；roadmap 不动（主控合入时写）。

## 三、关键格终态复跑（方案 §四-T3-1 的抽腿口径：M3/M8 三面同腿、M12+AU6 拒写门、M10 坏 GLB）

`bash loop/qa/t18-live.sh prep && … assets` 单相全量复跑（15 判定；三目标腿全在其中，
M13 SHA 链/M15 warn 扫描/M16 存活随相附带）。**14 PASS / 1 FAIL（FAIL=AR9 已知红）**：

| 腿/格 | 本轮数值 | 与 T2/T2.5 对齐 |
|---|---|---|
| **L3_M3_GLB + L3_M8_THREE_FACES**（铁证①全称量词） | 摆放=恰 1 盒→外写双盒（**一次 A6 丢事件→脚本预案再触发一次**，日志明示）→**Box0/Box1=2**（视口重生）+文件卡 Path 行+**新 mtime 缩略图** `bde84cd9464a4db4-18e38af96cec9db7.png` 像素 md5 `fa93ba8c…`（AR1 绿证）| 三面同腿全绿与 T2/T2.5 同形；缩略图名随 mtime 浮动 |
| **L7_M10_BAD_GLB**（铁证②坏 GLB） | 坏窗 `Reloaded`=0（拒载）+`Failed to load` =2+旧实例保持（2 盒不动）+存活；AR8 首载坏：place 不 spawn+`thumbnail:` 写 off 恰 2 行+存活；修好→2 盒重生 | 与 T2 逐项同形 |
| **L8_M12_BAD_AUDIO + L8_AU6_PICK_GATE**（AU6 处置证据） | 坏 wav+scene 重开真读→**panic=0**（第三轮未复现，诚实注记）；恢复+重开=0 增长；**拒写门**：picker 过滤 aaa_bad→点击→横幅 `is not a sound file the editor can decode` 命中+**文档仍 `AudioPlayer<…>("sounds/blip.wav")`**（盘 grep 硬断言） | 拒写门绿三度一致（T2 两次+本轮）；panic 面注记维持 |
| M13_INTEGRITY（附带） | 场景 SHA `d22caf81…` 坏文件梯全程不变+`jackdaw/audit` count=0+Board/Song 在 | 与 T2 双相绿一致 |
| M15_WARN_SCAN（附带） | `asset_load_failed=4 thumbnail_writeoff=2 index_refusal=1 playface_panics=0 unexpected=0`——4 条失败行逐条归因设计窗（board.png 坏×1、hero.glb 坏×1、broken_first 首载坏×2）；词表全量复扫（`AudioPlayer` 泛型/`scene component`/`game save:`/`UnresolvedTypes`/`cannot-apply`/`panicked at`）**全零** | 与 T2 预期列 7/2/1/0/0 同族（本轮 M5 探针窗并入故 4） |
| L7_M9_BAD_PNG（同相在跑） | **四面绿**：存活 ✅/旧内容保持（crop md5 恒等）✅/AR3 warn ×1（mtime 锁）✅/**AR10 引擎面 Reloaded=1**（T2.5 修复面再证）✅；红=板面恢复（fixed crop=broken crop）→**AR9** | 与 T2.5 §9.6 归档形态逐位一致——**唯一 FAIL=已知渲染侧缺陷，非新红** |
| 其余同相腿（附带） | M1 拖放+改写、M2 JPG、M4 材质、M5 音频 Reloaded、M7 导入选项、M11 坏材质全 PASS | 14/15 整相与 T2.5 判定表同形 |

**N13 记数**：本轮编辑器日志 `panicked at`=0（无 PIE 腿；N13 家族=PIE drain 面本轮零暴露，
记数即口径）。进程清理：pgrep 复核零残留。磁盘：真机门前 20Gi→门后清盘 22-30Gi 波动
（偏差 6 有低压记录）。

## 四、门禁（终树；日志归档 `loop/reports/t18t3_qa_*`，全文复核 exit 仅辅助）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0，零输出 | t18t3_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，0 warning 行 | t18t3_qa_clippy.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | t18t3_qa_clippy_physics.log |
| 单测 | `cargo test --workspace --lib --features dylib` | ✅ **3001 passed / 0 failed**（58 二进制求和亲算；**scaffold lib=91**——teaches 91 计数器与 T17-T2 一致，零扰动） | t18t3_qa_libtests.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，**Summary: 3001 tests run: 3001 passed, 0 skipped**（80.4s）；全文 error 词扫描仅测试名假阳性 | t18t3_qa_fast.log |
| integration | `cargo xtask integration` | ✅ **5456 run: 5455 passed, 1 failed**（47.1 min）；唯一红=`prefab_lifecycle::prefab_file_change_triggers_reload`（A6 已知件，3 try 同签名满载 flake）；**隔离复跑 1/1 绿（4.07s）**=`t18t3_a6_isolated.log`——**A6 口径 0 新增红达成** | t18t3_qa_integration.log |
| doctests | `cargo test --workspace --doc` | ✅ 全包跑完（包集与 T17 归档逐一相同）；`jackdaw_bind` dyld `libstd-*.dylib not loaded` **第 11 次目击**→**T15 处方单包复跑 `-p jackdaw_bind --doc` 1/1 绿** | t18t3_qa_doctests.log + t18t3_qa_doctests_bind_rerun.log |
| docs | `cargo doc --workspace --no-deps` | ✅ EXIT=0；17 条 `private_intra_doc_links` 警告=**T17 归档同数同族**（本轮零 src/ 改动，预存树态） | t18t3_qa_doc.log（对照 t17t3_doc.log） |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | ✅ **1/1 PASS**（171.5s）EXIT=0 | t18t3_qa_scaffold_e2e.log |

注：integration 总数 5456（T17 时代 5440）=T18 新增集成件（texture_import 5 件等）自然
增长；failed=1 的计数与 T17 终树「5439/5440 唯一红=A6」完全同构。

## 五、偏差清单（如实）

1. **⚪ L7_M9_BAD_PNG FAIL=AR9 已知红**（非新缺陷）：板面恢复半格红为 T2.5 另立的渲染侧
   缺陷的本轮持续红证；四面绿含 AR10 引擎面再证。无新 AR 编号。
2. **⚪ 单相复跑**：协调者抽 3 腿口径（M3/M8、M12+AU6、M10 全在 assets 相）→本轮跑
   prep+assets；docs 相（M14 外部改名+M13 重开）未复跑——M14 检测半格 T2 已绿、rebind
   半格红=A11 票留档（主控已裁不追入本轮），无需重证。
3. **⚪ M3 一次 A6 丢事件再触发**：脚本预案内（`retrigger_if_silent`，同内容新 mtime=
   新触发，非时序赌 retry）；A6 家族形态与 T2 各轮一致。
4. **⚪ M12 panic 面第三轮未复现**：编辑器音频 sink 构建对重载坏源的形态与 T16 时代读法
   的差异维持「诚实注记、非验收预期」口径；AU6 活修（拒写门）三度真机绿。
5. **⚪ doctests bind dyld 第 11 次目击**：T15 处方（单包复跑）有效，双日志归档。
6. **⚠️ scaffold_e2e 窗口磁盘低压（1Gi）**：该门构建期磁盘一度见底（incremental 复燃+
   陈旧 fixture 缓存），**门本身已完成绿（日志 171.5s 完整 PASS，未受扰）**；跑后立即
   清盘（`target/debug/incremental` 9.8G+陈旧 `target/bsn_game_run` 17G+`target/
   export_moved` 896M——均可再生构建缓存）→23Gi。教训入 QA 注意事项 5。
7. **⚪ book UI 名防杜撰核对**：初稿「Add > Model / New Asset > Material」与源码 label
   不符，现场核对改「Add > Reference Image」（entity.add.image）、「New Material」
   （material.create）；Add 菜单无模型项（模型入路=拖放+Place GLTF）如实写。
8. **⚪ docs 17 条警告为预存树态**：与 T17 归档同数同族，本轮零产品改动，不修不扩。
9. 其余零偏差：fork 零改动、协议/场景格式零变更、buglist/台账/roadmap 零触碰、
   RUST_BACKTRACE 全程未设。

## 六、给 QA 终验的注意事项

1. **门禁复核顺序**：`t18t3_qa_integration.log` 末行 Summary（5455/5456+唯一红 A6）→
   `t18t3_a6_isolated.log`（隔离 1/1 绿）→ fast/libtests/fmt/clippy 各 log 全文→
   doctests 双 log（bind dyld 家族+单包复跑绿）→ docs（17 条预存警告对照 t17t3_doc.log）。
2. **真机证据复核**：`t18t3_console-assets.log` 全读（三目标腿+M13+M15 判定行在）；
   截图亲看=shot-m3-hero-two（双盒）、shot-m12-after-refusal（橙色横幅+blip.wav 字段）、
   shot-m10-hero-good/broken；`t18t3_shot-m9-board-fixed.png` 为 AR9 红证（板面未跟新色）。
3. **唯一预期红双件**：真机 L7_M9_BAD_PNG=AR9（板面半格；引擎 Reloaded=1 是绿的），
   integration 唯一红=A6（隔离绿）。**两者之外出现任何红=新缺陷。**
4. **AU6 双面口径**（结案回写已落 t16 方案）：拒写门=真机绿三度（横幅逐字+文档 grep）；
   play 面 panic=三轮未复现的诚实注记+fork unwrap 静态红在案。**勿把「修后无 panic」
   写成验收预期。**
5. **复跑口径**：`cargo build --bin jackdaw` 先行（陈旧二进制 dyld 死教训）→
   `bash loop/qa/t18-live.sh prep && … assets`；**门前 df≥10Gi 复核**（本轮低压记录见
   偏差 6；scaffold_e2e/integration 是耗磁盘大户）；勿设 RUST_BACKTRACE；门禁与真机
   不同窗；结束 pkill+pgrep 复核。
6. **book 校对锚**：章内断言对照 `src/asset_failures.rs`（双形态文案+mtime 锁）、
   `src/inspector/asset_row.rs:525`（拒写门文案）、`src/asset_index.rs` AssetWatchChanges
   （300ms settle+路径粒度失效）、`src/thumbnail.rs`（mtime 键+写 off）、`Cargo.toml`
   features（jpeg/wav 注释原文）、`crates/jackdaw_scaffold/src/lib.rs`（模板 features
   只 wav）；30 秒清单与 T2-T2.5 QA 交接（§8a-2 AR9 限定+§8-3 修正式）逐条对应。
7. **主控合入时落笔面**（本程序未动）：roadmap T18 勾选+收官行、台账 progress.md 记行、
   buglist 如实记档（AR9 渲染侧票+AR7/AR8 ⚪ 记档；A10/A11 票无动作、A6 维持放行口径）。

## 七、产物清单

- `book/src/user-guide/assets.md`（新章）+ `book/src/SUMMARY.md`（挂目）
- `book/src/user-guide/{prefabs,audio,materials-textures}.md`（交叉引用三处；audio 含
  两处过时话改写）+ `book/src/developer-guide/open-challenges.md`（条目 7 按后现状改写）
- `loop/plans/t16-audio.md`（AU6 条目处置列结案回写）
- 归档 `loop/reports/t18t3_*`（26 件：门禁九 log+A6 隔离件+真机 console/editor/summary/
  warn/audit/lines 8 件+截图 9 张）；`loop/t18-live/` 工作目录随本轮刷新入库
