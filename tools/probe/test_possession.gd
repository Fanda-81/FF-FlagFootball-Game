extends SceneTree

var _main: Node3D
var _f := 0

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 5:
		print("换防前 offense_side=", _main.get("_offense_side"))
	if _f == 60:
		_main.call("debug_swap_possession")
	if _f == 70:
		print("换防后 offense_side=", _main.get("_offense_side"),
			" attack_dir=", _main.get("_attack_dir"))
		var qb := _main.get("_qb") as Node3D
		print("  新 QB = ", qb.name, " 位置=", qb.global_position)
		for slot in ["QB", "X", "CB1", "SS"]:
			var actor := (_main.get("_actors") as Dictionary).get(slot) as Node3D
			if actor != null:
				print("  槽位 ", slot, " -> ", actor.name, " 标签=", actor.get("actor_name"),
					" 位置=", actor.global_position.round())
	if _f >= 90:
		quit(0)
		return true
	return false