extends SceneTree
## 阶段 A：Huddle → 选战术 → 列阵 → Snap（真实 main.tscn）

var main: Node3D
var f := 0
var fails: Array[String] = []
var snap_id := 0

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _phase() -> int:
	return int(main.get("_phase"))

func _process(_d: float) -> bool:
	f += 1
	if f == 60:
		print("[A1] 初始 phase=%d play=%d" % [_phase(), main.get("_game").get("play_id")])
		main.call("_on_snap_pressed")            # 走真实开球入口
	if f == 140:
		print("[A1b] 开球后 phase=%d" % _phase())
		main.call("debug_sim_flag_pull", 20.0)   # 结束一档
	if f == 380:
		print("[A2] 一档结束后 phase=%d（8=HUDDLE）" % _phase())
		if _phase() != 8:
			fails.append("一档结束后没有进入 HUDDLE（phase=%d）" % _phase())
		var before := String(main.get("_current_play"))
		main.call("_select_play", "verticals")
		print("[A3] 选择战术后 phase=%d play: %s -> %s" % [_phase(), before, main.get("_current_play")])
		if String(main.get("_current_play")) != "verticals":
			fails.append("战术没有切换")
		if _phase() != 7:
			fails.append("选战术后应进入 LINEUP（phase=%d）" % _phase())
	if f == 680:
		print("[A4] 列阵结束 phase=%d（0=PRE_SNAP）" % _phase())
		if _phase() != 0:
			fails.append("列阵后没有回到 PRE_SNAP（phase=%d）" % _phase())
		main.call("_on_snap_pressed")
		main.call("_on_snap_pressed")   # 重复点击
	if f == 720:
		snap_id = int(main.get("_game").get("play_id"))
		print("[A5] 点两次开球后 play_id=%d" % snap_id)
		if _phase() != 1 and _phase() != 2:
			fails.append("开球后应进入 SNAP/PLAY（phase=%d）" % _phase())
		if fails.is_empty():
			print("[test_huddle] OK  Huddle→战术→列阵→Snap 全流程通过")
			quit(0)
		else:
			for m in fails:
				printerr("[test_huddle] FAIL ", m)
			quit(1)
		return true
	return false