# T18 任务 2「真机矩阵轮」QA 报告

> 分支 `loop/t18-assets`，程序提交 `c3d53410`（零产品代码改动亲证：diff 面=loop/ 脚本+报告+归档
> 54 件；fork 树干净；工作树干净）。核实对象：`loop/reports/t18-t2-report.md`；方案
> `loop/plans/t18-assets-hotreload.md` §二/§三/§四-T2+决策表；T1 交接口径（t18-t1-qa.md §4）；
> buglist A6/A7/A9/A10。日期 2026-10-31（QA 轮）。口径：只读+亲跑门禁（后台+轮询、勿设
> RUST_BACKTRACE、`env -u` 亲证）+证据原文全读+亲跑真机 assets 全相；buglist/台账/roadmap 未动。

## 0. 裁决

**PASS——放行 T18-T3（终验+文档）。**

依据：①门禁七门 QA 亲跑全绿（libtests/fast 双 2999 亲算，107 条 ERROR 行逐族归因=T1 QA
同族名单，零新失败签名）；②抽核 4 格（M3/M8、M4、M10、M12+AU6）证据原文全读+截图亲看，
与报告陈述一致、零虚报；③三铁证独立性判定全过（§3）；④两红腿+AR9 定性复核完成，QA 在
程序归档之外给出 AR10 的**源码级断点定位**（`TextureImportReader` 缓存失效缺失，§5——
把「引擎域」修复难题转成产品侧半天级小修），AR11 源码级亲核（`_ => false` 在案）；⑤
QA 亲跑真机 assets 全相：M8 三面亲跑绿、M12 存活+引用保持、AR10 第三度复现、M13/M15
全绿（§6）。报告有 4 处**表述**修正+1 处机理归因降级（§7），不动摇门禁与判定结论；
报告对两红（M9/M14）的诚实归档纪律执行到位。

## 1. 门禁（QA 亲跑，覆盖归档 `loop/reports/t18t2_qa_*`）

| 门 | 命令 | 结果 | 证据（QA 覆盖归档） |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0（净） | `t18t2_qa_fmt.log` |
| 单测 | `cargo test --workspace --lib --features dylib` | ✅ **2999 passed / 0 failed**（result 行求和亲算）；107 条 ERROR 行逐族归因：96 bevy_asset no-loader（无头测试 app 故意失败件）+4 asset path（无头）+2 scene save not-a-directory（故意）+1 screenshot 无视口（无头）+1 PIE SIGKILL+1 PIE E0560（故意坏构建）+1 scene_component+1 extract ClearColor——**与 T1 QA 族名单同族，零新签名** | `t18t2_qa_libtests.log` |
| fast | `cargo xtask fast` | ✅ EXIT=0，**Summary: 2999 tests run: 2999 passed, 0 skipped**；全文 error 词扫描仅 1 命中=测试名 `error::tests::display_text_is_pinned`（假阳性） | `t18t2_qa_fast.log` |
| 腿 asset_formats | `cargo test --test asset_formats` | ✅ 2/2 | `t18t2_qa_asset_formats.log` |
| 腿 asset_watch_reload | 同上 | ✅ 1/1（1.01s） | `t18t2_qa_asset_watch_reload.log` |
| 腿 audio_gate | 同上 | ✅ 7/7 | `t18t2_qa_audio_gate.log` |
| 腿 guards asset_lifecycle | `cargo test --test guards asset_lifecycle` | ✅ 5/5（239 filtered out） | `t18t2_qa_asset_lifecycle.log` |
| 定向单测 thumbnail | `cargo test --lib --features dylib thumbnail::tests` | ✅ 25/25 | `t18t2_qa_units_thumbnail.log` |

- **全仓 clippy/物理双包 clippy/integration：采信 T1 归档**（t18t1_qa_clippy*.log，QA 抽核
  在案）+本轮 fast 内含同参数 clippy（xtask fast 组成，T1 QA 亲读 main.rs:35）——零产品
  改动轮采信成立。
