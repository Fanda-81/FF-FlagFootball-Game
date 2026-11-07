extends SceneTree
## 规则引擎测试 A~L

var _f: Array[String] = []
var g: GameManager

func _initialize() -> void:
	g = GameManager.new()
	root.add_child(g)

	# A：推进 5 码不换权
	g.start_match(); g.begin_series(5, 1)
	var r := g.end_play("TACKLE", 10.0)
	_check(r["turnover"] == false, "A 推进 5 码不该换权")
	_check(r["down"] == 2, "A 档数应为 2（实际 %d）" % r["down"])

	# B：连续推进，档数正确累加
	g.begin_series(5, 2)
	r = g.end_play("TACKLE", 10.0)
	_check(r["down"] == 3, "B 档数应为 3（实际 %d）" % r["down"])
	g.begin_series(5, 3)
	r = g.end_play("TACKLE", 10.0)
	_check(r["down"] == 4, "B 档数应为 4（实际 %d）" % r["down"])

	# C：第 4 档没过 → 换权
	g.begin_series(5, 4)
	r = g.end_play("TACKLE", 9.0)
	_check(bool(r["turnover"]) == true, "C 四档未过应换权")
	_check(g.offense == "red", "C 球权应给红队（实际 %s）" % g.offense)
	_check(g.attack_dir < 0.0, "C 进攻方向应翻转")

	# D：越过中场 → 新首攻
	g.start_match(); g.begin_series(20, 1)
	r = g.end_play("CATCH", 27.0)
	_check(r["down"] == 1, "D 过中场应重置为 1 档（实际 %d）" % r["down"])
	_check(g.phase == 2, "D 应进入达阵阶段")
	_check(is_equal_approx(g.first_down_yards, 50.0), "D 首攻线应变成端线 50")

	# E：达阵 +6
	g.start_match()
	g.on_touchdown("blue")
	_check(g.blue_score == 6, "E 蓝队应 +6（实际 %d）" % g.blue_score)
	_check(g.state == GameManager.State.EXTRA_POINT, "E 应进入附加分状态")

	# F：传球未完成不加码
	g.start_match(); g.begin_series(20, 1)
	r = g.end_play("INCOMPLETE", 20.0)
	_check(is_equal_approx(g.ball_yards, 20.0), "F 未完成不该推进码数（实际 %.1f）" % g.ball_yards)
	_check(r["down"] == 2, "F 档数仍要 +1")

	# G：截球 → 换权（允许回攻，不直接放到对方 5 码线）
	g.start_match(); g.begin_series(20, 1)
	g.on_interception()
	_check(g.state == GameManager.State.TURNOVER, "G 应进入 TURNOVER")
	g.change_possession("INTERCEPTION")
	_check(g.offense == "red", "G 换权后应是红队进攻")
	_check(g.down == 1, "G 换权后档数应为 1")

	# H：拔旗记录球位置
	g.start_match(); g.begin_series(20, 1)
	g.end_play("FLAG_PULL", 31.5)
	_check(is_equal_approx(g.ball_yards, 31.5), "H 应记录拔旗位置 31.5（实际 %.1f）" % g.ball_yards)

	# I：出界结束本档
	g.start_match(); g.begin_series(20, 1)
	g.end_play("OUT_OF_BOUNDS", 26.0)
	_check(g.state == GameManager.State.PLAY_DEAD or g.state == GameManager.State.READY_TO_SNAP, "I 出界应结束本档")

	# J：换权后十名球员角色更新由场景负责，这里核对引擎状态
	g.start_match()
	var before := g.offense
	g.change_possession("TEST")
	_check(g.offense != before, "J 换权必须改变进攻方")
	_check(g.attack_dir < 0.0, "J 换权必须翻转方向")

	# K：方向翻转后码数换算仍正确
	var yards_right := g.z_to_yards(10.0, 1.0)
	var yards_left := g.z_to_yards(40.0, -1.0)
	_check(is_equal_approx(yards_right, 10.0), "K 正常方向 10 → %.1f" % yards_right)
	_check(is_equal_approx(yards_left, 10.0), "K 反向 40 → 应为 10（实际 %.1f）" % yards_left)

	# L：端区与场内不能混淆
	var in_field := g.z_to_yards(45.0, 1.0)
	var in_endzone := g.z_to_yards(55.0, 1.0)
	_check(in_field < 50.0, "L 45 码应在场内")
	_check(in_endzone >= 50.0, "L 55 码应已进端区")

	if _f.is_empty():
		print("[test_rules] OK  A~L 共 12 条规则测试全部通过")
		quit(0)
	else:
		for msg in _f:
			printerr("[test_rules] FAIL ", msg)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_f.append(msg)