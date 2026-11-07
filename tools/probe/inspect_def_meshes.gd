extends SceneTree

func _initialize() -> void:
	var scene := (load("res://assets/models/anims/Defeated.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var skeleton := _find(scene)
	if skeleton != null:
		var names: Array = []
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		print("bones(", skeleton.get_bone_count(), "): ", ", ".join(PackedStringArray(names)))
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		print("MESH '", mi.name, "' aabb=", mi.get_aabb().size)
	quit(0)


func _find(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find(child)
		if hit != null:
			return hit
	return null