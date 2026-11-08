extends SceneTree
var main: Node3D
var f := 0
var z0 := 0.0
var fails: Array[String] = []

func _initialize() -> void:
	PenaltyConfig.enabled = false   # 测试里关闭随机犯规，保证可复现
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 20:
		main.call("_on_snap_pressed")
	if f == 200:
		var js := main.get("_joystick_base") as Control
		var visible_now := false
		if js != null:
			visible_now = js.visible
		print("[J1] 比赛中摇杆可见=", visible_now)
		if not visible_now:
			fails.append("比赛中摇杆未显示")
		var qb := main.get("_qb") as Node3D
		z0 = qb.global_position.z
		main.call("debug_set_joystick", 0.0, -1.0)
	if f == 320:
		var qb2 := main.get("_qb") as Node3D
		var z1: float = qb2.global_position.z
		print("[J2] 摇杆推上后 QB z: %.2f -> %.2f (delta=%+.2f)" % [z0, z1, z1 - z0])
		if absf(z1 - z0) < 0.2:
			fails.append("摇杆没有驱动 QB 移动")
		main.call("debug_set_joystick", 0.0, 0.0)
		if fails.is_empty():
			print("[test_joystick] OK  摇杆显示并驱动持球人移动")
			quit(0)
		else:
			for m in fails:
				printerr("[test_joystick] FAIL ", m)
			quit(1)
		return true
	return false