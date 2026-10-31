# EG1 红证（T20-T1 预备，2026-10-28，main 46fdaeb5 + 决策 1-A 落地前的模板物化）
# 物化：./target/debug/jd new t20-red --path /Users/zhanglinbo/workspace/loop-mac --no-git
# 断言一：collect_pickups 胜局臂只有 info!，无任何 flow.set —— 集齐 3 拾取后 GameFlow 停留 Level。
CONFIRMED-RED: collect_pickups contains no flow transition (0 hits)
# 断言二：唯一的 GameOver 流转写点在 update_game_over（血尽臂）——胜局不可达结束面。
13:            next.set(GameFlow::GameOver);
# 断言三：全文件 flow.set 写点只落 Level/Menu 两态（on_screen_pressed），GameOver 无 collect 路径。
1606:            flow.set(GameFlow::Level);
1610:            flow.set(GameFlow::Menu);
# 静态语义：拾取物带 DespawnOnExit(GameFlow::Level)，GameOver 态下拾取物不存在、触发器不再进入——
#           该系统在 GameOver 后无法再次触发流转，玩家只能撞 Hazard 血尽见结束屏（方案事实四/EG1）。
