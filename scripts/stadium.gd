extends Node3D
class_name Stadium
## FF · 球场 / 看台 / 围栏 / 角旗 —— FFSIMU 原版几何的程序化复刻
##
## 本文件逐行对照移植自：
##   flag-football-mvp/godot/prototype_vertical_slice.gd
##     _build_world()                  -> 移到 main.gd（灯光/环境属于游戏层）
##     _build_field()                  -> _build_field()
##     _build_stands_and_spectators()  -> _build_stand_frames() + _build_spectators()
##     _build_standing_fans()          -> _build_standing_fans()
##     _build_pylons()                 -> _build_pylons()  (+ kick_nearby)
##     _material / _texture_material / _mesh_box -> 同名保留
##
## 约定：
##   * 这里只放"固态"场景物：地面、草皮、标线、端区、围栏、广告、看台、角旗。
##   * 球员、球、镜头、UI、规则一律放在游戏层，不要写进本文件。
##   * 单位与 FFSIMU 一致：1 单位 ≈ 1 米，球员 ≈ 1.82 高，场地 26.7 × 50。
##   * 所有尺寸/坐标都与原工程完全相同，改动前请先对照上面的源函数。

# --- 场地尺寸：与 FFSIMU prototype_vertical_slice.gd 第 7-10 行一致 -------------
const FIELD_WIDTH := 26.7
const FIELD_LENGTH := 50.0
const FIELD_Z_MIN := -10.0
const FIELD_Z_MAX := 60.0
const MIDFIELD_Z := FIELD_LENGTH * 0.5

@export_group("场地")
## 启球线位置（z）。原版 INITIAL_LOS = 5.0。
@export var line_of_scrimmage := 5.0
## 是否生成蓝色启球线（比赛层如果要自己画，可关掉）。
@export var show_line_of_scrimmage := true

@export_group("角旗")
@export var pylons_enabled := true
## 关闭后角旗只会被撞倒一次；开启后带冷却，可反复撞倒（原版行为）。
@export var pylons_physical := true

@export_group("观众")
@export var crowd_enabled := true
## 每侧坐多少人（原版固定 8 人/侧，共 16 人）。
@export var crowd_seats_per_side := 8
## 留空 => 使用本文件内置的低模观众（全新模型）。
## 想换成 FFSIMU 的 fan1..fan7：把 assets/models/new_cast/fan*.tscn 拷进来后拖到这个数组。
@export var crowd_scenes: Array[PackedScene] = []
@export var crowd_randomize := true
@export var crowd_seed := 20261106

@export_group("站席球迷")
@export var standing_fans_enabled := true

# --- 运行时状态 ---------------------------------------------------------------
var los_line: MeshInstance3D
## 场地上的文字（END ZONE / 码线数字），攻防转换时整体镜像
var _text_labels: Array[Label3D] = []
## 码线数字的成对节点（翻转时两位数字要互换位置）
var _digit_pairs: Array = []
var _current_digits: Array = []
var pylons: Array[Dictionary] = []
var _seated_crowd: Array[Node3D] = []
var _standing_crowd: Array[Node3D] = []

const _SHIRT_COLORS: Array[Color] = [
	Color("d94a4a"), Color("2f6fd0"), Color("e8e3d6"), Color("2b2f36"),
	Color("3fa66b"), Color("d89b2c"), Color("7a5cc4"), Color("b9c2cc"),
]

# --- 场地配色：原版几何不变，只改材质 ---
## 球场外围的深绿草地（明显比场内暗）。
const OUTER_GRASS_COLOR := Color("0c2f1e")
## 看台正下方保留的棕色泥地。
const STAND_DIRT_COLOR := Color("2a211d")
## 场内草皮底色（条带会盖在上面）。
const FIELD_GRASS_LIGHT := Color("1e7346")
## 每 5 码交替的两种绿。
const BAND_GREEN_A := Color("1f7749")
const BAND_GREEN_B := Color("16552f")


