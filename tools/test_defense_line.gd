extends SceneTree
## 真实主场景：验证防守球员启球线约束（两个方向 + 连续换权）

var main: Node3D
var f := 0
var stage := 0
var fails: Array[String] = []

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _report(tag: String) -> void:
	var defenders: Array = main.get("_defenders")
	var los: float = main.get("_los_z")
	var dir: int = main.get("_attack_dir")
	var line := los + 0.15 if dir > 0 else los - 0.15
	print("--- %s : attack_dir=%d los=%.2f line=%.2f ---" % [tag, dir, los, line])
	for d in defenders:
		var z: float = (d as Node3D).global_position.z
		var ok: bool = z >= line - 0.01 if dir > 0 else z <= line + 0.01
		print("  %s z=%.3f  %s" % [(d as Node).name, z, "OK" if ok else "VIOLATION"])
		if not ok:
			fails.append("%s %s z=%.3f line=%.3f" % [tag, (d as Node).name, z, line])

func _process(_delta: float) -> bool:
	f += 1
	if f == 90:
		_report("BLUE ATTACK")
		stage = 1
	if f == 100:
		(main.get("_game") as Node).call("change_possession", "TEST_SWAP", 15.0)
		main.call("_begin_series", 0.0, 1)
	if f == 320:
		_report("RED ATTACK")
		stage = 2
	if f == 330:
		(main.get("_game") as Node).call("change_possession", "TEST_SWAP", 15.0)
		main.call("_begin_series", 0.0, 1)
	if f == 560:
		_report("BLUE ATTACK AGAIN")
		if fails.is_empty():
			print("[test_defense_line] OK  两个方向五名防守球员全部在合法一侧")
			quit(0)
		else:
			for m in fails:
				printerr("[test_defense_line] FAIL ", m)
			quit(1)
		return true
	return false