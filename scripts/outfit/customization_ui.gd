extends Control
## 角色定制界面（竖屏布局）
##
##   ┌──────────────────────────────┐
##   │ 3D 预览（SubViewport，独立相机）  │  拖动旋转 / 滚轮缩放
##   ├──────────────────────────────┤
##   │ 上衣 裤子 鞋子 头发 帽子 配饰     │  分类
##   ├──────────────────────────────┤
##   │ [球衣] [无袖] [背心] …          │  服装列表（缩略色块 + 选中态）
##   ├──────────────────────────────┤
##   │ 颜色 [ColorPickerButton] [恢复默认] │
##   ├──────────────────────────────┤
##   │ [保存穿搭] [恢复默认穿搭] [退出]  │
##   └──────────────────────────────┘
##
## 预览用独立的 SubViewport + 自己的相机和灯光，完全不碰游戏主场景的摄像机。

signal closed

const CHARACTER := preload("res://assets/models/characters/FFfemale.glb")
const TARGET_HEIGHT := 1.82
const MARGIN := 24.0

var _manager: OutfitManager
var _editor: CharacterColorEditor

var _sub_viewport: SubViewport
var _character_holder: Node3D
var _model: Node3D
var _camera: Camera3D
var _camera_distance := 3.4
var _auto_rotate := 0.0

var _category_buttons: Dictionary = {}
var _item_row: HBoxContainer
var _item_buttons: Array[Button] = []
var _selected_label: Label
var _color_picker: ColorPickerButton
var _surface_button: Button
var _status_label: Label
var _current_category := "shirt"

var _dragging := false


func _ready() -> void:
	_build_preview()
	_build_layout()
	_select_category("shirt")


# =============================================================================
# 预览（SubViewport）
# =============================================================================

