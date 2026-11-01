# T21 任务 3「book sprites-2d 新章 + 剩余记档件书面处置 + 终验准备」程序报告

> 分支 `loop/t21-sprite`（`git merge main` 快进到 **bb4b75b9**——T2 已合入；T3 零 src/、
> 零 crates/ 产品改动，改动面=book 五文件+T2 报告勘误落账+`loop/qa/t21-live.sh` 脚本修复
> +本轮证据归档）；方案 `loop/plans/t21-sprite.md` §四-T3+§六-T3 书单；T2 交接
> `t21-t2-report.md`/`t21-t2-qa.md`（§七 A1-A7/§八-7 项回流随本轮落账）。真机 macOS
> arm64，fixture `/Users/zhanglinbo/workspace/loop-mac/t21-sprite`（每轮 `prep` 先行——
> D15 口径）；全程未设 RUST_BACKTRACE；df 门前 53Gi free（A6 家族脸行在 console-prep.log）。
> **判语：book 新章落地（sprites-2d.md 十节+SUMMARY 挂目+四处出链交叉引用）；T2 QA
> Errata 6 条（A1-A5+F3）+F4 附注全落账（t21-t2-report.md 原位修正+「E* 勘误」标注，
> T19-T3 先例形态）；关键格终态复跑=拾取+描边三轮全绿（window 级像素差 1.27%）、SP3
> 三态的可编辑/可保存/可运行链绿（New Asset→grid→重开→游戏 walk→staged 前基座回归），
> 移动链与 SP9 点击腿按 T2 QA 常规口径记「通道受限」（编辑器 BRP 读窗/实体重生 D13
> 家族在本会话三轮复现并取得跨实体写落的新证据）；**新发现（记档级）**：run 侧与编辑器
> 画布同形——图集 wear 的 sprite 在游戏窗口渲染全图（全分辨率截图归档），A17 机制注记
> 从「loader 缺面」精化为「场景 AssetServer 路径柄不解析到 walk 装载的卡（双柄空间）」；
> warn 扫描零命中（词表含 A6 增补）、N13=0。buglist/台账/roadmap 未动（主控合入时落笔）。
> 日期 2026-11-01。

## 〇、最终判定汇总

