extends CharacterBody3D
class_name PlayerActor
## FF · 球员（FFfemale.fbx 换掉原来的程序化模型）
##
## 节点结构：
##   PlayerActor (CharacterBody3D)        ← 位移与碰撞
##   ├── CollisionShape3D                 ← 胶囊碰撞
##   ├── Visual (Node3D)                  ← 整体前倾用
##   │   └── Character (Node3D)           ← 朝向 + 缩放
##   │       └── FFfemale (FFfemale.glb 实例)
##   │           ├── RootNode/HIFER/Skeleton3D（22 根 mixamorig_* 骨骼 + 9 个网格）
##   │           └── AnimationPlayer      ← 播放重定向后的 Fast Run
##   ├── Token (MeshInstance3D)           ← 队色圆盘（俯视识别用）
##   ├── SelectRing (MeshInstance3D)      ← 选中环
##   └── NameLabel (Label3D)              ← 名字
##
## 动画：
##   Fast Run 是从另一个 FBX 转出来的纯动画，静止姿势与角色不同，
##   所以通过 MixamoRetarget 做 delta 重定向，并且只保留旋转 → 髋部固定、原地跑。
##
## 对外接口（游戏层用）：
##   set_move_input(Vector3) / set_active(bool) / planar_speed()

signal became_active

const CHARACTER_SCENE := preload("res://assets/models/characters/FFfemale.glb")
## FFSIMU 里的站立动作（静止站立.fbx），重定向到本角色骨架上。
const IDLE_PATH := "res://assets/models/characters/Idle.glb"
## 角色归一化后的身高（米）。
const TARGET_HEIGHT := 1.82
## 模型本地朝向是 -X，旋转 90° 后正对游戏里的 +Z。
const MODEL_YAW := 0.0

@export_group("外观")
@export var jersey_color := Color("1f6fe0")
@export var skin_color := Color("c98f63")
@export var dark_color := Color("1b1f26")
@export var actor_name := "QB"
## true = 这件角色使用玩家保存的穿搭（自己队）；false = 用队伍色（对手）
@export var personal_outfit := false

@export_group("移动")
@export var max_speed := 6.4
@export var acceleration := 26.0
@export var turn_speed := 12.0
@export var gravity := 24.0

@export_group("动画")
## 静止时的播放速度倍率（Fast Run 是循环动作）。
@export var idle_rate := 0.65
@export var run_rate := 1.15
## 站立时手臂从 T-pose 放下来的角度（度）。
@export var arm_drop_degrees := 62.0

@export_group("场地边界")
@export var x_limit := 16.2
@export var z_min := -11.4
@export var z_max := 61.4

var is_active := false

var _move_input := Vector3.ZERO
var _visual: Node3D
var _character: Node3D
var _anim: AnimationPlayer
var _outfit: OutfitManager
var _ring: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	_build_collision()
	_build_visual()
	_refresh_active_visuals()


# =============================================================================
# 模型
# =============================================================================

