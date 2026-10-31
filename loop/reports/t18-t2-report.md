# T18 任务 2「真机矩阵轮」程序报告

> 分支 `loop/t18-assets`（续做；`git merge main` 快进到 e01f735b，T1 已合入）；方案
> `loop/plans/t18-assets-hotreload.md` §二/§三/§四-T2（M1-M16 格表+L1-L10 腿定义逐条）。
> T1 交接口径全部执行：M3/M4/M8 红段不复现（红证=T1 归档），绿段必断；M15 预期列按
> QA 口径（`asset load failed:`/缩略图写 off/AU6 拒写文案只在编辑器真机日志/状态栏）；
> 磁盘门前清盘（运行前清出 62Gi：删除已闭环 T17 fixture 39G + target/debug/incremental
> 15G）。buglist/台账/roadmap 未动（T3 职责）。日期 2026-10-31。

## 0. 一句话结论

**真机矩阵 17 腿 15 PASS**：铁证①（外部改资产→三面更新）的 M3/M8 单腿三面同断绿、
M1 PNG/M4 材质全链绿、M2 JPG 绿链（红=T1 归档）、M7 导入选项往返绿、M5 音频重载链绿；
铁证②（坏文件不崩不丢引用）的 M10/M11/M12 存活+保旧+反馈绿、M13 SHA+audit 零 Missing
双相绿、M16 全程存活；M15 两相 warn 扫描零意外（预期列 7/2/1/0/0 全归因）；AU6 拒写
门真机绿（状态栏点名+引用未写）。**两腿红、均立为新缺陷（只记不修，AR10/AR11）**：
M9 恢复半格（坏 PNG 修好后引擎不再重载该文件——AR10）与 M14 rebind 半格（tuple-struct
组件引用 audit 可报 Missing 但 rebind 链不重写——AR11）。另 AR9（texture.import meta
使外改不再到达视口板）以专项探针红证归档。门禁七门全绿（fmt/全仓 clippy/物理双包
clippy/libtests 2999/xtask fast 2999/受影响域 5 腿）。

## 1. 真机环境与驱动面