```
Errata 落账（t21-t2-report.md，原位修正+标注，原文不灭失）:
  E1=QA A1（「最后一轮 9 项 PASS」+M3 链数值无归档载体→「会话在证、归档缺失」降级）
  E2=QA A2（M7 归档对字节相同+viewport2d 通道陈旧帧；z 语义维持，补跑口径=window+帧差）
  E3=QA F3（「红绿双轴」措辞过强→所见=描边+蓝 stem/旋钮/中心枢轴）
  E4=QA A3（编辑器画布 wear「零警告+蓝 tile」被否定→全图+loader ERROR；SP11/A17）
  E5=QA A4（6.222%/3.339% 壁纸主导全屏普查→像素半无效，文档文本半维持）
  E6=QA A5（ATLAS_INDEX_PX 三拍字节相同=假阳性→无效）
  F4（§六 D2「清 78G 证据均在档」措辞降级——处置本身 df 脸 67Gi 在档复证）
  落账注记=该报告 §八（新增节）；T2 QA 报告本体零触碰。

book（本轮核心交付）:
  新章 book/src/user-guide/sprites-2d.md（10 节+A17/SP8/SP4/SP7/SP10/A16/A11 如实注记）
  SUMMARY.md 挂目（Game UI 与 Audio 之间）
  出链交叉引用四处：game-ui.md（两画布对照段）、assets.md（2D 拖放例外句）、
  remote-control.md（input.pointer space=world 段）、keyboard-shortcuts.md（Arrows 行
  2D 注记）——T1 报告 §五校对点清单五项全部兑现（第 5 项=新章本体）
  准确性校验：operator 形态逐个对源码（sprite.add/sprite.atlas.grid/canvas.guide.add/
  canvas.snap/anchor 九常量/PIE embedded-windowed 结论/PPU 对照表/吸附次序=源码 doc 措辞）

关键格终态复跑（t21-live.sh 三轮 editor+atlas+game；每轮 prep 先行）:
  格一：六 PR 拾取+描边    三轮全绿——M2_PICK/M2_OUTLINE_PX/M2_CLEAR；window 级描边
                          像素差 1.27%（702218→5739552px 通道对，A2 口径落地）
  格一：六 PR 移动         通道受限——读窗死+camera_state 死（60s 门未开）+截图证 Hero
                          未动；set_verified 取得跨实体写落证据（Hero z 值落在 TopSpr
                          面上）=D13 实体重生家族的新证据；能力面由 H 侧 sprite_gizmo
                          31/31（563 全量内）+M3B_ROTATE 三轮绿+T2 会话在证承载
  格二：SP3 图集三态       可编辑=NEW/GRID/REDO/REOPEN 绿（UNDO 本会话红，T2 绿在档）；
                          可保存=文档 wear+M9 三件绿（editor 相）；可运行=game 相 4/4
                          （NUMERIC/CAM2D/WINDOW_PX 关 TCC 弹窗后 0.033%/ATLAS 文档+
                          walk「Loaded 1 asset files」）
  格二附：ATLAS_INDEX_PX   严格判据（sprite 区域裁剪帧差）离线判定=三裁剪逐字节同→
                          无效（D9 组件写通道+A17 全图渲染），与 T2 QA A5 裁定同形；
                          归档 console 里宽判据（全窗 cmp）的 PASS 被本判定取代
                          （全窗 cmp 被窗口 chrome 噪音平凡满足=A5 的镜像缺陷，已修）
  格三：SP9 锚点预设       三轮 red=点击/滚动裁剪（D10 家族，本会话复现）——QA §八-4
                          常规口径「非 Retina/GPU 会话或工具票后」维持；判定由源码+
                          单测 3/3+DOM 九格点在证（T2 QA 亲证）承载，本轮零回退
  run 侧新发现（记档）     图集 wear 的 sprite 在 direct 游戏窗口渲染全图（shot-
                          M13_ATLAS-window.png 全分辨率+局部放大归档；文档 index:2+
                          walk 装载在案）——与编辑器画布 A17 同形且本会话无 loader
                          ERROR（prep 先建卡）→机制注记精化=「场景柄（AssetServer
                          路径）不解析到 walk 装载的卡」，A17 票修复面参考
纪律腿: warn 扫描（词表含 A6 增补 loader/asset_failures 行）editor/atlas/game 全零命中；
  N13=0（本轮未跑 PIE 相；全部 console 零 panicked 行）；游戏窗口像素腿先关 macOS TCC
  授权弹窗（osascript System Events 点「允许」，QA §八-4 口径）后重拍
门禁: 九门终态=fmt ✅ / clippy 全仓(--all-targets --features dylib) ✅ / 物理双包 ✅ /
  libtests **3029/0**（teaches **92**）✅ / fast **3029/3029** ✅ / integration 主段
  **5575/5575**+animation 1/1（唯一 flaky=prefab 文件监视族第 3 试过，0 新增红口径
  维持）✅ / doctests 全量轮 bind-dyld 第 14 次目击→单包复跑 **1/1 绿**（T15 处方，
  双 log 归档）✅ / docs EXIT=0（13 条警告=T17/T19/T20 基线同数同族）✅ /
  scaffold_e2e **1/1**（147.9s）✅
磁盘: 门前 53Gi free → 门后 47Gi（A6 家族无泄漏）；门后 pgrep 零残留。
```

归档：`loop/reports/t21t3_*`（门禁九 log+exit 台账+gate 脚本）；工作证据 `loop/t21-live/`
（editor 三轮 console `console-editor{,_r1,_r2,_r3}.log`、atlas/game console、M7 三轮窗口
截图对+round2 归档件、M13 游戏/图集窗口全分辨率截图+局部放大件、atlas index 三拍+严格
判据裁剪件、prep/T2 时代 console 保全件 `console-atlas_t2.log` 等）。

## 一、Errata 落账（T2 QA 回流；核对现状=缺，本轮补齐）

核对结论：`t21-t2-report.md` 在 T3 前无任何勘误标注（六条更正全部未落）。按派单
「缺则补」+T19-T3 先例（errata 随 T3 报告面落，纯报告面不触代码），逐条落账：

