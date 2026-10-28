# T10-T0 报告：物理栈编译探针 + 手柄 ledger 补行

> 任务：`loop/plans/t10-physics-triggers.md` §二 T0（决策 1/2/5 已裁，探针先行）。
> 分支 `loop/t10-physics`（自 main e0df824e）。
> **结论：探针 FAIL——且失败形态比 API 漂移更根本：patch 路线在机制层失效（semver pre-release），
> B 路线经网络实查不可行。按任务书失败处置停下回报，未自行换路线。**

## 一、探针执行记录（三轮迭代，日志 `loop/t10t0_probe_check1-3.log`）

任务书升格口径（把双 crate 并入主 workspace 构建当探针）：

1. **改动形态**（已全部回滚，见 §四）：主 `Cargo.toml` members+两物理 crate、
   `[workspace.dependencies]` 增 `avian3d = { version = "0.8", features = [3d, parry-f32,
   collider-from-mesh] }` 与 `jackdaw_avian_integration` path 声明、尾部
   `[patch.crates-io] bevy = { git = "https://github.com/bevyengine/bevy",
   rev = "c9c397ba1a73e6cfffe957318e0359330b701865" }`；聚合 `integrations/physics/Cargo.toml`
   删除（其 `[workspace]` 表会抢走子 crate，members 化的前提）；主 `[workspace.package]`
   补 `edition`/`license`/`repository`（子 crate 的 workspace 继承需要，两轮各补齐）。
2. **第三轮到达编译阶段，报出决定性事实**：

   ```
   warning: patch `bevy v0.20.0-dev (...rev=c9c397ba)` was not used in the crate graph
   help: Check that the patched package version and available features are compatible
   with the dependency requirements.
   ...
   Adding bevy v0.20.0            <- registry bevy 全家桶被拉入（90 packages）
   ...
   error[E0277]: `avian3d::prelude::SleepTimer` does not implement `GetTypeRegistration`
   note: there are multiple different versions of crate `bevy_reflect` in the dependency graph
   (git c9c397b 与 registry 0.20.0 并存)
   error: could not compile `jackdaw_avian_integration` (lib) due to 66 previous errors
   ```

## 二、根因：不是 API 漂移，是 patch 机制层失效

- **semver pre-release 规则**：avian 0.8.0 的依赖是 registry `bevy ^0.20`。cargo 的
  `[patch.crates-io]` 要求被 patch 的包**满足所有依赖方的版本要求**；`^0.20` 的区间是
  `>=0.20.0, <0.21.0` 且**不含 pre-release**（pre-release 版本只匹配显式 pre-release 要求）。
- **git 树的版本号是 `0.20.0-dev`**（lock 实证：`version = "0.20.0-dev"`）——`0.20.0-dev <
  0.20.0`，不满足 `^0.20` → cargo **静默忽略 patch**（仅 warning），avian 照拉 registry
  bevy 0.20.0 → git 树（jackdaw 全家）与 registry 树（avian 全家）并存 → 任何共享类型
  （`GetTypeRegistration`/`Plugin`/...）互不识别 → 66 错。错误面 100% 是「双 bevy_reflect」，
  **零个** bevy-main-13-天增量的 API 漂移错误（还没编译到那一步就被类型分裂挡住——即使到了
  那一步也不是本失败的原因）。
- **方案 §二 T0 的「直通概率高」预判在 API 层面或仍成立（未触及），但被版本机制层一票否决。**

## 三、B 路线网络实查（给主控的完整裁决输入）

avian 仓库 **main 分支** `crates/avian3d/Cargo.toml` 的 bevy 依赖（raw 实查 2026-10-27）：

```toml
bevy = { version = "0.20", default-features = false, features = ["std", "bevy_log"] }
bevy_curve = { version = "0.20", ... }
bevy_math  = { version = "0.20", ... }
bevy_shape = { version = "0.20", ... }
```

**registry 声明、无 git**——方案 §二 T0-2 预判的「若 avian main 也是 registry → B 不可行」
**成立**。avian 没有任何分支以 git bevy 为依赖基础。

**剩余可选路线**（均需主控重裁，未自行尝试）：

