extends Node
class_name OutfitManager
## 服装管理器：装备 / 卸下 / 改色 / 存档状态。
##
## 挂在角色下面（PlayerActor 会自己创建），负责：
##   · 找到 Skeleton3D 和它下面的所有 MeshInstance3D；
##   · 按分类隐藏/显示网格（切衣服只改 visible，不碰动画）；
##   · 每块网格的每个材质表面只复制一次材质实例，改色互不影响；
##   · 记录每件服装的自定义颜色。
##
## 注意：MeshInstance3D 必须保持挂在 Skeleton3D 下面、skin 不变，
## 否则蒙皮会失效 —— 这里从不移动节点，只切 visible。

signal outfit_changed(category: String, item_id: String)
signal color_changed(category: String, item_id: String, surface: int, color: Color)

var _character_root: Node3D
var _skeleton: Skeleton3D
var _meshes: Dictionary = {}          # 网格节点名 -> MeshInstance3D
var _catalog: Dictionary = {}         # 分类 -> Array[OutfitItem]
var _equipped: Dictionary = {}        # 分类 -> 服装 id（"" = 未装备）
var _colors: Dictionary = {}          # "分类:服装id" -> Array[Color]（按下标对应网格表面）
var _material_cache: Dictionary = {}  # "网格名|表面" -> StandardMaterial3D（独立实例）
var _original_colors: Dictionary = {} # "网格名|表面" -> 原始颜色


func setup(character_root: Node3D) -> bool:
	_character_root = character_root
	_skeleton = _find_skeleton(character_root)
	if _skeleton == null:
		push_error("OutfitManager: 找不到 Skeleton3D")
		return false
	_meshes.clear()
	for node in _skeleton.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(node.name)] = node
	_catalog = OutfitCatalog.build()
	for category in _catalog:
		_equipped[category] = ""
	# 初始一律不穿：把所有可换装网格藏起来
	for category in _catalog:
		for item in items(category):
			for mesh_name in (item as OutfitItem).mesh_names:
				var mesh := mesh_node(String(mesh_name))
				if mesh != null:
					mesh.visible = false
	# 但身体必须有默认肤色，否则角色会变成隐形人
	if _catalog.has("skin") and not items("skin").is_empty():
		equip("skin", (items("skin")[0] as OutfitItem).id)
	return true


func skeleton() -> Skeleton3D:
	return _skeleton


# =============================================================================
# 查询
# =============================================================================

func categories() -> Array:
	return OutfitCatalog.category_ids()


func category_label(category: String) -> String:
	return OutfitCatalog.category_label(category)


func items(category: String) -> Array:
	return _catalog.get(category, [])


func item_by_id(category: String, item_id: String) -> OutfitItem:
	for item in items(category):
		if item.id == item_id:
			return item
	return null


func equipped_id(category: String) -> String:
	return String(_equipped.get(category, ""))


func equipped_item(category: String) -> OutfitItem:
	return item_by_id(category, equipped_id(category))


func mesh_names() -> Array:
	return _meshes.keys()


func mesh_node(mesh_name: String) -> MeshInstance3D:
	return _meshes.get(mesh_name)


# =============================================================================
# 装备 / 卸下
# =============================================================================

## 装备某个分类下的一件服装。item_id 传 "" 等同于卸下。
func equip(category: String, item_id: String) -> bool:
	if not _catalog.has(category):
		return false
	var item := item_by_id(category, item_id)

	# 1. 先把该分类下所有网格藏起来
	for entry in items(category):
		for mesh_name in entry.mesh_names:
			var mesh := mesh_node(String(mesh_name))
			if mesh != null:
				mesh.visible = false

	# 2. 再显示新服装用到的网格
	if item != null:
		for mesh_name in item.mesh_names:
			var mesh := mesh_node(String(mesh_name))
			if mesh != null:
				mesh.visible = true
		_equipped[category] = item.id
		_apply_item_colors(item)
	else:
		_equipped[category] = ""

	outfit_changed.emit(category, String(_equipped[category]))
	return true


func unequip(category: String) -> void:
	equip(category, "")


## 全部分类回到默认穿搭（每个分类的第一件）。
func reset_outfit() -> void:
	for category in _catalog:
		var list: Array = items(category)
		if list.is_empty():
			equip(category, "")
		else:
			equip(category, (list[0] as OutfitItem).id)


# =============================================================================
# 颜色
# =============================================================================

## 某件服装某个表面的当前颜色。
func item_color(category: String, item_id: String, surface: int) -> Color:
	var colors: Array = _colors.get(_key(category, item_id), [])
	if surface >= 0 and surface < colors.size():
		return colors[surface]
	var item := item_by_id(category, item_id)
	return item.default_color if item != null else Color.WHITE


