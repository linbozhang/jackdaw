# T21-T2 QA 报告：真机矩阵+SP7 探针+剩余记档件 —— 裁决 PASS（放行 T21-T3，附 7 项回流）

> 验收对象=`loop/reports/t21-t2-report.md`（分支 `loop/t21-sprite`，程序提交 c4413043，
> 终树与提交一致、工作树干净）。QA 亲跑日期 2026-11-01。归档=`loop/reports/t21t2_qa_*`
> （12 门日志）+`loop/t21-live/`（QA 亲跑产物：`console-qa.log`/`editor-all.log` 会话一、
> `console-qa2.log`/`editor-qa2.log` 重试、`shot-qa-m7-*.png`/`shot-qa-atlas-canvas.png`）。
> RUST_BACKTRACE 全程未设；warn 命中逐条归属；结束进程已清（无 jackdaw/t21-sprite 残留）。

## 一、结论

**PASS。** 验收句「图片或 Sheet→可编辑可保存可运行」的 T2 真机面骨架成立：SP7 判别
7/7 在档且 QA 亲测复现（普查 0.187/0.000/0.187 与条带视觉双证）、六 PR 能力面核心项
有独立证据（M2 选中/描边/gizmo 窗口对、GUIDES 亲跑绿、M9 三件亲跑绿、z 排序语义画布
旁证）、SP3 资产链头（卡/grid/undo-redo/重开/walk 装载/staged 包）全链在案、SP9 源码
+单测+DOM 在证、门禁 12 门亲跑全绿（3029/3029×2、stage 全量 563/563）。
**但程序报告有三处声明与归档证据不符或证据链断裂（§六 A1-A3），均按本报告更正记档，
不动摇骨架，不单独回流程序轮**；另有 7 项回流建议随 T3 落地（§八）。

## 二、门禁表（QA 亲跑终树 c4413043；日志全文复核为准）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0（零输出） | t21t2_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 error/warning 行（34.9s） | t21t2_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0，全文零行（19.7s） | t21t2_qa_clippy_phys.log |
| 单测 | `cargo nextest run --profile ci --workspace --lib` | ✅ **3029/3029**（=T1 基线 3025+SP9 单测 3+M10 探针 1，拆账与报告 §四一致） | t21t2_qa_libtests.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，lib 段 **3029/3029**，fmt/clippy 段零行 | t21t2_qa_fast.log |
| stage 全量 | `cargo nextest run --profile ci -p jackdaw --test stage` | ✅ **563/563**（333.6s，含 sprite_gizmo/picking/snap/drop/world_guides 五族） | t21t2_qa_targeted_stage_full.log |
| 定向 operators | `--test operators sprite_ops` | ✅ 13/13 | t21t2_qa_targeted_ops.log |
| 定向 inspector | `--test inspector sprite_atlas` | ✅ 2/2 | t21t2_qa_targeted_atlas.log |
| 定向 asset_formats | `--test asset_formats` | ✅ 2/2 | t21t2_qa_targeted_formats.log |
| 定向 watch | `--test asset_watch_reload` | ✅ 1/1 | t21t2_qa_targeted_watch.log |
| 定向 runtime | `-p jackdaw_runtime --lib asset_file_tests`（M10） | ✅ 10/10 | t21t2_qa_targeted_runtime.log |
| SP9 单测亲跑 | `--lib anchor_presets` | ✅ 3/3（常量表/applier 契约/噪声容差） | 本报告 §五-1 |

注：派单写「sprite 族 563」——程序归档的 t21t2_gates_targeted.log 是 stage 二进制
全量 563（非名字过滤；名字过滤 `sprite` 实为 63 测）。QA 以全量二进制复跑同数，
口径以此为准（563=stage 二进制测试总数）。

## 三、SP7 判别结论复核（首步定案）——维持

- **7/7 判定行在档**：`console-probe.log` 尾行 `PROBE done: L1_KIND/SP7_ALIVE/
  SP7_EMBEDDED_PX/SP7_NUMERIC/SP7_STOP_SHA/SP7_TEMPCOPY/SP7_WINDOWED_PX=PASS` ✓。
- **QA 亲测复现普查**（对归档 PNG 以脚本同款解码/步进重测）：embedded 条带 **0.187**、
  windowed 条带 **0.000**、temp-copy 条带 **0.187**——三数与脚本日志逐位一致 ✓。
