extends Node3D
## FF · 截图场景控制器（QA 工具，不属于游戏本体）
##
## 用法：
##   <godot> --path <项目> res://tools/closeup.tscn      --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/fullview.tscn     --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/helpview.tscn     --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/spectatorview.tscn --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/ballfocus.tscn    --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/snapview.tscn     --write-movie out.png --fixed-fps 30 --quit-after 40
##   <godot> --path <项目> res://tools/tdview.tscn       --write-movie out.png --fixed-fps 30 --quit-after 30

@export_enum("default", "close", "field", "help", "spectator", "throw", "throwhigh", "focus", "snap", "td", "opendrawers") var mode := "default"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var main := get_node_or_null("Main")
	if main == null:
		push_error("tools/closeup.gd: 找不到 Main 节点")
		return
	match mode:
		"close":
			main.call("debug_zoom_in")
		"field":
			main.call("debug_zoom_out")
		"help":
			main.call("show_help")
		"spectator":
			main.call("debug_spectator")
		"throw":
			main.call("debug_throw_at", Vector3(6.0, 0.0, 24.0), 0)
		"throwhigh":
			main.call("debug_throw_at", Vector3(6.0, 0.0, 24.0), 1)
		"focus":
			main.call("debug_focus_ball")
			main.call("debug_throw_at", Vector3(0.0, 0.0, 40.0), 1)
		"snap":
			main.call("debug_snap_now")
		"opendrawers":
			main.call("debug_open_menu")
			main.call("debug_open_play_drawer")
		"td":
			main.call("debug_touchdown")
		_:
			pass