- 磁盘：门前 37Gi/门后 26Gi（门禁+编辑器重编译消耗）。全程未设 RUST_BACKTRACE。
- **执行注记**：门禁重编译后 target 内 binary/dylib 符号失配，QA 亲跑轮首启
  EDITOR_BOOT_FAIL（dyld Symbol not found，环境性非产品）——`cargo build` 重编译后消除；
  后续真机复跑遇 boot 失败先重编译再查产品。
- 进程清理：结束 `pkill -x jackdaw`+pgrep 复核，无 cargo/rustc/jackdaw 残留。

## 2. 逐格核实（M1-M16/L1-L10）

抽核 4 格证据原文全读+其余格归档交叉核对，结论与报告 §2/§3 判定表**一致**：

| 格/腿 | QA 核实 | 关键证据（亲读/亲看/亲跑） |
|---|---|---|
| **M3/M8**（L3） | ✅ 成立 | console-all:4-13 全读：1 盒→外写（A6 丢事件一次→预案再触发，非时序赌）→Box 计数 2+新 mtime 缩略图 `bde84cd9…-18e37ec9….png`+像素 md5 在案；截图 m3-hero-one/two 亲看（1 白盒→双盒，视口重生实锤）；`Reloaded matrix/hero.glb` 在 editor 日志在案。**QA 亲跑轮同腿复绿**（§6） |
| **M4**（L4） | ✅ 成立（证据面注记） | `mat_set_color` 换值脚本亲读（red/green/blue 三通道正则）+tile 新 mtime PNG（两相归档同像素 md5=同绿球渲染）+浏览器保有 redshift+**shot-m4-material-card 亲看：材质卡 `base_color: #0DFF0D` 现场可见+Project 窗绿球 tile**。注记：脚本的 ui_tree 文本走查两次报「card hex did not show 0DFF0D」（walk 对 hex 盲，软检查不参与判定）——「现场读到」的证据面是**截图**非 walk；报告判定成立 |
| **M10**（L7） | ✅ 成立 | console:55-64+editor 日志交叉：坏窗 `Reloaded hero.glb` 增量=0+`Failed to load 'matrix/hero.glb'` 增量=2+旧实例保持（Box 计数不变）+AR8 首载坏 place（`broken_first.glb` 不 spawn+写 off 恰 2 行=`m10-thumbnail-lines.log` 亲读）+修好 2 盒重生；截图 m10-hero-good/broken 亲看 |
| **M12+AU6**（L8） | ✅ 成立 | console:69-87+script m12 段亲读：坏 wav+save→reopen 真读→panic 恒 0（5 窗一致，诚实注记见 §7-6）；AU6 拒写门=状态栏横幅（**shot-m12-after-refusal 亲看：橙色横幅 `sounds/aaa_bad.wav is not a sound file th…`+Inspector 字段仍 blip.wav**）+文档 grep 硬断言（`AudioPlayer<…>("sounds/blip.wav")` 在案）；fork unwrap 静态红亲核仍在（`audio_source.rs:101 .unwrap()`） |
| M1（L1） | ✅ | 视口全帧像素 md5 red≠blue（两相各自在案）+drop 注入 FileDragAndDrop（MCP 优先的结构化替身，方案 §六预案内）+refimage 计数 1→2 |
| M2（L2） | ✅ | 绿链 loader 失败行 0+板生成；红=T1 归档（InvalidImageExtension） |
| M5/M6（L5） | ✅ | `Reloaded sounds/blip.wav` 增量 ≥1（好/坏探针各 1）+零 panic；柄 Uuid 面=T1 headless 锚（交接口径维持） |
| M7（L6） | ✅ | shot-m7-card-compressed 亲看：卡面 Import=Compressed, mipmaps+Compress/Original 两钮+References t18.bsn；`.meta` 落盘+重写后卡面不变 |
| M9 | ⚠️ 半红=AR10 | 存活 ✅、旧内容保持（crop md5 恒等）✅、AR3 反馈 ×1 ✅、引用原样 ✅；恢复半格红**三度复现**（run-1/run-2/QA 亲跑轮，§5+§6） |
| M13（L9） | ✅ 成立（表述修正见 §7-1） | SHA 链：pre9（M12 save 时点）=终态（147aa5…，console:88）；audit count=0 两相 json 亲读；Board/Song 实体断言+docs 重开 Board 路径（shot 亲看：紫板+R 路径） |
| M14（L10） | ⚠️ 半红=AR11 | 检测半格绿：audit Missing 1 finding（json 亲读：entity Song/field 0/`sounds/blip.wav`）；rebind 半格红：rebind+save 后 audit 仍 1（clean.json 亲读）+console「the rebind never reached the document」+editor-all.log:43-45 rebind→save 时序亲读 |
| M15 | ✅ | 终轮 live 计数：7/2/1/0/0 全归因+意外=0（console:92/108）；词表族 QA 亲扫复核（`asset load failed:`/thumbnail 写 off/索引拒读/panicked/unsaved edits/relationship——后两族仅 run-1 出现，已归档已归因） |
| M16 | ✅ | 每坏窗后 BRP 应答+pid 一致（console 各「editor alive」行） |