- **视觉双证**（条带裁剪亲读）：embedded 条带=红色 hero 块+模板 HUD（「100/100
  Pickups」+bind 噪音在帧，即决策 6-A 的家具噪音在证）；windowed 条带=「No build
  running/building…」文本，无 sprite。FrameCaptureCamera=Camera3d 疑点证实成立。
- **N13 记数**：windowed 相 `swap_remove` panic+`drain_game_events` ERROR 在档，记数 1，
  编辑器存活读回重试绿 ✓（editor-probe.log :62-65）。
- **M14 形态裁定（embedded 保 PX、windowed 降数值轨）合理性：同意**。与决策 7 预案、
  T19 决策 4 同型；降级面最小（默认通道保像素，非默认通道以 direct 为 truth）。
  QA 无修正意见。

## 四、六 PR 能力真机逐个核（抽样三项+sprite.add 三件）

### 1. 画布拾取+描边+gizmo（M2，#650）——绿，QA 亲验窗口对

`shot-m2-unselected-window.png` 与 `shot-m2-selected-window.png`（相隔 18s，md5 相异）
亲读：选中拍=Hero 在 Outliner 高亮+画布 sprite 蓝描边+gizmo 手柄（蓝 stem+旋钮+白色
中心枢轴，与 `sprite_gizmo.rs` :276-281 的 `ACCENT_BLUE` bar/knob 形态吻合）+状态栏
「Entity: Hero」；未选拍=裸方块无描边无手柄。**拾取→选中→描边/gizmo 全链窗口级证据
成立。** 画布级小图两拍 md5 相同（A7 同帧 flake，报告 D7 自认，同意）——但报告 §二
「移动 gizmo 红绿双轴绘制在画布」措辞过强：该截图里可见的是描边+蓝 stem/旋钮/中心枢轴，
未见红绿双轴手柄；按所见措辞降级记档（F3）。

### 2. 移动 gizmo 拖拽/方向键/undo 链（M3，#653）——归档零证据，QA 三次亲跑被通道堵

- **归档缺口（A1）**：报告 §二「交互钉死：0→90→92→90→0」无任何归档载体——
  console-editor.log（终轮）只有 M1a/M7_NEW_TOP/M1b 三腿并以 ecomp 尾巴截断；
  `RESULTS_FILE` 判定行、M3 链数值均不在档。
- **根因之一已钉死**：终轮 console 恰死于脚本 M1c 的 `$drop_sprite` 未绑定变量
  （`set -u` 下必死；t21-live.sh :1090 附近）——**归档版脚本不可能跑完 M1c 之后的
  腿**，9 项 PASS 声明只能出自未归档的会话/改版（A1）。
- **QA 亲跑三次尝试**：会话一（GUIDES/SP9/M9 绿；M3 窗口 Transform 读全空）、
  重试二/三（加了「读就绪门」仍 NEVER-READY 整轮 120s+）；对照诊断 boot（同 boot 流程、
  原始 BRP 直读）`get_components(Hero, Transform)` 即时全量应答（translation [0,0,0]）
  且 20s 后稳定。**编辑器 BRP 读窗口期不稳（世界查询答、组件读空/整窗读空）被 QA
  独立复现 ≥3 次**——D5/D13 的现象族真实存在，且比报告描述更广（连 world.query
  也会整窗失败）。
- **裁定**：M3 链真机判定=「声明未归档，QA 复跑通道受阻」；能力面由 H 侧 App 级
  stage 族（sprite_gizmo 31/31 在 563 全量内）+诊断 boot 的组件读回+M2 选中链在证
  支撑。**T3 用修复后的工具通道补跑真机拖拽链**（§八-3/4）。

### 3. 绘制顺序 z 翻转 PX（M7）——归档对字节相同（无效），QA 复跑再现通道僵死；z 语义旁证成立

- **A2（归档证据无效）**：`shot-m7-blue-top.png` 与 `shot-m7-red-top.png` **字节相同**
  （md5 08cd8071…双双相等）——一对截图里没有翻转。报告 §二 引的「0.583%→0.674%」
  与派单注记「0.743%>0.652%」都对不上归档文件（QA 实测该帧 red 0.737/blue 0.646）。
  0.743/0.652 恰是 QA 在自己会话对同一僵死帧的实测值——**归档对是 17:32 那帧的
  复制品**。
