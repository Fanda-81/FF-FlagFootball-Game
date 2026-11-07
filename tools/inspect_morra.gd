extends SceneTree

func _initialize() -> void:
	var packed := load("res://assets/models/characters/morra.glb") as PackedScene
	if packed == null:
		print("load failed"); quit(1); return
	var scene := packed.instantiate()
	root.add_child(scene)
	var skeleton := _find_skeleton(scene)
	print("bones: ", skeleton.get_bone_count() if skeleton else 0)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		print("MESH '", mi.name, "' parent=", mi.get_parent().name, " surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0,
			" aabb=", aabb.size)
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for lib in player.get_animation_library_list():
			for anim in player.get_animation_library(lib).get_animation_list():
				print("anim: ", anim, " len=", player.get_animation_library(lib).get_animation(anim).length)
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null