func _build_preview() -> void:
	var container := SubViewportContainer.new()
	container.name = "PreviewContainer"
	container.stretch = true
	container.anchor_left = 0.0
	container.anchor_top = 0.0
	container.anchor_right = 1.0
	container.anchor_bottom = 0.0
	container.offset_bottom = 540.0
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(_on_preview_input)
	add_child(container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "PreviewViewport"
	_sub_viewport.size = Vector2i(720, 540)
	_sub_viewport.own_world_3d = true
	_sub_viewport.transparent_bg = false
	_sub_viewport.handle_input_locally = false
	container.add_child(_sub_viewport)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("20293a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfe0f5")
	environment.ambient_light_energy = 1.0
	world_environment.environment = environment
	_sub_viewport.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	_sub_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.light_color = Color("9fc4ff")
	_sub_viewport.add_child(fill_light)

	# 圆形展台
	var podium := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.95
	cylinder.bottom_radius = 0.85
	cylinder.height = 0.12
	cylinder.radial_segments = 40
	podium.mesh = cylinder
	var podium_material := StandardMaterial3D.new()
	podium_material.albedo_color = Color("2f3c52")
	podium_material.roughness = 0.85
	podium.material_override = podium_material
	podium.position = Vector3(0.0, -0.06, 0.0)
	_sub_viewport.add_child(podium)

	_character_holder = Node3D.new()
	_character_holder.name = "CharacterHolder"
	_sub_viewport.add_child(_character_holder)

	_model = CHARACTER.instantiate() as Node3D
	_model.name = "PreviewCharacter"
	_character_holder.add_child(_model)
	var bounds := _model_bounds(_model)
	if bounds.size.y > 0.01:
		_model.scale = Vector3.ONE * (TARGET_HEIGHT / bounds.size.y)
	_model.position.y = -bounds.position.y * _model.scale.y

	_play_idle_animation(_model)

	_manager = OutfitManager.new()
	_manager.name = "OutfitManager"
	_model.add_child(_manager)
	_manager.setup(_model)
	OutfitSaveManager.load_into(_manager)

	_editor = CharacterColorEditor.new()
	_editor.name = "ColorEditor"
	add_child(_editor)
	_editor.setup(_manager)
	_editor.selection_changed.connect(_on_selection_changed)
	_editor.color_applied.connect(_on_color_applied)

	_camera = Camera3D.new()
	_camera.fov = 34.0
	_sub_viewport.add_child(_camera)
	_camera.current = true
	_update_camera()


func _update_camera() -> void:
	var target := Vector3(0.0, 0.95, 0.0)
	_camera.position = target + Vector3(0.0, 0.35, _camera_distance)
	_camera.look_at(target, Vector3.UP)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clampf(_camera_distance - 0.25, 1.8, 6.0)
			_update_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clampf(_camera_distance + 0.25, 1.8, 6.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_character_holder.rotation.y -= (event as InputEventMouseMotion).relative.x * 0.012
	elif event is InputEventScreenDrag:
		_character_holder.rotation.y -= (event as InputEventScreenDrag).relative.x * 0.012


# =============================================================================
# 布局
# =============================================================================

func _build_layout() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.06, 0.09, 1.0)
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_top = 540.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# 预览提示
	var hint := _make_label("拖动旋转 · 滚轮缩放", 18, Color("8fa6c4"))
	hint.position = Vector2(MARGIN, 496.0)
	add_child(hint)

	# --- 分类 ---
	var category_row := HBoxContainer.new()
	category_row.position = Vector2(MARGIN, 552.0)
	category_row.size = Vector2(720.0 - MARGIN * 2.0, 60.0)
	category_row.add_theme_constant_override("separation", 8)
	add_child(category_row)

	for category_id in OutfitCatalog.category_ids():
		var button := _make_button(OutfitCatalog.category_label(category_id), 22)
		button.custom_minimum_size = Vector2(0, 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_category.bind(String(category_id)))
		category_row.add_child(button)
		_category_buttons[String(category_id)] = button

	# --- 服装列表 ---
	var scroll := ScrollContainer.new()
	var scroll_position := Vector2(MARGIN, 626.0)
	scroll.position = scroll_position
	scroll.size = Vector2(720.0 - MARGIN * 2.0, 150.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 12)
	_item_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_row)

	# --- 颜色 ---
	var color_panel := PanelContainer.new()
	color_panel.position = Vector2(MARGIN, 790.0)
	color_panel.size = Vector2(720.0 - MARGIN * 2.0, 160.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.12, 0.17, 1.0)
	panel_style.set_corner_radius_all(18)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.24, 0.33, 0.46, 1.0)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	color_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(color_panel)

	var color_column := VBoxContainer.new()
	color_column.add_theme_constant_override("separation", 8)
	color_panel.add_child(color_column)

	_selected_label = _make_label("未选中", 20, Color("dbe4f0"))
	color_column.add_child(_selected_label)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	color_column.add_child(color_row)

	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(190, 62)
	_color_picker.color_changed.connect(_on_picker_changed)
	color_row.add_child(_color_picker)

	var reset_color := _make_button("恢复默认颜色", 20)
	reset_color.custom_minimum_size = Vector2(0, 62)
	reset_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_color.pressed.connect(_on_reset_color)
	color_row.add_child(reset_color)

	_surface_button = _make_button("表面 1/1", 18)
	_surface_button.custom_minimum_size = Vector2(120, 62)
	_surface_button.pressed.connect(_on_next_surface)
	color_row.add_child(_surface_button)

	# --- 底部 ---
	var bottom_row := HBoxContainer.new()
	bottom_row.position = Vector2(MARGIN, 1180.0)
	bottom_row.size = Vector2(720.0 - MARGIN * 2.0, 78.0)
	bottom_row.add_theme_constant_override("separation", 12)
	add_child(bottom_row)

	var save_button := _make_button("保存穿搭", 22)
	save_button.custom_minimum_size = Vector2(0, 74)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_save)
	bottom_row.add_child(save_button)

	var default_button := _make_button("恢复默认穿搭", 22)
	default_button.custom_minimum_size = Vector2(0, 74)
	default_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_button.pressed.connect(_on_reset_outfit)
	bottom_row.add_child(default_button)

	var close_button := _make_button("退出", 22)
	close_button.custom_minimum_size = Vector2(150, 74)
	close_button.pressed.connect(_on_close)
	bottom_row.add_child(close_button)

	_status_label = _make_label("", 18, Color("9fb3cd"))
	_status_label.position = Vector2(MARGIN, 1130.0)
	add_child(_status_label)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color("e8eef7"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.17, 0.24, 1.0)
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.26, 0.35, 0.48, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.24, 0.33, 1.0)
	hover.border_color = Color(0.42, 0.56, 0.78, 1.0)
	button.add_theme_stylebox_override("hover", hover)
	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.10, 0.14, 0.20, 1.0)
	button.add_theme_stylebox_override("pressed", pressed_style)
	return button


# =============================================================================
# 交互
# =============================================================================

func _select_category(category: String) -> void:
	_current_category = category
	for id in _category_buttons:
		var button: Button = _category_buttons[id]
		var active := String(id) == category
		var style := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.bg_color = Color(0.20, 0.34, 0.55, 1.0) if active else Color(0.13, 0.17, 0.24, 1.0)
		style.border_color = Color(0.45, 0.66, 0.95, 1.0) if active else Color(0.26, 0.35, 0.48, 1.0)
		button.add_theme_stylebox_override("normal", style)
	_refresh_items()


