# 迁移手册：本机（Mac 1）→ 局域网另一台 Mac（Mac 2）

> 生成：2026-11-06。当前状态：main = `977bf778`（T25 收官合并），工作树干净，任务分支已删
> （仅保留探针分支 `loop/t22-probe-a`）。Loop 停在「T25 闭环、T26 待用户指令」。
> 旧迁移手册（Windows→Mac）见 `loop/MIGRATION.md`，其 fork/工具链经验仍适用。

## 一、要迁移什么（三样东西，按优先级）

| 内容 | 路径（本机） | 体量 | 必要性 |
|---|---|---|---|
| ① jackdaw 仓库（含全部 Loop 工作流） | `/Users/zhanglinbo/workspace/jackdaw` | 源码+loop ≈ **2.3 GB**（含 `.git` 654 MB）；`target/` **146 GB 可不迁**（可重建） | 必须 |
| ② bevy fork（构建硬依赖，不在仓库内） | `/Users/zhanglinbo/workspace/bevy-fork-pinned` | **178 MB**（无 target，小） | 必须 |
| ③ `loop-mac/` 真机证据目录（仓外） | `/Users/zhanglinbo/workspace/loop-mac` | **131 GB**，其中 T20-T25 五个暖工程占 ~131G | **可选**——只是历史证据+可重建暖工程；关键判定文件已全部提交在仓库 `loop/reports/` 内 |

**建议：先迁 ①+②（约 2.5 GB，几分钟），③ 后台慢传或按需挑目录。**

## 二、迁移方式（局域网 Mac 对 Mac，三选一）

### 方式 A：`rsync` 直传（推荐，断点可续）
在**本机**执行（把 `mac2` 换成目标机名或 IP；两台机都要开「远程登录/SSH」）：

```bash
# ① 仓库（排除可重建的 target，节省 146G）
rsync -avz --exclude 'target/' \
  /Users/zhanglinbo/workspace/jackdaw \
  mac2:/Users/你的用户名/workspace/

# ② fork
rsync -avz /Users/zhanglinbo/workspace/bevy-fork-pinned \
  mac2:/Users/你的用户名/workspace/

# ③（可选，后台慢慢传）真机证据
rsync -avz /Users/zhanglinbo/workspace/loop-mac \
  mac2:/Users/你的用户名/workspace/
```

### 方式 B：`git bundle`（只要仓库时最小最稳）
```bash
cd /Users/zhanglinbo/workspace/jackdaw
git bundle create /tmp/jackdaw.bundle --all
# 拷到 Mac 2 后：
git clone jackdaw.bundle jackdaw   # clone 出完整仓库（含所有分支/loop 内容）
```
注意 bundle 不含未提交文件（当前工作树干净，无损失）；fork 和 loop-mac 仍需 rsync/scp。

### 方式 C：AirDrop/移动硬盘
直接拷上述三个目录（排除 `jackdaw/target/`）。

## 三、Mac 2 上的落地步骤（迁完后在新机执行）

1. **路径对齐**：两台机都用 `~/workspace/jackdaw` 与 `~/workspace/bevy-fork-pinned`
   （本机 Cargo.toml 的 10 处 patch 写的是绝对路径
   `/Users/zhanglinbo/workspace/bevy-fork-pinned`，**若 Mac 2 用户名/路径不同需改
   `Cargo.toml` 底部两段 `[patch…]` 共 10 行**；路径一致则零改动）。
2. **fork 就位判定**：`bevy-fork-pinned/jackdaw-pinned-rev` 存在且内容 =
   `c9c397ba1a73e6cfffe957318e0359330b701865`；fork HEAD = `f83d83b41`（TextureAtlasLayout
   Default/ReflectDefault）。不符则参考 `loop/MIGRATION.md` 第二节用脚本重建
   （`scripts/make-bevy-fork.ps1` 是 PowerShell 旧版，Mac 上按其逻辑手动执行或网络 clone）。
3. **工具链**（Mac 2 首次）：
   - `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`（仓库
     `rust-toolchain.toml` 锁 1.99.0，rustup 会自动装对版本）
   - `cargo install cargo-nextest --locked`
   - Xcode Command Line Tools：`xcode-select --install`
4. **预热构建**：`cd ~/workspace/jackdaw && cargo build --workspace`（首次约 1 小时级；
   期间不并行其他 cargo）。验证三连：
   `cargo fmt --all -- --check` / `cargo test -p jackdaw --test guards`（248）/
   `cargo test --workspace --lib`（**3091** = T25 基线）。
5. **Loop 恢复点**：读 `loop/README.md`（契约）→ `loop/progress.md` 尾部（恢复地图）→
   `loop/plans/roadmap-game-dev.md`（T01-T25 已勾选，T26+ 待指令）→ `buglist.md`（活票
   LT5-LT10/A 系等）。
6. **ZCode 注意**：本机的每 30 分钟巡检自动化（automation-c664b2a5…）是**本机会话**的，
   不随仓库旅行；Mac 2 的 ZCode 需按 `loop/progress.md` 头部说明重建定时任务；本机待
   Mac 2 验收后再决定关闭。

## 四、本机收尾清单（迁移验证通过后）

- [ ] Mac 2 上 `guards 248 / libtests 3091` 复跑通过
- [ ] Mac 2 读通台账尾部（T25 闭环行）
- [ ] 本机巡检 cron 关闭或改为「待命只读」
- [ ] （可选）本机 `target/` 146G 清理：`rm -rf /Users/zhanglinbo/workspace/jackdaw/target`
- [ ] （可选）推送 GitHub：本地 main 领先 origin/main **32 个提交**（origin 停在 a058ce58），
      `git push origin main`；注意仓库 origin 指向**本机另一目录**
      `/Users/zhanglinbo/workspace/jackdraw_local`（本地 bare 备份），如需改指 GitHub 先
      `git remote set-url`。

## 五、已知环境差异提示（Windows→Mac 时已验证，Mac2 大概率复用）

- N13（PIE drain panic，Mac 100% 复发）是 Mac 形态——Mac 2 上大概率同样存在，census 归因
  口径照旧（buglist N13）。
- T25 起真机脚本全部 bash+curl+jq（无 PowerShell 依赖），Mac 2 开箱可用。
- 外部 `loop-mac/` 暖工程的绝对路径记录在各 T 报告头部，路径变了不影响已提交证据的效力。
