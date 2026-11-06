extends SceneTree
## 阶段 1 测试：服装切换
##   <godot> --headless --path <项目> --script res://tools/test_outfit.gd

var _failures: Array[String] = []


func _initialize() -> void:
	var scene := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var manager := OutfitManager.new()
	manager.name = "OutfitManager"
	scene.add_child(manager)

	if not manager.setup(scene):
		_report("OutfitManager 初始化失败")
		_finish()
		return

	# --- 目录 ---
	var categories: Array = manager.categories()
	if categories.size() != 7:
		_report("分类数量 %d（应为 7）" % categories.size())
	if manager.items("shirt").size() < 2:
		_report("上衣选项少于 2 件")
	var names: Array = manager.mesh_names()
	if names.size() != 9:
		_report("网格数量 %d（应为 9）：%s" % [names.size(), names])

	# --- 默认全隐藏 ---
	for category in categories:
		# 肤色必须有默认值（否则身体是隐形的），其它分类初始不穿
		if category == "skin":
			continue
		if manager.equipped_id(category) != "":
			_report("初始状态 %s 不应装备任何东西" % category)

	# --- 装备：主场球衣 = 上衣 + 短袖 ---
	manager.equip("shirt", "shirt_home")
	if not _visible(manager, "上衣抹胸") or not _visible(manager, "短袖"):
		_report("主场球衣应同时显示「上衣抹胸」和「短袖」")
	if _visible(manager, "短裤"):
		_report("穿上衣时不该影响裤子")

	# --- 切换到无袖：短袖必须隐藏 ---
	manager.equip("shirt", "shirt_away")
	if not _visible(manager, "上衣抹胸"):
		_report("客场球衣应显示「上衣抹胸」")
	if _visible(manager, "短袖"):
		_report("客场球衣是无袖的，「短袖」应该隐藏")

	# --- 同分类只能装备一件 ---
	manager.equip("shirt", "shirt_training")
	if _visible(manager, "上衣抹胸"):
		_report("训练背心只有袖子，「上衣抹胸」应隐藏")

	# --- 卸下 ---
	manager.unequip("shirt")
	if _visible(manager, "短袖"):
		_report("卸下上衣后「短袖」应隐藏")

	# --- 身体网格永远可见 ---
	if not _visible(manager, "Cube"):
		_report("身体网格不应被隐藏")

	# --- 默认穿搭 ---
	manager.reset_outfit()
	if manager.equipped_id("shirt") != "shirt_home":
		_report("恢复默认穿搭后上衣应为 shirt_home，实际 %s" % manager.equipped_id("shirt"))
	if not _visible(manager, "鞋子"):
		_report("默认穿搭应穿上鞋子")

	# --- 动画/骨架不受影响 ---
	var skeleton := manager.skeleton()
	if skeleton == null or skeleton.get_bone_count() != 22:
		_report("骨架被破坏")
	if skeleton.get_bone_name(0) != "mixamorig_Hips":
		_report("骨骼绑定顺序被改变")

	# --- 状态导出 ---
	var state := manager.state()
	if not state.has("equipped") or not state.has("colors"):
		_report("state() 结构不完整")

	_finish()


func _visible(manager: OutfitManager, mesh_name: String) -> bool:
	var mesh := manager.mesh_node(mesh_name)
	return mesh != null and mesh.visible


func _report(text: String) -> void:
	_failures.append(text)


func _finish() -> void:
	if _failures.is_empty():
		print("[test_outfit] OK  服装切换、卸下、默认穿搭、骨架完好")
		quit(0)
	else:
		for failure in _failures:
			printerr("[test_outfit] FAIL ", failure)
		quit(1)