- **通道僵死被 QA 再证**：会话一 qa-m7 两拍与程序归档帧**跨会话逐字节相同**
  （settle 6s 无效）——`jackdaw/screenshot kind=viewport2d` 返回陈旧帧；QA 的
  atlas-canvas 拍则整幅黑帧。**viewport2d 截图通道在本环境（1 FPS 软渲染）不可作
  像素判据**（A7 家族 sprite 形态）；window 级截图是新鲜帧（M2 窗口对为证）。
- **z 排序语义旁证成立**：QA 会话画布（shot-qa-atlas-canvas.png）亲读=TopSpr（蓝，
  z=3）盖 Dropped（红，z=2）且左侧露出恰 10 世界单位宽的红条——与两实体 x 坐标差
  几何一致；FS（scene.bsn）z=2/3 在档；引擎 sort key 语义（方案事实八）+stage 族
  在案。**「z 值可编辑、叠序随 z」判定维持绿；「翻转两拍 PX」半格降级为通道受阻，
  T3 用 window 级截图+帧差判据补跑**（§八-4）。

### 4. 参考线（#656 GUIDES_ADD）——绿，QA 亲跑

QA 会话：`canvas.guide.add vertical@64`→根实体（4735v1）`CanvasGuides` face
`{"horizontal":[],"vertical":[64.0]}` BRP 读回 ✓（console-qa.log 在档）。报告判定维持。
（注：盘面 scene.bsn 无 CanvasGuides——该证据是活世界 BRP 面，与报告口径一致。）

### 5. sprite.add 三件核（#657）

- **占位签名**：M1_OPERATOR_PASS 在档（console-editor.log :2-4：selection=OpSprite2、
  face `custom_size:[32,32]`+`texture_atlas:null`+Anchor 组件在）✓。
- **画布拾取**：§四-1 窗口对 ✓。
- **保存重开**：QA 亲跑三件（§六 M9 行）✓。FS 旁证：scene.bsn 含 OpSprite 占位
  （custom_size 32×32）+Dropped（hero.png 图片形态）——占位/图片双态落盘 ✓。

## 五、SP3 图集真机+三态复核

### 1. 资产链头（绿，全项在档）

ATLAS_KIND_FACE（菜单文本未检出，脚本如实记 FAIL 走 operator 路）→ATLAS_NEW（卡落盘）
→ATLAS_GRID（6 URect 2×3 of 32×16）→ATLAS_UNDO/REDO（FS 双向）→ATLAS_REOPEN——
七判定行在 console-atlas.log；QA 亲验 staged/工程两处 `content/sheet.bsn` 均含
6 URect ✓；staged export-manifest.json 含该卡的 sha256 行 ✓。

### 2. wear 三路堵（D9）——同意记档；「盘面正门」两态成立、一态被归档否定

- **交互三路堵**：console-atlas.log :9-12 原文在档（-23402 Handle-in-struct 结构限制
  尾巴）✓，报告 D9 诚实。
- **可保存**（FS）：工程 scene.bsn `texture_atlas: Some(bevy_image::texture_atlas::
  TextureAtlas { layout: "content/sheet.bsn", index: 2 })` 在档 ✓（QA 亲读）。
- **可运行**（游戏侧 walk 装载）：direct-m13.log「**Loaded 1 asset files** from …/
  assets」+零装载 error/warn+SheetSpr `With<Sprite>` presence 在档——**图集卡经 M10
  walk 进游戏**（与 headless M10 测试同链）✓；staged 同形（staged-run.log+包内文件）✓。
- **A3（编辑器画布渲染声明与归档相反）**：报告 §三「编辑器解析零警告+画布渲染
  31×13 蓝 index-2 tile」**不被归档支持且被否定**——①17:34 终轮与 17:18 export boot
  与 QA 自己的 boot 三处一致出现 `Could not find an asset loader matching …
  content/sheet.bsn`（bevy_asset ERROR+asset_failures WARN「showing the previous
  content」，editor-editor.log/editor-export.log/editor-all.log 在档，QA 会话 5 行）；
  ②17:26 编辑器画布截图（shot-m2-selected-window.png SheetSpr 区域亲读放大）与 QA
  会话画布（shot-qa-atlas-canvas.png）均为 **64×48 全图渲染**，非蓝 tile。**编辑器
  侧 wear 的画布渲染=全图+loader ERROR，是一致、可复现的现状**。定性：新候选缺陷
  （建议 SP11）：编辑器 scene→Sprite Atlas 定义资产 handle 解析链缺 loader 面（编辑
  卡本身可开可编——走 catalog 面；穿它的场景 sprite 的 layout handle 走 AssetServer
  面失败）。「可编辑」三态判定不受阻（创建/切分/指认/保存全在），受损的是「画布即
  预览」对图集的覆盖——**T3 book 图集节必须如实写此现状**（§八-2）。
