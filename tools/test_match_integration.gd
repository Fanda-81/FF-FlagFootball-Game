extends SceneTree
## 实际比赛流程集成测试（全部通过 FootballGameManager 的事件接口）

var fails: Array[String] = []
var g: GameManager

func _initialize() -> void:
	g = GameManager.new()
	root.add_child(g)

	# ---- 测试 1：红方第一档传球失败 ----
	g.start_match()
	g.possession_team = "red"          # 红方进攻
	g.line_of_scrimmage = 55.0          # 红方自己 5 码线（红方底线 60，向 0 方向进攻）
	g.ball_position_yards = 55.0
	g.first_down_line = 35.0            # 冲中场
	g.down_number = 1
	g._set_state(GameManager.State.READY_TO_SNAP)
	g.start_play()
	g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.possession_team == "red", "1 红方仍应进攻（实际 %s）" % g.possession_team)
	_check(g.down_number == 2, "1 档数应变为 2（实际 %d）" % g.down_number)
	_check(is_equal_approx(g.ball_position_yards, 55.0), "1 球应留在开球线（实际 %.1f）" % g.ball_position_yards)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "1 开球线不应变化（实际 %.1f）" % g.line_of_scrimmage)
	_check(absf(g.get_attacking_direction() - (-1.0)) < 0.01, "1 进攻方向不应变化")
	_check(not g.is_in_opponent_endzone(g.ball_position_yards), "1 不能跳到对方达阵区")

	# ---- 测试 2：连续三次传球失败 ----
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.down_number == 3, "2 第二档失败后应为 3 档（实际 %d）" % g.down_number)
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.down_number == 4, "2 第三档失败后应为 4 档（实际 %d）" % g.down_number)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "2 球始终在原开球线")

	# ---- 测试 3：第四档传球失败 → 换权，位置不变 ----
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.possession_team == "blue", "3 应换成蓝方进攻（实际 %s）" % g.possession_team)
	_check(absf(g.get_attacking_direction() - 1.0) < 0.01, "3 方向应反转")
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "3 球应留在实际位置 55（实际 %.1f）" % g.line_of_scrimmage)
	_check(not g.is_in_opponent_endzone(g.ball_position_yards), "3 不能传送到达阵区前")

	# ---- 测试 4：拔旗推进 5 码 ----
	g.possession_team = "blue"
	g.line_of_scrimmage = 40.0
	g.ball_position_yards = 40.0
	g.first_down_line = 35.0
	g.down_number = 1
	g._set_state(GameManager.State.READY_TO_SNAP)
	g.start_play()
	g.end_play("FLAG_PULL", 45.0)
	_check(is_equal_approx(g.ball_position_yards, 45.0), "4 球应停在新位置 45（实际 %.1f）" % g.ball_position_yards)
	_check(g.possession_team == "blue", "4 球权不变")

	# ---- 测试 5：越过中场 → 新首攻 ----
	g.line_of_scrimmage = 30.0
	g.ball_position_yards = 30.0
	g.down_number = 1
	g.first_down_line = 35.0
	g._set_state(GameManager.State.READY_TO_SNAP)
	g.start_play()
	g.end_play("FLAG_PULL", 36.0)
	_check(g.down_number == 1, "5 过中场应重置为 1 档（实际 %d）" % g.down_number)
	_check(g.phase == 2, "5 应进入达阵阶段")
	_check(is_equal_approx(g.first_down_line, 60.0), "5 首攻线应变成红方达阵线 60")
	_check(g.score_blue == 0, "5 过中场不该加分")

	# ---- 测试 6：截球 ----
	g.possession_team = "blue"
	g.line_of_scrimmage = 40.0
	g.ball_position_yards = 40.0
	g.down_number = 3
	g._set_state(GameManager.State.READY_TO_SNAP)
	g.start_play()
	g.end_play("INTERCEPTION", 40.0)
	g.process_interception()
	_check(g.possession_team == "red", "6 截球后红方持球（实际 %s）" % g.possession_team)
	_check(is_equal_approx(g.line_of_scrimmage, 40.0), "6 球应留在截球位置")

	# ---- 测试 7：达阵 +6 ----
	g.reset_match()
	g.possession_team = "blue"
	g.line_of_scrimmage = 58.0
	g.ball_position_yards = 60.0
	g.down_number = 1
	g._set_state(GameManager.State.READY_TO_SNAP)
	g.start_play()
	g.process_touchdown()
	_check(g.score_blue == 6, "7 蓝方应 +6（实际 %d）" % g.score_blue)
	var first := g.score_blue
	g.process_touchdown()
	_check(g.score_blue == first, "7 不能重复加分")

	# ---- 测试 8：换权后世界坐标不变 ----
	g.reset_match()
	g.possession_team = "blue"
	g.line_of_scrimmage = 42.0
	g.ball_position_yards = 42.0
	g._set_state(GameManager.State.READY_TO_SNAP)
	var world_before := g.field_yards_to_world(42.0)
	g.change_possession("TEST", 42.0)
	var world_after := g.field_yards_to_world(g.line_of_scrimmage)
	_check(is_equal_approx(world_before, world_after), "8 换权后物理位置不变（%.1f vs %.1f）" % [world_before, world_after])
	_check(absf(g.get_attacking_direction() - (-1.0)) < 0.01, "8 方向应反转")
	_check(is_equal_approx(g.first_down_line, 35.0), "8 首攻线应重算成中场 35")

	if fails.is_empty():
		print("[test_match_integration] OK  8 项实际比赛流程全部通过")
		quit(0)
	else:
		for m in fails:
			printerr("[test_match_integration] FAIL ", m)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)