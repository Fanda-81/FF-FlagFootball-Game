extends Node3D
## 新角色检查场景（QA 工具）
##
##   <godot> --path <项目> res://tools/charactercheck.tscn --write-movie out.png --fixed-fps 30 --quit-after 6
##
## 4 个朝向各摆一个 FFfemale，mode 决定播什么：
##   "bind"   不播动画，看绑定姿势
##   "own"    播模型自带的 mixamo_com（烘进模型的那段跑步）
##   "idle"   播从 FFSIMU 静止站立.fbx 重定向过来的站立动作
##   "fastrun" 播外部 Fast Run.fbx 的重定向结果

@export_enum("bind", "own", "idle", "fastrun") var mode := "own"

const CHARACTER := preload("res://assets/models/characters/FFfemale.glb")
const RUN_PATH := "res://assets/models/characters/FastRun.glb"
const IDLE_PATH := "res://assets/models/characters/Idle.glb"
const TARGET_HEIGHT := 1.82


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1a2230")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9d2ee")
	environment.ambient_light_energy = 0.9
	world_environment.environment = environment
	add_child(world_environment)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("2c3a4d")
	ground.material_override = ground_material
	add_child(ground)

	var angles := [0.0, 90.0, 180.0, 270.0]
	for i in angles.size():
		var holder := Node3D.new()
		holder.position = Vector3((float(i) - 1.5) * 1.15, 0.0, 0.0)
		holder.rotation.y = deg_to_rad(float(angles[i]))
		add_child(holder)

		var model := CHARACTER.instantiate() as Node3D
		holder.add_child(model)

		var bounds := _model_bounds(model)
		var scale_factor := TARGET_HEIGHT / maxf(0.001, bounds.size.y)
		model.scale = Vector3.ONE * scale_factor
		model.position.y = -bounds.position.y * scale_factor
		if i == 0:
			print("[check] 绑定姿势包围盒 min.y=%.2f 高=%.2f 缩放=%.4f" % [bounds.position.y, bounds.size.y, scale_factor])

		var skeleton := _find_skeleton(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skeleton == null or player == null:
			push_error("check: 缺骨架或动画")
			continue
		var bones: Array = []
		for b in skeleton.get_bone_count():
			bones.append(skeleton.get_bone_name(b))

		match mode:
			"own":
				var list := player.get_animation_library("").get_animation_list()
				if list.size() > 0:
					player.play(list[0])
					if i == 0:
						print("[check] 播放模型自带动画: ", list[0], " 长度 ", player.get_animation(list[0]).length)
			"idle", "fastrun":
				var path := IDLE_PATH if mode == "idle" else RUN_PATH
				var source := MixamoRetarget.load_source_animation(path)
				var rests := MixamoRetarget.read_rest_rotations(path)
				if source != null and not rests.is_empty():
					var clip := MixamoRetarget.build_animation(source, rests, skeleton, "RootNode/HIFER/Skeleton3D")
					var library := AnimationLibrary.new()
					library.add_animation("clip", clip)
					player.add_animation_library("ff", library)
					player.play("ff/clip")
					if i == 0:
						print("[check] %s 重定向: 源轨道 %d → %d，长度 %.2f" % [mode, source.get_track_count(), clip.get_track_count(), clip.length])

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 2.1, -7.0)
	camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
	camera.fov = 58.0
	camera.current = true


func _model_bounds(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null
