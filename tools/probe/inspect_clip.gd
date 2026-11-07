extends SceneTree

func _initialize() -> void:
	var packed := load("res://tools/probe/111111.glb") as PackedScene
	if packed == null:
		print("load failed"); quit(1); return
	var scene := packed.instantiate()
	root.add_child(scene)
	var meshes := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	var skeleton := _find_skeleton(scene)
	print("meshes: ", meshes, "  bones: ", skeleton.get_bone_count() if skeleton else 0)
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		print("NO ANIMATION")
	else:
		for lib in player.get_animation_library_list():
			var library := player.get_animation_library(lib)
			for anim in library.get_animation_list():
				var a := library.get_animation(anim)
				var rot := 0
				var pos := 0
				for t in a.get_track_count():
					if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
						rot += 1
					elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						pos += 1
				print("ANIM '", anim, "' len=", a.length, "s tracks=", a.get_track_count(), " rot=", rot, " pos=", pos, " loop=", a.loop_mode)
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null