- **A4（游戏/导出蓝 tile 普查无效）**：M13_ATLAS「6.222%」/M15「3.339%」两数 QA 亲测
  复现（6.268/3.389，步进差），**但 gshot 是全屏捕获**——蓝色份额主体是桌面壁纸
  （游戏窗内裁剪重测=0.211/0.191，且 worn/unworn 两对同值）；tile 的世界位置恰被
  macOS TCC 授权弹窗（「ZCode.app 想访问网络宗卷上的文件」）遮挡（三张截图同弹窗在
  档）。**蓝 tile 的游戏/导出窗口像素证据不成立**（判据阈值 >0.005% 被壁纸平凡满足，
  ATLAS 两腿的 PASS 名义无效）；document 文本半（index: 2）成立。T3 重跑口径：先关
  TCC 弹窗+用窗口内裁剪 census 或帧差（§八-4）。
- **ATLAS_INDEX_PX（atlas 相）=假阳性**：三张 index 截图（index0/1/2）**字节相同**
  （md5 全等）——wear 未生效时全图渲染本就恒含红绿蓝三色，腿判据（各自 >0.02%）
  平凡通过。同意报告 D9 的「component.set 路线未生效」结论，但该腿名义 PASS 应记
  无效（A5）。

### 3. 三态结论裁定

**维持报告的三态成立**：图片/Sheet→**可编辑**（三入口 operator 在证+拾取/描边/gizmo
窗口对+Inspector 机器+图集卡创建/切分/undo/重开；画布对图集 wear 的预览现状按 A3
如实降格）→**可保存**（save→重开逐字段+bsn 全路径类型+kind 再识别，QA 亲跑三件绿；
图集引用 FS 在档）→**可运行**（direct：walk 装载「1 asset files」+presence+Transform
读回==授权值；导出：export_wait+SHA+manifest 全清单+staged 数值+包内 atlas 卡——
M15 六件判定行在 console-export.log；游戏/导出窗口蓝 tile 像素半按 A4 记无效，
loader 链由 walk 日志承载）。16 格正式判定仍归 T3。

## 六、SP9/M10 产品落地复核——成立

1. **SP9 源码亲读**：`src/inspector/anchor_presets.rs`（274 行）——ANCHOR_PRESETS
   九常量与 fork `bevy_sprite` Anchor 九常量逐值相等（sprite.rs :308-316 亲读对表）；
   写路=`.0` 字段经 `apply_field_json_with_undo`（与裸 Vec2 行同一函数、同 undo 通道，
   reflect_fields.rs :2179/:2666/:2746/:2784/:2816 调用面亲读）；glam serde 二数序列
   形态契约+`apply_json_to_reflect` 生产 applier+1e-5 噪声容差+形状负测试；
   spawn 钩在 `spawn_reflected_fields` 的 Anchor downcast（reflect_fields.rs :76-87），
   卡内先于裸 offset 行。**单测 3/3 QA 亲跑绿**。`paint_anchor_presets` 跟随组件真值
   （undo/轴输入回落均刷色）✓。
2. **SP9 真机**：QA 会话 walk 亲证 **9 个格点+Anchor 头+Pivot 标签在 DOM、rect 全零**
   （`walk-qa.json` 抽取）——D10 的「widget 在证+滚动裁剪」精确再现；QA 补做的
   ui_drag 滚动尝试未揭示（面板滚动对 walk rect 无效）。点击腿=两轮三堵（程序 1+QA 2），
   按原口径留非 Retina/GPU 会话或 T3。**SP9 判定维持**（代码+单测+widget 在证；
   写路径契约生产级在测）。
3. **M10 源码亲读+亲跑**：`crates/jackdaw_runtime/src/lib.rs` :2146-2211——编辑器
   catalog 序列化器产身（`serialize_assets_to_bsn`+`with_asset_header`）→
   `load_walked_assets`→catalog 句柄+Assets store 6 tile+帧序断言（第三帧开第二行）；
   **10/10 亲跑绿**；与游戏日志「Loaded 1 asset files」互证（§五-2）。

