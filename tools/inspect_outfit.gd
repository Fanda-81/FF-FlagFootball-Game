extends SceneTree
## 阶段 0：检查角色模型里可用于换装的 Mesh 节点、材质表面、以及蒙皮绑定。

func _initialize() -> void:
	var scene := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene)
	_dump(scene, 0)
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	if node is Skeleton3D:
		print(indent, node.name, " [Skeleton3D] bones=", (node as Skeleton3D).get_bone_count())
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		print(indent, "MESH '", mi.name, "' surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0,
			" skin=", mi.skin != null, " skeleton=", mi.skeleton, " parent=", mi.get_parent().name,
			" surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0)
		for s in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat := mi.get_active_material(s)
			var desc := "null"
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				desc = "StandardMaterial3D albedo=%s tex=%s" % [std.albedo_color, std.albedo_texture != null]
			elif mat != null:
				desc = mat.get_class()
			var override := mi.get_surface_override_material(s)
			print(indent, "   surface ", s, ": ", desc, " override=", override != null)
	else:
		print(indent, node.name, " [", node.get_class(), "]")
	for child in node.get_children():
		_dump(child, depth + 1)