## 3. 三铁证/验收句独立性判定

- **铁证①「外部改资产→三面更新」：主流链（无 meta）成立，meta 纹理链两红在案。**
  独立性：M3/M8 单腿内三断（视口 Box 计数+PX／文件卡 ui_tree Path 行／缩略图新 mtime+像素）
  互不依赖手工刷新——单腿判定 ✓；M1 视口像素 diff 与文件卡面独立取证 ✓；M4 tile MD5 与
  卡面 `#0DFF0D` 独立取证 ✓。**限定注记**：带 texture.import meta 的纹理外改不达视口板
  （AR9 探针+AR10 机理，§5）——「全绿」的适用面=无 meta 主流链，30 秒清单的「勿演示带
  meta PNG」注记必须进 book。
- **铁证②「坏文件不崩不丢引用」：成立。** 不崩=M16 全程（每坏窗 BRP+pid，QA 亲跑轮同过）；
  不丢引用=M13 SHA 链（坏文件梯全程文档字节不变）+audit 0+组件引用原样（M12 文档 grep）
  ——三条证据面相互独立（盘上字节/BRP 审计/文档内容 grep）✓。「修好→恢复」半格红=AR10
  如实立新缺陷，不计入本铁证字面（验收句只考「不崩不丢引用」）。
- **铁证③「重导入/选项往返」：成立。** M5 引擎重载链（Reloaded 行）✓；M6 换值不换柄=
  卡面现场换值活证+T1 headless 柄 Uuid 锚（BRP 对 Handle 无 ReflectSerialize 的真机不可
  读口径=T1 QA 交接口径，维持）✓；M7 Compress meta 往返（落盘+重写后选项仍生效）✓。
  三者触发源、断言通道各不相同 ✓。

## 4. L1-L10 逐腿：与报告一致（15/17 PASS；M9 恢复半格、M14 rebind 半格红）

QA 抽验 L3（亲跑绿）、L7（亲跑轮 M9 红 third-occurrence+M10 绿）、L8（亲跑轮 M11/M12 绿）、
L9（亲跑轮 M13 绿）——判定表维持。

## 5. 两红腿+AR9 定性复核（主控裁定面的 QA 建议）

### AR10（M9 恢复半格）——🔴 建议主控裁定**吸收修**（产品侧，非引擎域）

- **红证复核**：run-1 editor-assets.log 35 行失败行亲数（03:08:40→03:09:46，晚于修复写盘
  数分钟）+修后 `Reloaded board.png`=0（仅 03:07:42/03:08:22 两行，均在坏窗前）+对照
  hero.glb 同梯 fail→fix→`Reloaded`+2 盒重生 ✓。QA 亲跑轮第三度复现（31 行+crop 恒等）。
