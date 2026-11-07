extends SceneTree
var main: Node3D
var f := 0
func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	var g = main.get("_game")
	if f == 30:
		print("has debug_sim_flag_pull: ", main.has_method("debug_sim_flag_pull"))
		print("before snap: phase=", main.get("_phase"), " state=", g.get("match_state"), " ended=", g.get("play_already_ended"))
		main.call("_on_snap_pressed")
	if f == 60:
		print("after snap : phase=", main.get("_phase"), " state=", g.get("match_state"), " ended=", g.get("play_already_ended"))
		main.call("debug_sim_flag_pull", 20.0)
	if f == 90:
		print("after pull : phase=", main.get("_phase"), " state=", g.get("match_state"), " ended=", g.get("play_already_ended"),
			" down=", g.get("down_number"), " los=", g.get("line_of_scrimmage"))
		quit(0)
		return true
	return false