func _ready() -> void:
	if crowd_randomize:
		seed(crowd_seed)
	_build_field()
	_build_stand_frames()
	if crowd_enabled:
		_build_spectators()
	if standing_fans_enabled:
		_build_standing_fans()
	if pylons_enabled:
		_build_pylons()


# =============================================================================
# 材质 / 小工具（与 FFSIMU 完全相同）
# =============================================================================

func _material(color: Color, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission != Color.TRANSPARENT:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 0.7
	return material



## 草地材质：在纯色上叠一层噪点，模拟草皮颗粒
func _grass_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.42
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.80, 0.80, 0.80), Color(1.14, 1.14, 1.14)])
	texture.color_ramp = ramp
	material.albedo_texture = texture
	material.uv1_scale = Vector3(7.0, 7.0, 1.0)
	material.roughness = 0.95
	return material

func _texture_material(path: String, fallback: Color, uv_scale := Vector3.ONE, transparent := false, unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = fallback
	material.roughness = 0.92
	var texture := load(path) as Texture2D
	if texture != null:
		material.albedo_texture = texture
		material.albedo_color = Color.WHITE
		material.uv1_scale = uv_scale
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _mesh_box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = position
	add_child(node)
	return node


func _mesh_plane(size: Vector2, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	node.mesh = plane
	node.material_override = material
	node.position = position
	add_child(node)
	return node


# =============================================================================
# 球场：土地、草皮、码线、端区、边线、启球线、黄色虚线、围栏、广告、碰撞地面
# 对照 FFSIMU _build_field()（第 441-604 行）
# =============================================================================

## 攻防转换：场地文字整体镜像，抵消相机 180° 造成的左右翻转
func set_flipped(value: bool) -> void:
	for label in _text_labels:
		if label != null and is_instance_valid(label):
			# 相机绕视线滚 180° 是双轴翻转，文字也要双轴镜像才正
			label.scale = Vector3(-1.0, -1.0, 1.0) if value else Vector3.ONE
	# 两位数字在翻转后顺序会反过来（"10" 看成 "01"），所以互换它们的位置
	for pair in _digit_pairs:
		var digits: Array = pair
		if digits.size() >= 4:
			var a: Label3D = digits[0]
			var b: Label3D = digits[1]
			a.position = digits[3] if value else digits[2]
			b.position = digits[2] if value else digits[3]
			# 双保险：文字也跟着换
			if digits.size() >= 6:
				a.text = String(digits[5]) if value else String(digits[4])
				b.text = String(digits[4]) if value else String(digits[5])


func _build_field() -> void:
	# 外围改为深绿色草地（明显暗于场内草皮）；看台正下方仍保留棕色泥地。
	var outer_grass := _material(OUTER_GRASS_COLOR)
	_mesh_box(Vector3(FIELD_WIDTH + 62.0, 0.06, FIELD_LENGTH + 54.0), Vector3(0, -0.07, FIELD_LENGTH * 0.5), outer_grass)
	_build_stand_dirt()

	# 场内草皮：纯色打底。原版贴图自带密集的深浅条纹，铺满后会比 5 码一条密得多，
	# 所以这里不再使用 grass_turf.png，让场内唯一的深浅变化只来自下面的 5 码条带。
	var grass := _material(FIELD_GRASS_LIGHT)
	_mesh_box(Vector3(FIELD_WIDTH, 0.10, FIELD_LENGTH + 20.0), Vector3(0, -0.06, FIELD_LENGTH * 0.5), grass)

	# 比赛区每 5 码交替两种绿。这是场内唯一的大面积深浅变化：
	# 原版贴图自带的密集条纹已经去掉，所以不会再出现比 5 码更细的纹理。
	var band_colors: Array[Color] = [BAND_GREEN_A, BAND_GREEN_B]
	for i in range(10):
		var band_material := _grass_material(band_colors[i % 2])
		_mesh_box(Vector3(FIELD_WIDTH, 0.012, 5.0), Vector3(0, 0.0, 2.5 + i * 5.0), band_material)

	var white := _material(Color("f7f7ef"))
	for z in range(0, 51, 5):
		_mesh_box(Vector3(FIELD_WIDTH, 0.008, 0.13), Vector3(0, 0.016, z), white)

	# 达阵区沿用同一套草皮纹理，只把色相调成蓝色，并叠加半透明 END ZONE 水印。
	var endzone_grass := _texture_material("res://assets/textures/endzone_grass.png", Color("2b4fc7"), Vector3(7, 2.6, 1))
	for endzone_z in [-5.0, 55.0]:
		var endzone := MeshInstance3D.new()
		var endzone_plane := PlaneMesh.new()
		endzone_plane.size = Vector2(FIELD_WIDTH, 10.0)
		endzone.mesh = endzone_plane
		endzone.material_override = endzone_grass
		endzone.position = Vector3(0, 0.012, endzone_z)
		add_child(endzone)
		var watermark := Label3D.new()
		_text_labels.append(watermark)
		watermark.text = "END ZONE"
		watermark.font_size = 104
		watermark.pixel_size = 0.018
		watermark.modulate = Color(0.82, 0.93, 1.0, 0.28)
		watermark.shaded = false
		watermark.outline_size = 0
		watermark.outline_modulate = Color(0, 0, 0, 0)
		watermark.double_sided = true
		watermark.position = Vector3(0, 0.034, endzone_z)
		# 顶视镜头下屏幕右方对应世界 -X；这样水印是正向可读的。
		watermark.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
		add_child(watermark)

	# 两侧大号码数：旋转 90°，10 码线两侧分别放 1 和 0。
	for side in [-1.0, 1.0]:
		for yard_mark in [{"z": 10.0, "text": "10"}, {"z": 20.0, "text": "20"}, {"z": 30.0, "text": "20"}, {"z": 40.0, "text": "10"}]:
			var digits := str(yard_mark["text"])
			for digit_index in digits.length():
				var number := Label3D.new()
				_text_labels.append(number)
				number.text = digits[digit_index]
				number.font_size = 118
				number.pixel_size = 0.012
				number.modulate = Color(1, 1, 1, 0.86)
				number.outline_size = 0
				number.outline_modulate = Color(0, 0, 0, 0)
				var z_offset := -0.9 if digit_index == 0 else 0.9
				var digit_slot := _current_digits
				number.position = Vector3(side * 12.5, 0.032, yard_mark["z"] + z_offset)
				number.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)).rotated(Vector3.UP, PI * 0.5)
				add_child(number)
				_current_digits.append(number)
				if _current_digits.size() == 2:
					_digit_pairs.append([
						_current_digits[0], _current_digits[1],
						(_current_digits[0] as Label3D).position, (_current_digits[1] as Label3D).position,
						(_current_digits[0] as Label3D).text, (_current_digits[1] as Label3D).text])
					for d in _current_digits:
						_text_labels.append(d)

	# 白线框住整个草皮，低到和草面同一平面。
	_mesh_box(Vector3(0.16, 0.008, 70.0), Vector3(-FIELD_WIDTH * 0.5, 0.018, 25.0), white)
	_mesh_box(Vector3(0.16, 0.008, 70.0), Vector3(FIELD_WIDTH * 0.5, 0.018, 25.0), white)
	_mesh_box(Vector3(FIELD_WIDTH, 0.008, 0.16), Vector3(0, 0.018, FIELD_Z_MIN), white)
	_mesh_box(Vector3(FIELD_WIDTH, 0.008, 0.16), Vector3(0, 0.018, FIELD_Z_MAX), white)

	# 半透明蓝色启球线。
	var los_material := StandardMaterial3D.new()
	los_material.albedo_color = Color(0.22, 0.55, 1.0, 0.48)
	los_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	los_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	los_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	los_line = MeshInstance3D.new()
	var los_mesh := BoxMesh.new()
	los_mesh.size = Vector3(FIELD_WIDTH, 0.008, 0.16)
	los_line.mesh = los_mesh
	los_line.material_override = los_material
	los_line.position = Vector3(0, 0.030, line_of_scrimmage)
	los_line.visible = show_line_of_scrimmage
	add_child(los_line)

	# 黄色虚线外圈：在白色边线外，玩家跑不过去。
	var yellow := _material(Color("ffd84b"), Color("ffd84b"))
	var dash_x := FIELD_WIDTH * 0.5 + 3.1
	for side in [-1.0, 1.0]:
		for z in range(-12, 63, 3):
			_mesh_box(Vector3(0.14, 0.012, 1.55), Vector3(side * dash_x, 0.022, z), yellow)
	for x in range(-16, 17, 3):
		_mesh_box(Vector3(1.55, 0.012, 0.14), Vector3(x, 0.022, -12.0), yellow)
		_mesh_box(Vector3(1.55, 0.012, 0.14), Vector3(x, 0.022, 62.0), yellow)

	# 围栏、栏杆和广告海报。
	var fence_x := 24.0
	var metal := _material(Color("232b32"))
	var chain := _texture_material("res://assets/textures/chainlink.png", Color(0.5, 0.55, 0.6, 0.4), Vector3(16, 1, 1), true)
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(78.0, 2.9)
		panel.mesh = quad
		panel.material_override = chain
		panel.position = Vector3(side * fence_x, 1.45, 25.0)
		panel.rotation.y = PI * 0.5
		add_child(panel)
		for z in range(-14, 65, 5):
			_mesh_box(Vector3(0.18, 3.0, 0.18), Vector3(side * fence_x, 1.5, z), metal)
		_mesh_box(Vector3(0.12, 0.12, 78.0), Vector3(side * fence_x, 0.32, 25.0), metal)
		_mesh_box(Vector3(0.12, 0.12, 78.0), Vector3(side * fence_x, 2.75, 25.0), metal)
	for z in [-14.0, 64.0]:
		var end_panel := MeshInstance3D.new()
		var end_quad := QuadMesh.new()
		end_quad.size = Vector2(fence_x * 2.0, 2.9)
		end_panel.mesh = end_quad
		end_panel.material_override = chain
		end_panel.position = Vector3(0, 1.45, z)
		add_child(end_panel)
		for x in range(-24, 25, 5):
			_mesh_box(Vector3(0.18, 3.0, 0.18), Vector3(x, 1.5, z), metal)

	var poster_paths := [
		"res://assets/textures/ad_flagbowl.png",
		"res://assets/textures/ad_ffsimu.png",
		"res://assets/textures/ad_playhard.png",
	]
	for side in [-1.0, 1.0]:
		for i in range(4):
			var z := 3.0 + i * 13.0
			var ad := MeshInstance3D.new()
			var ad_quad := QuadMesh.new()
			ad_quad.size = Vector2(4.8, 1.35)
			ad.mesh = ad_quad
			ad.material_override = _texture_material(poster_paths[i % poster_paths.size()], Color("263a55"), Vector3.ONE, false, true)
			ad.position = Vector3(side * (fence_x - 0.18), 1.45, z)
			ad.rotation.y = -side * PI * 0.5
			add_child(ad)

	# 远端 “FLAG BOWL” 横幅。
	var banner := MeshInstance3D.new()
	var banner_quad := QuadMesh.new()
	banner_quad.size = Vector2(13.0, 3.0)
	banner.mesh = banner_quad
	banner.material_override = _texture_material("res://assets/textures/ad_flagbowl.png", Color("171c37"), Vector3.ONE, false, true)
	banner.position = Vector3(0, 2.2, 63.2)
	banner.rotation.y = PI
	add_child(banner)

	# 所有失手、被碰掉的球都交给物理引擎在这块碰撞地面上反弹。
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(FIELD_WIDTH + 8.0, 0.16, FIELD_LENGTH + 24.0)
	ground_shape.shape = ground_box
	ground.position = Vector3(0, -0.08, FIELD_LENGTH * 0.5)
	ground.add_child(ground_shape)
	add_child(ground)


