extends SceneTree
var main: Node3D
var f := 0
func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	if f == 40:
		main.call("_select_play", "inside_run")
		main.call("_on_snap_pressed")
	if f > 40 and f % 40 == 0 and f <= 240:
		print("f=%d phase=%d play_elapsed=%.2f handoff=%s dropback=%s run=%s" % [
			f, int(main.get("_phase")), float(main.get("_play_elapsed")),
			str(main.get("_handoff_done")), str(main.get("_dropback_active")),
			str(main.call("_play_is_run"))])
	if f >= 250:
		quit(0)
		return true
	return false