- fixture=`/Users/zhanglinbo/workspace/loop-mac/t18-assets/t18-assets`（`jd new` 模板，
  自带 sounds/*.wav+Scene Camera 注记）；资产族全脚本化：PNG（python3 手拼 zlib/struct）、
  JPG（sips 转换）、GLB（手写 glTF 二进制，Box0..BoxN 节点命名，单盒/双盒两态）、WAV
  （python3 wave 正弦）、坏字节（头四字节覆写/非 RIFF 伪装）。
- 脚本 `loop/qa/t18-live.sh`（phase: prep|assets|docs|all；t16-live.sh 形态：分相+leg/
  summary/trap+`$PHASE` 日志名 warn 扫描+A6 五纪律注释在头）。**A6 五纪律执行**：单触发
  源/外写后 settle 4s/断言预算有界超时即 FAIL/门禁与编辑器零同窗（PIE 预构建以
  `JACKDAW_PIE_PREBUILD=0` 抑制，门禁在编辑器杀死后单跑）/门前清盘。
- 关键驱动面（本轮实测钉死，脚本头注释在案）：外部拖放注入=`world.write_message`
  `bevy_window::event::FileDragAndDrop`（DroppedFile）——**工程内路径只触发选中（W8 修复
  的行为），生成视口板必须投工程外路径且光标在视口内**；glTF 重实例化按 Box0/Box1 节点
  Name 计数（respawn 重排子树实体 id）；引擎热重载的铁证行=AssetServer 的
  `Reloaded <path>` INFO；缩略图缓存名=FNV-1a(绝对路径)+mtime 纳秒（重渲染=新文件，
  AR1 绿证）；音频柄不反射不可经 BRP 读（Uuid 面归 T1 headless 锚）。

## 2. 矩阵逐格判定（M1-M16）

| 格 | 判定 | 铁证（最终 `all` 轮 + 归档） |
|---|---|---|
| M1 PNG 三面 | ✅ | 拖放链：drop 注入→`t18-drop-src.png` 导入+参考板生成（refimage 计数 1→2+R 路径断言+PX）；外写 red→blue：视口全帧像素 md5 变化+Board 引用原样+文件卡 Path/Texture 行在（AR4 面）；`Reloaded matrix/board.png` 在案（shot-m1-board-red/blue/drop-plate/file-card） |
| M2 JPG | ✅ | sips 真 JPEG 投放→板生成（`t18-tone-src-2.png`）、loader 失败行 0（绿链）；红=T1 归档 `t18t1_jpg-probe_red.log`（InvalidImageExtension），本分支 jpeg feature 在（shot-m2-jpg-plate） |
| M3 GLB 三面 | ✅ | place→恰 1 盒（Name 计数）；外写双盒（watcher 丢事件一次→按脚本再触发一次，A6 家族形态，日志在案）→**Box0/Box1=2**（视口重生）+文件卡 Path 行+**缩略图新 mtime PNG+像素 md5 变化**（`bde84cd9464a4db4-18e37ec9a6cedd2b.png`，AR1 绿证）；`Reloaded matrix/hero.glb`（shot-m3-hero-one/two） |
| M4 材质 | ✅ | material.create→save→asset.open→asset.set red→save（编辑器自己的机器写入文件）→外写 green→**缩略图新 mtime PNG+像素 md5 变化**+浏览器列表保有 redshift+文件卡 base_color 现场读到重写后的 `#0DFF0D`（换值不换柄的活证） |
| M5 音频 | ✅ | 外写 blip.wav→`Reloaded sounds/blip.wav` ≥1（引擎同柄重载）；坏字节探针仍 Reloaded（装载只存字节，设计内无失败事件）+零 panic+引用原样。无听感面=静音门设计态，如实注记 |
| M6 柄稳定 | ✅（活证+锚） | 活证=M4 卡片现场读到换值（同柄新值）+M5 Reloaded 同柄重载行；柄 Uuid 不变的面由 T1 fs e2e 锚 headless 钉死（BRP 对 Handle 无 ReflectSerialize，真机不可读，QA 口径注记） |
| M7 导入选项 | ✅ | texture.import→`.meta` 落盘+文件卡 "Compressed, mipmaps"→外写源 PNG→`.meta` 仍在+卡面仍是 Compressed 行（选项被重导入尊重） |
| M8 三面同腿 | ✅ | =M3 单腿内视口（Box 计数+PX）+Inspector（文件卡）+缩略图（MD5）三断全绿，互不依赖手工刷新 |
| M9 坏 PNG | ⚠️ 半红 | 存活（pid+BRP）✅、旧内容保持（board 区域 crop md5 相等）✅、AR3 反馈（`asset load failed:` ×1，mtime 锁一次）✅、引用原样 ✅；**恢复半格红**：修好（+再触发+touch 第三种触发形态）后引擎零 `Reloaded`、板区域 md5 不变→**AR10**（§4） |
| M10 坏 GLB | ✅ | 坏窗口：`Reloaded`=0（拒绝）+`Failed to load asset 'matrix/hero.glb'` ≥1（引擎负面行）+旧实例保持（Box 计数不变）+存活；AR8 首载坏刻画：坏文件直接 place→不入场景+`thumbnail: …broken_first.glb could not be photographed` ×2（写 off 不吊死）+编辑器存活；修好→2 盒重生 |
| M11 坏材质 | ✅ | 非法 bsn→存活+索引自述 `matrix/redshift.material.bsn no longer holds a type this project knows` +浏览器列表保有 redshift→修好→卡面回到 redshift |
| M12 坏音频 | ✅（含诚实注记） | 坏 wav+scene 重开（save 后 reload 真读）→**零 panic 行**（5 个编辑器窗口一致；见 §6 偏差 4 的诚实注记）；恢复+重开→panic 不增长；编辑器存活；文档引用原样。**AU6 拒写门绿**：picker 过滤 aaa_bad→点击→状态栏 `sounds/aaa_bad.wav is not a sound file the editor can decode; the reference was not written`+字段仍 blip.wav（shot-m12-audio-picker/after-refusal） |
| M13 不丢引用 | ✅ 双相 | assets 相：坏文件梯全程场景 SHA 不变（prep 快照=终态）+`jackdaw/audit` count=0+Board/Song 实体在；docs 相：重开 Board 路径 `matrix/board.png`+audit 0+（shot-m13-reopened） |
| M14 外部改名 | ⚠️ 半红 | **检测半格绿**：mv→audit **报 Missing**（1 finding，entity Song/field 0/reference sounds/blip.wav，m14-audit-missing.json 归档）；**rebind 半格红**：asset.rebind 喂 finding 原样字段→文档未重写→audit 仍 1→**AR11**（§4）；浏览器刷新面本轮 walk 未捕到新名（时窗，检测面以 audit 为准） |
| M15 warn 形态 | ✅ 两相 | assets 相：`asset load failed`=7（M9/M10/M5 探针设计窗）+`thumbnail:`=2（AR8 写 off）+索引拒读=1（M11）+playface panic=0+**意外=0**；docs 相全零意外。预期列口径=T1 QA 交接口径，全数归因 |
| M16 编辑器存活 | ✅ | 每个坏文件窗后 BRP `jackdaw/status` 应答+pid 与 boot 一致（M9/M10/M11/M12 各窗+恢复后，console 全程） |

**矩阵统计**：✅ 14 格（含 M8/M13/M15/M16 横切）｜⚠️ 2 格半红（M9 恢复半格=AR10、M14
rebind 半格=AR11）——铁证①全绿；铁证②「不崩不丢引用」全绿，「修好→恢复」半格立 AR10。

## 3. L1-L10 逐腿

| 腿 | 判定 | 注 |
|---|---|---|
| L1（M1 PNG 全链） | ✅ | 拖放腿=注 FileDragAndDrop 消息（MCP 优先原则的结构化替身；真 Finder 拖放不属可脚本驱动面），A7 记数：本轮零坐标赌（drop 点=结构化事件） |
| L2（M2 JPG 红绿） | ✅ | 红=T1 归档；绿链真机全通 |
| L3（M3/M8 三面同腿） | ✅ | 含一次 A6 丢事件再触发（日志明示） |
| L4（M4 材质） | ✅ | 卡面 #0DFF0D 现场读 |
| L5（M5/M6 音频+柄） | ✅ | Reloaded 面交接口径执行 |
| L6（M7 导入选项） | ✅ | |
| L7（M9/M10 坏文件） | ⚠️ | M10 全绿；M9 恢复半格红=AR10 |
| L8（M11/M12+AU6） | ✅ | AU6 拒写门=真机绿证（banner 文案逐字在案） |
| L9（M13 四件套） | ✅ | SHA+audit+实体+重开四件全过 |
| L10（M14 改名边界） | ⚠️ | audit 检测绿（AR6 边界验证格成立）；rebind 半格红=AR11 |

## 4. 新发现（AR 系续编，只记不修→主控裁定吸收面）

> **T2.5 状态更新（见 §9）**：AR10 已修（读取层读时复验+真机引擎面绿）；
> AR11 已修（TupleStruct 双臂+单测红绿）；AR9 判别复探仍在（读取层修复不吸收它，
> 定位为渲染/板面缺陷）另立记档，M9 板面半格红归它。

| 编号 | 严重度 | 描述 | 红证 | 备注 |
|---|---|---|---|---|
| **AR9** | 🟡 | **texture.import meta 使外改不再到达视口板**：给在用 PNG 落 Bevy `.meta`（Compress）后，外写同路径：引擎照常 `Reloaded matrix/board.png`（processed 管线在动），但参考板的可见面**冻结在 meta 落盘前的内容**，直至编辑器重启 | 专项探针（归档 `t18t2_ar9-{editor.log,before,after}.png`）：meta 在→外写 orange→Reloaded 在→板区域像素采样仍 (128,50,156)=旧 purple；对照=无 meta 的 M1 同路径重写板面跟随（shot-m1-board-red/blue 全帧 md5 变化） | run-2 首次观测（当时 M9 三 shot 全帧 md5 恒等），后经专项探针复钉；M9 腿为隔离 AR10 先删 meta 再跑 |
| **AR10** | 🟡 | **图片资产一次重载失败后，后续合法改写不再重载**：坏 PNG 重载失败（`Failed to load asset 'matrix/board.png' …Invalid PNG signature` 持续刷屏）后，磁盘恢复合法字节（+同字节重写+mtime touch 三种触发形态）→引擎零 `Reloaded`、失败行继续发生（磁盘文件已是合法 PNG，`file` 实证）——「修好→恢复」验收面断裂，板永久停在旧内容 | 终轮 editor-assets.log：03:08:40 起失败行连发（03:08:40/45/49/53/…03:09:46，共 35 行）晚于修复写盘数分钟；crop md5 good=broken=fixed；对照=M10 的 glb 走同梯（fail→fix→`Reloaded matrix/hero.glb`+2 盒重生 ✅）→**AR10 为 Image 域特有**；M15 预期列归因在案 | AR3 的 (path,mtime) warn 锁让反馈只报一次（设计内）；坏的是引擎重载自愈面 |
| **AR11** | 🟡 | **rebind 链不能重写 tuple-struct（newtype）组件的引用**：`AudioPlayer<AudioSource>` 类引用 audit 正确报 Missing（field=0），但 `asset.rebind`/Missing References 列表的 `rewrite_ast_reference` 组件匹配只有 Struct/Base 两臂，TupleStruct 落 `_ => false` → 永不重写（audit 维持 1 finding） | `t18t2_m14-audit-missing.json`（finding 原样）+`t18t2_m14-audit-clean.json`（rebind+save 后仍 Missing）+console「the rebind never reached the document」；finding.component 形态=`AudioSource>`（tuple-struct patch 的 type_path 截断拼写，两侧同源，修 matcher 时一并核） | T05 测试面覆盖的是 struct 组件（IsA/struct 字段）；newtype 组件（AudioPlayer/MeshMaterial3d 等）是漏斗盲区——M14 的 rebind 半格、Missing References 列表 UI 同链同病 |

观察（不立 AR）：①首次 glTF place 的实例化在编辑器开局加载风暴下落在 60-100s 后
（M3 预算 120s 有界判 Fail；probe 静窗内 ~2s）——已知加载时序形态，编辑器自有
model cost 量测在案；②AR8 首载坏 place 的缩略图写 off 每次 place 恰好两行
（`thumbnail: …could not be photographed`）——每路径一次锁语义与 T14 测试一致。

## 5. 门禁（日志全文复核，`loop/reports/t18t2_qa_*`）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 | `t18t2_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，1m39s，零 error 行 | `t18t2_qa_clippy.log` |
| 物理双包 clippy | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | `t18t2_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib --features dylib` | ✅ **2999 passed / 0 failed**（58 二进制求和亲算）；唯一 ERROR 行=PIE 故意坏构建场景（T1 QA 已归因族） | `t18t2_qa_libtests.log` |
| fast | `cargo xtask fast` | ✅ EXIT=0，**Summary: 2999 tests run: 2999 passed, 0 skipped**；全文扫描仅故意场景测试名命中 | `t18t2_qa_fast.log` |
| 腿 asset_formats | `cargo test --test asset_formats` | ✅ 2/2 | `t18t2_qa_asset_formats.log` |
| 腿 asset_watch_reload | 同上 | ✅ 1/1（0.96s） | `t18t2_qa_asset_watch_reload.log` |
| 腿 audio_gate | 同上 | ✅ 7/7 | `t18t2_qa_audio_gate.log` |
| 腿 guards asset_lifecycle | `cargo test --test guards asset_lifecycle` | ✅ 5/5 | `t18t2_qa_asset_lifecycle.log` |
| 定向单测 thumbnail | `cargo test --lib --features dylib thumbnail::tests` | ✅ 25/25 | `t18t2_qa_units_thumbnail.log` |

磁盘：门禁前 44Gi（运行中清理后）/门禁后 37Gi。全程未设 RUST_BACKTRACE。T2 零产品
代码改动（分支与 T1 合入点同树），门禁为放行性复跑，与编辑器零同窗；长命令后台+轮询，
进程无残留（pgrep 复核）。

## 6. 偏差清单（如实）

1. **M5 的「load 状态」面改走 `Reloaded <path>` 行**：BRP 对 `Handle<T>` 无
   ReflectSerialize（实测 error -23402，AudioPlayer 值不可读），计划写的「R 断 load
   状态」不可机械化；`Reloaded` 行是引擎自己的重载完成面，语义更强。柄 Uuid 面归
   T1 headless 锚（T1 QA 交接口径已备）。
2. **拖放腿的驱动形态**：`entity.add.image` 开原生对话框（不可脚本驱动，方案 §六
   预案亦写明），实际走 `world.write_message(FileDragAndDrop::DroppedFile)` 注入；
   实测工程内路径只选中不生成板（W8 修复后的设计行为），故投放物用工程外源文件且
   光标先落到视口内（`input.pointer` move）。两次腿 PASS。
3. **M9 腿先删 `.meta`**：为隔离 AR10（无 meta 的普通管线），meta 冻结面（AR9）以
   专项探针另证；run-2 的原始观测文件被后续轮次覆盖，AR9 红证以专项探针归档为准。
4. **AU6 play 面 panic 风暴未在真机复现**：计划预测「场景已挂坏音频 play 逐帧 panic
   风暴仍在」，5 个编辑器窗口（含坏 wav 后 scene 重开真读、9 实体重生）实测 `panicked at`
   恒 0。fork unwrap 未动的静态红以 fork 源码+T16 记档为准；AU6 的活修（拒写门）
   真机绿。**勿把「修后无 panic」写成验收预期**（T1 QA 口径维持）——本轮补充：连
   「修前 panic」也未复现，编辑器音频 sink 构建路径对重载坏源的表现与 T16 时代读法
   存在差异，留 QA/T3 注记。
5. **M14 浏览器刷新面未捕到新名**（mv+settle 4s+show_folder 后 walk 无 blip_renamed）：
   Create/Remove/Name 链的时窗一次未中；AR6 边界格的判定面以 audit（✅ 报 Missing）
   为准，浏览器面记观察。rebind 半格红=AR11（产品根因，非脚本），红证归档。
6. **M3 的 A6 丢事件再触发**：watcher 对 M3 重写丢事件一次（无 `Reloaded` 行），脚本
   按预案再写一次（同内容新 mtime=新触发，日志明示「A6 family missed event」）——
   非时序赌 retry，是丢事件的第二触发；M9 修复写盘同理（两种再触发形态+touch 第三
   形态，均未唤起重载——即 AR10 红证本身）。
7. 其余零偏差：fork 零改动；协议/场景格式零变更；T1 交付件（AssetWatchChanges/AR1/
   AR3/AU6 门）全部按交接口径消费，未改产品代码。

## 7. 给 QA / T3 的注意事项

1. **复跑口径**：`bash loop/qa/t18-live.sh prep && … assets && … docs`（或 `all`）。
   脚本自睿：prep 幂等（重建资产族+清残留），doc 相自带 M14 的 mv→rebind→save；
   **勿与门禁同窗**（脚本头五纪律）。
2. **AR10/AR11 是本轮两个待裁定红**：AR10 建议主控裁定吸收面（引擎域，fork 纪律
   优先→编辑器侧缓解形态待议，例如失败后的显式 re-ask 入口）；AR11 的修向明确
   （rewrite_ast_reference 补 TupleStruct 臂+type_path 截断拼写核对，T05 邻域小件）。
   两项均只记不修，buglist/台账由 T3 处置。
3. **AR9（meta 板面冻结）** 与 AR10（失败后不重载）可叠合观察：meta 存在时外写仍
   Reloaded 但板不动（无失败路径）；无 meta 时失败后外写连 Reloaded 都没有。QA 复验
   时注意区分两条机制。
4. **AU6**：拒写门真机绿（banner 文案逐字：`…is not a sound file the editor can
   decode; the reference was not written`）；play 面未复现 panic（偏差 4）——T3 写
   book/结案时按「fork unwrap 静态红+编辑器未复现」双面诚实注记。
5. **picker 腿驱动**：AudioPlayer 卡需先点 chevron 展开；picker 行不可见（TextSpan），
   走「点搜索框→input.text 过滤→首行槽位点击」；标题行 y+42 步进、x=700 实测可靠。
6. **用户 30 秒清单草稿**（T3 book/终验用）：打开工程→Project 窗看 matrix 文件夹
   （板/材质球/模型缩略图在）→外部改一下 hero.glb 或材质颜色→回编辑器看视口、
   Inspector 文件卡、缩略图三面自己变（改动→三面，≤30s）→外部把一张在用 PNG 改坏
   （改字节）→编辑器不死、板保持旧图、状态栏出 `…failed to load; showing the
   previous content`→改回好图。**（勿演示「修好即恢复」——AR10；勿演示带 meta 的
   PNG 外改——AR9。）**

## 8. 产物与证据索引

- 脚本：`loop/qa/t18-live.sh`（probe-earned facts 注释在头）。
- 最终判定：`t18t2_summary-assets.txt`/`t18t2_summary-docs.txt`/`t18t2_summary-all.txt`；
  全程控制台 `t18t2_console-all.log`+编辑器日志 `t18t2_editor-all.log`（assets 相分卷
  `t18t2_console-assets.log`/`t18t2_editor-assets.log`）。
- 红证：AR9=`t18t2_ar9-{editor.log,before.png,after.png}`；AR10=`t18t2_editor-all.log`
  （board.png 失败行族+crop 恒等，board-region md5 序列在 console）+`t18t2_shot-m9-board-{good,broken,fixed}.png`；
  AR11=`t18t2_m14-audit-missing.json`/`t18t2_m14-audit-clean.json`/`t18t2_m14-missing-sample.log`。
- 反馈面归档：`t18t2_m9-ar3-lines.log`（AR3 逐字）、`t18t2_m10-thumbnail-lines.log`
  （AR8 写 off）、`t18t2_m11-lines.log`（索引拒读）、`t18t2_m12-storm-sample.log`
  （空=未复现，诚实注记）、`t18t2_m13-audit.json`/`t18t2_m13-docs-audit.json`（零 Missing）、
  `t18t2_warn-lines-{assets,all}.log`（意外=空）。
- 视觉：`t18t2_shot-*.png` 13 张（M1 三态+板卡、M2 板、M3 单/双盒、M4 材质卡、
  M10 好/坏、M12 picker/拒写后、M13 重开）。
- fixture 可复跑：`jd new t18-assets --path /Users/zhanglinbo/workspace/loop-mac/t18-assets
  --no-git`+脚本 prep 自建资产族。

---

## 9. §补 T2.5 小修轮（2026-10-31，QA PASS 放行 T3 后的主控裁定返工）

> 三件吸收：AR10 修复+AR9 判别复探+AR11 顺手修；脚本 boot 日志分窗；门禁复跑覆盖归档；
> M9 全段真机重跑。红态先归档（`t18t25_ar10-red.log`/`t18t25_ar11-red.log`）。
> 产品改动面：`crates/jackdaw_runtime/src/texture_import.rs`（读时复验，最小正确面）、
> `src/inspector/missing_list.rs`（TupleStruct 双臂）。fork 零改动；勿设 RUST_BACKTRACE
> 全程执行；磁盘门前 26Gi/后 24Gi（≥10Gi 线）。

### 9.1 AR10 修复 ✅（引擎/读取层）

- **根因（QA 定位+代码形态确认）**：`TextureImportReader.processed` map 只插不删不复验。
  两条链：①meta 删除后 `read()` 仍命中 map 服务陈旧 `.basis` 字节→普通 loader 拿到
  Basis 字节→`Invalid PNG signature` 失败风暴+资产卡死（T2 终轮 35 行失败、修复写盘后
  数分钟仍失败的红证）；②meta 仍在而源字节重写时，仅动源的 reload 不重跑 `read_meta`，
  `read()` 命中旧 map 项→服务上一轮画面（AR9 的读取层半边）。
- **修复=读时复验（路径失效删除+内容哈希复验的合体，最小正确面）**：新私有
  `fresh_processed(path)` 在每次 `read()` 时——meta 不在/非本处理器→`forget(path)` 删项
  并服务源字节；meta 是我们的→重算源+meta 内容哈希对照缓存名，一致即服务，不一致/
  无项→走 `process()` 同一门重处理并回填 map（处理失败→warn+forget+回落源字节）。
  代价=每次资产读一次小 meta 读+一次源哈希（只在 load/reload 路径）。
- **红绿**：新集成测试二件（`t18t25_ar10-red.log`：两件 FAILED，3 passed/2 failed，
  EXIT=101）→修复后（`t18t25_ar10-green.log` 及 `t18t25_qa_texture_import.log`：
  **5/5 含 3 件既有回归**）。
- **真机引擎面 ✅**：M9 全段重跑（`t18t25_verdict-assets.txt`/`t18t25_console-assets.log`）：
  坏窗失败行=1（AR3 一次）→修复写盘→**`Reloaded matrix/board.png`=1**（AR10 引擎面；
  T2 终轮同窗为 0）。卡死失败风暴消失。

### 9.2 AR9 判别性复探 →**仍在，如实记档另立**（⚠️ 不随 AR10 消失）

- **判别探针**（`t18t25_ar9b-{editor.log,state0.png,after.png}`）：texture.import 落
  meta→外写 orange（与现有 teal 不同色）→引擎 `Reloaded matrix/board.png` 在（05:36:50）
  →板区域 crop md5 前后恒等（d3e1fadc…）。
- **机理定位（T2.5 新证据链）**：读取层修复后，资产内容确实随重载更新（Reloaded 在、
  失败风暴消失）；冻结的是**渲染/板面**——且冻结起点=第一次 processed（Basis/Bc7 格式）
  重载：此后同路径的一切重载（含 M9 恢复普通 png 的 teal 重写，Reloaded=1）都不再上屏，
  板永久显示**首次加载的内容**（M1 的 blue）。M1（plain→plain 重载）板面跟随正常，
  格式不变的重载无此问题。
- **AR9 记档形态（另立）**：🔴/🟡「经 texture.import（Basis/BC7）重载过的图片资产，
  其引用面（参考板/材质槽等 GPU 消费面）停止跟随同 AssetId 的后续重载——Modified 事件
  在、Asset 内容在变、GPU 纹理不更新；首次加载内容持续显示」。修复面在渲染提取/GPU
  纹理重建（格式变更的重上传），非读取层，T2.5 不动。M9 腿的板面断言即此格的持续红：
  leg 其余四面（旧内容保持/AR3/存活/引擎 Reloaded）全绿，`L7_M9_BAD_PNG` 的 FAIL
  仅落在板面恢复半格=AR9。

### 9.3 AR11 修复 ✅

- `src/inspector/missing_list.rs::rewrite_ast_reference`：matcher 补
  `BsnPatch::TupleStruct(data) => data.type_path == finding.component`（audit 与重写
  两侧同源同拼写，泛型原样相等即匹配，注记在码）；重写 match 补 TupleStruct 臂
  （newtype 的唯一 held 值即 audit 所指引用）。
- **红绿**：`t18t25_ar11-red.log`（中性化单臂后 `a_tuple_struct_reference_rebinds`
  FAILED，EXIT=101——真单臂归零，非整文件回退）→修复后
  `a_tuple_struct_reference_rebinds`+`a_tuple_struct_rebind_stays_on_its_own_component`
  两件绿（1/1+负控，libtests 总 3001=2999+2 新）。

### 9.4 脚本改进 ✅

- `t18-live.sh` boot 日志分窗：`WINDOW` 计数+`EDITOR_LOG`（`editor-$PHASE-$N.log`），
  全部日志读者（mark_log/log_lines_since/M5/M9-M12/M15 扫描）随 `$EDITOR_LOG`——
  docs 相 boot 不再截断 assets 相编辑器日志（QA 回流⑤）。

### 9.5 门禁复跑（覆盖归档 `t18t25_qa_*`）

| 门 | 结果 |
|---|---|
| fmt | ✅ EXIT=0 |
| 全仓 clippy（-D warnings） | ✅ EXIT=0（两轮返工：manual-let-else→let-else 改写、doc-markdown 三处补反引号后绿） |
| 物理双包 clippy | ✅ EXIT=0 |
| libtests | ✅ **3001 passed / 0 failed**（=2999+2 新 missing_list 测试） |
| xtask fast | ✅ EXIT=0，**3001 tests run: 3001 passed, 0 skipped** |
| 腿 asset_formats / asset_watch_reload / audio_gate | ✅ 2/2、1/1、7/7 |
| 腿 guards asset_lifecycle | ✅ 5/5 |
| 定向单测 thumbnail::tests | ✅ 25/25 |
| 新测试 texture_import（runtime 集成） | ✅ 5/5（3 既有+2 新 AR10/AR9 面） |

进程无残留（pgrep 复核）；编辑器二进制随源重建（T2.5 教训：live 跑前必须
`cargo build --bin jackdaw`——首跑 EDITOR_BOOT_FAIL 即陈旧二进制 dyld 死亡，已修）。

### 9.6 T2.5 真机重跑判定（M9 全段+全相复跑）

`VERDICT_ASSETS_PHASE`：14/15 PASS——**L7_M9_BAD_PNG FAIL 仅板面恢复半格=AR9（另立
记档）**，其四面全绿：旧内容保持（crop 相等）✅、AR3 一次 ✅、存活 ✅、
**修复写盘 Reloaded=1（AR10 引擎面）✅**。其余 14 腿全 PASS（M3 含一次 A6 丢事件再
触发，日志明示）。M16 各存活窗照旧全过。

### 9.7 T2.5 偏差清单（如实）

1. **M9 腿判别面重设计**：修复色从「M7 同款 purple」改为**新色 teal**——恢复到与坏前
   相同的画面在像素上与「从未坏」不可区分（T2.5 首跑即误判 FAIL 的根因），现要求
   fixed≠broken 且 fixed≠good（板跟随新状态）。AR9 存在时该面注定红——这正是 AR9
   的持续红证。
2. **AR10 修复面收敛为引擎/读取层**：板面恢复半格划归 AR9（另立）——QA 预案「仍在则
   如实记档另立」执行。
3. **AR11 测试红证的取证形态**：真单臂归零（sed 中性化 matcher 单臂后跑测试），
   非整文件 stash 回退（stash 连测试一起带走，首取无效，归档以单臂中性化版为准）。
4. **编辑器二进制陈旧教训**：T2.5 首跑 EDITOR_BOOT_FAIL=libs 重编后旧二进制 dyld 死；
   `cargo build --bin jackdaw` 后复跑即绿。后续 QA 真机轮建议跑前显式重建。

### 9.8 给 QA 复验注意事项

1. **AR10 复验**：单元层=`cargo test -p jackdaw_runtime --test texture_import`
   （5 件含 2 新）；真机层=M9 腿（引擎 Reloaded=1+失败风暴消失）；**板面不算 AR10 的
   账**——它归 AR9。
2. **AR9 复验**：判别探针脚本化步骤在 §9.2（compress→外写异色→Reloaded 在→crop 恒等）；
   或直接复跑 M9 腿看板面半格。裁定吸收面时注意：修复面在渲染提取（格式变更重上传），
   读取层已由 AR10 修复覆盖。
3. **AR11 复验**：`cargo test --lib --features dylib missing_list::tests`（2 件）；
   真机=M14 腿的 rebind 半格（本次未重跑 docs 相——M14 的 audit 检测面在 T2 已绿，
   rebind 面由单测钉死；QA 若要真机 M14 全段，跑 docs 相即可）。
4. 编辑器二进制先 `cargo build --bin jackdaw`；勿设 RUST_BACKTRACE；门禁与真机不同窗
   纪律照旧。
