extends SceneTree
## 验证红方 QB 后撤方向（应为 +Z，远离防守）
var main: Node3D
var f := 0
var start_z := 0.0
func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	f += 1
	if f == 30:
		var g = main.get("_game")
		g.call("change_possession", "TEST", 55.0)   # 红方在 55 码进攻
		main.call("_begin_series", 0.0, 1)
	if f == 60:
		main.call("_on_snap_pressed")
		start_z = (main.get("_qb") as Node3D).global_position.z
	if f == 140:
		var z := (main.get("_qb") as Node3D).global_position.z
		var dir := int(main.get("_attack_dir"))
		print("[D] attack_dir=%d QB: start=%.2f now=%.2f  delta=%+.2f" % [dir, start_z, z, z - start_z])
		var ok := (z > start_z) if dir < 0 else (z < start_z)
		print("[D] 后撤方向 %s" % ("正确（远离防守）" if ok else "错误（撞向防守）"))
		quit(0 if ok else 1)
		return true
	return false