extends RigidBody3D
## FF · 橄榄球（移植自 FFSIMU `football_actor.gd`）
##
## 保留原版的三段结构：
##   FootballRoot
##   └─ SpinPivot（本地 Z = 校准后的长轴）
##      └─ ModelCorrection（固定模型朝向修正）
##         └─ FootballModel
##
## 两种运动模式：
##   * start_flight() 手动弹道：用于传球/弃球，按解析抛物线走，不参与物理，
##     这样落点精确、滞空时间可控（和 FFSIMU 完全一致）。
##   * begin_physics() 交回物理引擎：用于落地弹跳、脱手等。
##
## 自转 `spin_pivot` 让球在飞行时绕长轴旋转，视觉上就是标准的橄榄球螺旋。

@export var gravity := 9.8
@export var spin_rps := 8.0
## 由脚本推进弹道（main.gd 只负责在结束时判定）。
@export var auto_advance := true

@onready var spin_pivot: Node3D = $SpinPivot
@onready var model_correction: Node3D = $SpinPivot/ModelCorrection
@onready var football_model: Node3D = $SpinPivot/ModelCorrection/FootballModel

var flight_velocity := Vector3.ZERO
var flight_elapsed := 0.0
var flight_time := 0.0
var flight_target := Vector3.ZERO
var manual_flight := false
## 到达预定落点（接球判定就在这一刻做）。
var reached_target := false
## 真正触地（没人接住时会继续往前飞，直到落地）。
var landed := false

# 手持和手动弹道期间要关掉碰撞层，否则球体碰撞盒会顶开持球人的胶囊体。
var _default_layer := 1
var _default_mask := 1


func _ready() -> void:
	_default_layer = collision_layer
	_default_mask = collision_mask
	mass = 0.62
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 0.55
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	freeze = true
	body_entered.connect(_on_body_entered)
	_apply_football_material()
	# 让球落地后能靠惯性弹两下，而不是"啪"一下贴在地上。
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.45
	bounce.friction = 0.85
	physics_material_override = bounce


func _apply_football_material() -> void:
	var leather := StandardMaterial3D.new()
	leather.albedo_texture = preload("res://assets/models/football_basecolor.png")
	leather.roughness_texture = preload("res://assets/models/football_roughness.png")
	leather.normal_enabled = true
	leather.normal_texture = preload("res://assets/models/football_normal.png")
	leather.roughness = 1.0
	leather.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 原模型（橄榄球.fbx 导出的 glb）没有材质球，只能按体积区分：
	#   * 最大的网格是球皮 → 皮革贴图；
	#   * 其余是球两端的白色条纹、白色防滑条、鞋带和中间那条球线 → 保持白色。
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f4ead7")
	white.roughness = 0.45
	white.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body: MeshInstance3D = null
	var largest_volume := 0.0
	for mesh in football_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		var volume := bounds.size.x * bounds.size.y * bounds.size.z
		if volume > largest_volume:
			largest_volume = volume
			body = mesh_instance

	for mesh in football_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var material := leather if mesh_instance == body else white
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)


## 平滑接管：让球以固定朝向握在某人手里（不参与物理、不旋转）。
func hold_at(world_position: Vector3, facing: Basis) -> void:
	manual_flight = false
	reached_target = false
	landed = false
	flight_velocity = Vector3.ZERO
	freeze = true
	sleeping = true
	collision_layer = 0
	collision_mask = 0
	global_transform = Transform3D(facing, world_position)


## 开始一段解析弹道。落点与滞空时间由调用方算好。
func start_flight(start: Vector3, target: Vector3, duration: float) -> void:
	global_position = start
	flight_target = target
	flight_time = maxf(duration, 0.05)
	flight_elapsed = 0.0
	reached_target = false
	landed = false
	manual_flight = true
	freeze = true
	# 手动弹道是直接改坐标，不该和球员/地面产生物理碰撞。
	collision_layer = 0
	collision_mask = 0
	spin_pivot.rotation.z = 0.0
	var vy := (target.y - start.y + 0.5 * gravity * flight_time * flight_time) / flight_time
	flight_velocity = Vector3(
		(target.x - start.x) / flight_time,
		vy,
		(target.z - start.z) / flight_time
	)
	_orient_to_velocity(flight_velocity)


## 弹道积分：到达落点后不中断，继续按同一条抛物线飞到地面。
## 这样没人接住的球会"多飞一段"再落地，落地时把速度交给物理引擎自然弹跳。
func step(delta: float) -> void:
	if not manual_flight or landed:
		return
	flight_velocity.y -= gravity * delta
	global_position += flight_velocity * delta
	flight_elapsed += delta
	_orient_to_velocity(flight_velocity)
	spin_pivot.rotate_object_local(Vector3(0, 0, 1), -TAU * spin_rps * delta)
	if not reached_target and flight_elapsed >= flight_time:
		reached_target = true
	# 0.16m ≈ 球的半径 + 一点点余量，再低就交给物理。
	if reached_target and global_position.y <= 0.16:
		landed = true


## 交回物理引擎（落地弹跳、脱手等）。
func begin_physics(initial_velocity: Vector3) -> void:
	manual_flight = false
	reached_target = false
	landed = false
	gravity_scale = 1.0
	freeze = false
	sleeping = false
	collision_layer = _default_layer
	collision_mask = _default_mask
	linear_velocity = initial_velocity
	angular_velocity = Vector3(
		randf_range(-7.0, 7.0),
		randf_range(-3.0, 3.0),
		randf_range(-7.0, 7.0)
	)


func is_flying() -> bool:
	return manual_flight and not landed


func _orient_to_velocity(velocity: Vector3) -> void:
	if velocity.length() < 0.01:
		return
	var direction := velocity.normalized()
	var up := Vector3.UP
	# 接近竖直时换一个参考上方向，避免 look_at / 正交化奇异。
	if absf(direction.dot(up)) > 0.98:
		up = Vector3.BACK
	var side := up.cross(direction)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var local_up := direction.cross(side).normalized()
	# 本地 -Z 对准速度方向；本地 Z 是球的长轴。
	# 使用右手基，避免 Basis 行列式为负导致模型镜像/翻面。
	var z_axis := -direction
	var x_axis := local_up.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	global_transform = Transform3D(basis, global_position)


func _physics_process(delta: float) -> void:
	if auto_advance:
		step(delta)


func _on_body_entered(_body: Node) -> void:
	if manual_flight or freeze:
		return
	var speed := linear_velocity.length()
	if speed < 0.25:
		return
	linear_velocity += Vector3(randf_range(-0.55, 0.55), 0.18, randf_range(-0.55, 0.55))
	angular_velocity += Vector3(
		randf_range(-7.0, 7.0),
		randf_range(-3.0, 3.0),
		randf_range(-7.0, 7.0)
	)
	angular_velocity = angular_velocity.limit_length(16.0)
