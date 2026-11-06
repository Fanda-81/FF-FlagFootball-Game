extends SceneTree
## 阶段 3 测试：穿搭存档（user://outfit_save.json）
##   <godot> --headless --path <项目> --script res://tools/test_save.gd

var _failures: Array[String] = []


func _initialize() -> void:
	OutfitSaveManager.delete_save()

	var scene := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var manager := OutfitManager.new()
	scene.add_child(manager)
	manager.setup(scene)
	manager.reset_outfit()

	# 搭配一套自定义穿搭
	manager.equip("shirt", "shirt_away")
	manager.equip("pants", "pants_skin")
	manager.equip("hair", "hair_ash")
	manager.set_item_color("shirt", "shirt_away", 0, Color("12ab34"))
	manager.set_item_color("hair", "hair_ash", 0, Color("abcdef"))

	if not OutfitSaveManager.save(manager):
		_report("保存失败")
		_finish()
		return
	if not OutfitSaveManager.has_save():
		_report("保存后找不到存档文件")
		_finish()
		return

	# 换一个全新的角色读档
	var scene2 := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene2)
	var manager2 := OutfitManager.new()
	scene2.add_child(manager2)
	manager2.setup(scene2)

	if not OutfitSaveManager.load_into(manager2):
		_report("读档失败")
		_finish()
		return

	if manager2.equipped_id("shirt") != "shirt_away":
		_report("上衣没有恢复：%s" % manager2.equipped_id("shirt"))
	if manager2.equipped_id("pants") != "pants_skin":
		_report("裤子没有恢复：%s" % manager2.equipped_id("pants"))
	if manager2.equipped_id("hair") != "hair_ash":
		_report("头发没有恢复：%s" % manager2.equipped_id("hair"))
	if manager2.item_color("shirt", "shirt_away", 0) != Color("12ab34"):
		_report("上衣颜色没有恢复：%s" % manager2.item_color("shirt", "shirt_away", 0))
	if manager2.item_color("hair", "hair_ash", 0) != Color("abcdef"):
		_report("头发颜色没有恢复：%s" % manager2.item_color("hair", "hair_ash", 0))

	# 读档后穿着的网格应当是可见的
	if not manager2.mesh_node("上衣抹胸").visible:
		_report("读档后上衣网格没有显示")
	if manager2.mesh_node("短袖").visible:
		_report("读档后不该显示「短袖」（客场球衣是无袖的）")

	# 读档后材质上也要真的变色
	var material := manager2.mesh_node("上衣抹胸").get_surface_override_material(0)
	if not (material is StandardMaterial3D) or (material as StandardMaterial3D).albedo_color != Color("12ab34"):
		_report("读档后材质颜色没有生效")

	# 没有存档时应回退默认
	OutfitSaveManager.delete_save()
	var scene3 := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene3)
	var manager3 := OutfitManager.new()
	scene3.add_child(manager3)
	manager3.setup(scene3)
	if OutfitSaveManager.load_into(manager3):
		_report("没有存档时 load_into 应返回 false")
	if manager3.equipped_id("shirt") != "shirt_home":
		_report("没有存档时应回退到默认上衣")

	_finish()


func _report(text: String) -> void:
	_failures.append(text)


func _finish() -> void:
	if _failures.is_empty():
		print("[test_save] OK  存档 / 读档 / 颜色恢复 / 无存档回退默认")
		quit(0)
	else:
		for failure in _failures:
			printerr("[test_save] FAIL ", failure)
		quit(1)