# =============================================================================
# 看台正下方的棕色泥地
# =============================================================================

## 外围已经换成深绿草地，但看台脚下保留 FFSIMU 原版的棕色土地。
## 尺寸按看台footprint 取（x 16.3–21.9，z 13.5–36.5，两端各留一点余量）。
func _build_stand_dirt() -> void:
	var dirt := _material(STAND_DIRT_COLOR)
	for side in [-1.0, 1.0]:
		_mesh_box(Vector3(5.6, 0.012, 23.0), Vector3(side * 19.1, -0.03, 25.0), dirt)


# =============================================================================
# 看台：三级台阶 + 踏板 + 支柱（几何与 FFSIMU 完全相同）
# 对照 _build_stands_and_spectators() 第 699-717 行
# =============================================================================

func _build_stand_frames() -> void:
	var steel := _material(Color("39434b"))
	var plank := _material(Color("9aa4ac"))
	# 看台以中场 25 码为对称中心，左右各 10 码。
	for side in [-1.0, 1.0]:
		for tier in 3:
			var x: float = side * (17.7 + tier * 1.55)
			var seat_y: float = 0.43 + tier * 0.58
			_mesh_box(Vector3(0.62, 0.08, 20.0), Vector3(x, seat_y, 25.0), plank)
			_mesh_box(Vector3(0.10, 0.10, 20.0), Vector3(x, seat_y - 0.18, 25.0), steel)
			# 落脚钢板稍微下沉，让鞋面露出，不再穿进踏板。
			_mesh_box(Vector3(0.48, 0.06, 20.0), Vector3(x - side * 0.55, seat_y - 0.52, 25.0), plank)
			for z in range(15, 36, 5):
				_mesh_box(Vector3(0.10, seat_y, 0.10), Vector3(x - 0.28, seat_y * 0.5, z), steel)
				_mesh_box(Vector3(0.10, seat_y - 0.2, 0.10), Vector3(x + 0.28, (seat_y - 0.2) * 0.5, z), steel)
			for step in 4:
				var sy: float = 0.18 + step * (seat_y / 4.0)
				_mesh_box(Vector3(0.10, 0.08, 20.0), Vector3(x, sy, 25.0), steel)


