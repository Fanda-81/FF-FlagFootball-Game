extends Node3D
## FF · 橄榄球模型特写（QA 工具，不属于游戏本体）
##
## 用法：
##   <godot> --path <项目> res://tools/ballcheck.tscn --write-movie out.png --fixed-fps 30 --quit-after 4
##
## 只加载 football.tscn，用一盏灯和一个近距离相机把球拍清楚，
## 用来检查材质：应当只有球皮是棕色贴图，白色防滑条与中间球线保持白色，
## 不能出现 FFSIMU 那圈程序化的白色腰环。

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("141a22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9c6e8")
	environment.ambient_light_energy = 0.9
	world_environment.environment = environment
	add_child(world_environment)

	var ball: Node3D = load("res://scenes/football.tscn").instantiate() as Node3D
	add_child(ball)

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.17, 0.11, 0.23)
	camera.look_at(Vector3(0.0, 0.01, 0.0), Vector3.UP)
	camera.fov = 38.0
	camera.current = true