- **QA 断点定位（新证据，报告未及）**：根因在**产品代码** `TextureImportReader`
  （`crates/jackdaw_runtime/src/texture_import.rs`）——编辑器默认资产源全程包裹
  （`src/launch.rs:171-180` `with_texture_imports` 亲读）。链：①`read_meta` 命中导入 meta
  时 `process()` 并把 `processed: HashMap<PathBuf,PathBuf>` 插入 path→缓存 .basis
  （:207-221，**只插不删不复验**）；②meta 删除后每次 load 的 meta 读走 NotFound→
  default_meta（fork server/mod.rs:1448-1460，FromExtension→Png），而字节读 `read()`
  **命中 map 服务陈旧 .basis 字节**（:189-200）；③PNG 解码器对 .basis 头报
  「Invalid PNG signature」——**与归档错误文本严丝合缝**（basis 魔数非 PNG 签名，普通陈旧
  字节无法解释）；④每次重试同一陈旧字节→失败连发+零 Reloaded+板面恒旧=AR10 全部观测。
  glb/wav 无 meta 历史→普通 read 直读盘→跟随正常——**「Image 域特有」应修正为「纹理导入
  meta 残留特有」**（M1 证明无 meta 的 png 外改三面跟随）。
- **修复建议**：map 失效化三选一（①`read()` 永不服务 processed 缓存、只有 `read_meta` 的
  process 路径服务；②缓存按源 mtime/哈希复验；③meta NotFound 时清条目）——产品侧半天级
  +单测，零 fork 改动；AR7 的「清 `.jackdaw/imported` 安全」注记不受影响（map miss 回落
  inner.read）。报告 §7-2 的「编辑器侧缓解形态（显式 re-ask 入口）」方向**不成立**——
  re-ask 已经在发生（35 次重试），坏的是字节服务层。
- **范围建议**：验收句正主（「外部改资产正确更新」对 meta 纹理不成立，而 Compress 按钮
  是一等公民面）→**建议 T18 增补半天级小修轮（修+红绿探针）再进 T3 终验**；若主控裁收口，
  则立票并在 book/30 秒清单延续「勿演示」注记。

### AR11（M14 rebind 半格）——🟡 源码亲核成立；建议立票（T05 邻域小件），主控可裁顺手修

- 源码亲核：`src/inspector/missing_list.rs:551-559` 组件匹配仅 Struct/Base 两臂，
  **`_ => false` 在 ：558**，TupleStruct patch 永不匹配——与报告陈述一致；audit 侧命名
  截断亲核（`reference_audit.rs:225-230` `rsplit("::")` 对泛型 type_path 尾段=
  `AudioSource>`）与归档 finding 逐字一致。
- 修向评估：**单臂新增**（TupleStruct 臂+按 field 索引重写 values+两侧命名归一：audit 剥
  泛型再取尾段、matcher 同则）vs **域级缺失扫描**（复用 `rewrite_ast`——follow_a_move 路径
  已有 TupleStruct 正臂，`reference_rewrite.rs:291-296` 亲读；但其语义是全文档 moves 批
  重写，rebind 是定点——直接复用会扩大重写面）。**建议单臂新增**，T05 邻域小件；
  Missing References 列表 UI 同链同治。
- 范围建议：AR6 边界格（外部改名）本在设计边界内，rebind 兜底链不属验收两句字面——
  **立票**为宜；主控若裁「T18 顺手修」亦小。

### AR9（meta 板面冻结）——🟡 事实成立；**机理归因降级为「待判别复探」**

- 归档事实复核：探针日志时序亲读（texture.import 03:24:14→before 03:24:21→Reloaded
  03:24:23→after 03:24:29）+**QA 亲算 before/after 板区 crop 像素逐字节恒等**（md5
  8903e4ae… 双同，中心像素 (128,50,157)≈报告 (128,50,156)）——「外写后板面未跟」成立。
