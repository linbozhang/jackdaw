# T10-T1 报告：物理栈解锁与双侧接线（A+ 路线，主控裁定实施）

> 任务：`loop/plans/t10-physics-triggers.md` §二 T1（F1+F2；决策 1-A+/2-A 已主控裁定）。
> 分支 `loop/t10-physics`，提交 **`0972ee41`** `Unseal the physics stack through a pinned-version
> bevy fork`（24 文件 +1446/−836；前置于同分支的 `1f4eb774` 手柄 ledger 行）。
> **QA 退回小修轮（2026-10-27）**：`357b6f80` `Drop two unused imports and ledger the CI fork gap`
> ——editor 测试 util.rs 两处 unused import 删除（QA 复现的 clippy 红）+open-challenges 补
> 第五条 ledger（CI/协作者的 fork 路径断裂，归 fork 托管决策）；修复后 fast 全量与物理单包
> clippy 复验绿（见 §七）。
> 日志归档：`loop/t10t1_*`（probe×3/update×3/editor_check/scaffold_check/build×2/new/game_build/
> physics_tests×2/gate_fast×5/clippy_physics_fix/gate_fast_fix）。

## 一、A+ 路线实现（三源统一）

T0 结论（git bevy 0.20.0-dev 的 pre-release 版本号永远不满足 registry 的 `^0.20`，patch 被静默
忽略）→ A+ = 版本对齐 fork：

