extends Node3D
## 把 111111.glb 平铺渲染，用于肉眼检查动作。

const MODEL := preload("res://tools/probe/111111.glb")

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1a2230")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9dcf2")
	environment.ambient_light_energy = 1.0
	env.environment = environment
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("2c3a4d")
	ground.material_override = gm
	add_child(ground)

	var holder := Node3D.new()
	add_child(holder)
	var model := MODEL.instantiate() as Node3D
	holder.add_child(model)
	holder.rotation.y = deg_to_rad(35.0)

	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if bounds.size.y > 0.01:
		var factor := 1.82 / bounds.size.y
		model.scale = Vector3.ONE * factor
		model.position.y = -bounds.position.y * factor

	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		var lib := player.get_animation_library("")
		if lib == null:
			lib = player.get_animation_library(player.get_animation_library_list()[0])
		var names := lib.get_animation_list()
		if names.size() > 0:
			# 这段动画自带根位移（25 条 position 轨道），会把角色带出画面，
			# 这里复制一份只保留旋转，方便看清跑步循环本身。
			var source := player.get_animation(names[0])
			var stripped := Animation.new()
			stripped.length = source.length
			stripped.loop_mode = Animation.LOOP_LINEAR
			for ti in source.get_track_count():
				if source.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
					continue
				var ni := stripped.add_track(Animation.TYPE_ROTATION_3D)
				stripped.track_set_path(ni, source.track_get_path(ti))
				for ki in source.track_get_key_count(ti):
					stripped.track_insert_key(ni, source.track_get_key_time(ti, ki), source.track_get_key_value(ti, ki))
			var library := AnimationLibrary.new()
			library.add_animation("clip", stripped)
			if player.has_animation_library("probe"):
				player.remove_animation_library("probe")
			player.add_animation_library("probe", library)
			player.play("probe/clip")

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(1.2, 1.15, -3.1)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	camera.fov = 42.0
	camera.current = true