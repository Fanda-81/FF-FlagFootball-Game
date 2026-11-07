extends SceneTree
## 阶段 B：跑球战术 → QB 交球给跑锋（真实 main.tscn）

var main: Node3D
var f := 0
var fails: Array[String] = []
var _captured_carrier = null
var _captured_holder = null
var _captured_phase := -1
var _recorded := false

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 60:
		main.call("_select_play", "inside_run")
		print("[B1] 选择战术=", main.get("_current_play"), " is_run=", main.call("_play_is_run"))
		main.call("_on_snap_pressed")
	if f == 70:
		print("[B2] 开球后 phase=", main.get("_phase"), " carrier=", main.get("_carrier"))
	# 记录交球发生那一帧的状态（之后本档可能很快结束）
	if not _recorded and bool(main.get("_handoff_done")):
		_recorded = true
		_captured_carrier = main.get("_carrier")
		_captured_holder = main.get("_holder")
		_captured_phase = int(main.get("_phase"))
		print("[B3] 交球瞬间 phase=%d carrier=%s holder=%s" % [
			_captured_phase, (_captured_carrier.name if _captured_carrier else "null"),
			(_captured_holder.name if _captured_holder else "null")])
	if f == 200:
		var carrier = _captured_carrier
		var holder = _captured_holder
		var rb = (main.get("_actors") as Dictionary).get("Y")
		print("[B3] phase=%d handoff=%s carrier=%s holder=%s rb=%s" % [
			_captured_phase, str(main.get("_handoff_done")),
			(carrier.name if carrier else "null"), (holder.name if holder else "null"), (rb.name if rb else "null")])
		if not bool(main.get("_handoff_done")):
			fails.append("没有发生交球")
		if carrier == null or carrier != rb:
			fails.append("持球人不是跑锋")
		if holder != carrier:
			fails.append("holder 与 carrier 不一致（可能双持球）")
		if _captured_phase != 4:
			fails.append("交球后应进入 RUN（phase=%d）" % _captured_phase)
		if fails.is_empty():
			print("[test_handoff] OK  跑球战术交球给跑锋全流程通过")
			quit(0)
		else:
			for m in fails:
				printerr("[test_handoff] FAIL ", m)
			quit(1)
		return true
	return false