## 修改某件服装某个表面的颜色；如果这件正穿着，立刻生效。
func set_item_color(category: String, item_id: String, surface: int, color: Color) -> void:
	var item := item_by_id(category, item_id)
	if item == null or not item.color_editable:
		return
	var key := _key(category, item_id)
	var colors: Array = _colors.get(key, [])
	while colors.size() <= surface:
		colors.append(item.default_color)
	colors[surface] = color
	_colors[key] = colors

	if equipped_id(category) == item_id:
		_apply_color_to_meshes(item, surface, color)
	color_changed.emit(category, item_id, surface, color)


## 恢复某件服装某个表面的默认颜色。
func reset_item_color(category: String, item_id: String, surface: int) -> void:
	var item := item_by_id(category, item_id)
	if item == null:
		return
	# 直接从存储里删掉，之后再取就是默认色
	var key := _key(category, item_id)
	var colors: Array = _colors.get(key, [])
	if surface < colors.size():
		colors.remove_at(surface)
		_colors[key] = colors
	set_item_color(category, item_id, surface, item.default_color)


func _apply_item_colors(item: OutfitItem) -> void:
	for mesh_name in item.mesh_names:
		var mesh := mesh_node(String(mesh_name))
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			_apply_color_to_meshes(item, surface, item_color(item.category, item.id, surface))


func _apply_color_to_meshes(item: OutfitItem, surface: int, color: Color) -> void:
	for mesh_name in item.mesh_names:
		var material := _ensure_material(String(mesh_name), surface)
		if material != null:
			material.albedo_color = color


## 取得（必要时复制出）某块网格某个表面的独立材质实例。
func _ensure_material(mesh_name: String, surface: int) -> StandardMaterial3D:
	var key := "%s|%d" % [mesh_name, surface]
	if _material_cache.has(key):
		return _material_cache[key]
	var mesh := mesh_node(mesh_name)
	if mesh == null or mesh.mesh == null or surface >= mesh.mesh.get_surface_count():
		return null

	var base := mesh.get_active_material(surface)
	var material: StandardMaterial3D
	if base is StandardMaterial3D:
		# 关键：复制一份，避免多个配件共用材质导致一起变色
		material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
		if base != null:
			material.albedo_texture = _texture_of(base)
	# 有贴图就保留贴图，只改 albedo_color 做 Tint
	if material.albedo_texture == null and base != null:
		material.albedo_texture = _texture_of(base)

	# 球鞋用 Nike 鞋面贴图（glb 里没带贴图，只能从工程里补），
	# albedo_color 仍然作为 Tint 叠加，所以"每只鞋不同颜色"照样有效。
	if false and _is_boot(mesh_name):
		var base_tex := load("res://assets/models/textures/boot_basecolor.png") as Texture2D
		var normal_tex := load("res://assets/models/textures/boot_normal.png") as Texture2D
		if base_tex != null:
			material.albedo_texture = base_tex
		if normal_tex != null:
			material.normal_enabled = true
			material.normal_texture = normal_tex
			material.normal_scale = 0.8
		material.roughness = 0.55
		material.metallic = 0.0
	# 腰旗这类单面片在 Blender 里看不出问题，但 Godot 默认背面剔除会把它们藏起来，
	# 所以统一改成双面渲染。
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.set_surface_override_material(surface, material)
	_material_cache[key] = material
	_original_colors[key] = material.albedo_color
	return material




## 是不是球鞋的网格
func _is_boot(mesh_name: String) -> bool:
	return mesh_name.begins_with("Left_Boot") or mesh_name.begins_with("Right_Boot") \
		or mesh_name.begins_with("Left_Stud") or mesh_name.begins_with("Right_Stud")

func _texture_of(material: Material) -> Texture2D:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_texture
	return null


func _key(category: String, item_id: String) -> String:
	return "%s:%s" % [category, item_id]


# =============================================================================
# 存档用的状态
# =============================================================================

func state() -> Dictionary:
	var equipped := {}
	for category in _equipped:
		equipped[category] = String(_equipped[category])
	var colors := {}
	for key in _colors:
		var list: Array = _colors[key]
		var hex: Array = []
		for color in list:
			hex.append((color as Color).to_html(false))
		colors[key] = hex
	return {"equipped": equipped, "colors": colors}


func restore(data: Dictionary) -> void:
	var equipped: Dictionary = data.get("equipped", {})
	var colors: Dictionary = data.get("colors", {})

	_colors.clear()
	for key in colors:
		var list: Array = colors[key]
		var parsed: Array = []
		for hex in list:
			parsed.append(Color.html(String(hex)))
		_colors[String(key)] = parsed

	for category in _catalog:
		var item_id := String(equipped.get(category, ""))
		# 存档里没有的新分类（比如后加的腰旗/球袜）自动用默认件，否则会一直不显示
		if item_id == "" and not items(category).is_empty():
			item_id = (items(category)[0] as OutfitItem).id
		equip(category, item_id)


# =============================================================================
# 工具
# =============================================================================

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null