1. **`scripts/make-bevy-fork.ps1`（入仓）**：clone bevy@rev（优先 cargo git 本地缓存，无则
   blobless 网络 clone）→ 改写全树 77 个 Cargo.toml 的 `0.20.0-dev`→`0.20.0`（828 行对称替换，
   纯版本字符串）→ 两个 commit（版本改写+`jackdaw-pinned-rev` 记录上游 rev）→ 输出 patch 行。
   **用法**：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-bevy-fork.ps1`
   （默认 rev c9c397ba…，输出目录 `E:\Project\rust\bevy-fork-pinned`；bevy pin 前进时带新 rev
   重跑+`cargo update`）。当前 fork：bevy c9c397ba + pin 文件，commit `ccdcb683f`。
2. **主 workspace 双 patch 段**（Cargo.toml 尾）：
   - `[patch.crates-io]`：bevy/bevy_curve/bevy_math/bevy_reflect/bevy_shape → fork path
     （重定向 avian 的 registry 源+glam_matrix_extras 的 bevy_reflect——它是 Reflect 实现的
     真正主人，T0 二轮探针实证）；
   - `[patch."https://github.com/bevyengine/bevy"]`：同名五包 → fork path（重定向全仓 24 个
     git 声明 manifest 的 git 源——git 声明与 fork 内容相同但 package id 不同，不 patch 依旧双 bevy，
     三轮探针实证：69 错「avian Collider 不是 Component」全是 git-树 Component trait 与
     fork-树类型互不识别）。
3. **物理双 crate 并入主 workspace**：members+`[workspace.package]` 补 edition/license/repository
   +workspace.dependencies 增 avian3d/jackdaw_avian_integration/jackdaw_physics；聚合
   `integrations/physics/Cargo.toml`（原独立 workspace）删除退役。

## 二、编译结果：avian 0.8 × bevy c9c397ba 零漂移

- **探针三轮后 `cargo check --workspace` CLEAN**。第一轮 27 错（glam_matrix_extras 的
  bevy_reflect 源未统一）与第二轮 69 错（git 源未统一）**全部是源分裂、零 API 漂移**；
  三源统一后 avian 0.8.0 + 两物理 crate + 全 workspace **零错误**——13 天 main 增量对 avian
  无破坏（方案「直通概率高」的预判在版本机制障碍清除后成立）。
- **唯一小适配（非 bevy 漂移）**：`cargo update` 顺带升级 rmcp 3.7→3.8，`ServerInfo` 弃用改名
  `ServerConfig`——`jackdaw_mcp` 3 处机械更新（记档）。
- 游戏侧独立构建：`jd new phys-game`（Physics 模块默认带）→ `cargo build` **GAME_BUILD_OK**
  （avian 全家桶在 fork patch 下完整编译）。

## 三、解封与断言反转（红→绿）

- **解封**：`modules.json` physics 摘 `unavailable`；两物理 crate 的
  `package.metadata.jackdaw.unavailable` 摘除；编辑器 `src/lib.rs` 内置注册
  `PhysicsExtension`（builtin 块，随 `enable_builtin_extensiosn`）。
- **「不能启用」断言反转为「开箱启用」**（`tests/stage/new_project.rs`）：
  `an_unavailable_module_is_offered_but_cannot_be_ticked` →
  `physics_is_on_by_default_and_ships_with_the_game`。**红**：反转后首跑 FAIL
  （dev checkout 下 `jackdaw_avian_integration` 的 path 指向不存在的 `crates/` 子目录，工程
  无法解析）——顺带暴露两个真实缺口（见 §五）；**绿**：3.12s 全断言过（physics 默认勾选+
  jackdaw.toml `physics = true`+Cargo.toml 含 avian3d 与 `[patch.crates-io]`+main.rs 含
  `PhysicsPlugins::default()`）。
- **六件物理编辑器测试复活**：harness 的重复 `register_extension` 移除（编辑器已内置注册）
  后 **20/20 全绿**（physics_ops 8/picker 4/toggles 3/tool 2/round_trip/preview_guard 各 1
  +lib 4+integration 4——`t10t1_physics_tests2.log`）。

## 四、游戏侧接线（scaffold 注入）

- `add_module_crates`（edit 链）+ `module_patch_lines`（模板链 `{{module_patches}}` 占位）双路：
  physics 模块的工程自动获得同款双 patch 段（fork 路径来自编译期
  `JACKDAW_BEVY_FORK`/`BEVY_FORK`，由 build.rs 从主 manifest patch 表解析+导出）。
- **dev checkout path 化扩容**：`DEV_PATH_DEPS` 增 `jackdaw_avian_integration`；
  `build_source::crate_path` 增 `CRATES_ELSEWHERE` 位置表（物理两 crate 在
  `integrations/physics/` 而非 `crates/`）——这是反转红证揪出的真缺口。
- **BEVY_REV 锚迁移**：主 lock 的 bevy 变 path 源后无 git rev——`emit_bevy_source` 增 fallback
  读 fork 的 `jackdaw-pinned-rev`（脚本写入），`jackdaw.toml` 的 bevy_rev 记录链保持。

## 五、过程发现的真缺口（已修，红绿如上）

1. `crate_path` 对 `crates/` 外的 crate 生成不存在路径（物理 crate 首次以 dev-checkout 形态
   被依赖时暴露）→ `CRATES_ELSEWHERE` 表；
2. dev_checkout 的 path 重写清单缺物理 crate → 增补；
3. toml_edit 隐式下标把 `[patch]` 写成行首 inline 表（`the_runtime_edit_keeps_manifest_comments`
   测试揪出）→ 显式 `Item::Table` 构造（`path_patch_section`/`path_table`）。

## 六、守卫适配

| 守卫 | 适配 |
|---|---|
| core_deps（xtask） | violations 收紧为「integrations 成员之外的使用者才算违规」——物理集成 crate 是绑foreign引擎的正当场所，编辑器核心依旧零第三方 Bevy 生态 |
| git_deps（xtask） | patch 检查放行唯一形态：bevy 前缀包的 **path** patch（fork 重定向）；其余任何 patch 仍违规 |
| template_versions 守卫 | avian3d 源一致性读位：聚合 manifest（已删）→ 主 Cargo.toml `[workspace.dependencies]` |
| modules.rs 守卫 | 同上读位迁移 |
| example doc | `--manifest-path integrations/physics/Cargo.toml` → `-p jackdaw_physics` |
| CI physics job | 删除（75 行）——物理随主 workspace CI（其 unavailable 门曾是该 job 的存在理由） |
| 既有测试语义更新 | modules.rs 两测（defaults=physics/available 直接过）、cli upgrade note 断言（无可用性注记）、scaffold modules-flag（physics 可显式选）、changing_modules（detected 含默认 physics） |

## 七、门禁

| 门 | 结果 |
|---|---|
| fast（fmt+core_deps+git_deps+clippy workspace all-targets -D warnings+nextest --lib 全 workspace） | **CLEAN，2955/2955 passed**（2 skipped 既有；五轮迭代后过：fmt×2+rmcp 适配+六测语义更新；**QA 退回轮复验**：unused import 修复后重跑 CLEAN 2955/2955，`gate_fast_fix.log`） |
| 物理双 crate 全部测试 | **44/44**（integration 4+editor 20+physics lib 15+doc 等，`t10t1_physics_tests2.log`） |
| 物理单包 clippy（QA 复现口径） | **CLEAN**（`clippy -p jackdaw_physics --all-targets -- -D warnings`，`clippy_physics_fix.log`） |
| 新工程独立构建 | `jd new`+`cargo build` GAME_BUILD_OK |

## 八、真机 PIE 不穿地首证（降级记档）

编辑器/PIE 双腿「Play 中动态体带重力落地静止」首证**未在本轮跑**：会话两度用量中断+多轮
测试语义收尾后，真机窗口（新物理工程 prebuild 冷编 20-40 分钟级+编辑器全链）在本轮会话内
不再可靠。**降级记档**（机制层证据齐：物理六件编辑器测试的 `tool::space_keeps_where_a_
thrown_body_settled`/`escape_puts_a_thrown_body_back` 正是「扔出→模拟→落地静止」的编辑器腿
headless 全绿+游戏侧独立构建绿+avian 引擎自身测试套）——**真机首证挂账 T2 开工腿**（T2
触发器矩阵本就要真机物理行为断言，届时 `H:\workspace_AI\t10-phys\phys-game` 暖工程直接用）。

## 九、偏差与记档

1. **rmcp 3.8 小适配**（cargo update 顺带升级）——非 bevy 漂移，3 处机械改名；
2. **fork 是机器本地约定**（`E:\Project\rust\bevy-fork-pinned` 绝对路径，patch 与 scaffold
   注入都指向它）——协作者克隆后需先跑 fork 脚本；上游正解（官方选 registry 或 fork 托管）
   已在 T0 报告记档，open-challenges 可后续补行；
3. **真机首证挂账 T2**（§八）；
4. **CI 的 fork 依赖**：CI 环境（无本地 fork 目录）物理构建会失败——CI 需要先跑 fork 脚本
   （Linux 形态的等价脚本或 fork 托管，上游正解范畴）——记档给主控（本地工作流已全绿，
   CI 适配建议随 fork 托管决策一并处置）；
5. buglist：无打钩项。

## 十、工程处置

- `H:\workspace_AI\t10-phys\phys-game`：**保留**（T2 真机暖工程：物理默认+已预构建）。
- `E:\Project\rust\bevy-fork-pinned`：**保留**（workspace 编译的活依赖，非测试残留）。
