extends SceneTree
## 阶段 D：犯规罚码（引擎级、确定性）

var fails: Array[String] = []
var g: GameManager

func _initialize() -> void:
	PenaltyConfig.enabled = false
	g = GameManager.new()
	root.add_child(g)

	# 1 蓝方早动：LOS 后退 5，档数不变
	g.reset_match(); g.debug_setup("blue", 15.0, 2)
	g.apply_penalty("false_start", "blue")
	_check(is_equal_approx(g.line_of_scrimmage, 12.5), "1 蓝方在 5 码线内早动减半退到 12.5（实际 %.2f）" % g.line_of_scrimmage)
	_check(g.down_number == 2, "1 早动应重打本档（实际 %d 档）" % g.down_number)

	# 2 红方早动：LOS 后退 5（向 +码数方向）
	g.reset_match(); g.debug_setup("red", 55.0, 1)
	g.apply_penalty("false_start", "red")
	_check(is_equal_approx(g.line_of_scrimmage, 57.5), "2 红方在 5 码线内早动减半退到 57.5（实际 %.2f）" % g.line_of_scrimmage)

	# 3 防守越线：进攻方推进 5 码
	g.reset_match(); g.debug_setup("blue", 15.0, 1)
	g.apply_penalty("offside", "red")
	_check(is_equal_approx(g.line_of_scrimmage, 20.0), "3 防守越线应让蓝方推进到 20（实际 %.1f）" % g.line_of_scrimmage)

	# 4 护旗：不重打，掉一档
	g.reset_match(); g.debug_setup("blue", 15.0, 1)
	g.apply_penalty("flag_guarding", "blue")
	_check(g.down_number == 2, "4 护旗应掉档到 2（实际 %d）" % g.down_number)
	_check(is_equal_approx(g.line_of_scrimmage, 12.5), "4 护旗在 5 码线内减半退到 12.5（实际 %.2f）" % g.line_of_scrimmage)

	# 5 边界：罚码不能越出场地
	g.reset_match(); g.debug_setup("blue", 3.0, 1)
	g.apply_penalty("false_start", "blue")
	_check(g.line_of_scrimmage >= 0.0, "5 罚码不应越出底线（实际 %.1f）" % g.line_of_scrimmage)

	# 6 防守方犯规推进后不越出底线
	g.reset_match(); g.debug_setup("red", 8.0, 1)
	g.apply_penalty("offside", "blue")
	_check(g.line_of_scrimmage >= 0.0, "6 推进不应越出底线（实际 %.1f）" % g.line_of_scrimmage)

	# 7 己方端区前 5 码内：罚码减半（5 → 2.5）
	g.reset_match(); g.debug_setup("blue", 15.0, 1)   # 距本方端区正好 5 码
	g.apply_penalty("false_start", "blue")
	_check(is_equal_approx(g.line_of_scrimmage, 12.5), "7 5 码内罚码减半应退到 12.5（实际 %.2f）" % g.line_of_scrimmage)

	# 8 再犯一次：2.5 → 1.25
	g.apply_penalty("false_start", "blue")
	_check(is_equal_approx(g.line_of_scrimmage, 11.25), "8 再犯应退到 11.25（实际 %.2f）" % g.line_of_scrimmage)

	# 9 10 码罚球在 5 码内也只减半到 2.5
	g.reset_match(); g.debug_setup("blue", 15.0, 1)
	g.apply_penalty("pass_interference", "red")       # 防守犯规 → 推进，不减半
	_check(is_equal_approx(g.line_of_scrimmage, 25.0), "9 防守 10 码罚应推进到 25（实际 %.2f）" % g.line_of_scrimmage)

	# 10 远离端区时按全额罚
	g.reset_match(); g.debug_setup("blue", 30.0, 1)
	g.apply_penalty("false_start", "blue")
	_check(is_equal_approx(g.line_of_scrimmage, 25.0), "10 远离端区时全额罚 5 码（实际 %.2f）" % g.line_of_scrimmage)

	if fails.is_empty():
		print("[test_penalty] OK  犯规罚码 6 项全部通过")
		quit(0)
	else:
		for m in fails:
			printerr("[test_penalty] FAIL ", m)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)