# =============================================================================
# 观众：站位沿用原版座位分布（每侧 3 级 × 10 个 z 槽，洗牌后取 8 个）
# 模型换成 FF 自己的低模观众；也可通过 crowd_scenes 换回 FFSIMU 的 fan*.tscn
# =============================================================================

func _seat_slots() -> Array:
	var all_slots: Array = []
	for side in [-1.0, 1.0]:
		var side_slots: Array = []
		for tier in 3:
			var x: float = side * (17.7 + tier * 1.55)
			var seat_y: float = 0.43 + tier * 0.58
			for z in range(16, 35, 2):
				side_slots.append({
					"x": x,
					"y": seat_y - 0.48,
					"z": float(z),
					"yaw": PI * 0.5 if side < 0.0 else -PI * 0.5,
				})
		side_slots.shuffle()
		for i in mini(crowd_seats_per_side, side_slots.size()):
			all_slots.append(side_slots[i])
	all_slots.shuffle()
	return all_slots


func _build_spectators() -> void:
	for slot in _seat_slots():
		var root := Node3D.new()
		root.position = Vector3(float(slot["x"]), float(slot["y"]), float(slot["z"]))
		root.rotation.y = float(slot["yaw"])
		root.name = "SeatedFan"
		add_child(root)
		root.add_child(_make_audience_member(false))
		_seated_crowd.append(root)