- **机理降级**：报告的「引擎照常 Reloaded（processed 管线在动）但板冻结」未被探针钉死——
  代码链（fork server/mod.rs:1409-1477：meta 每载必读+`TextureImportReader::process()`
  每次重读源换新哈希新缓存）表明 **reload 真触发且 meta 在场 ⇒ 面应更新**；探针未时戳
  orange 写盘时刻，无法排除「orange 写的 reload 未触发（A6 丢事件，本 fixture 已三次
  观测）而唯一 Reloaded 行是 meta 落盘自己的回声」。
- **判别性复探方案**（修 AR10 时顺手）：orange 写盘前后 offset 计数 `Reloaded board.png`
  +时戳写盘；对带 meta 的源写坏一次——`texture_import.rs:215` 的「Texture import of …
  failed」warn 出现与否直接判别 read_meta 路径是否走到。
- 范围建议：与 AR10 同根（map 失效化修复+上述复探做红绿），**不单独立票**。

## 6. QA 亲跑真机（assets 全相，门禁后单窗）

`bash loop/qa/t18-live.sh prep && … assets`（A6 五纪律执行：单触发源/settle 4s/预算超时即
FAIL/与门禁不同窗/门前磁盘复核）。结果（`loop/t18-live/console-assets.log` 本轮在案）：

- **M8 三面同腿亲跑绿**：1 盒→外写（A6 丢事件一次→预案再触发）→2 盒+新 mtime 缩略图
  （像素 md5 与程序归档同值=同渲染）+文件卡 Path 行——亲验仲裁铁证① ✓。
- **M12 亲跑绿**（存活+引用保持+panic 0——panic 风暴未复现第二次证）；M11/M10/M13/M15
  亲跑全绿（warn 计数 7/2/1/0/0 与终轮同形）。
- **AR10 亲跑复现**（31 行失败行+crop md5 good=broken=fixed）——第三独立观测，红坐实。
- **L8_AU6_PICK_GATE=FAIL（亲跑轮）**：picker 横幅手势未命中（行几何点击 A7 家族 flaky，
  脚本自注「write-face 仍持；gate 腿判横幅」）——write-face（文档仍 blip.wav）亲跑持住；
  拒写门真机绿证以程序两次归档（横幅文案逐字+截图）为准，不构成返工；A7 记数+1。
- M3 首腿 60-100s 实例化时窗未复现（本轮 ~2s 级落定）——报告观察①的「开局加载风暴」
  形态属编辑器开局负载，非确定性，维持观察不立票。

## 7. 偏差裁定与报告修正（表述类，不动摇裁决）

| # | 项 | QA 核实 | 裁定 |
|---|---|---|---|
| 1 | §2 M13「prep 快照=终态」 | **不准确**：归档 prep 相 SHA（7e432c…）≠终态（147aa5…）；实际基线=scene-sha-pre9（M12 save 时点）与终态一致。实质成立（坏文件梯零写入文档；两次 save 重写属编辑器自己的机器），表述需改为「pre9 基线=终态」 | 修正表述 |
| 2 | §4 AR10 证据「终轮 editor-assets.log」 | **标注失真**：该 35 行=独立 assets 相窗口（run-1，03:07-03:16，pid 8233）；终轮（all）的 assets 窗口编辑器日志被 docs 相 boot **截断**（editor-all.log 仅存 docs 段 03:17-03:18——脚本 `boot_log` 跨窗复用同名之弊）。红本身三度复现（run-1 35 行/run-2 console 判 FAIL+03:16 时戳的 m9-ar3-lines.log/QA 亲跑轮 31 行），证据有效；**建议 T3 前脚本改进：boot 日志按窗命名或 append** | 修正标注+脚本改进 |
| 3 | §2 M15「两相 ✅」 | 适用面=终轮 live 计数；run-1 曾 M15_FAIL（2 意外：scene.open unsaved-edits 守卫+bevy relationship 重实例化噪声，warn-lines-assets.log 在案）——报告未提 run-1 的 M15/M3/M8 FAIL（M3 时窗以观察①披露，M15 未提） | 修正表述（「终轮零意外」为准）；两意外归因既有家族不立红 |
| 4 | M4 卡面 hex「现场读到 #0DFF0D」 | 判定成立（截图亲看）；但脚本 walk 对 hex 盲（console 两次 note），证据面=截图非 walk | 注记（复跑别依赖 walk 断 hex） |
| 5 | 偏差 1-3/5-6（M5 Reloaded 改道/drop 注入/M9 先删 meta/M14 浏览器面/M3 再触发） | 全部核实为真：Reloaded 行=引擎自己的重载完成面（更强）；FileDragAndDrop 注入=方案 §六预案+W8 设计行为；先删 meta 意图成立但**未达隔离目的**（map 残留仍在，§5——M9 的「无 meta 普通管线」实为 meta 残留管线，AR10 的正确刻面因此更准）；浏览器面以 audit 为准 | 接受（偏差 3 的结论按 §5 修正） |
| 6 | 偏差 4（AU6 panic 风暴未复现） | 口径核实：脚本与报告均未把「修后无 panic」写成验收预期（本轮连「修前 panic」也未复现，QA 亲跑轮第二次证 0）；静态红=fork unwrap（亲核在案）。「T16 时代读法差异」的待注记维持——T3 book 按「fork unwrap 静态红+真机两轮未复现」双面诚实注记 | 接受 |

