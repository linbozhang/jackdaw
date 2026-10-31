# EG1 绿证（T20-T1，决策 1-A 落地后）
# 物化：loop/qa/t20-live.sh prep（./target/debug/jd new t20-game，模板已带胜局流转）
# 断言一：胜局臂 = info! + blip 三行 + flow.set(GameFlow::GameOver)。
29:            AudioPlayer::<AudioSource>(server.load(BLIP_SOUND)),
31:            SfxBus,
33:        flow.set(GameFlow::GameOver);
# 断言二：teaches 面同步（新锚在物化文件中齐备）。
  needle [flow.set(GameFlow::GameOver)] hits=1
  needle [the run is won] hits=1
  needle [the button blip] hits=2
  needle [server.load(BLIP_SOUND)] hits=2
# 红绿闭环：红证 loop/reports/t20t1_eg1_red.md（停留 Level）→ 修复 → 本绿证（GameOver 迁移+blip）。
# 重开整环语义：GameOver 的 Restart 走既有 "restart" 臂 → Level 重入 reset_run/道具重生（模板既有，T2 L2 真机复验）。
