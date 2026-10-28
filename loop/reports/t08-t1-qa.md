# T08-T1 QA 验收报告：「配置资产→Resource 注入链+模板教学」（只验不修）

> QA 角色产出，2026-10-27。分支 `loop/t08-config`，提交 `69cc71cb`（父 `6119a066` = main），
> 6 文件 +776/−3。程序报告：`loop/reports/t08-t1-report.md`（§四 5 条偏差已逐条裁定）。
> 纪律：buglist/loop 文本 findstr/Read；长命令后台+轮询；QA 真机三段全程（含漂移复现）。

## 一、路线修正裁定（核心）：**成立**

- **架构事实 QA 三重核实**：①`load_asset_file`（runtime lib.rs）直接 `read_document_text`+
  parse+构造值填 store——**完全绕过 AssetServer loader 管线**；②`.bsn` 资产类型无注册 loader
  （仅 JackdawScene 有 loader），`AssetServer::load("game-config.bsn")` 路线在该架构下不可行；
  ③方案决策 2-A 的「资产就绪后」原设想的轮询面不存在。**catalog/walk 修正是贴合既有架构的
  唯一可行路线**。
- **用户面语义五要素完整保留**（与决策 2-A 一致，仅实现路线变）：一行
  （`ConfigPlugin::<T>::default()`）/初值（initial value，store 后改值不重注入有钉）/一次
  （loader despawn by construction）/缺文件 default+一次 warn/约定名糖
  （`DEFAULT_CONFIG_PATH`+`Default`）。
- **两个新公开面面积克制**：`AssetsWalked`（walk 尾部 insert 的完成标志资源，doc 明确用途）；
  `JackdawCatalog::register_file`（把内部已有的 files.insert 提为一行 pub 方法，**walk 自身
  未改道**，消费方=guards 测试与游戏自加载场景）。prelude 分层（Plugin/Loader 进 prelude，
  底层三样走 pub use）合理。

## 二、红→绿真实性

- **runtime 5/5 QA 亲跑全绿**。红半模式（同测两 App：`app_with_assets(false)` 同 fixture 同
  walk、唯一变量=系统注册→Resource 永不出现）——功能新增类的**行为红证**（T1 之前
  ConfigLoader 类型不存在，旧码红不可编译），与存在性红证（UnknownId）同级口径，接受；
- **guards 2/2 QA 亲跑全绿**：正向往返=**真 emit 路径**（`write_asset_file`+`AssetValue::Handle`
  →游戏侧 walk（消费 register_file+AssetsWalked 新公开面）→三字段=编辑器所写，形态漂移即红）；
  负向=编辑器 world 写 999→**零文件断言**→游戏侧起 default——「面板值不落盘、游戏读文件」的
  P1 现状边界钉死；
- **build 期 default 就位**（`the_plugin_has_the_resource_ready_before_the_first_update`：
  No update 断言 default 已在）——真机 cargo run 101 panic 揪出的时序缺陷的防回归钉（真红绿
  在真机层完成：首版缺陷→修复→钉）。测试文件形态钉了编辑器真形态（含 `-` 名字 emitter 加引号
  的实测坑）。

## 三、真机（QA 三段独立执行）

1. **编辑器全链**：程序 PASS 归档核实（live 日志：`asset.new` 成功+盘上 game-config.bsn 形态
   逐字=runtime 测试钉的形态：header+quoted name+struct patch+f32 全精度）。**QA 独立复跑被
   wgpu 漂移复现阻断**（见 §六-②：新工程 prebuild E0308→schema.json 未产→`asset.new` 不认
   game_config）——阻断本身构成偏差②的最强实证。
2. **行为腿前台复跑：仍受阻，且证伪了「可见窗口」假设**——QA 以可见窗口（1600x900 前台）在
   my-game（健康 lock）跑 play→running→`scene_snapshot` 两帧差：snapshot **持续
   watching-pending 无数据**（10 轮轮询全空）——与程序受阻现象一致。**QA 新线索**：T06 系真机
   读投影走 `scene_tree` 且**先切 Live 视图**（`Switch-View 'Live'`），本脚本选的
   `scene_snapshot` 通道未切视图——疑似**快照通道的视图态依赖**而非窗口可见性问题。按任务书
   口径裁定：**放行**（机制语义由 headless 5/5+guards 往返+程序真机全链三腿覆盖），行为断言
   通道问题记档给 T08-T2/T3（P2 面板任务会打开 Live/快照链，届时收口）。
3. **PIE 生命周期**（抽验其一）：QA 行为腿脚本顺带覆盖 play_current→running→stop→stopped
   全链干净落地；cargo run 101 缺陷链由时序修复钉+预热构建（QA 工程 cargo build 绿 2m51s）
   等价覆盖。

## 四、代码 review：无新 🔴（🟡×2 建议，见 §六）

- `ConfigPlugin::build`：**default 先插**（消费系统永不竞态）+spawn loader（先于首帧）+注册
  系统；`apply_config_defaults` 等 `AssetsWalked`（无则 return 等待）；三分支（值注入/类型不符
  warn+default/缺键 warn+default）**全部 despawn=一次/进程 by construction**；store 空值的
  「类型撒谎」分支处理细致；缺文件仅一次 warn 不刷屏有钉；`.jackdaw-pie/` temp 不遮蔽配置有钉。