| # | 落账位置与内容 |
|---|---|
| E1（QA A1） | §二 editor 相导语+M3 行：终轮归档 console 恰死于脚本 `$drop_sprite` 未绑定（`set -u` 必死，M1c 处）——「最后一轮 9 项 PASS」与 M3 链数值（0→90→92→90→0）无归档载体，降级「会话在证、归档缺失」；能力面由 H 侧 stage 族+M2 选中链+诊断 boot 组件读回在证 |
| E2（QA A2） | §二 z 行：归档截图对字节相同（md5 08cd8071…），引注普查数不被归档支持；viewport2d 通道陈旧帧；z 排序语义维持绿（QA 几何旁证+FS+引擎 sort key），「翻转两拍 PX」半格降级通道受阻 |
| E3（QA F3） | §二 #650 行：「红绿双轴」措辞过强——归档截图亲读所见=描边+蓝 stem/旋钮/白色中心枢轴（ACCENT_BLUE 形态吻合） |
| E4（QA A3） | §三 wear 行：「解析零警告+画布蓝 tile」被归档否定——三会话一致 loader ERROR+画布全图渲染；SP11（buglist A17）立票；本报告 §三-4 另有机制精化 |
| E5（QA A4） | §三 direct/export 行：6.222%/3.339% 系全屏捕获壁纸主导（窗内 0.211/0.191，worn/unworn 同值；tile 被 TCC 弹窗遮挡）——像素半记无效；文档文本半+walk 装载日志维持 |
| E6（QA A5） | §三 index 行：ATLAS_INDEX_PX 三拍字节相同=假阳性 PASS 记无效；D9「component.set 路线未生效」结论与盘面值证据维持 |
| F4（附注） | §六 D2 行：「清 78G 证据均在档」措辞降级（未见于归档）；处置本身由终 prep df 脸 67Gi 复证 |

原位修正处均带「E* 勘误（T2 QA …，T3 落账）」标注，原文数字不灭失（报告面可审计）；
`loop/reports/t21-t2-report.md` 尾部新增 §八「Errata 落账注记」节列对照表。T2 QA 报告
本体零触碰；后续引用以 t21-t2-qa.md 为准。

## 二、book 新章（方案 §六-T3 书单+T2 QA §八-2 扩节书单）

**`book/src/user-guide/sprites-2d.md`**（新章，10 节，~230 行；章名「Sprites in 2D」）：

1. **导语**：2D 世界场景=3D 视口的平面对应物（1 world unit : 1 texel）；UI 场景对照
   指路 game-ui.md。
2. **A 2D scene**：`File > New Scene` 2D kind（`scene.new kind=2d`）+画布 pan/zoom
   （viewport-navigation）+launcher「2D game」模板；**决策 6-A 家具噪音如实注记**
   （模板 lib 仍带 3D rig/物理，「runs fine; trimming that furniture is your first
   edit」）。
3. **Making a sprite**：三入口同归一 operator（Add 菜单 2D 组 Sprite/Empty 2D 行、
   `sprite.add path/x/y/parent/name`、图片拖放）；占位 32×32；新 sprite z=最高+1；
   2D 场景 UI 节点/参考板对照；**SP10 注记**（3D 组照常出现，Cube 不报错但 2D 相机
   画不出）。
4. **Select, move, rotate, scale**：拾取+描边+三 gizmo（move 全选/rotate-scale 主
   sprite/绕 Anchor 旋转）+方向键+逐级 undo；参考线（`canvas.guide.add axis=…
   position=…`，存场景根）；吸附（Use Snap/Use Pixel Snap；先邻 sprite 边/心或参考
   线、再网格、再整像素；Ctrl 反转）；`input.pointer space=world` 指路
   remote-control.md。
5. **The Inspector: sprite fields**：Sprite 字段表（image/color/flip/custom_size/
   rect/texture_atlas/image_mode 四态含 Sliced 九宫/alpha_mode）；**SP9 Pivot 面**
   （3×3 九常量预设格+裸 offset 行，同一写路同一 undo）。
6. **Sizes and pixels（the PPU question）**：**SP5/决策 2-A 定性教学**——无 PPU 概念、
   1:1 量纲、Unity PPU 对照表（PPU100 的 64px ↔ custom_size 0.64 或 scale 0.01/
   半尺寸=custom_size 32×32 或 scale 0.5/像素完美=两者都不动）；custom_size vs scale
   二选一纪律；**SP4 过滤注记**（per-asset sampler 不持久，今日=全局默认或代码侧，
   per-asset 持久面记 open work）。
7. **Sprite atlases**：New Asset→Sprite Atlas 卡；`sprite.atlas.grid tile_size=…
   columns=… rows=… [padding] [offset]`（帧序左→右上→下、整刀一条 undo、卡内
   URect 手编=非网格布局）；Sprite.texture_atlas 指认+index；**A17 现状如实注记**
   （编辑器画布渲全图——本会话证据精化：卡已在盘时 loader ERROR 不出现而全图渲染
   依旧，机制=场景柄不解析到卡；游戏/导出经 walk 装载卡但 wear 的 sprite 同样渲染
   全图——**本轮新证据**，见 §三-4）。
