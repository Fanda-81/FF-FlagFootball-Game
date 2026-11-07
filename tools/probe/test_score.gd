extends SceneTree
var _main: Node3D
var _f := 0
var _red_before := 0
func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
func _process(_delta: float) -> bool:
	_f += 1
	if _f == 5:
		_red_before = _main.get("_score_red")
		_main.call("debug_force_interception")
		print("抄截回攻开始，red=", _red_before, " offense=", _main.get("_offense_side"))
	if _f == 200 or (_f > 10 and _f % 40 == 0):
		print("  f", _f, " blue=", _main.get("_score_blue"), " red=", _main.get("_score_red"),
			" offense=", _main.get("_offense_side"), " td=", _main.get("_td_celebrating"))
	if _f >= 240:
		quit(0)
		return true
	return false