## 8. 放行 T18-T3 的建议（含红腿处置路径）

1. **裁决面（主控三件）**：①AR10/AR9 同根（TextureImportReader 缓存失效缺失，产品侧
   半天级）——建议 **T18 增补小修轮（T2.5）后进 T3**，红绿探针用 §5 判别方案；若收口则
   立票+book「勿演示带 meta PNG 外改」延续。②AR11 立票（T05 邻域单臂+命名归一）或裁
   顺手修。③AU6 结案按偏差 6 双面注记回写 T16 清单。
2. **T3 终验注意**：book/30 秒清单按报告 §7-6 草稿+本报告 §7 修正（勿演示「修好即恢复」
   ——AR10 未修前；勿演示带 meta 的 PNG 外改）；复跑前重编译 binary/dylib 一致性（§1
   执行注记）；boot 日志按窗命名改进先行（否则终验归档再现截断）。
3. **台账/buglist**：T3 职责照方案；AR 编号续编面（AR9/AR10/AR11）的严重度建议——
   AR10 升 🔴（验收句正主+一等公民面）、AR9 并入 AR10 同票、AR11 维持 🟡。

## 8a. T2.5 小修轮复验（2026-10-31 第二轮，提交 `29f6658a`）

> 主控按本报告 §5/§8 裁定面派发：AR10 修复（读时复验）、AR9 判别复探、AR11 单臂修复、
> 门禁复跑、偏差核。QA 复验口径：源码 diff 亲读+亲跑门禁 10 门（覆盖归档
> `loop/reports/t18t25_qa_*`）+真机 docs 相亲跑（M14 rebind 决定性判定，程序未跑的面）。

### 复验裁决：**三件两落一打回——AR10 ✅、AR9 另立 ✅、AR11 ✗ 打回（第三轮微修）；T18-T2 暂不放行 T3，AR11 补齐即放行**

#### 1) AR10 修复 ✅ 通过

- **源码亲读**：`fresh_processed()`（texture_import.rs 新增）=本报告 §5 建议的 ②+③ 合体
  ——每次 `read()` 读时复验：meta 不在/非本处理器→`forget` 删项+回落源字节；是本处理器
  →源+meta 内容哈希对照缓存名，一致即服务，不一致/无项→`process()` 同门重处理回填。
  `read_all` 委托 inner（无递归）；失败路径 warn+forget+回落。两条死链（T2 的失败风暴+
  上一轮画面服务）都断掉。
- **红绿亲核**：`t18t25_ar10-red.log`（修前 2 新件 FAILED——红证 left 字节头=`0x73 0x42…`
  非 PNG magic，**陈旧 basis 字节进 PNG loader 的实锤**，3 件回归绿）→
  `t18t25_ar10-green.log`+QA 亲跑 **5/5**（3 既有回归+2 新）。
