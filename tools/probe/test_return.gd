extends SceneTree

var _main: Node3D
var _frames := 0
var _carrier: Node3D

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_main.call("debug_force_interception")
		_carrier = _main.get("_carrier") as Node3D
	if _frames > 10 and _carrier != null and _frames % 30 == 0:
		print("  f", _frames,
			" move_input=", _carrier.get("_move_input"),
			" vel=", "%.2f" % (_carrier as CharacterBody3D).velocity.length(),
			" processing=", _carrier.is_physics_processing(),
			" active=", _carrier.get("is_active"),
			" z=", "%.2f" % _carrier.global_position.z)
	if _frames >= 100:
		quit(0)
		return true
	return false