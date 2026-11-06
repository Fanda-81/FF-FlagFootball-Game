extends SceneTree
## 阶段 2 测试：颜色编辑（材质实例隔离 / 只改选中对象 / 恢复默认）
##   <godot> --headless --path <项目> --script res://tools/test_color.gd

var _failures: Array[String] = []


func _initialize() -> void:
	var scene := (load("res://assets/models/characters/FFfemale.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var manager := OutfitManager.new()
	scene.add_child(manager)
	manager.setup(scene)
	manager.equip("shirt", "shirt_home")
	manager.equip("accessory", "acc_gloves")

	var editor := CharacterColorEditor.new()
	scene.add_child(editor)
	editor.setup(manager)

	# --- 选中 ---
	if not editor.select("shirt", "shirt_home"):
		_report("选中上衣失败")
	if editor.current_color() != manager.item_by_id("shirt", "shirt_home").default_color:
		_report("初始颜色应等于默认颜色")

	# --- 改色 ---
	var red := Color("ff0000")
	editor.apply_color(red)
	if _material_albedo(manager, "上衣抹胸") != red:
		_report("上衣颜色没有实时生效")
	if _material_albedo(manager, "短袖") != red:
		_report("同属上衣的「短袖」应该一起变色")

	# --- 其它分类不受影响 ---
	var glove_before := _material_albedo(manager, "手套")
	if glove_before == red:
		_report("改上衣把配饰的颜色也改了")
	var body_before := _material_albedo(manager, "Cube")
	if body_before == red:
		_report("改上衣把身体颜色也改了")

	# --- 材质实例必须互不共享 ---
	var shirt_material := _material(manager, "上衣抹胸")
	var glove_material := _material(manager, "手套")
	if shirt_material == glove_material:
		_report("上衣和配饰共用同一个材质实例")

	# --- 切到另一件上衣，颜色按服装各自保存 ---
	manager.equip("shirt", "shirt_away")
	if _material_albedo(manager, "上衣抹胸") == red:
		_report("换上衣后不该沿用上一件的颜色")

	# --- 恢复默认颜色 ---
	editor.select("shirt", "shirt_home")
	editor.reset_color()
	if editor.current_color() != manager.item_by_id("shirt", "shirt_home").default_color:
		_report("恢复默认颜色后 current_color 不对")
	if manager.equipped_id("shirt") == "shirt_home" and _material_albedo(manager, "上衣抹胸") != manager.item_by_id("shirt", "shirt_home").default_color:
		_report("恢复默认颜色没有作用到材质上")

	# --- 没有选中时改色应被忽略 ---
	editor.clear_selection()
	var before := _material_albedo(manager, "手套")
	editor.apply_color(Color("00ff00"))
	if _material_albedo(manager, "手套") != before:
		_report("没选中时不应该改到任何颜色")

	# --- 换回默认穿搭后，颜色也不该串 ---
	manager.reset_outfit()
	_finish()


func _material(manager: OutfitManager, mesh_name: String) -> Material:
	var mesh := manager.mesh_node(mesh_name)
	if mesh == null:
		return null
	return mesh.get_surface_override_material(0)


func _material_albedo(manager: OutfitManager, mesh_name: String) -> Color:
	var material := _material(manager, mesh_name)
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	return Color(-1, -1, -1)


func _report(text: String) -> void:
	_failures.append(text)


func _finish() -> void:
	if _failures.is_empty():
		print("[test_color] OK  材质实例隔离、只改选中对象、恢复默认")
		quit(0)
	else:
		for failure in _failures:
			printerr("[test_color] FAIL ", failure)
		quit(1)