- **真机引擎面 ✅（两轮一致）**：M9 修复写盘窗口 `Reloaded matrix/board.png`=1
  （**offset 计数，脚手架改进后语义无歧义**——T2 终轮同窗为 0）；失败风暴消失
  （35 行→4 行，全部落在坏窗内）；QA 抽读 editor-assets-1.log：board.png 3 次 Reloaded
  （M1/M7/M9 修复窗）+4 次失败（坏窗）——与机理链逐环吻合。

#### 2) AR9 判别复探 ✅ 定位论证闭合（判据升级：以 M9 窗为准，探针单 Reloaded 歧义不再阻断）

- 探针三件亲核：`ar9b-editor.log` 时序（import 05:36:45→Reloaded 05:36:50→after 05:36:55）
  +**QA 亲算 state0/after 板区 crop 像素逐字节恒等**（md5 `b44df40d…`，中心 (50,142,143)
  teal）。注记：探针自身仍是单一 Reloaded 行（外写 reload vs import 回声不可分辨——T2-QA
  §5 的歧义保留）；**但定位论证由 M9 窗闭合**：修复写盘的 `Reloaded=1` 是 offset 计数
  （外写之后必有新 reload），读取层新鲜字节由单测 5 钉死（陈旧服务已不可能），而板面
  crop 恒等（good=broken=fixed）→「reload 触发+字节新鲜+Asset 更新+GPU 面冻结于首载内容」
  四环齐备——**渲染/GPU 重建面定位成立，读取层排除**。
- **另立记档接受**：AR9=「经 texture.import（Basis/BC7）重载过的图片资产，其 GPU 消费面
  停止跟随同 AssetId 后续重载」；M9 板面恢复半格红归它（脚本判别色 teal+
  fixed≠broken 且 fixed≠good 的重设计亲读 ✓——恢复与「从未坏」像素可分）；修复面在
  渲染提取/GPU 纹理重建（格式变更重上传），T2.5 不动如实。严重度建议 🟡→🔴 由主控随
  T3 处置（一等公民面+永久静默误导）。

#### 3) AR11 修复 ✗ 打回——**单测绿但生产路径未修（QA 真机 docs 相实证）**

- **源码亲读**：matcher 新臂 `BsnPatch::TupleStruct(data) => data.type_path ==
  finding.component`（等值匹配）+重写臂（held 值替换）——臂本身正确；**但等值的两侧
  拼写在生产不相等**：audit 的 finding.component=「type_path rsplit("::") 尾段」
  （`reference_audit.rs:225-230` 亲读+python 亲证：全路径尾段=`AudioSource>`，归档 json
  逐字一致），而 patch 的 type_path=parser 全路径含泛型（`syntax/types.rs:163-178`
  `to_type_path` 亲读）——`"bevy_audio::audio::AudioPlayer<…>" == "AudioSource>"` 恒假。
  码内注释「the audit reports as its component, spelled the same way here (generics and
  all)」**前提不成立**（audit 截断，非原样）。UI（findings() 原样）与 BRP（asset.rebind
  params 原样，`reference_audit.rs:616-639` 亲读）两条生产通路都送截断拼写；等值成立的
  唯一输入=测试自建的 component=完整 type_path（`tuple_struct_finding` 助手注释自称
  「the way the audit builds it」——**与 audit 实际构建方式不符**，测试自洽故绿）。
- **红绿取证复核**：`t18t25_ar11-red.log`（真单臂 sed 中性化后红，取证形态诚实 ✓）+
  QA 亲跑 2/2 绿——但红绿都只在「完整拼写」输入上成立，未覆盖生产拼写。
- **QA 真机 docs 相亲跑（决定性面，程序 §9.8-3 留给 QA 的那一格）**：
  `bash loop/qa/t18-live.sh prep && docs`（二进制先 `cargo build --bin jackdaw`，教训
  执行）——**T2 的红逐字复现**：`component=AudioSource>` 喂 asset.rebind→「the rebind
  never reached the document」→rebind+save 后 audit 仍 1 finding（`t18t25_qa_m14-
  audit-{missing,clean}.json` 亲读：前后同源同值）。**AR11 在生产上未修。**