8. **Draw order**：z 语义（小 z 先画；新 sprite=top+1）；**SP8 注记**（排序面板/
   Y-sort 记 open work，今日 z 即全部授权面）。
9. **Playing and shipping**：**SP7 结论**（embedded 流送帧忠实、windowed 流=Camera3d
   无 2D pass→以游戏窗口为 truth）；导出携带整树含图集卡；**A16 一句话注记**（模板
   流程读文档根标记，`State<GameFlow>` 尚不可 BRP 读，修复=模板一行，挂下轮触模板）；
   **A11 注记**（编辑器外改名/移动→Rebind 重写文档，活世界组件持旧柄至重开）。
10. **The 30-second check**：五条（2D 模板开箱 Play→拖 png→点选拖动 nudge undo→
    Pivot 预设+color→图集卡全链含 A17 现状句→重开逐字段）。

**SUMMARY.md**：`- [Sprites in 2D](user-guide/sprites-2d.md)` 挂 Game UI 与 Audio
之间（方案口径「game-ui 附近」）。

**出链交叉引用（T1 §五校对点清单全兑现）**：

| 文件 | 改动 |
|---|---|
| `game-ui.md` | The 2D canvas 节尾新增两画布对照段（UI=屏幕像素/2D 世界=世界单位；2D 组仅在 2D 世界场景出现）指路新章 |
| `assets.md` | 五族导入段拖放句尾补 2D 世界场景例外（拖图成 sprite 而非参考板）指路新章——T1 校对点 1 |
| `developer-guide/remote-control.md` | Turning the camera 节补 `input.pointer space=world` 段（世界坐标 y up 随 pan/zoom）指路新章——T1 校对点 3 |
| `keyboard-shortcuts.md` | Arrows 行补「in a 2D scene, moves the selected sprite」——T1 校对点 4 |

**入链（新章出链目标）**：game-ui/scene-management/viewport-navigation/assets/
play-in-editor/game-flow/asset-references/remote-control 八个相对链接逐一核实存在；
链接目标章节用词对照既定名防杜撰（Embedded/Windowed=play-in-editor.md :294-311；
「Missing References」/「Rebind」=assets.md 原词）。

## 三、关键格终态复跑（派单抽 3 格：六 PR 拾取+描边+移动／SP3 图集三态／SP9 锚点预设）

### 1. 脚本修复（T2 QA §八-5 三件+本轮判据两件，全部随本轮落 `loop/qa/t21-live.sh`）

| 修复 | 内容 | 对应回流 |
|---|---|---|
| M1c unbound | `$drop_sprite` 未赋值即判（`set -u` 必死，T2 终轮死因）→赋值+判定改 `With<Sprite>` presence 查询（Sprite 组件 -23402 结构限制下 face `.image` 判据永不成立=D4 口径的脚本面落实） | QA §八-5 |
| WARN_PATTERN | 增补 `asset load failed\|Could not find an asset loader`（捕获归属用；fail-set 仍=UnresolvedTypes/cannot-apply/panicked 不变） | QA A6 |
| M7 判据 | viewport2d 截图（陈旧帧通道）→window 级+帧差（md5）+色彩份额随翻转移动（红升蓝降；chrome 恒量不参与判据） | QA A2/§八-4 |
| ATLAS_INDEX_PX 判据 | 存在性普查（A5 假阳性）→帧差；**二修**：全窗 cmp 被窗口 chrome 噪音平凡满足（A5 的镜像缺陷，本轮实见）→sprite 区域 sips 裁剪 cmp（裁剪件归档） | QA A5/§八-4 |
| 读就绪门+写验证 | `read_ready`（组件读门，QA §八-4 口径）+`camera_ready`（ortho_scale 门，M3 reach 数学前提）+`set_verified`（component.set 写后读回验证，3 试）——后者取得 §五-D1 的新证据 | QA §八-4/§八-3② |
| atlas_face 拼写 | 场景 wear 判定 grep 同时接受 `bevy_image::…`（编辑器保存拼写）与 `bevy_sprite::…`（fixture 复-export 拼写，引擎两侧均解析） | 本轮实证 |

selftest 4/4 绿（png_pixels_md5/tiles/census/solid）。

