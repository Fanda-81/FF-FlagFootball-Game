extends SceneTree
## 阶段 B：跑球战术 → QB 交球给跑锋（真实 main.tscn，按真实秒采样）

var main: Node3D
var f := 0
var snap_ms := -1
var recorded := false
var carrier_at_handoff = null
var holder_at_handoff = null
var phase_at_handoff := -1
var fails: Array[String] = []

func _initialize() -> void:
	PenaltyConfig.enabled = false   # 测试里关闭随机犯规，保证可复现
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 40:
		main.call("_select_play", "inside_run")
		main.call("_on_snap_pressed")
		snap_ms = Time.get_ticks_msec()
		print("[B1] 战术=", main.get("_current_play"), " is_run=", main.call("_play_is_run"))
	if snap_ms > 0 and not recorded and bool(main.get("_handoff_done")):
		recorded = true
		carrier_at_handoff = main.get("_carrier")
		holder_at_handoff = main.get("_holder")
		phase_at_handoff = int(main.get("_phase"))
		print("[B2] 交球瞬间 phase=%d carrier=%s holder=%s 用时=%.2fs" % [
			phase_at_handoff,
			(carrier_at_handoff.name if carrier_at_handoff else "null"),
			(holder_at_handoff.name if holder_at_handoff else "null"),
			(Time.get_ticks_msec() - snap_ms) / 1000.0])
	if snap_ms > 0 and Time.get_ticks_msec() - snap_ms >= 2000:
		var rb = (main.get("_actors") as Dictionary).get("Y")
		if not recorded:
			fails.append("2 秒内没有发生交球")
		if carrier_at_handoff == null or carrier_at_handoff != rb:
			fails.append("持球人不是跑锋")
		if holder_at_handoff != carrier_at_handoff and recorded:
			fails.append("holder 与 carrier 不一致（可能双持球）")
		if recorded and phase_at_handoff != 4:
			fails.append("交球时应处于 RUN（phase=%d）" % phase_at_handoff)
		if fails.is_empty():
			print("[test_handoff] OK  跑球战术交球给跑锋全流程通过")
			quit(0)
		else:
			for m in fails:
				printerr("[test_handoff] FAIL ", m)
			quit(1)
		return true
	return false