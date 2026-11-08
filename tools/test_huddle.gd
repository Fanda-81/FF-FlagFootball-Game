extends SceneTree
## 每档节奏：结束后 ≤2 秒内进入下一档列阵，球员往回跑，不再有 Huddle 停顿

var main: Node3D
var f := 0
var fails: Array[String] = []
var end_ms := -1
var checked_mid := false
var checked_ready := false
var checked_snap := false

func _initialize() -> void:
	PenaltyConfig.enabled = false   # 测试里关闭随机犯规，保证可复现
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 40:
		main.call("_on_snap_pressed")
	if f == 110:
		main.call("debug_sim_flag_pull", 20.0)   # 结束一档
		end_ms = Time.get_ticks_msec()
	if end_ms > 0 and not checked_mid and Time.get_ticks_msec() - end_ms >= 1500:
		checked_mid = true
		# 2.5 秒（150 帧 @60fps）后必须已经进入列阵或准备开球
		var ph := int(main.get("_phase"))
		print("[P] 结束一档后 1.5s phase=%d（7=列阵 0=准备开球 8=Huddle）" % ph)
		if ph == 8 or ph == 5:
			fails.append("每档之间仍有停顿（phase=%d）" % ph)
		if ph != 0 and ph != 7:
			fails.append("2.5 秒后应进入列阵/准备开球（phase=%d）" % ph)
	if end_ms > 0 and not checked_ready and Time.get_ticks_msec() - end_ms >= 2000:
		checked_ready = true
		var ph2 := int(main.get("_phase"))
		print("[P] 结束一档后 4.3s phase=%d" % ph2)
		if ph2 != 0:
			fails.append("应在 PRE_SNAP 等待开球（phase=%d）" % ph2)
		main.call("_select_play", "verticals")
		main.call("_on_snap_pressed")
	if end_ms > 0 and not checked_snap and Time.get_ticks_msec() - end_ms >= 2600:
		checked_snap = true
		print("[P] 下一档开球后 phase=%d play=%d" % [int(main.get("_phase")), main.get("_game").get("play_id")])
		if int(main.get("_phase")) != 1 and int(main.get("_phase")) != 2:
			fails.append("下一档没能开球（phase=%d）" % int(main.get("_phase")))
		if fails.is_empty():
			print("[test_huddle] OK  档间无停顿，≤2.5s 进入列阵并可直接开球")
			quit(0)
		else:
			for m in fails:
				printerr("[test_huddle] FAIL ", m)
			quit(1)
		return true
	return false