func _build_standing_fans() -> void:
	# 四个站席球迷：黄色虚线外、靠近镜头一侧。
	var spots := [
		Vector3(-FIELD_WIDTH * 0.5 - 2.7, 0, 4.0),
		Vector3(FIELD_WIDTH * 0.5 + 2.7, 0, 7.5),
		Vector3(-FIELD_WIDTH * 0.5 - 2.9, 0, 17.0),
		Vector3(FIELD_WIDTH * 0.5 + 2.9, 0, 21.0),
	]
	for i in spots.size():
		var spot: Vector3 = spots[i]
		spot.z += randf_range(-1.2, 1.2)
		var root := Node3D.new()
		root.position = spot
		root.rotation.y = PI * 0.5 if spot.x < 0.0 else -PI * 0.5
		root.name = "StandingFan"
		add_child(root)
		root.add_child(_make_audience_member(true))
		_standing_crowd.append(root)


## 若填了 crowd_scenes，优先用外部模型；否则用下面的程序化低模观众。
func _make_audience_member(standing: bool) -> Node3D:
	if not crowd_scenes.is_empty():
		var scene: PackedScene = crowd_scenes[randi() % crowd_scenes.size()]
		var instance: Node = scene.instantiate()
		if instance.has_method("play_state"):
			instance.call("play_state", "Standing" if standing else "Sitting1")
			instance.call_deferred("play_state", "Standing" if standing else "Sitting1")
		return instance as Node3D
	var shirt: Color = _SHIRT_COLORS[randi() % _SHIRT_COLORS.size()]
	return _make_procedural_fan(shirt, standing)


