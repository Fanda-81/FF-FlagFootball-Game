extends SceneTree
## 临时诊断脚本：打印 FFfemale / FastRun 导入后的节点结构与骨骼、动画信息。
##   <godot> --headless --path <项目> --script res://tools/inspect_rig.gd

func _initialize() -> void:
	_dump_scene("res://assets/models/characters/FFfemale.glb")
	print("")
	_dump_scene("res://assets/models/characters/FastRun.glb")
	quit(0)


func _dump_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	print("=== ", path, " ===")
	if packed == null:
		print("  加载失败")
		return
	var root := packed.instantiate()
	_print_tree(root, 0)
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	if skeleton != null:
		print("  Skeleton3D 名称: ", skeleton.name, "  骨骼数: ", skeleton.get_bone_count())
		var names: Array[String] = []
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		print("  骨骼: ", ", ".join(PackedStringArray(names)))
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	if player != null:
		print("  AnimationPlayer: ", player.name)
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				var animation := library.get_animation(animation_name)
				print("    动画 '", animation_name, "' 长度 ", animation.length, " 轨道 ", animation.get_track_count())
				var paths := {}
				for t in animation.get_track_count():
					paths[String(animation.track_get_path(t))] = true
				var sample: Array = paths.keys()
				sample.sort()
				print("      轨道路径示例: ", sample.slice(0, 6))
				if paths.has("Skeleton3D:mixamorig_Hips"):
					print("      Hips 有轨道 ✓")
	root.queue_free()


func _print_tree(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			line += "  verts=" + str(mesh_instance.mesh.get_faces().size())
	print(line)
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var hit := _find(child, cls)
		if hit != null:
			return hit
	return null
