extends Node3D
## 角色近景：用真实 PlayerActor（带服装系统），拍全身 + 腰胯特写

const ACTOR_SCENE := preload("res://scenes/player_actor.tscn")

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, -35.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("243046")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6e6f8")
	environment.ambient_light_energy = 1.1
	env.environment = environment
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("33415a")
	ground.material_override = gm
	add_child(ground)

	# 正面全身
	_spawn(Vector3(-1.1, 0.0, 0.0), 0.0)
	# 侧面全身（看腰旗侧挂）
	_spawn(Vector3(1.1, 0.0, 0.0), deg_to_rad(90.0))

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 1.05, -2.6)
	camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
	camera.fov = 45.0
	camera.current = true


func _spawn(position3d: Vector3, yaw: float) -> void:
	var actor := ACTOR_SCENE.instantiate() as Node3D
	actor.set("personal_outfit", false)
	actor.set("jersey_color", Color("2f7cf6"))
	actor.position = position3d
	actor.rotation.y = yaw
	add_child(actor)