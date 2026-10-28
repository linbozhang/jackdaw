$ErrorActionPreference = 'Stop'
$p = 'E:\Project\rust\jackdaw\loop\progress.md'
$lines = [System.Collections.Generic.List[string]](Get-Content -Encoding UTF8 $p)
$clean = '- 2026-10-24 ✅ 专项#5 任务3 程序 DONE commit f6c12924：R3 Add 菜单 E2E 真机五项全通（UI 驱动建 Cube/PointLight、Inspector UI 输入 translation.x=2、保存重开持久、picker 入口；新方法论=BRP world.query 拉取 UI Text/UiGlobalTransform 物理像素坐标定位点击）。真机发现：①灯光实体 Inspector 无可达编辑卡（分类无映射，主控候选排期）②分类条纯图标可发现性差 ③pin_project 只回钉 bevy 不统一 windows range 依赖（my-game Cargo.lock 三行手工对齐 0.61.3→0.62.2 修复 wgpu-hal 类型冲突）。B 工具链锁定：模板 rust-toolchain.toml.template（{{rust_toolchain}}→jackdaw_env::RUSTUP_TOOLCHAIN）+ my-game 写 1.99.0 + Play 真机全链路通（预构建 schema 刷新、pie_running、进程实跑）。四门：fast 2802/2、integration 4938/3(+1)、doc 0、doctests 基线非回归。报告 loop/reports/feature-05-t3-report.md'
$lines[$lines.Count - 1] = $clean
[System.IO.File]::WriteAllLines($p, $lines, (New-Object System.Text.UTF8Encoding($true)))
'last line rewritten'