- **打回修法（第三轮，微件）**：①matcher 臂放宽一行——
  `data.type_path == finding.component || data.type_path.rsplit("::").next() ==
  Some(finding.component.as_str())`（两侧同法取尾段含泛型，与 Struct 臂的 ends_with
  短名先例同型）；②把测试助手的 component 构建改为 audit 的实际方式（rsplit 尾段）——
  让「the way the audit builds it」成真，并保留完整拼写等值绿；③收口面=live docs 相
  （M14 rebind 半格绿）。预计十分钟级。

#### 4) 门禁复跑 ✅（QA 亲跑，覆盖归档 `loop/reports/t18t25_qa_*`）

fmt EXIT=0｜libtests **3001/0**（=2999+2 新，result 行求和亲算）｜fast **3001 passed/
0 skipped** EXIT=0｜腿 asset_formats 2/2、asset_watch_reload 1/1、audio_gate 7/7、
guards asset_lifecycle 5/5、thumbnail::tests 25/25｜**missing_list::tests 2/2**｜
**texture_import 集成 5/5**（QA 新增两门覆盖归档）。clippy（全仓 -D warnings/物理双包）
采信程序 t18t25_qa_clippy*.log 归档（两轮返工后绿，抽核在案）+fast 内含同参 clippy。
勿设 RUST_BACKTRACE（env -u 亲证）；磁盘门前 26Gi/后 23Gi。

#### 5) 偏差与合规核 ✅

①M9 判别色重设计（teal+双不等判据）亲读 ✓——首跑误判根因（恢复同画面与从未坏像素不可
分）成立；②「live 跑前必须 cargo build --bin jackdaw」教训在案且 QA 本轮执行（重建
22s 后 docs 相 boot 一次成）；③boot 日志分窗（WINDOW+EDITOR_LOG，全部读者随动）亲读 ✓
——T2-QA 回流②落实；④红态先归档（ar10-red/ar11-red 先于绿）纪律 ✓；⑤fork 零改动、
零协议/场景格式变更、勿设 RUST_BACKTRACE 全程 ✓；⑥`git show 29f6658a` 提交面=两产品
文件+新集成测试+脚本+报告+归档（本 QA 报告随提交入库，内容与 QA 存档一致）✓。

#### 6) 转裁（SV 类比）

- **AR10**：落判——修复吸收进 T18，随分支合入。**AR9**：落判——另立记档（渲染面），
  不阻 T18-T3；book/30 秒清单延续「带 meta 纹理外改勿演示（板面）」注记，验收句的
  视口面限定「无 meta 主流链」。
- **AR11**：打回——生产拼写缺口（本节 §3），第三轮微修后以 live docs 相收口。
- **T18-T2 → T3**：**暂不放行**。放行条件唯一：AR11 打回件落地（matcher 放宽+audit
  拼写测试+docs 相绿）。其余一切（门禁/合规/AR10/AR9/脚本改进）已就绪，AR11 补齐后
  无需再复验其他面——QA 对该微件做点验（单测 3 件+docs 相 M14 半格绿）即转 PASS，
  主控即可合入+派发 T3。
- 循环纪律：单任务修复循环上限 5 轮，本任务已用 3 轮（T2/T2.5/T2.6），余量 2。

## 9. 产物

- QA 门禁覆盖归档：`loop/reports/t18t2_qa_{fmt,libtests,fast,asset_formats,
  asset_watch_reload,audio_gate,asset_lifecycle,units_thumbnail}.log`（亲跑覆盖）。
- 亲跑真机：`loop/t18-live/`（本轮 console/editor/截图/审计 json——QA 轮工作目录，程序
  归档不被覆盖）。
- 本报告未动任何产品代码/buglist/台账/roadmap；待主控随 T18-T2 收尾一并入库（QA 不自行
  commit）。
