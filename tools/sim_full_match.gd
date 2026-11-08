extends SceneTree
## 完整比赛流程演练：真实 main.tscn，连续多档，输出连续日志

var main: Node3D
var g: Node
var t0 := 0
var step := 0
var next_at := 0
var downs_played := 0
var log_lines: Array[String] = []

func _initialize() -> void:
	PenaltyConfig.enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()

func _now() -> int:
	return Time.get_ticks_msec() - t0

func _line(s: String) -> void:
	log_lines.append(s)
	print(s)

func _phase() -> int:
	return int(main.get("_phase"))

func _process(_d: float) -> bool:
	g = main.get("_game")
	if g == null:
		return false
	var now := _now()
	if now < next_at:
		return false
	match step:
		0:
			_line("[MATCH] 场景就绪，开始演练")
			step = 1
			next_at = now + 300
		1:
			if _phase() == 0:
				_line("[MATCH] ===== 第 %d 档：%s DOWN %d @ %.1f =====" % [
					downs_played + 1, String(g.get("possession_team")).to_upper(),
					int(g.get("down_number")), float(g.get("line_of_scrimmage"))])
				main.call("_on_snap_pressed")
				step = 2
				next_at = now + 1500
			else:
				next_at = now + 100
		2:
			var los: float = float(g.get("line_of_scrimmage"))
			var dir_pos: float = float(g.call("get_attacking_direction"))
			# 一半传球未完成、一半拔旗推进
			if downs_played % 2 == 0:
				main.call("debug_sim_flag_pull", los + 6.0 * dir_pos)
			else:
				main.call("debug_sim_flag_pull", los + 1.0 * dir_pos)
			downs_played += 1
			step = 3
			next_at = now + 2500
		3:
			_line("[MATCH]   得分 蓝 %d : %d 红" % [int(g.get("score_blue")), int(g.get("score_red"))])
			if downs_played >= 8:
				_line("[MATCH] 演练结束：共 %d 档" % downs_played)
				var f := FileAccess.open("user://match_log.txt", FileAccess.WRITE)
				if f != null:
					f.store_string("\n".join(log_lines))
					f.close()
					_line("[MATCH] 日志已写入 " + ProjectSettings.globalize_path("user://match_log.txt"))
				quit(0)
				return true
			step = 1
			next_at = now + 200
	return false