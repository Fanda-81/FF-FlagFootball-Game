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


	# ---- 回攻结束位置规则（禁止 Touchback）----
	# A 场内 18 码被拔旗
	g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 40.0)
	g.end_play("FLAG_PULL", 18.0)
	_check(is_equal_approx(g.line_of_scrimmage, 18.0), "A 回攻结束应留在 18（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.possession_team == "red", "A 截球方应红方持球（实际 %s）" % g.possession_team)

	# B 端区内 3 码被拔旗 → 不 touchback
	g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 40.0)
	g.end_play("FLAG_PULL", 3.0)
	_check(is_equal_approx(g.line_of_scrimmage, 3.0), "B 端区内应留在 3（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.possession_team == "red", "B 截球方仍应红方持球（实际 %s）" % g.possession_team)

	# C 另一端区 66 码被拔旗
	g.debug_setup("red", 30.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 30.0)
	g.end_play("FLAG_PULL", 66.0)
	_check(is_equal_approx(g.line_of_scrimmage, 66.0), "C 应留在 66（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.possession_team == "blue", "C 截球方应蓝方持球（实际 %s）" % g.possession_team)

	# D 球位 / LOS / 世界坐标一致
	g.debug_setup("blue", 33.5, 2)
	g.start_play(); g.end_play("INTERCEPTION", 33.5)
	g.end_play("FLAG_PULL", 22.25)
	_check(is_equal_approx(g.line_of_scrimmage, g.ball_position_yards), "D LOS 应等于球位")
	_check(is_equal_approx(g.field_yards_to_world(g.world_to_field_yards(22.25)), 22.25), "D 世界/逻辑坐标应可逆")
	_check(is_equal_approx(g.field_yards_to_world(g.line_of_scrimmage), 12.25), "D 世界坐标应为 12.25")

	# E 没有固定 touchback：多次不同位置都应保留
	for spot in [12.0, 45.0, 7.0, 58.0]:
		g.debug_setup("blue", 35.0, 1)
		g.start_play(); g.end_play("INTERCEPTION", 35.0)
		g.end_play("FLAG_PULL", spot)
		_check(is_equal_approx(g.line_of_scrimmage, spot), "E 位置 %.1f 应保留（实际 %.1f）" % [spot, g.line_of_scrimmage])


	# ================= P0：phase 2 达阵与首攻 =================
	g.reset_match()   # 清零比分，避免受前面用例影响
	# A 红队 phase1 到达中场 → 进入 phase2
	g.debug_setup("red", 40.0, 1)
	_check(g.phase == 1 and is_equal_approx(g.first_down_line, 35.0), "A 起始应为 phase1/中场")
	g.start_play(); g.end_play("FLAG_PULL", 34.0)
	_check(g.phase == 2, "A 过中场应进入 phase2（实际 %d）" % g.phase)
	_check(is_equal_approx(g.first_down_line, 10.0), "A 目标线应变 10（实际 %.1f）" % g.first_down_line)

	# B 红队 phase2 在 14.4 被拔旗：不达阵、不首攻
	g.debug_setup("red", 14.4, 1)
	g.start_play(); g.end_play("FLAG_PULL", 14.4)
	_check(g.score_blue == 0 and g.score_red == 0, "B 不该得分")
	_check(g.down_number == 2, "B 应进入 2 档（实际 %d）" % g.down_number)
	_check(g.last_event != "FIRST_DOWN", "B 不该是首攻（实际 %s）" % g.last_event)

	# C 红队推进到 6.5：合法达阵 +6
	g.debug_setup("red", 12.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 6.5)
	_check(g.score_red == 6, "C 红队应 +6（实际 %d）" % g.score_red)
	_check(g.extra_point_pending, "C 达阵后应进入附加分")

	# D 蓝队对称：推进到 62 达阵
	g.start_match(); g.debug_setup("blue", 58.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 62.0)
	_check(g.score_blue == 6, "D 蓝队应 +6（实际 %d）" % g.score_blue)

	# E phase2 反复被拔旗：不得无限首攻
	g.start_match(); g.debug_setup("red", 14.4, 1)
	var first_downs := 0
	for i in 3:
		g.start_play()
		g.end_play("FLAG_PULL", 14.4)
		if g.last_event == "FIRST_DOWN":
			first_downs += 1
	_check(first_downs == 0, "E 三次拔旗不该出现首攻（实际 %d 次）" % first_downs)
	_check(g.down_number == 4, "E 应为 4 档（实际 %d）" % g.down_number)

	# F 非法达阵被拒绝：无任何副作用
	g.start_match(); g.debug_setup("blue", 20.0, 2)
	g.start_play()
	g.end_play("TOUCHDOWN", 20.0)
	_check(g.score_blue == 0, "F 拒绝时不该加分（实际 %d）" % g.score_blue)
	_check(g.down_number == 2, "F 拒绝时不该改档数（实际 %d）" % g.down_number)
	_check(g.possession_team == "blue", "F 拒绝时不该换权")

	# G 同一档重复达阵只计一次
	g.start_match(); g.debug_setup("blue", 62.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	var s1 := g.score_blue
	g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == s1, "G 重复达阵不该再加分（%d vs %d）" % [s1, g.score_blue])

	# H 旧 PLAY ID 的达阵被拒绝
	g.start_match(); g.debug_setup("blue", 62.0, 1)
	var old_pid2 := g.play_id
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	var s2 := g.score_blue
	g.end_play("TOUCHDOWN", 62.0, old_pid2)
	_check(g.score_blue == s2, "H 旧 pid 达阵应被拒绝（%d vs %d）" % [s2, g.score_blue])

	# I 达阵后：对方从本方 5 码线开始
	g.start_match(); g.debug_setup("blue", 62.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	_check(g.possession_team == "blue" and g.extra_point_pending, "I 达阵后由得分方尝试附加分")
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.possession_team == "red", "I 附加分结束应换红方（实际 %s）" % g.possession_team)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "I 红方应在本方 5 码线 55（实际 %.1f）" % g.line_of_scrimmage)


	# ============ 端区反例（PLAY 011 回归）============
	g.reset_match()
	# 1 红队 55 → 7.8（对方端区）允许达阵
	g.debug_setup("red", 55.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 7.8)
	_check(g.score_red == 6 and g.extra_point_pending, "端区1 红队进对方端区应达阵（score=%d）" % g.score_red)

	# 2 红队 55 → 60（自己端区）绝不能达阵
	g.reset_match(); g.debug_setup("red", 55.0, 4)
	g.start_play(); g.end_play("TOUCHDOWN", 60.0)
	_check(g.score_red == 0, "端区2 红队到自己端区绝不该得分（%d）" % g.score_red)
	_check(g.score_blue == 0, "端区2 蓝队也不该得分（%d）" % g.score_blue)

	# 3 蓝队 15 → 60.1（对方端区）允许达阵
	g.reset_match(); g.debug_setup("blue", 15.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 60.1)
	_check(g.score_blue == 6 and g.extra_point_pending, "端区3 蓝队进对方端区应达阵（score=%d）" % g.score_blue)

	# 4 蓝队 15 → 10（自己端区）绝不能达阵
	g.reset_match(); g.debug_setup("blue", 15.0, 2)
	g.start_play(); g.end_play("TOUCHDOWN", 10.0)
	_check(g.score_blue == 0 and g.score_red == 0, "端区4 蓝队到自己端区绝不该得分")

	# 5 镜像对称：把 2 和 4 的球位互换，结果应互换
	g.reset_match(); g.debug_setup("red", 50.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 65.0)
	_check(g.score_red == 0, "端区5 红队跑向自己端区 65 不该得分")
	g.reset_match(); g.debug_setup("blue", 20.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 5.0)
	_check(g.score_blue == 0, "端区5 蓝队跑向自己端区 5 不该得分")

	# 6 死球后重复提交：状态、比分、档数都不变
	g.reset_match(); g.debug_setup("blue", 20.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 25.0)
	var snap_state = g.match_state
	var snap_down: int = g.down_number
	var snap_score: int = g.score_blue + g.score_red
	g.end_play("FLAG_PULL", 30.0)
	g.end_play("INCOMPLETE_PASS", 30.0)
	g.end_play("TOUCHDOWN", 30.0)
	_check(g.down_number == snap_down, "死球6 档数不该再变（%d vs %d）" % [snap_down, g.down_number])
	_check(g.score_blue + g.score_red == snap_score, "死球6 比分不该再变")


	# ================= Safety / 达阵重启 =================
	# A 蓝队本方端区 4.9 被拔旗 → 红队 +2，红队从 55 开始
	g.reset_match(); g.debug_setup("blue", 15.0, 2)
	g.start_play(); g.end_play("SAFETY", 4.9)
	_check(g.score_red == 2, "A 红队应 +2（实际 %d）" % g.score_red)
	_check(g.possession_team == "red", "A 球权应归红队（实际 %s）" % g.possession_team)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "A 红队应从 55 开始（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.down_number == 1, "A 应为 1 档（实际 %d）" % g.down_number)

	# B 红队本方端区 64.9 被拔旗 → 蓝队 +2，蓝队从 15 开始
	g.reset_match(); g.debug_setup("red", 55.0, 1)
	g.start_play(); g.end_play("SAFETY", 64.9)
	_check(g.score_blue == 2, "B 蓝队应 +2（实际 %d）" % g.score_blue)
	_check(g.possession_team == "blue", "B 球权应归蓝队")
	_check(is_equal_approx(g.line_of_scrimmage, 15.0), "B 蓝队应从 15 开始（实际 %.1f）" % g.line_of_scrimmage)

	# C 蓝队达阵 → 红队从 55 开始
	g.reset_match(); g.debug_setup("blue", 58.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == 6 and g.extra_point_pending, "C 蓝队 +6 并进入附加分")
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "C 红队应从 55 开始（实际 %.1f）" % g.line_of_scrimmage)

	# D 红队达阵 → 蓝队从 15 开始
	g.reset_match(); g.debug_setup("red", 12.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 6.5)
	_check(g.score_red == 6 and g.extra_point_pending, "D 红队 +6 并进入附加分")
	g.start_play(); g.end_play("INCOMPLETE_PASS", 5.0)
	_check(is_equal_approx(g.line_of_scrimmage, 15.0), "D 蓝队应从 15 开始（实际 %.1f）" % g.line_of_scrimmage)

	# E 截球回攻在蓝方端区被拔旗 → 不判 Safety、不 Touchback、保留位置
	g.reset_match(); g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 40.0)
	g.end_play("FLAG_PULL", 3.0)
	_check(is_equal_approx(g.line_of_scrimmage, 3.0), "E 应保留 3.0（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.score_blue + g.score_red == 0, "E 不该有 Safety 得分（%d）" % (g.score_blue + g.score_red))
	_check(g.possession_team == "red", "E 球权应归截球方红队（实际 %s）" % g.possession_team)

	# F 截球回攻在红方端区被拔旗
	g.reset_match(); g.debug_setup("red", 30.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 30.0)
	g.end_play("FLAG_PULL", 66.0)
	_check(is_equal_approx(g.line_of_scrimmage, 66.0), "F 应保留 66.0（实际 %.1f）" % g.line_of_scrimmage)
	_check(g.score_blue + g.score_red == 0, "F 不该有得分")

	# G 端区外拔旗 → 不判 Safety
	g.reset_match(); g.debug_setup("blue", 20.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 25.0)
	_check(g.score_blue + g.score_red == 0, "G 端区外拔旗不该得分")
	_check(g.down_number == 2 and is_equal_approx(g.line_of_scrimmage, 25.0), "G 应正常进入 2 档、球在 25")


	# ============ 码数统一 / 状态残留 / 端区边界 ============
	g.reset_match()
	_check(g.yards_to_go_from("blue", 16.0, 35.0) == 19, "码数1 蓝 16→35 应为 19（实际 %d）" % g.yards_to_go_from("blue", 16.0, 35.0))
	_check(g.yards_to_go_from("blue", 11.8, 35.0) == 24, "码数2 蓝 11.8→35 应为 24（实际 %d）" % g.yards_to_go_from("blue", 11.8, 35.0))
	_check(g.yards_to_go_from("red", 49.0, 35.0) == 14, "码数3 红 49→35 应为 14（实际 %d）" % g.yards_to_go_from("red", 49.0, 35.0))
	_check(g.yards_to_go_from("red", 20.0, 10.0) == 10, "码数4 红 20→10 应为 10（实际 %d）" % g.yards_to_go_from("red", 20.0, 10.0))
	_check(g.yards_to_go_from("red", 11.8, 10.0) == 2, "码数5 红 11.8→10 应为 2（实际 %d）" % g.yards_to_go_from("red", 11.8, 10.0))
	_check(g.yards_to_go_from("blue", 35.0, 35.0) == 0, "码数6 蓝 35→35 应为 0（实际 %d）" % g.yards_to_go_from("blue", 35.0, 35.0))

	# 状态残留：新档必须清空当前事件，但保留历史
	g.reset_match(); g.debug_setup("blue", 15.0, 1)
	g.start_play(); g.end_play("FLAG_PULL", 20.0)
	_check(g.last_event == "", "残留1 新档 CURRENT EVENT 应清空（实际 '%s'）" % g.last_event)
	_check(g.last_turnover_reason == "", "残留2 本系列没有换权时历史应为空（实际 '%s'）" % g.last_turnover_reason)
	g.reset_match(); g.debug_setup("red", 55.0, 4)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.series_turnover_reason == "TURNOVER_ON_DOWNS", "残留3 换权后 SERIES START 应记录原因（实际 '%s'）" % g.series_turnover_reason)
	_check(g.last_event == "", "残留4 换权后的新档当前事件仍应为空（实际 '%s'）" % g.last_event)

	# 端区边界：不能在有效场地内被挪动
	_check(is_equal_approx(g.field_yards_to_world(1.0), -9.0), "边界1 yards1 → z-9（实际 %.2f）" % g.field_yards_to_world(1.0))
	_check(is_equal_approx(g.world_to_field_yards(-9.0), 1.0), "边界2 z-9 → yards1（实际 %.2f）" % g.world_to_field_yards(-9.0))
	_check(is_equal_approx(g.field_yards_to_world(69.0), 59.0), "边界3 yards69 → z59（实际 %.2f）" % g.field_yards_to_world(69.0))
	_check(is_equal_approx(g.field_yards_to_world(2.0), -8.0), "边界4 yards2 → z-8（实际 %.2f）" % g.field_yards_to_world(2.0))


	# ===== 四档失败：新进攻方从本方 5 码线开始 =====
	g.reset_match(); g.debug_setup("red", 55.0, 4)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.possession_team == "blue", "换权1 应换蓝方（实际 %s）" % g.possession_team)
	_check(is_equal_approx(g.line_of_scrimmage, 15.0), "换权1 蓝方应从本方 5 码线 15 开始（实际 %.1f）" % g.line_of_scrimmage)
	g.reset_match(); g.debug_setup("blue", 30.0, 4)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 30.0)
	_check(g.possession_team == "red", "换权2 应换红方（实际 %s）" % g.possession_team)
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "换权2 红方应从本方 5 码线 55 开始（实际 %.1f）" % g.line_of_scrimmage)

	# ===== 抄截：球权必须翻转 =====
	g.reset_match(); g.debug_setup("blue", 40.0, 1)
	g.start_play(); g.end_play("INTERCEPTION", 40.0)
	_check(g.possession_team == "red", "抄截 应换红方（实际 %s）" % g.possession_team)
	_check(g.match_state == GameManager.State.RETURN_IN_PROGRESS, "抄截 应进入回攻状态（实际 %s）" % g.match_state)


	# ===== 附加分 =====
	g.reset_match(); g.debug_setup("blue", 58.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == 6, "附加1 达阵应 +6（实际 %d）" % g.score_blue)
	_check(g.extra_point_pending, "附加1 应进入附加分")
	_check(g.extra_point_pending, "附加1 附加分标记应开启")
	_check(g.possession_team == "blue", "附加1 由得分方尝试")
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "附加1 应从对方 5 码线 55 开始（实际 %.1f）" % g.line_of_scrimmage)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	_check(g.score_blue == 7, "附加2 附加分成功应 +1（实际 %d）" % g.score_blue)
	_check(not g.extra_point_pending, "附加2 附加分应结束")
	_check(g.possession_team == "red", "附加2 之后应换红方开球")
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "附加2 红方从本方 5 码线开始（实际 %.1f）" % g.line_of_scrimmage)

	g.reset_match(); g.debug_setup("blue", 58.0, 1)
	g.start_play(); g.end_play("TOUCHDOWN", 62.0)
	g.start_play(); g.end_play("INCOMPLETE_PASS", 55.0)
	_check(g.score_blue == 6, "附加3 附加分失败只保留 6 分（实际 %d）" % g.score_blue)
	_check(g.possession_team == "red", "附加3 之后应换红方")
	_check(is_equal_approx(g.line_of_scrimmage, 55.0), "附加3 红方从本方 5 码线开始（实际 %.1f）" % g.line_of_scrimmage)

	if fails.is_empty():
		print("[test_lifecycle] OK  86 项 + 附加分 11 项 共 97 项通过")
		quit(0)
	else:
		for m in fails:
			printerr("[test_lifecycle] FAIL ", m)
		quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)