extends Node3D

const CHARACTER := preload("res://assets/models/characters/morra.glb")

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, -35.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("25314a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e6f8")
	environment.ambient_light_energy = 1.1
	env.environment = environment
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("364660")
	ground.material_override = gm
	add_child(ground)

	var model := CHARACTER.instantiate() as Node3D
	add_child(model)
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
		var f := 1.82 / bounds.size.y
		model.scale = Vector3.ONE * f
		model.position.y = -bounds.position.y * f
	model.rotation.y = deg_to_rad(25.0)

	var skeleton := _find_skeleton(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var base: Node = player.get_node_or_null(player.root_node)
	if base == null:
		base = player.get_parent()
	var prefix := String(base.get_path_to(skeleton))
	var clip := AnimLibrary.load_clip("defeat", skeleton, prefix)
	if clip != null:
		var library := AnimationLibrary.new()
		library.add_animation("defeat", clip)
		player.add_animation_library("ff", library)
		player.play("ff/defeat")

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.6, 1.2, -2.6)
	camera.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)
	camera.fov = 45.0
	camera.current = true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null