func _build_collision() -> void:
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.70
	shape_node.shape = capsule
	shape_node.position = Vector3(0, 0.85, 0)
	add_child(shape_node)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# 朝向与缩放挂在 Character 上，_visual 只用来做整体微调。
	_character = Node3D.new()
	_character.name = "Character"
	_character.rotation.y = MODEL_YAW
	_visual.add_child(_character)

	var model := CHARACTER_SCENE.instantiate() as Node3D
	model.name = "FFfemale"
	_character.add_child(model)

	var bounds := _model_bounds(model)
	var scale_factor := TARGET_HEIGHT / maxf(0.001, bounds.size.y)
	model.scale = Vector3.ONE * scale_factor
	model.position.y = -bounds.position.y * scale_factor

	_apply_body_material(model)
	_start_animations(model)
	_setup_outfit(model)

	# 俯视用的队色圆盘：正上方视角下 3D 模型只剩头顶，靠这块圆盘分辨敌我。
	var token := MeshInstance3D.new()
	token.name = "Token"
	var token_mesh := CylinderMesh.new()
	token_mesh.top_radius = 0.52
	token_mesh.bottom_radius = 0.52
	token_mesh.height = 0.02
	token_mesh.radial_segments = 24
	token.mesh = token_mesh
	var token_material := StandardMaterial3D.new()
	token_material.albedo_color = Color(jersey_color, 0.55)
	token_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	token_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	token_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	token.material_override = token_material
	token.position = Vector3(0, 0.02, 0)
	add_child(token)

	# 选中环
	_ring = MeshInstance3D.new()
	_ring.name = "SelectRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.60
	ring_mesh.outer_radius = 0.72
	ring_mesh.rings = 28
	ring_mesh.ring_segments = 12
	_ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("ffd84b")
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.emission_enabled = true
	ring_material.emission = Color("ffd84b")
	ring_material.emission_energy_multiplier = 0.6
	_ring.material_override = ring_material
	_ring.position = Vector3(0, 0.035, 0)
	_ring.scale = Vector3(1.0, 0.3, 1.0)
	_ring.visible = false
	add_child(_ring)

	# 名字：只给当前持球/选中的人显示
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.text = actor_name
	_label.font_size = 64
	_label.pixel_size = 0.0042
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 10
	_label.modulate = Color(1, 0.92, 0.55, 1.0)
	_label.position = Vector3(0, 2.06, 0)
	_label.visible = false
	add_child(_label)


## FFfemale.fbx 没有贴图，身体单独上肤色；其余服装颜色交给 OutfitManager 管理。
func _apply_body_material(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or String(mesh_instance.name) != "Cube":
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = skin_color
		material.roughness = 0.78
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)


## 挂上服装管理器：自己人读存档，对手用队伍色覆盖。
func _setup_outfit(model: Node3D) -> void:
	_outfit = OutfitManager.new()
	_outfit.name = "OutfitManager"
	model.add_child(_outfit)
	if not _outfit.setup(model):
		return
	if personal_outfit:
		# 有存档就按存档穿，没有就默认穿搭
		OutfitSaveManager.load_into(_outfit)
	else:
		_outfit.reset_outfit()
		for category in ["shirt", "pants", "accessory"]:
			var item_id := _outfit.equipped_id(category)
			if item_id != "":
				_outfit.set_item_color(category, item_id, 0, jersey_color)


func outfit() -> OutfitManager:
	return _outfit


## 重新读取存档穿搭（衣柜关闭后调用）。
func refresh_outfit() -> void:
	if _outfit == null:
		return
	OutfitSaveManager.load_into(_outfit)