| 路线 | 形态 | 成本/风险 |
|---|---|---|
| **A+（bevy fork 版本对齐）** | fork bevyengine/bevy@c9c397ba，把 bevy 及全部子 crate 的 `version` 从 `0.20.0-dev` 改为 `0.20.0`（纯字符串，diff 可验证仅 version 行），patch 指 fork | 零代码适配、零 avian 改动、类型统一有把握；成本=fork 托管（jackdaw org 下）+bevy pin 前进时 fork 重制（checkout rev→改 version→push，可脚本化）；git_deps 守卫需放行 fork URL 白名单 |
| **B'（avian fork 改依赖）** | fork avian 0.8.0，其 bevy 依赖行改 git c9c397ba，jackdaw 以 `[patch.crates-io] avian3d = { git = fork }` 指向 | avian 代码零改动；成本=fork 托管+avian 升版跟进；比 A+ 重（avian 的 workspace 依赖一致性要跟） |
| **C（主 workspace 切 registry bevy 0.20.0）** | 全仓 re-pin 到 registry | 决策 1 曾否（bleeding-edge 哲学+`template_versions.rs:113-115` 断言 pins bevy=main/channel=bleeding-edge 需翻转）；patch 失效后 C 相对成本下降（无 fork），但 jackdaw 代码是否依赖 main 13 天增量 API 是**新未知数**（需一次「主 bevy 切 registry 编译」小探针） |
| **等窗口** | bevy 0.21 / avian 0.9 | 时间不可控（方案既判） |

**建议**（供主控参考，非决定）：A+ 的确定性最高（机制层一次到位、维护动作可脚本化、
与既有 git_deps 守卫的「单一 bevy 源」精神一致——只是源换成 fork）；若主控接受放弃
bleeding-edge，C 值得先花 20 分钟跑一个小探针（主 workspace 切 registry bevy 编一次）再比价。

## 四、失败处置执行（任务书 §3）

- **探针改动全部回滚**：`git checkout -- Cargo.toml Cargo.lock` + 聚合
  `integrations/physics/Cargo.toml` 恢复（unstage+restore HEAD）。`git status` 仅剩
  book 手柄行（§五）与既有无关项（`.gitignore`/`.mimosa/`/`buglist.md`，均不提交）。
- **主 workspace 无残留证明**：回滚后 `cargo xtask fast` **clean**（fmt+core_deps+
  git_deps+clippy --workspace --all-targets -D warnings+lib 全测一路过，归档
  `loop/t10t0_gate_fast.log`）。
- **守卫同步项取消**：探针若过需同步的四个守卫（core_deps 豁免 integrations 成员/
  git_deps 放行 bevy patch+rev 一致校验/`template_versions.rs`+`modules.rs` 守卫改读主
  manifest/example doc 命令）——探针未过，全部不做（已在探针期间核实改动点与读位，
  供 T1 按重裁路线复用：守卫测试读位清单在报告 §一-1 与 modules.rs:the_physics_module_
  adds_the_avian_its_integration_uses、examples/editor.rs doc 注释）。
- **已试 patch 形态与报错留档**：`loop/t10t0_probe_check1.log`（manifest 继承错）、
  `check2.log`（license 继承错）、`check3.log`（**2679 行全文**：patch 未用 warning+90 包
  拉入清单+66 错双 bevy_reflect 详情）。

## 五、手柄 ledger 补行（任务书 §2，已完成）

`book/src/developer-guide/open-challenges.md` PIE 节：`"Three smaller ledgers"` →
`"Four smaller ledgers"`，追加第四条（physical-gamepad 端到端腿无硬件验证：机制层以
游戏进程 GilrsPlugin 直读+合成事件链红绿钉死，真机腿挂账待设备）。既有三条原文未动
（前后对照以 git diff 为证）。book docs 门随 fast 不涉（book 无 mdbook 本机面，纯文本改）。

## 六、数字与耗时

- 探针三轮：check1/2 = manifest 继承错误（秒级）；check3 = 90 包解析+增量编译至
  `jackdaw_avian_integration` 报错（首次 avian 树解析，分钟级完成——未到 20-40 分钟
  预估的深水区，因类型分裂在早期挡住）。
- 回滚后 fast 门：**clean**（§四）。
- buglist：无打钩项；roadmap 不动（主控）。

## 七、结论

**探针 FAIL（决定性）**：A 路线直通与带小适配均不成立（patch 被 semver pre-release
规则忽略，非代码适配可救）；B 路线不可行（avian main 是 registry bevy）。**T1 的解锁
路线需主控在 A+/B'/C（或等窗口）中重裁**——本报告 §三 为裁决输入。T0 的独立交付
（手柄 ledger 行）已落盘；探针改动零残留。
