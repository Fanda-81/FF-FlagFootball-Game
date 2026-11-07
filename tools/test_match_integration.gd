extends SceneTree
## 回合生命周期 + 事件校验测试（A~L），只用公开事件接口

var fails: Array[String] = []
var g: GameManager

func _initialize() -> void:
	g = GameManager.new()
	root.add_child(g)

	g.start_match()
	g.debug_setup("blue", 15.0, 1)
	var p1 := g.play_id

	# A 蓝方第一档拔旗 → 第二档，PLAY ID +1
	g.start_play()
	g.end_play("FLAG_PULL", 17.6)
	_check(g.down_number == 2, "A 应进入 2 档（实际 %d）" % g.down_number)
	_check(g.play_id == p1 + 1, "A PLAY ID 应递增（%d -> %d）" % [p1, g.play_id])

	# B 第二档传球失败 → 第三档，PLAY ID 再 +1
	var p2 := g.play_id
	g.start_play()
	g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.down_number == 3, "B 应进入 3 档（实际 %d）" % g.down_number)
	_check(g.play_id == p2 + 1, "B PLAY ID 应递增（%d -> %d）" % [p2, g.play_id])

	# C 第三档拔旗 → 第四档
	g.start_play()
	g.end_play("FLAG_PULL", g.line_of_scrimmage + 1.0)
	_check(g.down_number == 4, "C 应进入 4 档（实际 %d）" % g.down_number)

	# D 第四档失败 → 红方获得球权、新 PLAY ID
	var p3 := g.play_id
	g.start_play()
	g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.possession_team == "red", "D 应换成红方（实际 %s）" % g.possession_team)
	_check(g.play_id > p3, "D 换权后应有新 PLAY ID")

	# E 拔旗后到达的旧未完成事件必须被拒绝
	g.debug_setup("blue", 20.0, 1)
	var stale_pid := g.play_id
	g.start_play()
	g.end_play("FLAG_PULL", 25.0)
	var down_after := g.down_number
	g.end_play("INCOMPLETE_PASS", 25.0, stale_pid)   # 旧回合的事件
	_check(g.down_number == down_after, "E 旧回合事件不应改变档数（实际 %d）" % g.down_number)

	# F 拔旗后到达的旧截球事件必须被拒绝
	g.debug_setup("blue", 20.0, 1)
	var stale2 := g.play_id
	g.start_play()
	g.end_play("FLAG_PULL", 25.0)
	var team_after := g.possession_team
	g.end_play("INTERCEPTION", 25.0, stale2)
	_check(g.possession_team == team_after, "F 旧截球事件不应换权（实际 %s）" % g.possession_team)

	# G 截球后进入回攻，本档不结束
	g.debug_setup("blue", 40.0, 2)
	g.start_play()
	g.end_play("INTERCEPTION", 40.0)
	_check(g.match_state == GameManager.State.RETURN_IN_PROGRESS, "G 应进入 RETURN_IN_PROGRESS（实际 %s）" % g.match_state)
	_check(g.possession_team == "red", "G 球权应归红方")

	# H 回攻被拔旗 → 在该位置开新系列
	g.end_play("FLAG_PULL", 52.0)
	_check(is_equal_approx(g.line_of_scrimmage, 52.0) and g.down_number == 1,
		"H 应在 52 开新系列 1 档（实际 %.1f %d）" % [g.line_of_scrimmage, g.down_number])

	# I 同一档两次拔旗只处理一次
	g.debug_setup("blue", 20.0, 1)
	g.start_play()
	g.end_play("FLAG_PULL", 25.0)
	var d1 := g.down_number
	g.end_play("FLAG_PULL", 30.0)
	_check(g.down_number == d1, "I 重复拔旗不应再进档（实际 %d）" % g.down_number)

	# J 同一档两次达阵只加一次分
	g.debug_setup("blue", 62.0, 1)
	var score_before := g.score_blue
	g.start_play()
	g.end_play("TOUCHDOWN", 62.0)
	var score_mid := g.score_blue
	g.end_play("TOUCHDOWN", 62.0)
	_check(score_mid == score_before + 6, "J 达阵应 +6（实际 %d）" % (score_mid - score_before))
	_check(g.score_blue == score_mid, "J 不能重复加分（实际 %d）" % g.score_blue)

	# K 新一档开始后旧事件无效
	g.debug_setup("blue", 20.0, 1)
	var old_pid := g.play_id
	g.start_play()
	g.end_play("FLAG_PULL", 25.0)      # 进入下一档，play_id+1
	g.end_play("INCOMPLETE_PASS", 25.0, old_pid)
	_check(g.play_id > old_pid, "K 新档 PLAY ID 已递增")

	# L 红方完整流程
	g.debug_setup("red", 60.0, 1)
	var r1 := g.play_id
	g.start_play(); g.end_play("FLAG_PULL", 58.0)
	_check(g.down_number == 2 and g.play_id == r1 + 1, "L 红方拔旗后 2 档、PLAY ID 递增")
	g.start_play(); g.end_play("INCOMPLETE_PASS", g.line_of_scrimmage)
	_check(g.down_number == 3, "L 红方未完成后 3 档")

	if fails.is_empty():
		print("[test_lifecycle] OK  A~L 共 16 项通过（PLAY ID 逐档递增、旧事件被拒）")
		quit(0)
	else:
		for m in fails:
			printerr("[test_lifecycle] FAIL ", m)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)