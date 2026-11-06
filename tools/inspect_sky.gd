extends SceneTree

func _initialize() -> void:
	var packed := load("res://assets/models/environment/SKYDome.glb") as PackedScene
	if packed == null:
		print("加载失败"); quit(1); return
	var scene := packed.instantiate()
	root.add_child(scene)
	_dump(scene, 0)
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		print(indent, "MESH '", mi.name, "' surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0,
			" aabb=", aabb, " cast_shadow=", mi.cast_shadow)
		for s in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat := mi.get_active_material(s)
			var desc := "null"
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				desc = "Std albedo=%s tex=%s unshaded=%s cull=%s" % [std.albedo_color, std.albedo_texture != null, std.shading_mode, std.cull_mode]
			elif mat != null:
				desc = mat.get_class()
			print(indent, "   surface ", s, ": ", desc)
	else:
		print(indent, node.name, " [", node.get_class(), "] xform=", (node as Node3D).transform if node is Node3D else "")
	for child in node.get_children():
		_dump(child, depth + 1)