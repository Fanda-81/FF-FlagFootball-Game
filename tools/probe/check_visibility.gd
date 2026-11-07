extends SceneTree
## 对比：原始 glb 的网格可见性 vs 经过 OutfitManager 之后的可见性

func _initialize() -> void:
	var raw := (load("res://assets/models/characters/morra.glb") as PackedScene).instantiate()
	root.add_child(raw)
	print("=== 原始 glb（探针渲染用的就是这种） ===")
	_dump(raw)

	var scene := (load("res://assets/models/characters/morra.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var manager := OutfitManager.new()
	scene.add_child(manager)
	manager.setup(scene)
	print("=== OutfitManager.setup() 之后（未装备任何东西） ===")
	_dump(scene)

	OutfitSaveManager.load_into(manager)
	print("=== load_into() 之后（存档优先） ===")
	_dump(scene)
	print("装备状态: ", manager.state()["equipped"])
	quit(0)


func _dump(scene: Node) -> void:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		print("  %-16s visible=%s" % [String(mi.name), mi.visible])