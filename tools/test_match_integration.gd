extends SceneTree
## 通过公开比赛事件接口跑完整流程（A~M）

var fails: Array[String] = []
var g: GameManager

func _initialize() -> void:
	g = GameManager.new()
	root.add_child(g)

	# A 红方第一档传球失败
	g.start_match(); g.debug_setup("red", 55.0, 1)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.possession_team == "red" and g.down_number == 2 and is_equal_approx(g.line_of_scrimmage, 55.0),
		"A 红方应仍进攻、2 档、球在 55（实际 %s %d %.1f）" % [g.possession_team, g.down_number, g.line_of_scrimmage])

	# B 连续三次失败仍保持球权
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.possession_team == "red" and g.down_number == 4,
		"B 三档失败后应仍红方、4 档（实际 %s %d）" % [g.possession_team, g.down_number])

	# C 第四档失败 → 蓝方在同一物理位置获得球权
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.possession_team == "blue" and is_equal_approx(g.line_of_scrimmage, 55.0),
		"C 应换蓝方且在 55（实际 %s %.1f）" % [g.possession_team, g.line_of_scrimmage])

	# D 蓝方在 55 获得球权 → 首攻目标 60
	g.debug_setup("blue", 55.0, 1)
	_check(is_equal_approx(g.first_down_line, 60.0), "D 蓝方 55 的首攻线应为 60（实际 %.1f）" % g.first_down_line)

	# E 红方在 30 获得球权 → 首攻目标 10
	g.debug_setup("red", 30.0, 1)
	_check(is_equal_approx(g.first_down_line, 10.0), "E 红方 30 的首攻线应为 10（实际 %.1f）" % g.first_down_line)

	# F 蓝方不完整传球不加码
	g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 40.0)
	_check(is_equal_approx(g.ball_position_yards, 40.0), "F 未完成不该推进（实际 %.1f）" % g.ball_position_yards)

	# G 蓝方拔旗推进 5 码
	g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 45.0)
	_check(g.down_number == 2 and is_equal_approx(g.line_of_scrimmage, 45.0),
		"G 应进入 2 档、球在 45（实际 %d %.1f）" % [g.down_number, g.line_of_scrimmage])

	# H 截球后允许回攻，不固定到另一端
	g.debug_setup("blue", 40.0, 2)
	g.start_play(); g.end_play("INTERCEPTION", 40.0)
	_check(g.possession_team == "red" and is_equal_approx(g.ball_position_yards, 40.0) and g.awaiting_return,
		"H 截球后应红方持球、球在 40、等待回攻（实际 %s %.1f %s）" % [g.possession_team, g.ball_position_yards, g.awaiting_return])

	# I 回攻被拔旗 → 在实际拔旗位置开新系列
	g.start_play(); g.end_play("FLAG_PULL", 52.0)
	_check(is_equal_approx(g.line_of_scrimmage, 52.0) and g.down_number == 1,
		"I 应在 52 开新系列、1 档（实际 %.1f %d）" % [g.line_of_scrimmage, g.down_number])

	# J 进入错误达阵区不得分
	g.start_match(); g.debug_setup("blue", 12.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 12.0)
	_check(g.score_blue == 0, "J 蓝方在 12 码不该达阵（实际 %d 分）" % g.score_blue)

	# K 正确达阵区得 6 分（只算一次）
	g.start_match(); g.debug_setup("blue", 62.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == 6, "K 蓝方在 62 码应得 6 分（实际 %d）" % g.score_blue)
	var before := g.score_blue
	g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == before, "K 不能重复加分")

	# L 同一回合重复事件不能重复换权
	g.start_match(); g.debug_setup("blue", 40.0, 4)
	g.start_play()
	g.end_play("INCOMPLETE_PASS", 40.0)     # 换权
	var team_after := g.possession_team
	g.end_play("INCOMPLETE_PASS", 40.0)     # 应被忽略
	_check(g.possession_team == team_after, "L 重复结束不该再次换权（实际 %s）" % g.possession_team)

	# M 换权后世界坐标不变
	g.start_match(); g.debug_setup("blue", 42.0, 1)
	var world_before := g.field_yards_to_world(42.0)
	g.change_possession("TEST", 42.0)
	var world_after := g.field_yards_to_world(g.line_of_scrimmage)
	_check(is_equal_approx(world_before, world_after), "M 换权后世界坐标应不变（%.1f vs %.1f）" % [world_before, world_after])

	if fails.is_empty():
		print("[test_match_integration] OK  A~M 共 13 项流程全部通过")
		quit(0)
	else:
		for m in fails:
			printerr("[test_match_integration] FAIL ", m)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)