func _refresh_items() -> void:
	for child in _item_row.get_children():
		child.queue_free()
	_item_buttons.clear()

	var list: Array = _manager.items(_current_category)
	if list.is_empty():
		var empty := _make_label("该分类暂无服装", 20, Color("8fa6c4"))
		_item_row.add_child(empty)
		_clear_selection_ui()
		return

	var equipped := _manager.equipped_id(_current_category)
	for item in list:
		var entry := item as OutfitItem
		var button := _make_button(entry.display_name, 19)
		button.custom_minimum_size = Vector2(210, 118)
		button.pressed.connect(_select_item.bind(entry.id))
		if entry.id == equipped:
			var style := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
			style.border_color = Color("ffd84b")
			style.set_border_width_all(4)
			button.add_theme_stylebox_override("normal", style)
		_item_row.add_child(button)
		_item_buttons.append(button)

		# 色块缩略图
		var swatch := ColorRect.new()
		swatch.color = _manager.item_color(_current_category, entry.id, 0)
		swatch.custom_minimum_size = Vector2(210, 18)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.position = Vector2(0, 96)
		button.add_child(swatch)

	# 正在穿的那件设为当前选中（注意：这里不能回头再调 _refresh_items，会递归）
	if equipped == "":
		_clear_selection_ui()
	else:
		_editor.select(_current_category, equipped, 0)


func _select_item(item_id: String) -> void:
	# 点一下 = 穿上它（同分类只能有一件）
	_manager.equip(_current_category, item_id)
	_editor.select(_current_category, item_id, 0)
	_status_label.text = "已穿上：%s" % _manager.item_by_id(_current_category, item_id).display_name
	_refresh_items()


func _on_selection_changed(category: String, item_id: String, surface: int) -> void:
	if item_id == "":
		_clear_selection_ui()
		return
	var item := _manager.item_by_id(category, item_id)
	if item == null:
		return
	_selected_label.text = "%s · %s" % [OutfitCatalog.category_label(category), item.display_name]
	_color_picker.color = _editor.current_color()
	_color_picker.disabled = not item.color_editable
	_surface_button.text = "表面 %d/%d" % [surface + 1, _editor.surface_count()]
	_surface_button.disabled = _editor.surface_count() <= 1


func _clear_selection_ui() -> void:
	_selected_label.text = "未选中（先选一件服装）"
	_color_picker.disabled = true
	_surface_button.disabled = true
	_surface_button.text = "表面 -/-"


func _on_picker_changed(color: Color) -> void:
	_editor.apply_color(color)
	_refresh_swatches()


func _on_reset_color() -> void:
	_editor.reset_color()
	_color_picker.color = _editor.current_color()
	_refresh_swatches()


func _on_next_surface() -> void:
	if not _editor.has_selection():
		return
	var next := (_editor.selected_surface() + 1) % _editor.surface_count()
	_editor.select(_editor.selected_category(), _editor.selected_item_id(), next)


func _on_save() -> void:
	if OutfitSaveManager.save(_manager):
		_status_label.text = "已保存到 %s" % OutfitSaveManager.save_path()
	else:
		_status_label.text = "保存失败"


func _on_reset_outfit() -> void:
	_manager.reset_outfit()
	_color_picker.color = Color.WHITE
	_refresh_items()
	_status_label.text = "已恢复默认穿搭"


func _on_close() -> void:
	closed.emit()
	hide()


func _refresh_swatches() -> void:
	var index := 0
	var list: Array = _manager.items(_current_category)
	for child in _item_row.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		for sub in button.get_children():
			if sub is ColorRect and index < list.size():
				(sub as ColorRect).color = _manager.item_color(_current_category, (list[index] as OutfitItem).id, 0)
		index += 1


func _on_color_applied(_category: String, _item_id: String, _surface: int, _color: Color) -> void:
	_refresh_swatches()


func _process(delta: float) -> void:
	# 轻微自动摆动，让角色看起来是"活着"的（只在没有拖动时）
	if not _dragging:
		_auto_rotate += delta * 0.35
		_character_holder.rotation.y = sin(_auto_rotate) * 0.28



## 预览里摆个站姿，别让角色僵在 T-pose。
func _play_idle_animation(model: Node3D) -> void:
	var skeleton := _find_skeleton(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null:
		return
	var base: Node = player.get_node_or_null(player.root_node)
	if base == null:
		base = player.get_parent()
	var prefix := String(base.get_path_to(skeleton))
	var clip := AnimLibrary.load_clip("idle_huddle", skeleton, prefix)
	if clip == null:
		return
	var library := AnimationLibrary.new()
	library.add_animation("idle_huddle", clip)
	if player.has_animation_library("ff"):
		player.remove_animation_library("ff")
	player.add_animation_library("ff", library)
	player.play("ff/idle_huddle")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null
func _model_bounds(root_node: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