## FF 全新低模观众：胶囊躯干 + 球头 + 坐姿/站姿双腿。
## 坐姿时髋部约在本地 y=0.58（与 FFSIMU 看台座面高度对齐）。
func _make_procedural_fan(shirt: Color, standing: bool) -> Node3D:
	var root := Node3D.new()
	var skin := _material(Color("c68d61"))
	var pants := _material(Color("2a2f36"))
	var shirt_mat := _material(shirt)

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.19
	torso_mesh.height = 0.56 if not standing else 0.62
	torso.mesh = torso_mesh
	torso.material_override = shirt_mat
	torso.position = Vector3(0, 0.80, 0)
	root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.105
	head_mesh.height = 0.21
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0, 1.17 if not standing else 1.33, 0.02)
	root.add_child(head)

	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.078
		leg_mesh.height = 0.52
		leg.mesh = leg_mesh
		leg.material_override = pants
		if standing:
			leg.position = Vector3(side * 0.105, 0.26, 0)
		else:
			# 坐姿：小腿向前伸，脚跟落在踏板上。
			leg.position = Vector3(side * 0.105, 0.30, 0.20)
			leg.rotation.x = -1.15
		root.add_child(leg)

		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.062
		arm_mesh.height = 0.46
		arm.mesh = arm_mesh
		arm.material_override = shirt_mat
		arm.position = Vector3(side * 0.245, 0.90 if not standing else 1.02, 0)
		arm.rotation.z = -side * 0.16
		root.add_child(arm)

	# 站席球迷再补一双鞋，避免脚浮在草上。
	if standing:
		for side in [-1.0, 1.0]:
			var shoe := MeshInstance3D.new()
			var shoe_mesh := BoxMesh.new()
			shoe_mesh.size = Vector3(0.13, 0.07, 0.25)
			shoe.mesh = shoe_mesh
			shoe.material_override = _material(Color("15181c"))
			shoe.position = Vector3(side * 0.105, 0.035, 0.04)
			root.add_child(shoe)

	return root


# =============================================================================
# 角旗：红/黄两色，可被撞倒；物理参数与 FFSIMU 一致
# =============================================================================