### 2. 格一：六 PR 拾取+描边+移动（editor 相三轮；每轮 prep 先行）

| 腿 | r1 | r2 | r3 | 判定 |
|---|---|---|---|---|
| M1_OPERATOR（sprite.add 占位签名） | PASS | PASS | PASS | 绿（三轮稳定） |
| M1_IMAGE（图片形态 presence） | FAIL(face 判据) | PASS | PASS | 绿（判定改 presence 后两轮绿；r1 红系旧判据与 D4 结构限制相抵，脚本已修） |
| M1_MENU（picker 2D 行） | FAIL | FAIL | FAIL | D6 驱动缝（常规口径，不升级产品缺陷） |
| M7_NEW_TOP（新 sprite z=top+1 读回） | FAIL('') | FAIL(未入表) | FAIL('') | 读窗死（写侧语义由 T2 交互钉死+H 侧在案） |
| M2_PICK（真指针拾取） | PASS | PASS | PASS | **绿（关键格：拾取）** |
| M2_OUTLINE_PX（描边） | (viewport2d 对) | **PASS（window 1.27% 差）** | PASS | **绿（关键格：描边；window 级像素差=A2 口径落地）** |
| M2_CLEAR | PASS | PASS | PASS | 绿 |
| M3_DRAG/ARROWS/UNDO（移动链） | FAIL('') | FAIL('') | FAIL('') | **通道受限**：读窗死（read_ready 门开而随读即死）+camera_state 60s 门未开（r3）+**截图证 Hero 未动**（m2 选中拍 vs m7 拍同位）——能力面由 H 侧 sprite_gizmo 31/31+M3B_ROTATE 三轮绿+T2 会话在证承载 |
| M3B_ROTATE / SCALE | PASS/FAIL | PASS/FAIL | PASS/FAIL | rotate 绿三轮；scale 读窗死 |
| SNAP_GRID / GUIDES_SNAP | FAIL | FAIL | FAIL | 读窗死（读回 ''） |
| GUIDES_ADD（#656） | PASS | PASS | PASS | 绿（CanvasGuides 根组件读回） |
| M7_Z_FLIP_PX（绘制顺序） | FAIL | FAIL | FAIL | **本会话红**：set_verified 证明写未落（§五-D1 新证据）；z 语义判定维持 T2 QA §四-3（几何旁证+FS+引擎 sort key+stage 族），通道修复归工具票 |
| SP9_PRESET | FAIL | FAIL | FAIL | D10 滚动裁剪家族复现——QA 常规口径维持；判定由源码+单测 3/3+DOM 九格点（T2 QA 亲证）承载 |
| M9_REOPEN/BSN_TYPES/KIND_REOPENED | PASS×3 | PASS×3 | PASS×3 | **绿（可保存链三轮稳定）** |

### 3. 格二：SP3 图集三态（atlas 相+game 相）

- **可编辑**：ATLAS_NEW（卡落盘）/ATLAS_GRID（6 URect 2×3 of 32×16）/ATLAS_REDO/
  ATLAS_REOPEN 绿；ATLAS_UNDO 本会话红（undo+save 后 6 行仍在——T2 绿归档
  `console-atlas_t2.log` 在案，本会话降级面随编辑器通道恶化，如实记）；ATLAS_WEAR 红
  =D9 交互驱动三路堵（常规口径）。
- **可保存**：文档 wear（`texture_atlas: Some(…TextureAtlas { layout: "content/
  sheet.bsn", index: 2 } })`）+editor 相 M9 三件绿（save→重开→逐字段+bsn 全路径类型
  +kind 再识别）。
