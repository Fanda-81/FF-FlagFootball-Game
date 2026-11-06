extends SceneTree
## 对比：角色 T-pose 与「静止站立」源骨架的手臂世界朝向差。

func _initialize() -> void:
	var char_scene := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(char_scene)
	var skeleton := _find_skeleton(char_scene)
	var rests := MixamoRetarget.read_rest_rotations("res://assets/models/characters/Idle.glb")
	var parents := MixamoRetarget.read_hierarchy("res://assets/models/characters/Idle.glb")

	for bone in ["mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_LeftUpLeg"]:
		var idx := skeleton.find_bone(bone)
		var wc := _world_rest(skeleton, idx)
		var ws: Quaternion = _source_world_rest(bone, rests, parents)
		var delta: Quaternion = wc * ws.inverse()
		print("%s  角色世界静止=%s  源世界静止=%s  差角=%.1f°" % [bone, wc, ws, rad_to_deg(delta.get_angle())])
	quit(0)


func _world_rest(skeleton: Skeleton3D, idx: int) -> Quaternion:
	var chain := []
	var cur := idx
	while cur >= 0:
		chain.push_front(cur)
		cur = skeleton.get_bone_parent(cur)
	var q := Quaternion.IDENTITY
	for b in chain:
		q = q * skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
	return q


func _source_world_rest(name: String, rests: Dictionary, parents: Dictionary) -> Quaternion:
	var q := Quaternion.IDENTITY
	var chain := []
	var cur := name
	while cur != "":
		chain.push_front(cur)
		cur = parents.get(cur, "")
	for b in chain:
		q = q * (rests.get(b, Quaternion.IDENTITY) as Quaternion)
	return q


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null