func _build_pylons() -> void:
	var red := _material(Color("d83232"))
	var yellow := _material(Color("ffd84b"))
	var x_edge := FIELD_WIDTH * 0.5
	var red_spots := [
		Vector3(-x_edge, 0.28, FIELD_Z_MIN), Vector3(x_edge, 0.28, FIELD_Z_MIN),
		Vector3(-x_edge, 0.28, 0.0), Vector3(x_edge, 0.28, 0.0),
		Vector3(-x_edge, 0.28, FIELD_LENGTH), Vector3(x_edge, 0.28, FIELD_LENGTH),
		Vector3(-x_edge, 0.28, FIELD_Z_MAX), Vector3(x_edge, 0.28, FIELD_Z_MAX),
	]
	for spot in red_spots:
		_create_pylon(spot, red)
	_create_pylon(Vector3(-x_edge, 0.28, MIDFIELD_Z), yellow)
	_create_pylon(Vector3(x_edge, 0.28, MIDFIELD_Z), yellow)


func _create_pylon(position: Vector3, material: Material) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.7
	body.gravity_scale = 1.0
	body.linear_damp = 0.45
	body.angular_damp = 0.5
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.position = position
	add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.55, 0.18)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 0.55, 0.18)
	collision.shape = shape
	body.add_child(collision)
	pylons.append({
		"body": body,
		"home": position,
		"home_rotation": body.rotation,
		"ready_at": 0,
	})


## 游戏层每帧传一次"有人跑到这里"，角旗就会被撞飞。
## 直接复用原版 _advance_pylons() 的冲量与冷却参数。
func kick_nearby(world_position: Vector3, radius := 1.35) -> void:
	if not pylons_physical:
		return
	var now := Time.get_ticks_msec()
	for pylon in pylons:
		if now < int(pylon["ready_at"]):
			continue
		var body := pylon["body"] as RigidBody3D
		if body == null:
			continue
		var to_pylon := body.global_position - world_position
		to_pylon.y = 0.0
		if to_pylon.length() < radius:
			body.freeze = false
			body.sleeping = false
			var direction := to_pylon.normalized() if to_pylon.length() > 0.01 else Vector3(0, 0, 1)
			body.apply_central_impulse(Vector3(direction.x, 0.35, direction.z) * 2.2)
			body.apply_torque_impulse(Vector3(direction.z, 0.0, -direction.x) * 0.45)
			pylon["ready_at"] = now + 450


func reset_pylons() -> void:
	for pylon in pylons:
		var body := pylon["body"] as RigidBody3D
		if body == null:
			continue
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_position = pylon["home"]
		body.rotation = pylon["home_rotation"]
		body.sleeping = true
		pylon["ready_at"] = 0


# =============================================================================
# 对外接口
# =============================================================================

## 移动蓝色启球线（新的进攻/防守回合可以直接调用）。
func set_line_of_scrimmage(z: float) -> void:
	line_of_scrimmage = z
	if los_line != null:
		los_line.position.z = z


## 场地中心，供镜头默认取景使用。
func field_center() -> Vector3:
	return Vector3(0, 0, MIDFIELD_Z)


func field_bounds() -> Dictionary:
	return {
		"half_width": FIELD_WIDTH * 0.5,
		"z_min": FIELD_Z_MIN,
		"z_max": FIELD_Z_MAX,
	}


## 给验证脚本 / 调试面板用的统计。
func scenery_stats() -> Dictionary:
	var meshes := 0
	var static_bodies := 0
	for child in get_children():
		if child is MeshInstance3D:
			meshes += 1
		elif child is StaticBody3D:
			static_bodies += 1
	return {
		"meshes": meshes,
		"static_bodies": static_bodies,
		"pylons": pylons.size(),
		"seated_crowd": _seated_crowd.size(),
		"standing_crowd": _standing_crowd.size(),
		"los_z": line_of_scrimmage,
	}