- **可运行**：game 相终轮 **4/4**——M13_NUMERIC（Hero Transform 读回==授权值+
  SheetSpr `With<Sprite>` presence）/M13_CAM2D/M13_WINDOW_PX（**先关 macOS TCC 授权
  弹窗后** hero-red 0.033%，QA §八-4 口径实操）/**M13_ATLAS**（文档 wear+walk
  「Loaded 1 asset files」+窗图集面普查 6.363%——注：全屏普查口径按 A4 降为参考值，
  见 §三-4 的全图渲染发现）。staged 导出半边本轮未跑（T2 M15 六件绿在档；T3 派单
  抽格口径未含 export，省 release 冷编）。
- **ATLAS_INDEX_PX**：宽判据（全窗 cmp）名义 PASS 被严格判据取代——sprite 区域
  sips 裁剪（三拍各 130×110）离线 cmp **逐字节相同**（md5 0c15a625…×3）→无效；
  与 QA A5 裁定同形（D9 组件写通道+A17 全图渲染下「索引切换」无画布可见面）。裁剪
  三件归档 `loop/t21-live/`。

### 4. 新发现（记档级）：run 侧图集渲染与编辑器画布同形——A17 机制注记精化

终轮 game 相全分辨率截图（`shot-M13_ATLAS-window.png`，3024×1964）+局部放大归档：

- 游戏（direct run）窗口里 wear 的 SheetSpr 渲染 **全 2×3 sheet**（六 tile 逐色可
  辨：red/green/blue/yellow/magenta/cyan），非 index-2 蓝 tile；同帧编辑器画布
  （m7 截图对）同样全图。
- 本会话与 T2 会话的一个差异：prep 先建 `content/sheet.bsn` 后，**编辑器侧 loader
  ERROR 不再出现**（editor-editor/editor-atlas 日志零 `Could not find an asset
  loader` 行；T2 三会话均有），而全图渲染依旧——即「全图渲染」不以 loader ERROR
  为必要条件。机制注记从 A17 票面的「loader 缺面」精化为：**场景文档里的
  `Handle<TextureAtlasLayout>`（AssetServer 路径柄）与 walk/catalog 装载进 Assets
  store 的卡不在同一柄空间，路径柄永不就绪→sprite 提取回落全图**（两侧进程同形；
  游戏侧 WARN 零命中=回落静默）。A17 票的修复方向两臂（「scene 内 loader」或「改
  持图片路径+运行时构建」）以票面原文为准，本证据供主控裁修复面时参考；buglist
  本轮零触碰（纪律）。
- QA A4 的两数（窗内 worn/unworn 0.211/0.191 同值）与本帧互证：T2 的「游戏/导出
  窗口蓝 tile」像素半从一开始就不成立——全图渲染本就恒含蓝 tile 色彩。

### 5. 纪律腿

- **warn 扫描**：editor 三轮+atlas+game 五份 console 全零命中（词表=`UnresolvedTypes|
  cannot-apply|panicked|asset load failed|Could not find an asset loader`——A6 增补
  后首跑，零漏报复证）。
- **N13 记数=0**：本轮未跑 PIE 相（probe/PIE 腿属 T2 已定案范围）；全部 console 零
  `panicked` 行。
- **TCC 弹窗**：游戏窗口像素腿前经 osascript System Events 定位 UserNotificationCenter
  弹窗并点「允许」（QA §八-4「先关 TCC 弹窗」的实操；弹窗本体截图在
  `console-game_r1-occluded.log` 轮的归档帧）。
- **pkill 清盘**：每相 trap 清理；终态 `pgrep jackdaw|t21-sprite` 零残留（r1 编辑器
  相后与 game 相后各验一次）。

## 四、门禁（终树；全文捕获+全文复核，exit 仅辅助）

> 门链单独跑（T2 D3 纪律）；脚本=`loop/reports/t21t3_gates.sh`（T20-T3 同形），
> 逐门 log=`loop/reports/t21t3_gates_*.log`，exit/df 台账=`t21t3_gates_exit.txt`。
> RUST_BACKTRACE 全程未设。

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0，零输出（零 Diff） | t21t3_gates_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，63 行进度零 error/warning 行 | t21t3_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0，零行 | t21t3_gates_clippy_phys.log |
| 单测 | `cargo test --workspace --lib` | ✅ EXIT=0，**3029 passed / 0 failed**（`running 92 tests` 在文=teaches 92 达标） | t21t3_gates_libtests.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，lib 段 **3029/3029**（Summary 行在文），fmt/clippy 段零行 | t21t3_gates_fast.log |
| integration | `cargo xtask integration` | ✅ EXIT=0——主段 **5575/5575**（Summary「5575 passed (1 slow, 1 flaky)」）+runtime animation 分包 **1/1**；唯一 flaky=`prefab_lifecycle::prefab_file_change_triggers_reload` TRY 1/2 FAIL **第 3 试过**（文件监视时序族=T1/QA 两轮同族，非 sprite 域）——**A6 口径 0 新增红维持**；全文零 dyld 行 | t21t3_gates_integration.log |
| doctests | `cargo test --workspace --doc` | ⚠️ EXIT=101=**bind-dyld 家族第 14 次目击**（`-p jackdaw_bind --doc` 的 rustdoctest 临时目录 dyld `libstd` 不加载；红态全文归档 `_red.log`）→**T15 处方单包复跑 `-p jackdaw_bind --doc` 1/1 绿**（双 log 归档） | t21t3_gates_doctests_full-run_red.log + t21t3_gates_doctests_bind_retry.log |
| docs | `cargo doc --workspace --no-deps` | ✅ EXIT=0，**13 条**警告=12「public documentation for」+1「unresolved link to」——与 T17/T19/T20 基线同数同族（private-doc-link 家族；本轮零 src/ 改动=预存树态） | t21t3_gates_docs.log |
| scaffold_e2e | `cargo nextest run --profile ci -E 'binary(scaffold_e2e)'` | ✅ **1/1**（147.9s 含 check 新产品冷编） | t21t3_gates_scaffold_e2e.log |

门禁时间线 19:57-20:38（warm cache）；磁盘 53Gi→47Gi（A6 家族无泄漏）；门后
`pgrep jackdaw|t21-sprite|cargo` 零残留。纪律注记：bind 单包复跑与门链 docs/scaffold
段发生一次 cargo 锁串行（无日志污染，各自 log 独立归档）——「门链单独跑」纪律下
程序自查点，如实记。

## 五、偏差清单（如实分级）

| # | 偏差 | 级别 | 处置 |
|---|---|---|---|
| D1 | editor 相三轮的读窗/写落降级远重于 T2 会话：camera_state 60s 门未开、Transform 读连 `read_ready` 门开后仍死、**set_verified 取得跨实体写落直接证据**（Hero 的 z=3 落在 TopSpr 面上 `[-150,-40,3.0]`，Hero 本面 `[0,0,0]` 不动）——D13 实体重生/柄漂移家族的机制性新证据 | 记档（工具票弹药） | 三轮判定全部如实按通道受限记；根因钉死与修复=QA §八-3② 工具票（读窗 flake+服务侧指纹）范畴，MCP 优先原则归主控 |
| D2 | M3 移动链真机面在 T3 三轮均未取得新绿证（拖拽 dispatched 但截图证 Hero 未动——zoom 假设 1.0 时 handle 抓空） | 记档 | 关键格「移动」判定按 QA §四-2 既有裁定引用（H 侧+T2 会话在证），不另立产品缺陷 |
| D3 | atlas 相 ATLAS_UNDO 本会话红（undo+save 后 6 行仍在；T2 绿在档） | 记档 | 与编辑器通道恶化同窗；T2 归档 `console-atlas_t2.log` 保全，QA 终验可对照 |
| D4 | editor 相降级会话把 fixture 场景保存成 wear 丢失+重复 SheetSpr2 的盘面（跨实体写落的下游伤害），game 相首跑 M13_ATLAS 文档半因此红 | 已处置 | prep 重写 fixture 恢复 wear 前提后重跑 game 相 4/4；**降级会话会经「保存」污染盘面**这一点已入 §六 QA 注意事项（编辑器相与 game/export 相之间必须 prep 隔离） |
| D5 | game 相中间轮（wear 丢失前提那轮）console 被第三轮覆盖前未归档（D14 家族复发一次） | 流程偏差，如实记档 | 判定行已入本报告 §三-3 文字；r1 遮挡轮已归档 `console-game_r1-occluded.log`；终轮 console 在档 |
| D6 | ATLAS_INDEX_PX 宽判据（全窗 cmp）被 chrome 噪音平凡满足——A5 的镜像假阳性，本轮实见并二修为 sprite 区域裁剪判据 | 已处置（脚本） | 严格判据离线判定=无效（裁剪三件 md5 同）；归档 console 里该腿名义 PASS 以本判定为准 |
| D7 | M13_WINDOW_PX 首轮红=TCC 弹窗遮挡（QA A4 预言的实况再现）；osascript 关弹窗后 PASS | 已处置 | 弹窗处置命令与窗口枚举输出在 §三-5；QA 复跑前置同口径 |
| D8 | 派单「抽 3 格」建议含「六 PR 移动」——三轮尽瘁于通道受限，未复现出 T2 的交互绿 | 记档 | 依据 QA §四-2 既有裁定（工具票后补跑）；本轮贡献=门/验证器三件与跨实体写落证据 |
| D9 | export 相未跑（T2 M15 六件绿在档） | 记档 | 派单抽格口径未含；省 release 冷编与磁盘（53Gi 前提下 A6 风险规避） |

## 六、给 QA 终验的注意事项

1. **会话降级是本会话第一事实**：编辑器 BRP 的读窗与写落（含跨实体写落）在本会话
   三轮复现，远重于 T2。QA 复跑任何 editor 相腿请按「读就绪门+写后读回验证」口径
   （脚本已带 `read_ready`/`set_verified`，现版即口径）；**编辑器相跑完必须 prep
   重置 fixture 再跑 game/export 相**——降级会话的「保存」会把跨实体写落固化进盘面
   （D4）。
2. **TCC 弹窗前置**：游戏窗口像素腿先关 macOS「访问网络宗卷」授权弹窗（osascript
   System Events → UserNotificationCenter → 允许）；弹窗不关则 hero/tile 普查全废
   （A4 实况）。
3. **A17 注记已精化（book+本报告 §三-4）**：全图渲染在「卡已在盘、无 loader ERROR」
   时依旧出现（编辑器+游戏两侧同形，全分辨率帧归档）——QA 复核 A17 时勿以 loader
   ERROR 行的出现与否作为机制判据；修复面的两臂表述以 buglist 原文为准。
4. **book 图集节按本会话证据写作**：QA 校对 book sprites-2d.md §Sprite atlases 与
   30 秒清单第 4 条时，注意「游戏/导出渲正确 tile」的旧表述已被本轮证据否定（E5/A4
   +本帧）；book 现行文本=「两侧均渲染全图（记录缺陷 A17），数据往返无损」。
5. **关键格「移动」与 SP9 点击腿**：维持 QA §八-4 常规口径（工具票后或非 Retina/
   GPU 会话）；勿以本轮的通道红升级产品缺陷——M3B_ROTATE 三轮绿+M2 三轮绿说明
   交互栈本身工作，死面在读/写寻址。
6. **脚本现版即口径**：`t21-live.sh` 本轮六件修复（§三-1 表）——QA 复跑用现版；
   selftest 4/4；`atlas_face` 双拼写 grep 勿再「修回」单拼写。
7. **export 半边**：T2 M15 六件绿在档（`console-export.log`+staged-run.log）；
   QA 终验若复跑 export 请单独跑（D3 纪律）并预期与 §三-4 全图渲染发现同形（staged
   包内文档 wear 在、渲染全图）。
8. **门禁九门**：§四 表+归档日志全文复核；integration 唯一预期红=A6 定案口径隔离
   绿（T1/T2 同口径）；doctests 若见 bind-dyld 家族按 T15 处方单包复跑。
9. **book 零风险面**：本轮 book 改动=一全新章+四文件一句话级出链+SUMMARY 一行；
   无 src/、crates/、templates/ 产品改动——门禁红只可能来自环境（A6 家族）或
   预存树态（docs 的 private-doc-link 家族=T17/T19 基线同数）。

## 七、用户 30 秒清单（book 章节尾定稿；终验抽查项）

1. 新工程选 **2D game** 模板，开 starter 场景：2D 画布上一个 sprite；**Play**：
   Game 面板看得见它（embedded 忠实）。
2. 拖任意 PNG 进画布：落点生成以文件命名的 sprite；点选→描边+移动 gizmo；拖动、
   方向键微调、`Ctrl+Z` 逐步回退。
3. Inspector 里点 **Pivot** 预设（如 Top Center）：sprite 绕自身位移；改 `color`：
   画布立刻跟随。
4. **New Asset → Sprite Atlas** 切网格、把 sprite 的 `texture_atlas` 指到卡上设
   index：**Save**、**Play**——游戏带着 wear 跑（今日画布与窗口都画全图——A17
   记录缺陷；切分/指认/index 的保存与重载逐字无损）。
5. 重开场景：transform、pivot、图集引用与 index 逐字段回来。

## 八、交接与边界

- **buglist/台账/roadmap 零触碰**（纪律；A16/A17/A11 的注记只进 book 与本报告，
  票面更新归主控合入时落笔）。
- **给主控的两句话**：①A17 的机制证据已从「loader 缺面」精化到「场景路径柄不解析
  到 walk 卡（双柄空间）」，修复面裁定请以 §三-4 新证据+buglist 原文两臂并读；
  ②编辑器 BRP 读窗/实体重生（D13）在本会话取得跨实体写落的机制性证据（§五-D1），
  QA §八-3② 的两件工具票（viewport2d 截图通道、读窗 flake+指纹落盘）建议随 T22
  前立项。