- 模板教学面全核：GameConfig 双 derive（Asset+Resource+Reflect+Clone+手写 Default
  100/1/-9.81）+@EditorCategory("Game Config")；两注册+一行；FallingCube 消费系统
  （gravity 下落+speed×move_speed 旋转——组件参数 vs 全局参数对照）；doc「Tuning parameters」
  节；scaffold 10 断言测试。
- guards 往返的真实性核实（§二）。

## 五、门禁

归档：fmt 0 字节 ✅、clippy 零 error ✅、guards **199/0** ✅；QA 亲跑：runtime config **5/5**、
guards config_injection **2/2**、scaffold **79/0**、主 crate lib **1169/0**（报告数字实测属实）。
⚪：`t08t1_runtime_tests.log` 归档为 4/0 过程轮（报告 5/5，QA 亲跑 5/5 终态为准）；主 crate
lib 无独立归档文件（QA 亲跑补证）。

## 六、偏差 5 条裁定 + QA 新发现

| # | 偏差/发现 | 裁定 |
|---|---|---|
| ① | 注入路线修正 | **成立**（§一） |
| ② | wgpu-hal 漂移 | **QA 完整复现并深化**：QA 新工程 fresh lock 解析到 bevy fe544043（仓库 c9c397ba）→编辑器 prebuild `error[E0308] wgpu-hal-30.0.1\dx12\suballocation.rs:83`（同版本 wgpu-hal！仓库 lock 也是 30.0.1）；**QA pin bevy rev 等价处置仍炸**（windows_core 宏 E0308/E0277 失配族，且两边 windows 系 crate 版本完全相同——失配在更深的组合层）；程序「workspace lock 引导重解析」的处置步骤未在报告留档、QA 未能复刻成功。**立项建议升级：T08-T3 前置小任务**（当前上游窗口内每个 fresh scaffold 工程的编辑器 prebuild 必炸，T08-T2/T3 的真机腿都会被阻断） |
| ②附 | **🟡 QA 新发现：pin 机制疑对 fresh lock 未生效**——模板 Cargo.toml 注释声称「The editor moves the lockfile back to it before each build」，但 QA 工程 prebuild 炸在 fe544043 组合（若 pin 生效应为 c9c397ba）——需产品侧查 pin_project 的 fresh-lock 路径；与②合并立项 |
| ③ | 模板 include_dir 编译期嵌入 | 记档口径可接受（QA 亲历佐证：模板改动后必须重编 jd.exe 才进新生成，本任务诊断成本主因的结论与 QA 复跑经验一致） |
| ④ | 首版时序缺陷 | 修复+真机红绿+防回归钉，闭环成立 |
| ⑤ | asset.new 命名口径 | 接受（id/type_path/label 语义已有测试钉） |
| ⚪ | `jd new` 绝对路径当 name | **QA 现场复现了程序的事故根因**：`jd new E:\...` 把路径剥成错名目录静默创建于 cwd（`<name>` 参数语义+丑失败）——建议 buglist backlog 记 UX 修正（含路径分隔符的 name 应拒绝并提示 `--path`）；仓库根事故目录已删（RESIDUE_ABSENT 核实） |
| ⚪ | 真机脚本健壮性 | 无 kill-stale 段（旧实例占端口致 QA 第二轮假失败——QA 亲历）+「idle 放行≠schema 就位」时序坑（首轮 asset.new 撞 schema watch 窗口）+默认参数指向已删事故名工程——三项脚本层记档，建议 T2 顺手修 |
| ⚪ | buglist | 未动核实（21 勾+无 T08 条目）✓ |

## 七、QA 汇总

- 新发现：🟡×2（漂移立项升级+pin 失效疑）、⚪×5（jd new UX/runtime 归档 4-5 差/主 crate lib
  归档缺/脚本三项）。
- 残留：无进程残留；工作区常规项；**QA 复现工程 `H:\workspace_AI\t08-qa-game` 保留**（含 QA
  rev pin 注释——漂移复现的活样本，供②立项调查与 T08-T3 处置验证；处置后可删）。
- 验收产物：`loop/qa/t08-qa-behavior.ps1`（行为腿前台复跑脚本，沉淀）；QA 工程事故目录已清。

## 八、PASS 条件核对

| 条件 | 判定 |
|---|---|
| 路线修正裁定成立（架构三重证据+语义五要素+公开面克制） | ✅ |
| 红绿真实（5/5+2/2 亲跑；红半模式裁定接受；build 期钉） | ✅ |
| 真机复跑（编辑器链读档+QA 三段：漂移实证/行为腿前台证伪+新线索/PIE 链覆盖） | ✅（行为腿按三腿证据+复核放行，如实记档） |
| review 无新 🔴（🟡×2 建议立案） | ✅ |
| 残留清（事故目录 ABSENT/进程/工作区） | ✅ |
| 门禁干净（归档+亲跑 5/5、2/2、79、1169） | ✅ |

VERDICT: PASS