func _start_animations(model: Node3D) -> void:
	var skeleton := _find_skeleton(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null:
		push_warning("PlayerActor: 找不到骨架或 AnimationPlayer")
		return

	# 骨架相对 AnimationPlayer 根节点的路径，避免把导入层级写死。
	var base: Node = player.get_node_or_null(player.root_node)
	if base == null:
		base = player.get_parent()
	var prefix := String(base.get_path_to(skeleton))

	var library := AnimationLibrary.new()

	# 跑步：直接用模型自带的那段动画（用户烘进 FFfemale 的跑步姿势，姿态最准），
	# 只保留旋转 —— 髋部固定、原地跑。
	var run_source := _largest_animation(player)
	if run_source != null:
		library.add_animation("run", MixamoRetarget.strip_to_rotations(run_source))
	else:
		push_warning("PlayerActor: 模型里没有自带的跑步动画")

	# 站立：FFSIMU 的「静止站立」，从另一套 Mixamo 骨架重定向过来。
	# 站立：从动作库取（Huddle Posture01），库里没有就退回生成的姿态
	var idle_clip := AnimLibrary.load_clip("idle_huddle", skeleton, prefix)
	if idle_clip != null:
		library.add_animation("idle_huddle", idle_clip)
	else:
		library.add_animation("idle_huddle", _build_standing_idle(skeleton, prefix))

	if player.has_animation_library("ff"):
		player.remove_animation_library("ff")
	player.add_animation_library("ff", library)
	if library.has_animation("idle_huddle"):
		player.play("ff/idle_huddle")
	elif library.has_animation("run"):
		player.play("ff/run")
	_anim = player


## 取模型自带轨道最多的那段动画（忽略只有一两帧的空动画）。
func _largest_animation(player: AnimationPlayer) -> Animation:
	var best: Animation = null
	var best_tracks := 0
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			var animation := library.get_animation(animation_name)
			var rotations := 0
			for t in animation.get_track_count():
				if animation.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					rotations += 1
			if rotations > best_tracks:
				best_tracks = rotations
				best = animation
	return best



## 站立姿态：以角色自己的绑定姿势为基准，把手臂放下来 + 加一点呼吸起伏。
## （FFSIMU 那批动画的骨架轴系和本角色相差 90°~240°，直接重定向会把手臂翻到头上，
##   所以站立动作在这里用绑定姿势现生成，跑步仍用模型自带的动画。）
func _build_standing_idle(skeleton: Skeleton3D, prefix: String) -> Animation:
	const DURATION := 2.6
	const SAMPLES := 14
	var animation := Animation.new()
	animation.length = DURATION
	animation.step = 0.0
	animation.loop_mode = Animation.LOOP_LINEAR

	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		var rest := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(prefix + ":" + bone_name))
		for s in SAMPLES:
			var time := DURATION * float(s) / float(SAMPLES)
			var wave := sin(time / DURATION * TAU)
			var pose := rest
			match bone_name:
				"mixamorig_LeftArm":
					pose = rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(arm_drop_degrees))
				"mixamorig_RightArm":
					pose = rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(-arm_drop_degrees))
				"mixamorig_LeftForeArm":
					pose = rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(-8.0))
				"mixamorig_RightForeArm":
					pose = rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(-8.0))
				"mixamorig_Spine":
					pose = rest * Quaternion(Vector3(1, 0, 0), deg_to_rad(wave * 1.2))
				"mixamorig_Head":
					pose = rest * Quaternion(Vector3(0, 1, 0), deg_to_rad(wave * 2.5))
			animation.track_insert_key(track, time, pose)
	return animation

func _model_bounds(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null


# =============================================================================
# 对外接口
# =============================================================================

func set_move_input(direction: Vector3) -> void:
	_move_input = Vector3(direction.x, 0.0, direction.z).limit_length(1.0)


func set_active(value: bool) -> void:
	if is_active == value:
		return
	is_active = value
	_refresh_active_visuals()
	if is_active:
		became_active.emit()


func planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _refresh_active_visuals() -> void:
	if _ring != null:
		_ring.visible = is_active
	if _label != null:
		_label.visible = is_active


# =============================================================================
# 每帧
# =============================================================================

func _physics_process(delta: float) -> void:
	var target := _move_input * max_speed
	var planar := Vector2(velocity.x, velocity.z)
	var target_planar := Vector2(target.x, target.z)
	planar = planar.move_toward(target_planar, acceleration * delta)
	velocity.x = planar.x
	velocity.z = planar.y

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()
	global_position.x = clampf(global_position.x, -x_limit, x_limit)
	global_position.z = clampf(global_position.z, z_min, z_max)

	var speed := planar_speed()
	if speed > 0.25:
		var target_yaw := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

	_animate(delta, speed)


func _animate(delta: float, speed: float) -> void:
	var speed_factor := clampf(speed / maxf(0.001, max_speed), 0.0, 1.0)
	if _anim != null:
		# 动起来播跑步，停住播站立（带 0.25 秒过渡）。
		var wanted := "ff/run" if speed_factor > 0.12 else "ff/idle_huddle"
		if not _anim.has_animation(wanted):
			wanted = "ff/run" if _anim.has_animation("ff/run") else "ff/idle_huddle"
		if _anim.current_animation != wanted:
			_anim.play(wanted, 0.25)
		if wanted == "ff/run":
			# 跑速越快，步频越快
			_anim.speed_scale = clampf(0.75 + speed_factor * 0.6, 0.75, 1.5)
		else:
			_anim.speed_scale = 1.0
	# 跑动时轻微前倾（模型本身已有跑姿，这里只补一点点）
	var lean := 0.05 * speed_factor
	_visual.rotation.x = lerpf(_visual.rotation.x, lean, clampf(delta * 6.0, 0.0, 1.0))