## 七、偏差 D1-D15 抽核裁定 + QA 新发现

| # | 抽核结果 | QA 裁定 |
|---|---|---|
| D1 | T2 子集口径 | 同意记档；16 格正式判定归 T3 不变 |
| D2 | 磁盘满复发 | 同意已处置；终 prep df 脸 67Gi 在档；「清 78G 证据均在档」未见于归档——措辞降级（F4），不阻断 |
| D3 | export 锁竞争 | 同意；重跑 6/6 判定行在档 ✓ |
| D4 | Sprite 两侧 BRP -23402 | **维持**：错误原文在档（console-probe.log :7 全文+editor 侧尾巴），「presence+Transform+盘面」拆分口径正确；SP11+ 候选照报告 |
| D5/D13 | 陈旧实体 id/重生 | **现象为真且比报告更广**（QA 复现：M3 窗口组件读空、两次 boot 整窗读空 NEVER-READY、诊断 boot 同流程全绿；atlas 会话 ChildOf-invalid ×4、QA 会话 ×1 在档）；「现取现读」缓解在档但 QA 加了读就绪门仍整窗堵——机制钉死（watch-reload vs 重建）与工具票建议维持；**归档证据弱**（editor 日志逐 boot 覆盖，-23401 原始行不在档）如实记 |
| D6 | M1_MENU | 判定行在档（M1_MENU_FAIL）✓ 同意驱动缝记档，不升级产品缺陷 |
| D7 | M2_OUTLINE_PX | 画布对 md5 相等 QA 亲证 ✓；窗口对有效（§四-1）✓ 同意 |
| D8 | snap 腿 | sprite_snap H 侧在全量 stage 563 内亲跑绿；真机腿同 D5 口径，同意 |
| D9 | wear 三路堵 | 原文在档 ✓；**附加 A3/A5**（§五-2） |
| D10 | SP9 点击 | walk 九格点 0-rect QA 亲证 ✓ 同意 |
| D11 | M7_NEW_TOP | 判定行在档（FAIL，读回空）✓ 同意（z=top+1 语义亦无归档载体，与 A1 同族） |
| D12 | Recovered Work 弹窗 | 自守代码在档（editor_boot：清 journal+ui_tree「Recovered」探弹+ui_click Discard）✓ 同意记档+自守勿删 |
| D14 | 红态 console 覆盖 | 同意如实记档（editor 相终轮同为覆盖受害者，见 A1） |
| D15 | claim_free_name 改名 | M1a 面里 OpSprite2 在档 ✓ 同意 |

**QA 新发现（A 系，记档级，不阻断）**：

| # | 发现 | 证据 | 建议 |
|---|---|---|---|
| A1 | 「最后一轮 9 项 PASS」与 M3「0→90→92」链**无归档载体**；终轮 console 恰死于脚本 `$drop_sprite` unbound（set -u 必死），归档版脚本不可能产出该轮 | console-editor.log 12 行即终；t21-live.sh M1c 块 | 报告相应声明降级为「会话在证、归档缺失」；下轮报告对每条 PASS 声明给归档指针 |
| A2 | 归档 M7 对**字节相同**；viewport2d 截图通道僵死帧（跨会话逐字节相同）/黑帧被 QA 双再现 | md5 08cd8071…；shot-qa-m7-*.png；shot-qa-atlas-canvas.png | 工具票（A7 家族续）：screenshot 通道补「强制重绘/新帧判据」；M 系像素腿改 window 级+帧差 |
| A3 | 编辑器对穿图集场景：**asset-loader ERROR（content/sheet.bsn 无 loader）+画布全图渲染**，三会话一致可复现——与报告「解析零警告+蓝 tile 31×13」相反 | editor-editor/editor-export/editor-all.log；两张画布截图放大亲读 | **新候选缺陷 SP11**（scene→定义资产 handle 的 loader 面）；T3 book 如实注记 |
| A4 | 游戏/导出「蓝 tile 普查 6.222%/3.339%」系**壁纸主导**（窗内 0.211/0.191，worn/unworn 同值；tile 被 TCC 弹窗遮挡） | gshot 全屏帧亲读+窗内裁剪重测 | 两腿 PASS 名义记无效；T3 先关 TCC 弹窗+窗内裁剪判据 |
| A5 | atlas 相 ATLAS_INDEX_PX 三拍**字节相同**=假阳性 PASS（判据为存在性非变化性） | md5 全等 | 判据改帧差；与 A2 同族 |
| A6 | warn 扫描模式（UnresolvedTypes|cannot-apply|panicked）**漏报** asset-loader ERROR/asset_failures WARN——三会话 ERROR 均未被 WARN_SCAN 捕获 | editor-export.log 3 行 ERROR 在档而各 WARN_SCAN=zero hits | WARN_PATTERN 增补 `asset load failed|Could not find an asset loader` |
| A7（nit） | 报告「0.187%（windowed 同位 0.000%）」的窗口全域 0.022% 与 QA 全窗复测 0.025% 之差为采样步进（步 1 vs 步 2），非矛盾——条带三数逐位一致 | 本报告 §三 | 无动作 |

