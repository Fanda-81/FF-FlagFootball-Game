extends SceneTree
var main: Node3D
var f := 0
func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	var g = main.get("_game")
	var ball = main.get("_ball")
	if f == 20:
		main.call("_on_snap_pressed")
	if f == 50:
		print("掷出前 phase=", main.get("_phase"), " state=", g.get("match_state"))
		main.call("debug_sim_throw", Vector3(-10.0, 0.0, 40.0), 0) if main.has_method("debug_sim_throw") else main.call("debug_throw_at", Vector3(-10.0, 0.0, 40.0), 0)
	if f > 50 and f % 20 == 0 and f <= 250:
		if ball == null:
			ball = main.get("_ball")
		print("f=%d phase=%d resolved=%s reached=%s landed=%s attempts=%s ballz=%.1f qbz=%.1f" % [
			f, int(main.get("_phase")), str(main.get("_resolved")),
			str(ball.get("reached_target")) if ball else "?",
			str(ball.get("landed")) if ball else "?",
			str(main.get("_attempts")),
			(ball.global_position.z if ball else 0.0),
			(main.get("_qb") as Node3D).global_position.z if main.get("_qb") else 0.0])
	if f >= 260:
		quit(0)
		return true
	return false