extends Node
class_name CharacterColorEditor
## 颜色编辑器：选中某件服装的某个材质表面，改它的颜色。
##
## 与 OutfitManager 的分工：
##   · OutfitManager 负责"哪件衣服穿着"以及材质实例的复制与缓存；
##   · 这里只负责"当前选中谁 + 取色 / 改色 / 恢复默认"。
##
## 改色只会写选中那件衣服的材质实例，其它服装和身体颜色不会被动到。

signal selection_changed(category: String, item_id: String, surface: int)
signal color_applied(category: String, item_id: String, surface: int, color: Color)

var _manager: OutfitManager
var _category: String = ""
var _item_id: String = ""
var _surface: int = 0


func setup(manager: OutfitManager) -> void:
	_manager = manager


# =============================================================================
# 选中
# =============================================================================

## 选中某件服装的某个材质表面。同一件衣服有多个表面时可以指定 surface。
func select(category: String, item_id: String, surface := 0) -> bool:
	if _manager == null:
		return false
	var item := _manager.item_by_id(category, item_id)
	if item == null:
		return false
	_category = category
	_item_id = item_id
	_surface = clampi(surface, 0, maxi(0, _surface_count(item) - 1))
	selection_changed.emit(_category, _item_id, _surface)
	return true


## 选中当前分类下正穿着的那件。
func select_equipped(category: String, surface := 0) -> bool:
	var item_id := _manager.equipped_id(category) if _manager != null else ""
	if item_id == "":
		return false
	return select(category, item_id, surface)


func clear_selection() -> void:
	_category = ""
	_item_id = ""
	_surface = 0
	selection_changed.emit("", "", 0)


func has_selection() -> bool:
	return _manager != null and _item_id != "" and _manager.item_by_id(_category, _item_id) != null


func selected_category() -> String:
	return _category


func selected_item_id() -> String:
	return _item_id


func selected_item() -> OutfitItem:
	if not has_selection():
		return null
	return _manager.item_by_id(_category, _item_id)


func selected_surface() -> int:
	return _surface


## 选中对象一共有几个材质表面（用来在 UI 上提供"表面切换"）。
func surface_count() -> int:
	var item := selected_item()
	return maxi(1, _surface_count(item)) if item != null else 1


# =============================================================================
# 颜色
# =============================================================================

func current_color() -> Color:
	var item := selected_item()
	if item == null:
		return Color.WHITE
	return _manager.item_color(_category, _item_id, _surface)


func default_color() -> Color:
	var item := selected_item()
	return item.default_color if item != null else Color.WHITE


func is_editable() -> bool:
	var item := selected_item()
	return item != null and item.color_editable


## 改当前选中对象的颜色，立刻生效。
func apply_color(color: Color) -> void:
	if not has_selection():
		return
	if not is_editable():
		return
	_manager.set_item_color(_category, _item_id, _surface, color)
	color_applied.emit(_category, _item_id, _surface, color)


## 恢复当前选中对象的默认颜色。
func reset_color() -> void:
	if not has_selection():
		return
	_manager.reset_item_color(_category, _item_id, _surface)
	color_applied.emit(_category, _item_id, _surface, current_color())


func _surface_count(item: OutfitItem) -> int:
	if item == null:
		return 0
	var count := 0
	for mesh_name in item.mesh_names:
		var mesh := _manager.mesh_node(String(mesh_name))
		if mesh != null and mesh.mesh != null:
			count = maxi(count, mesh.mesh.get_surface_count())
	return maxi(count, 1)
