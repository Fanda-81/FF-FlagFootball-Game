extends SceneTree
## 检查 Huddle Posture01 转换结果：骨架静息、骨骼数、动画轨道，并与 FFfemale 对比。

func _initialize() -> void:
	var packed := load("res://assets/models/anims/HuddlePosture01.glb") as PackedScene
	if packed == null:
		print("加载失败")
		quit(1)
		return
	var scene_root := packed.instantiate()
	root.add_child(scene_root)
	print("--- 节点树（前 12 层） ---")
	_print_tree(scene_root, 0, 0)
	var skeleton := _find_skeleton(scene_root)
	if skeleton != null:
		print("骨骼数: ", skeleton.get_bone_count())
		var hips := skeleton.find_bone("mixamorig_Hips")
		if hips >= 0:
			var rest := skeleton.get_bone_rest(hips)
			print("Hips rest position=", rest.origin, " quat=", rest.basis.get_rotation_quaternion())
	else:
		print("没有 Skeleton3D")
	var player := scene_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for lib_name in player.get_animation_library_list():
			var library := player.get_animation_library(lib_name)
			for anim_name in library.get_animation_list():
				var a := library.get_animation(anim_name)
				print("动画 '", anim_name, "' 长度 ", a.length, " 轨道 ", a.get_track_count())
				var counts := {}
				for t in a.get_track_count():
					var type := a.track_get_type(t)
					counts[type] = counts.get(type, 0) + 1
				print("   轨道类型统计(0=pos,1=rot,2=scale,3=method): ", counts)
				print("   示例路径: ", a.track_get_path(0))
	quit(0)


func _print_tree(node: Node, depth: int, count: int) -> void:
	if depth > 3:
		return
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]")
	for child in node.get_children():
		_print_tree(child, depth + 1, count)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null