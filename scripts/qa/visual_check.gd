extends Node3D
## 视觉核对场景（QA）
##   <godot> --path <项目> res://scenes/qa/visual_check.tscn --write-movie out.png --fixed-fps 30 --quit-after 62
##   0-14 全身正面 / 15-29 腰胯特写 / 30-44 双脚特写 / 45-59 侧面全身

const ACTOR_SCENE := preload("res://scenes/player_actor.tscn")

var _actor: Node3D
var _camera: Camera3D
var _frame := 0
var _view := -1


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -38.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color("a9c8ff")
	add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2a3752")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e2eefc")
	environment.ambient_light_energy = 1.2
	env.environment = environment
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("3a4a63")
	ground.material_override = gm
	add_child(ground)

	_actor = ACTOR_SCENE.instantiate() as Node3D
	_actor.set("personal_outfit", false)
	_actor.set("jersey_color", Color("2f7cf6"))
	add_child(_actor)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_apply_view(0)


func _process(_delta: float) -> void:
	_frame += 1
	var v := int(_frame / 15) % 4
	if v != _view:
		_view = v
		_apply_view(v)


func _apply_view(view: int) -> void:
	match view:
		0:
			_actor.rotation.y = 0.0
			_camera.position = Vector3(0.0, 1.0, -2.9)
			_camera.look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
			_camera.fov = 42.0
		1:
			_actor.rotation.y = deg_to_rad(18.0)
			_camera.position = Vector3(0.35, 1.05, -1.15)
			_camera.look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
			_camera.fov = 38.0
		2:
			_actor.rotation.y = deg_to_rad(-12.0)
			_camera.position = Vector3(0.28, 0.42, -0.95)
			_camera.look_at(Vector3(0.0, 0.12, 0.0), Vector3.UP)
			_camera.fov = 34.0
		3:
			_actor.rotation.y = deg_to_rad(90.0)
			_camera.position = Vector3(0.0, 1.05, -2.4)
			_camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
			_camera.fov = 40.0