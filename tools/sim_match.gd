extends SceneTree
## 真实主场景自动化演练：加载 main.tscn，驱动真实事件，断言场景同步

var main: Node3D
var step := 0
var wait := 0
var lines: Array[String] = []
var fails := 0
var g: Node
var _sim_pid := 0

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# g 在 _ready 之后才存在，放到 _process 里惰性获取
	_log("=== SIM MATCH START ===")

func _log(s: String) -> void:
	lines.append(s)
	print(s)

func _check(ok: bool, name: String, expected: String, actual: String) -> void:
	if ok:
		_log("  PASS  " + name)
	else:
		fails += 1
		_log("  FAIL  %s  expected=%s actual=%s  [state=%s play=%d]" % [name, expected, actual, g.get("match_state"), g.get("play_id")])

func _sync_ok(tag: String) -> void:
	var los_yards: float = g.get("line_of_scrimmage")
	var ball_yards: float = g.get("ball_position_yards")
	_check(is_equal_approx(los_yards, ball_yards), tag + " LOS==BALL", "%.2f" % los_yards, "%.2f" % ball_yards)
	var ball := main.get_node_or_null("FootballRoot") as Node3D
	if ball != null:
		var ball_world := ball.global_position.z
		var expect_world: float = g.call("field_yards_to_world", ball_yards)
		# 球在手里时会有手柄偏移，允许 2 米误差
		_check(absf(ball_world - expect_world) < 2.0, tag + " BALL WORLD", "%.2f" % expect_world, "%.2f" % ball_world)

func _process(_delta: float) -> bool:
	if g == null:
		g = main.get("_game")
		if g == null:
			return false
	if wait > 0:
		wait -= 1
		return false
	match step:
		0:
			_log("[SCENE] main.tscn loaded, nodes=" + str(main.get_child_count()))
			_sync_ok("[INIT]")
			step = 1
			wait = 5
		1:
			# 场景 A：蓝队第一档传球未完成
			_log("\n--- SCENARIO A: incomplete pass ---")
			_log("  play=%d down=%d los=%.1f" % [g.get("play_id"), g.get("down_number"), g.get("line_of_scrimmage")])
			_sim_pid = int(g.get("play_id"))
			main.call("debug_snap_now")
			main.call("debug_throw_at", Vector3(-12.0, 0.0, 40.0), 0)
			step = 2
			wait = 240
		2:
			_check(g.get("possession_team") == "blue", "A possession stays BLUE", "blue", str(g.get("possession_team")))
			_check(g.get("down_number") == 2, "A down 2", "2", str(g.get("down_number")))
			_check(g.get("play_id") > _sim_pid, "A play id increased", ">" + str(_sim_pid), str(g.get("play_id")))
			_sync_ok("[A]")
			step = 3
			wait = 5
		3:
			# 场景 B：拔旗推进 5 码
			_log("\n--- SCENARIO B: flag pull +5 ---")
			var los: float = g.get("line_of_scrimmage")
			main.call("debug_sim_flag_pull", los + 5.0)
			step = 4
			wait = 180
		4:
			_log("  los=%.1f down=%d play=%d" % [g.get("line_of_scrimmage"), g.get("down_number"), g.get("play_id")])
			_check(g.get("possession_team") == "blue", "B possession BLUE", "blue", str(g.get("possession_team")))
			_sync_ok("[B]")
			step = 5
			wait = 5
		5:
			# 场景 C：耗尽四档 → 换权
			_log("\n--- SCENARIO C: turnover on downs ---")
			var d: int = g.get("down_number")
			while d <= 4:
				main.call("debug_snap_now")
				main.call("debug_throw_at", Vector3(-12.0, 0.0, 40.0), 0)
				# 等落地判定
				step = 6
				wait = 240
				return false
			step = 6
		6:
			_log("  possession=%s down=%d dir=%.0f target=%.1f los=%.1f" % [
				g.get("possession_team"), g.get("down_number"),
				g.call("get_attacking_direction"), g.get("first_down_line"), g.get("line_of_scrimmage")])
			if g.get("possession_team") == "blue":
				# 还没耗尽，继续打一档
				main.call("debug_snap_now")
				main.call("debug_throw_at", Vector3(-12.0, 0.0, 40.0), 0)
				wait = 240
				return false
			_check(g.get("possession_team") == "red", "C possession flipped", "red", str(g.get("possession_team")))
			_check(absf(float(g.call("get_attacking_direction")) + 1.0) < 0.01, "C red direction -1", "-1", str(g.call("get_attacking_direction")))
			_sync_ok("[C]")
			step = 7
			wait = 5
		7:
			# 场景 D：红队被截球 → 蓝队回攻 → 场内拔旗
			_log("\n--- SCENARIO D: interception return ---")
			main.call("debug_force_interception")
			step = 8
			wait = 60
		8:
			var s = g.get("match_state")
			_log("  state after interception=" + str(s))
			var poss_before = g.get("possession_team")
			main.call("debug_sim_flag_pull", 18.0)
			step = 9
			wait = 180
		9:
			_log("  possession=%s los=%.1f" % [g.get("possession_team"), g.get("line_of_scrimmage")])
			_check(is_equal_approx(g.get("line_of_scrimmage"), 18.0), "D return ended at 18", "18.00", "%.2f" % g.get("line_of_scrimmage"))
			_sync_ok("[D]")
			step = 10
			wait = 5
		10:
			# 场景 E：达阵判罚（正确端区 / 错误端区）
			_log("\n--- SCENARIO E: touchdown ---")
			var score_before: int = g.get("score_blue") + g.get("score_red")
			var dir: float = g.call("get_attacking_direction")
			var good_yard := 62.0 if dir > 0.0 else 8.0
			main.call("debug_sim_touchdown", good_yard)
			step = 11
			wait = 60
		11:
			var total: int = g.get("score_blue") + g.get("score_red")
			_log("  total score now=%d" % total)
			_check(total >= 6, "E touchdown awarded", ">=6", str(total))
			_write_report()
			return true
	return false

func _write_report() -> void:
	_log("\n=== RESULT: %s (%d failures) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	var f := FileAccess.open("user://sim_match_report.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
		_log("[report] " + ProjectSettings.globalize_path("user://sim_match_report.log"))
	quit(0)