## 八、裁决与放行 T21-T3 建议

**裁决：PASS。** 依据：门禁 12 门亲跑全绿（§二）；SP7 定案维持且 QA 亲测复现（§三）；
能力面核心项独立证据成立（§四-1/4/5）；SP3 资产链+可保存+可运行在档（§五）；SP9/M10
产品落地亲读亲跑成立（§六）；D1-D15 抽核无虚报，三处声明过强按 A1-A4 更正（§七），
均不动摇验收句骨架。

**放行 T21-T3，附回流清单（按优先级）**：

1. **SP11 立票评估（新候选缺陷，主控裁）**：编辑器 scene→Sprite Atlas layout handle
   的 AssetServer loader 缺面（ERROR+全图渲染）；修复面在定义资产 handle 解析/loader
   注册；修复后编辑器画布应渲 index 帧——这同时是 book 图集节「画布预览」现状的
   修复门。
2. **T3 book 扩节书单**（sprites-2d.md+交叉引用）：scene.new kind=2d／sprite.add
   三入口／画布交互（拾取/描边/gizmo/参考线）／属性面+Anchor 九宫格（SP9）／量纲
   PPU 对照表（SP5 决策 2-A）／图集切分（Atlas 卡+grid operator+index；**编辑器画布
   wear 预览现状与盘面/游戏侧正道如实注记**，SP11 关联）／绘制顺序 z 语义（SP8 注记
   已在 open-challenges）／过滤现状与正道（SP4 决策 5-A）／PIE 与导出（**SP7 结论：
   embedded 保 PX、windowed 数值轨、direct 为 truth**）；game-ui.md/assets.md/
   scene-management.md 交叉引用。
3. **工具票两件（MCP 优先原则，主控裁并入 A7 或续编）**：①viewport2d screenshot
   僵死帧/黑帧（强制重绘或新帧判据能力）；②编辑器 BRP 读窗口期 flake（组件读整窗
   空，比 A9 游戏侧同族更广；读就绪门+服务侧指纹落盘建议照 A9 票内方法）。
4. **T3 真机补跑口径**：M3 拖拽链/M7 翻转腿用 window 级截图+帧差判据+读就绪门；
   M13/M15 蓝 tile 先关 TCC 弹窗再用窗内裁剪 census；M1_MENU 与 SP9 点击腿维持
   「非 Retina/GPU 会话或工具票后」。
5. **脚本修复三件**（t21-live.sh）：M1c `$drop_sprite` unbound（终轮死因）；
   ATLAS_INDEX_PX/M7 判据改帧差；WARN_PATTERN 增补 loader/asset_failures 行（A6）。
6. **报告更正记录**：t21-t2-report.md §二（9 项 PASS/M3 链出处）、§三（编辑器画布
   蓝 tile+零警告、6.222%/3.339% 口径、ATLAS_INDEX_PX）按本 QA 报告 §四/§五/§七
   更正——不回流程序轮，T3 引用时以本报告为准。
7. **A16/A11 注记交接**：两票与 T21 零耦合（T21 未走 flow 通道、未触碰 rebind），
   维持台账原状；T3 book 若涉「运行」节，flow 现状按 A16 口径（模板走文档根标记）
   一句话注记即可，不展开。

## 九、给主控的一句话

T21-T2 的建设面（六 PR 移植落地+SP3 图集授权链+SP9 Pivot 面+M10 walk 转正）与探针
定案（SP7）经 QA 亲跑成立；真机像素证据的三处缺口（编辑器画布 wear 渲染、M7 翻转对、
蓝 tile 普查）均已定位到根因（loader 缺面/截图通道僵死/全屏普查污染）并成票——
放行 T3，证据纪律按 §八-1/3/4/5 收口。
