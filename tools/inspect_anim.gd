extends SceneTree
## 临时诊断：对比 FFfemale 的髋部静止变换 与 Fast Run 动画写入的髋部数值。

func _initialize() -> void:
	var model := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(model)
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		print("没有骨架")
		quit(1)
		return
	print("骨骼数: ", skeleton.get_bone_count())
	var hips := skeleton.find_bone("mixamorig_Hips")
	var rest := skeleton.get_bone_rest(hips)
	print("Hips rest  position=", rest.origin, " quat=", rest.basis.get_rotation_quaternion(), " scale=", rest.basis.get_scale())
	var root_rest := skeleton.get_bone_rest(skeleton.find_bone("mixamorig_Spine"))
	print("Spine rest position=", root_rest.origin)

	var run_root := (load("res://assets/models/characters/FastRun.glb") as PackedScene).instantiate()
	for bone in ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_LeftUpLeg"]:
		var node := run_root.find_child(bone, true, false) as Node3D
		if node != null:
			print("FastRun 节点 ", bone, " rest position=", node.position, " quat=", node.quaternion, " scale=", node.scale)
	run_root.queue_free()
	var source := MixamoRetarget.load_source_animation("res://assets/models/characters/FastRun.glb")
	print("动画长度 ", source.length, " 轨道 ", source.get_track_count())
	for t in source.get_track_count():
		var bone := String(source.track_get_path(t)).get_file()
		if bone != "mixamorig_Hips":
			continue
		var type := source.track_get_type(t)
		var keys := source.track_get_key_count(t)
		print("  Hips 轨道 type=", type, " keys=", keys)
		for k in mini(3, keys):
			print("    t=", source.track_get_key_time(t, k), " value=", source.track_get_key_value(t, k))
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null
