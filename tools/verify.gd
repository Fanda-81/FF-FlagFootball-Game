extends SceneTree
## FF · 无头验证脚本
##
## 运行：
##   <godot> --headless --path <项目目录> --script res://tools/verify.gd
##
## 覆盖：
##   1. 球场几何仍是 FFSIMU 原版（275 块网格），配色与 5 码条带符合要求
##   2. 竖屏工程配置、正交俯视镜头、初始取景
##   3. 缩到最小时球场居中（中纵线在屏幕正中）
##   4. 观众视角是透视 + 侧上方
##   5. 竖屏 HUD：帮助 / 观众视角按钮、帮助窗口能开能关
##   6. 屏幕方向约定（右 = -X，上 = +Z）
##   7. 橄榄球：弹道起飞、按时落地；传球参数与 FFSIMU 一致
##   8. 球员站在原地不动、不会掉出地面

const STADIUM_CHECK_AT := 0.05
const SPAWN_MAIN_AT := 0.20
const CAMERA_CHECK_AT := 0.70
const ZOOM_OUT_AT := 0.80
const CENTER_CHECK_AT := 1.70
const SPECTATOR_AT := 1.75
## 开球前状态 → 开球 → 四分卫后撤
const PRE_SNAP_CHECK_AT := 0.95
const SNAP_GO_AT := 1.10
const DROPBACK_CHECK_AT := 2.00
## 第一次传球：直接扔到四分卫脚下，验证"四分卫不能接自己的球"。
const QB_THROW_AT := 2.30
const QB_CHECK_AT := 3.10
## 第二次传球：40 码高球，验证聚焦球。
const THROW_AT := 5.00
const FOCUS_CHECK_AT := 5.50
const UNFOCUS_AT := 5.70
const THROW_CHECK_AT := 9.70
const FINISH_AT := 9.90

## 原版 274 块：去掉重复的草皮顶面（-1），加上两块看台泥地（+2）。
const EXPECTED_MESHES := 275
const DESIGN_SIZE := Vector2(720.0, 1280.0)
## 四分卫站位（启球线后 2.2 码），用于"扔到他自己脚下"的测试。
const QB_SPOT_Z := 2.8
## 传球测试的落点（球在启球线前方一点，保证一定飞得出去）。
const LOS_TARGET_Z := 18.0

var _stadium: Node3D
var _main: Node3D

var _elapsed := 0.0
var _stadium_checked := false
var _main_spawned := false
var _camera_checked := false
var _zoomed := false
var _centered_checked := false
var _spectator_checked := false
var _qb_thrown := false
var _qb_checked := false
var _pre_snap_checked := false
var _snap_done := false
var _dropback_checked := false
var _qb_before_dropback := Vector3.ZERO
var _thrown := false
var _focus_checked := false
var _unfocused := false
var _throw_checked := false
var _finished := false

var _failures: Array[String] = []
var _actor_start := Vector3.ZERO
var _idle_actor: CharacterBody3D
## 缩到最小时的取景快照，用于最终报告（之后会切到观众视角，不能再读镜头）。
var _zoomed_rect := Rect2()
var _zoomed_focus := Vector3.ZERO
var _qb_start := Vector3.ZERO
var _qb_ready := false


func _initialize() -> void:
	root.size = Vector2i(720, 1280)

	var packed: PackedScene = load("res://scenes/stadium.tscn")
	if packed == null:
		printerr("[verify] FAIL 无法加载 res://scenes/stadium.tscn")
		quit(1)
		return
	_stadium = packed.instantiate() as Node3D
	root.add_child(_stadium)


func _process(delta: float) -> bool:
	_elapsed += delta

	if not _stadium_checked and _elapsed >= STADIUM_CHECK_AT:
		_stadium_checked = true
		_check_scene_loads()
		_check_geometry_matches_original()
		_check_ground_colors()
		_check_endzone_text()
		_check_football()
		_check_pass_tuning()
		_spawn_idle_actor()

	if not _main_spawned and _elapsed >= SPAWN_MAIN_AT:
		_main_spawned = true
		_spawn_main()

	if not _camera_checked and _elapsed >= CAMERA_CHECK_AT:
		_camera_checked = true
		_check_portrait_and_camera()
		_check_hud()
		_check_input_mapping()

	if not _pre_snap_checked and _elapsed >= PRE_SNAP_CHECK_AT:
		_pre_snap_checked = true
		_check_pre_snap()

	if not _snap_done and _elapsed >= SNAP_GO_AT:
		_snap_done = true
		if _main != null:
			_main.call("debug_snap_now")
			var qb := _main.get("_qb") as Node3D
			if qb != null:
				_qb_before_dropback = qb.global_position

	if not _dropback_checked and _elapsed >= DROPBACK_CHECK_AT:
		_dropback_checked = true
		_check_dropback()

	if not _zoomed and _elapsed >= ZOOM_OUT_AT:
		_zoomed = true
		if _main != null:
			_main.call("debug_zoom_out")

	if not _centered_checked and _elapsed >= CENTER_CHECK_AT:
		_centered_checked = true
		_check_zoom_out_centered()

	if not _spectator_checked and _elapsed >= SPECTATOR_AT:
		_spectator_checked = true
		_check_spectator_view()
		_check_ball_carry()

	if not _qb_thrown and _elapsed >= QB_THROW_AT:
		_qb_thrown = true
		if _main != null:
			# 直接把球扔到四分卫脚下：他不能接自己的球。
			_main.call("debug_throw_at", Vector3(0.0, 0.0, QB_SPOT_Z), 0)

	if not _qb_checked and _elapsed >= QB_CHECK_AT:
		_qb_checked = true
		_check_qb_cannot_catch()

	if not _thrown and _elapsed >= THROW_AT:
		_thrown = true
		if _main != null:
			# 高球扔到 40 码，滞空约 1.9 秒，足够检查"聚焦球"。
			_main.call("debug_throw_at", Vector3(0.0, 0.0, 40.0), 1)

	if not _focus_checked and _elapsed >= FOCUS_CHECK_AT:
		_focus_checked = true
		_check_ball_focus()

	if not _unfocused and _elapsed >= UNFOCUS_AT:
		_unfocused = true
		if _main != null:
			_main.call("debug_focus_ball")
			if bool(_main.call("is_ball_focus_on")):
				_failures.append("再次点击后没有取消聚焦")

	if not _throw_checked and _elapsed >= THROW_CHECK_AT:
		# 等真实状态事件：球还在飞（FLIGHT=3）就继续等，超时 5 秒再判
		if int(_main.get("_phase")) == 3 and _elapsed < THROW_CHECK_AT + 5.0:
			pass
		else:
			_throw_checked = true
			_check_throw_loop()

	if not _finished and _elapsed >= FINISH_AT:
		_finished = true
		_check_idle_actor()
		_report()
		return true

	return false


func _report() -> void:
	if _failures.is_empty():
		var stats: Dictionary = _stadium.call("scenery_stats")
		print("[verify] OK  ", stats)
		print("[verify] 画面  设计 %d×%d（竖屏锁定）" % [
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))])
		if _main != null:
			print("[verify] 缩到最小 view=%s focus=%s" % [_zoomed_rect, _zoomed_focus])
		quit(0)
	else:
		for failure in _failures:
			printerr("[verify] FAIL ", failure)
		quit(1)


# =============================================================================
# 1. 球场
# =============================================================================

func _check_scene_loads() -> void:
	if _stadium == null:
		_failures.append("stadium 实例为空")
		return
	var stats: Dictionary = _stadium.call("scenery_stats")
	if int(stats["meshes"]) != EXPECTED_MESHES:
		_failures.append("网格数量 %d（预期 %d）" % [int(stats["meshes"]), EXPECTED_MESHES])
	if int(stats["static_bodies"]) < 1:
		_failures.append("缺少物理地面 StaticBody3D")
	if int(stats["pylons"]) != 10:
		_failures.append("角旗数量 %d（原版应为 10）" % int(stats["pylons"]))
	if int(stats["seated_crowd"]) != 16:
		_failures.append("坐席观众 %d（原版应为 16）" % int(stats["seated_crowd"]))
	if int(stats["standing_crowd"]) != 4:
		_failures.append("站席球迷 %d（原版应为 4）" % int(stats["standing_crowd"]))


func _check_geometry_matches_original() -> void:
	if _stadium == null:
		return
	var meshes := _find_meshes(_stadium)

	if not _has_box(meshes, Vector3(17.7, 0.43, 25.0), Vector3(0.62, 0.08, 20.0)):
		_failures.append("找不到看台第一级踏板 (17.7, 0.43, 25)")
	if not _has_box(meshes, Vector3(-17.7, 0.43, 25.0), Vector3(0.62, 0.08, 20.0)):
		_failures.append("找不到左侧看台第一级踏板 (-17.7, 0.43, 25)")
	if not _has_box(meshes, Vector3(20.8, 1.59, 25.0), Vector3(0.62, 0.08, 20.0)):
		_failures.append("找不到看台第三级踏板 (20.8, 1.59, 25)")
	if not _has_box(meshes, Vector3(24.0, 1.5, -14.0), Vector3(0.18, 3.0, 0.18)):
		_failures.append("找不到右侧围栏立柱 (24, 1.5, -14)")

	var los := _stadium.get("los_line") as Node3D
	if los == null:
		_failures.append("缺少 los_line 节点")
	elif not is_equal_approx(los.position.z, 5.0):
		_failures.append("启球线位置 %.3f（应为 5.0）" % los.position.z)

	var ground_found := false
	for child in _stadium.get_children():
		if child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					var shape := (sub as CollisionShape3D).shape as BoxShape3D
					if shape != null and is_equal_approx(shape.size.x, 34.7) and is_equal_approx(shape.size.z, 74.0):
						ground_found = true
	if not ground_found:
		_failures.append("物理地面尺寸不是 34.7 × 0.16 × 74")


func _check_ground_colors() -> void:
	if _stadium == null:
		return
	var meshes := _find_meshes(_stadium)

	var outer: MeshInstance3D = null
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.mesh as BoxMesh
		if box != null and is_equal_approx(box.size.x, 88.7) and is_equal_approx(box.size.z, 104.0):
			outer = mesh_instance
			break
	if outer == null:
		_failures.append("找不到外围地面")
	else:
		var material := outer.material_override as StandardMaterial3D
		if material == null:
			_failures.append("外围地面没有材质")
		else:
			var color := material.albedo_color
			if not (color.g > color.r and color.g > color.b):
				_failures.append("外围地面不是绿色：%s" % color)
			if color.get_luminance() > 0.18:
				_failures.append("外围草地不够深：亮度 %.3f" % color.get_luminance())
			if material.albedo_texture != null:
				_failures.append("外围地面不应再使用带密集条纹的贴图")

	if not _has_box(meshes, Vector3(19.1, -0.03, 25.0), Vector3(5.6, 0.012, 23.0)):
		_failures.append("缺少右侧看台泥地 (19.1, -0.03, 25)")
	if not _has_box(meshes, Vector3(-19.1, -0.03, 25.0), Vector3(5.6, 0.012, 23.0)):
		_failures.append("缺少左侧看台泥地 (-19.1, -0.03, 25)")

	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.mesh as BoxMesh
		if box == null:
			continue
		if not (is_equal_approx(box.size.x, 26.7) and is_equal_approx(box.size.z, 70.0)):
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material != null and material.albedo_texture != null:
			_failures.append("场内草皮仍在用贴图（会重新出现密集条纹）")

	var bands := 0
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.mesh as BoxMesh
		if box == null:
			continue
		if is_equal_approx(box.size.x, 26.7) and is_equal_approx(box.size.z, 5.0):
			bands += 1
	if bands != 10:
		_failures.append("5 码条带数量 %d（应为 10）" % bands)


func _check_endzone_text() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 60.0, 25.0)
	camera.look_at(Vector3(0.0, 0.0, 25.0), Vector3(0.0, 0.0, 1.0))
	camera.size = 96.0
	var inverse := camera.global_transform.basis.inverse()

	var found := 0
	for child in _stadium.get_children():
		if not (child is Label3D):
			continue
		var label := child as Label3D
		if label.text != "END ZONE":
			continue
		found += 1
		var text_up := inverse * label.global_transform.basis.y
		var text_right := inverse * label.global_transform.basis.x
		if text_up.y <= 0.0:
			_failures.append("END ZONE 文字上下颠倒 (z=%.1f)" % label.position.z)
		if text_right.x <= 0.0:
			_failures.append("END ZONE 文字左右颠倒 (z=%.1f)" % label.position.z)
	if found != 2:
		_failures.append("END ZONE 水印数量 %d（应为 2）" % found)
	camera.queue_free()


# =============================================================================
# 2. 橄榄球 + 传球参数
# =============================================================================

func _check_football() -> void:
	var packed: PackedScene = load("res://scenes/football.tscn")
	if packed == null:
		_failures.append("无法加载 football.tscn")
		return
	var ball: RigidBody3D = packed.instantiate() as RigidBody3D
	if ball == null:
		_failures.append("football.tscn 根节点不是 RigidBody3D")
		return
	ball.set("auto_advance", false)
	root.add_child(ball)

	# 取消白边：不应再有 GripRing / 额外鞋带网格
	if ball.find_child("GripRing", true, false) != null:
		_failures.append("球模型上仍有白色握把环")

	# 原模型自带的白色防滑条与球线必须保留（只有球皮是皮革贴图）。
	var textured := 0
	var white := 0
	for node in ball.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var material := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if material == null:
			continue
		if material.albedo_texture != null:
			textured += 1
		else:
			white += 1
	if textured != 1:
		_failures.append("皮革材质的网格数 %d（应为 1：只有球皮）" % textured)
	if white < 10:
		_failures.append("球的白色防滑条/球线被去掉了：只剩 %d 个白色网格" % white)

	var material := ball.physics_material_override
	if material == null or material.bounce < 0.3:
		_failures.append("球没有弹性材质，落地不会弹两下")

	var start := Vector3(0.0, 1.2, 0.0)
	var target := Vector3(0.0, 1.2, 10.0)
	ball.call("start_flight", start, target, 1.0)
	if not bool(ball.get("manual_flight")):
		_failures.append("start_flight 之后没有进入弹道模式")
	for i in range(61):
		ball.call("step", 1.0 / 60.0)
	if not bool(ball.get("reached_target")):
		_failures.append("弹道 1 秒后没有到达落点")
	if absf(ball.global_position.z - 10.0) > 0.2:
		_failures.append("落点偏移：z=%.2f（应为 10）" % ball.global_position.z)

	# 没人接住：球越过落点继续飞，直到落地
	for i in range(120):
		ball.call("step", 1.0 / 60.0)
	if not bool(ball.get("landed")):
		_failures.append("球越过落点后没有落地")
	if ball.global_position.z <= 10.2:
		_failures.append("没人接住时球没有继续往前飞：z=%.2f" % ball.global_position.z)
	ball.queue_free()


func _check_pass_tuning() -> void:
	var tuning = load("res://scripts/pass_tuning.gd")
	var flat: float = tuning.flight_time(20.0, false)
	var high: float = tuning.flight_time(20.0, true)
	if absf(flat - 20.0 / 30.0) > 0.001:
		_failures.append("平传球速不是 30 m/s：%.3f" % flat)
	if absf(high - 20.0 / 20.0) > 0.001:
		_failures.append("高球球速不是 20 m/s：%.3f" % high)
	if absf(tuning.flight_time(0.5, false) - 0.55) > 0.001:
		_failures.append("最小滞空时间不是 0.55")
	if absf(tuning.flight_time(200.0, true) - 2.2) > 0.001:
		_failures.append("最大滞空时间不是 2.2")


func _spawn_idle_actor() -> void:
	var packed: PackedScene = load("res://scenes/player_actor.tscn")
	if packed == null:
		_failures.append("无法加载 player_actor.tscn")
		return
	_idle_actor = packed.instantiate() as CharacterBody3D
	_idle_actor.position = Vector3(-4.0, 0.1, 40.0)
	root.add_child(_idle_actor)
	_actor_start = _idle_actor.global_position


func _check_idle_actor() -> void:
	if _idle_actor == null:
		return
	var drift: float = Vector2(
		_idle_actor.global_position.x - _actor_start.x,
		_idle_actor.global_position.z - _actor_start.z).length()
	# 列阵阶段（phase 7）球员本来就在慢跑，不算漂移
	if drift > 0.15 and int(_main.get("_phase")) != 7:
		_failures.append("球员在没有输入时移动了 %.2f m" % drift)
	if _idle_actor.global_position.y < -0.2:
		_failures.append("球员掉到地面以下：y=%.2f" % _idle_actor.global_position.y)
	_check_character_rig()


## 新角色：FFfemale 骨架 + 重定向后的 Fast Run（髋部固定）。
func _check_character_rig() -> void:
	var skeleton := _find_node(_idle_actor, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		_failures.append("球员模型里没有 Skeleton3D")
		return
	if skeleton.get_bone_count() < 22:
		_failures.append("骨骼数 %d（morra 应为 25）" % skeleton.get_bone_count())
	if skeleton.find_bone("mixamorig_Hips") < 0:
		_failures.append("骨架里没有 mixamorig_Hips")

	var player := _find_node(_idle_actor, "AnimationPlayer") as AnimationPlayer
	if player == null:
		_failures.append("球员没有 AnimationPlayer")
		return
	if not player.is_playing():
		_failures.append("角色动画没有在播放")
	if player.current_animation != "ff/idle_huddle" and player.current_animation != "ff/run":
		_failures.append("当前动画不是 ff/idle 或 ff/run：%s" % player.current_animation)
	for clip_name in ["ff/run", "ff/idle_huddle"]:
		if not player.has_animation(clip_name):
			_failures.append("缺少动画 %s" % clip_name)
			continue
		var animation := player.get_animation(clip_name)
		if animation.get_track_count() < 20:
			_failures.append("%s 轨道过少：%d" % [clip_name, animation.get_track_count()])
		# 固定髋部：不应该存在任何位移轨道
		for t in animation.get_track_count():
			if animation.track_get_type(t) == Animation.TYPE_POSITION_3D:
				_failures.append("%s 里仍有位移轨道（髋部没有固定）：%s" % [clip_name, animation.track_get_path(t)])
				break
	# 脚底要贴着地面（骨骼在 0~0.20 之间都算正常，脚掌本身有厚度）
	var toe := skeleton.find_bone("mixamorig_LeftToeBase")
	if toe >= 0:
		var foot := skeleton.global_transform * skeleton.get_bone_global_pose(toe).origin
		if foot.y < -0.05 or foot.y > 0.30:
			_failures.append("脚没有踩在地上：ToeBase 世界高度 %.2f" % foot.y)


func _find_node(start: Node, cls: String) -> Node:
	return _search(start, cls)


func _search(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var hit := _search(child, cls)
		if hit != null:
			return hit
	return null


# =============================================================================
# 3. 竖屏 / 镜头
# =============================================================================

func _spawn_main() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_failures.append("无法加载 res://scenes/main.tscn")
		return
	_main = packed.instantiate() as Node3D
	root.add_child(_main)


func _check_portrait_and_camera() -> void:
	var design_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var design_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", 0))
	if design_height <= design_width:
		_failures.append("设计分辨率不是竖屏：%d×%d" % [design_width, design_height])
	if orientation != 1:
		_failures.append("手持方向没有锁定竖屏（orientation=%d）" % orientation)

	if _main == null:
		_failures.append("main.tscn 未加载")
		return
	var camera := _main.get_node_or_null("Camera") as Camera3D
	if camera == null:
		_failures.append("主场景缺少 Camera")
		return
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		_failures.append("主视角不是正交投影")
	var basis := camera.global_transform.basis
	if absf(basis.z.y - 1.0) > 0.01:
		_failures.append("主视角不是正上方俯瞰")
	if absf(basis.y.z - 1.0) > 0.01:
		_failures.append("屏幕上方向不是球场远端 +Z")
	if absf(camera.size - 54.0) > 1.0:
		_failures.append("初始可视高度 %.2f（应为 54）" % camera.size)
	if camera.get("follow") == null:
		_failures.append("镜头没有跟随持球人")

	# 记录四分卫位置，整局结束后确认他没有自己跑动
	var qb := _main.get("_qb") as Node3D
	if qb == null:
		_failures.append("场上看不到四分卫")
	else:
		_qb_start = qb.global_position
		_qb_ready = true


## 缩到最小时：可视范围必须大于球场，取景点锁定在球场中心。
func _check_zoom_out_centered() -> void:
	if _main == null:
		return
	var camera := _main.get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	var view: float = camera.call("current_view_size")
	if absf(view - 96.0) > 1.5:
		_failures.append("没有缩到最小：%.1f（应为 96）" % view)
	var focus: Vector3 = camera.call("current_focus")
	if absf(focus.z - 25.0) > 0.4:
		_failures.append("缩到最小时取景点 z=%.2f（应锁定在球场中场 25）" % focus.z)
	if absf(focus.x) > 0.2:
		_failures.append("缩到最小时取景点 x=%.2f（中纵线应在屏幕正中）" % focus.x)
	var rect: Rect2 = camera.call("current_view_rect")
	if rect.position.x > -26.0 or rect.end.x < 26.0:
		_failures.append("缩到最小看不到围栏：可视 x [%.1f, %.1f]" % [rect.position.x, rect.end.x])
	_zoomed_rect = rect
	_zoomed_focus = focus


func _check_spectator_view() -> void:
	if _main == null:
		return
	_main.call("debug_spectator")
	var camera := _main.get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		_failures.append("观众视角不是透视投影")
	var camera_position := camera.global_position
	if camera_position.y < 6.0:
		_failures.append("观众视角机位太低：y=%.1f" % camera_position.y)
	if absf(camera_position.x) < 8.0:
		_failures.append("观众视角不在场地侧面：x=%.1f" % camera_position.x)
	# 正侧方：相机和取景点的 z 必须一致（没有前后斜角）
	var focus: Vector3 = camera.call("current_focus")
	if absf(camera_position.z - focus.z) > 0.6:
		_failures.append("观众视角带前后斜角：相机 z=%.1f，取景点 z=%.1f" % [camera_position.z, focus.z])
	if camera.get("follow") == null:
		_failures.append("观众视角没有跟随持球人")

## 球被握在手里时，必须离开身体一段距离，不能穿模。
func _check_ball_carry() -> void:
	if _main == null:
		return
	var holder := _main.get("_holder") as Node3D
	var ball := _main.get_node_or_null("FootballRoot") as Node3D
	if holder == null or ball == null:
		_failures.append("持球人或球缺失")
		return
	var offset := ball.global_position - holder.global_position
	var flat := Vector2(offset.x, offset.z).length()
	if flat < 0.40:
		_failures.append("球贴着持球人会穿模：水平距 %.2f m" % flat)
	if offset.y < 0.70 or offset.y > 1.50:
		_failures.append("球不在手的高度：y=%.2f" % offset.y)


## 四分卫不能接自己传出的球。
func _check_qb_cannot_catch() -> void:
	if _main == null:
		return
	var pending := String(_main.call("debug_pending_result"))
	var last := String(_main.call("debug_last_result"))
	if pending == "" and last == "":
		_failures.append("四分卫测试的传球没有结算")
		return
	if pending.contains("接球成功") or last.contains("接球成功"):
		_failures.append("四分卫接住了自己传出的球：%s%s" % [pending, last])
	var thrower := _main.call("debug_thrower") as Node3D
	var qb := _main.get("_qb") as Node3D
	if thrower == null or thrower != qb:
		_failures.append("没有正确记录出手人")


## 传球途中点「聚焦球」：应该切到球的**正后方**近距离机位。
func _check_ball_focus() -> void:
	if _main == null:
		return
	if not bool(_main.call("debug_focus_ball")):
		_failures.append("传球途中点「聚焦球」没有进入聚焦")
		return
	var camera := _main.get_node_or_null("Camera") as Camera3D
	var ball := _main.get_node_or_null("FootballRoot") as Node3D
	if camera == null or ball == null:
		_failures.append("找不到相机或橄榄球")
		return
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		_failures.append("聚焦球不是透视机位")
	var distance := camera.global_position.distance_to(ball.global_position)
	if distance > 6.0 or distance < 1.2:
		_failures.append("聚焦球机位距离异常：%.2f m" % distance)
	var velocity: Vector3 = ball.get("flight_velocity")
	var to_ball := camera.global_position - ball.global_position
	to_ball.y = 0.0
	var forward := Vector3(velocity.x, 0.0, velocity.z)
	if forward.length() < 0.5:
		_failures.append("聚焦时球没有速度")
		return
	forward = forward.normalized()
	if to_ball.length() > 0.1 and to_ball.normalized().dot(forward) > -0.7:
		_failures.append("聚焦球机位不在球的正后方")


## 走完一整次传球：出手 → 弹道结束 → 判定 → 复位成 HOLD。
func _check_throw_loop() -> void:
	if _main == null:
		return
	var attempts := int(_main.get("_attempts"))
	if attempts < 1:
		_failures.append("传球没有被判定：attempts=%d" % attempts)
	var phase := int(_main.get("_phase"))
	if phase != 0 and phase != 7 and phase != 8:
		_failures.append("传球结束后没有复位到持球状态：phase=%d" % phase)
	if _main.get("_holder") == null:
		_failures.append("复位后没有持球人")
	if _qb_ready:
		var qb := _main.get("_qb") as Node3D
		if qb != null:
			var drift := qb.global_position.distance_to(_qb_start)
			if drift > 0.2:
				_failures.append("四分卫自己移动了 %.2f m" % drift)


# =============================================================================
# 4. HUD
# =============================================================================

func _check_hud() -> void:
	if _main == null:
		return
	_main.call("debug_open_menu")
	_main.call("debug_open_play_drawer")
	var screen := Rect2(Vector2.ZERO, DESIGN_SIZE)

	var help := _find_hud_button("HelpButton")
	if help == null:
		_failures.append("缺少右上帮助按钮")
	else:
		var rect := _design_rect(help)
		if rect.size.x < 120.0 or rect.size.y < 80.0:
			_failures.append("帮助按钮太小：%.0f×%.0f" % [rect.size.x, rect.size.y])
		if not screen.encloses(rect):
			_failures.append("帮助按钮超出屏幕：%s" % rect)


	var view_button := _find_hud_button("ViewButton")
	if view_button == null:
		_failures.append("缺少观众视角按钮")
	else:
		var rect := _design_rect(view_button)
		if rect.size.x < 120.0 or rect.size.y < 80.0:
			_failures.append("观众视角按钮太小：%.0f×%.0f" % [rect.size.x, rect.size.y])
		if help != null and _design_rect(help).intersects(rect):
			_failures.append("观众视角按钮与帮助按钮重叠")


	var focus_button := _find_hud_button("FocusButton")
	if focus_button == null:
		_failures.append("缺少聚焦球按钮")
	else:
		var rect := _design_rect(focus_button)
		if rect.size.x < 120.0 or rect.size.y < 80.0:
			_failures.append("聚焦球按钮太小：%.0f×%.0f" % [rect.size.x, rect.size.y])
		if view_button != null and _design_rect(view_button).intersects(rect):
			_failures.append("聚焦球按钮与观众视角按钮重叠")
		if not screen.encloses(rect):
			_failures.append("聚焦球按钮超出屏幕：%s" % rect)

	var overlay := _main.get_node_or_null("HUD/HudRoot/HelpOverlay") as Control
	if overlay == null:
		_failures.append("缺少帮助窗口")
		return
	if overlay.visible:
		_failures.append("帮助窗口初始应隐藏")

	_main.call("show_help")
	if not bool(_main.call("is_help_open")):
		_failures.append("show_help() 之后帮助窗口没有打开")
	var panel := overlay.get_node_or_null("HelpPanel") as Control
	if panel == null:
		_failures.append("帮助窗口缺少面板")
	else:
		var panel_rect := _design_rect(panel)
		if panel_rect.size.x < 560.0:
			_failures.append("帮助面板过窄：%.0f" % panel_rect.size.x)
		if not screen.encloses(panel_rect):
			_failures.append("帮助面板超出屏幕：%s" % panel_rect)
	_main.call("hide_help")
	if bool(_main.call("is_help_open")):
		_failures.append("hide_help() 之后帮助窗口没有关闭")




func _find_hud_button(button_name: String) -> Button:
	var hud := _main.get_node_or_null("HUD/HudRoot")
	if hud == null:
		return null
	return hud.find_child(button_name, true, false) as Button

func _design_rect(control: Control) -> Rect2:
	var top_left := Vector2(
		control.anchor_left * DESIGN_SIZE.x + control.offset_left,
		control.anchor_top * DESIGN_SIZE.y + control.offset_top)
	var bottom_right := Vector2(
		control.anchor_right * DESIGN_SIZE.x + control.offset_right,
		control.anchor_bottom * DESIGN_SIZE.y + control.offset_bottom)
	return Rect2(top_left, bottom_right - top_left)


# =============================================================================
# 5. 屏幕方向约定
# =============================================================================

func _check_input_mapping() -> void:
	if _main == null:
		return
	var camera := _main.get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	var center := root.get_visible_rect().size * 0.5
	var origin: Vector3 = camera.call("screen_to_ground", center)
	var right: Vector3 = camera.call("screen_to_ground", center + Vector2(20.0, 0.0))
	var up: Vector3 = camera.call("screen_to_ground", center - Vector2(0.0, 20.0))
	if not origin.is_finite() or not right.is_finite() or not up.is_finite():
		_failures.append("屏幕坐标无法映射到地面")
		return
	if right.x >= origin.x:
		_failures.append("屏幕右方应映射到世界 -X")
	if up.z <= origin.z:
		_failures.append("屏幕上方应映射到世界 +Z")


# =============================================================================
# 小工具
# =============================================================================

## 开球前：球在中锋手里、开球按钮在右下、档数/计时/TD 覆盖层就位。
func _check_pre_snap() -> void:
	if _main == null:
		return
	var ball := _main.get_node_or_null("FootballRoot") as Node3D
	var center := _main.get("_center") as Node3D
	var qb := _main.get("_qb") as Node3D
	if ball == null or center == null or qb == null:
		_failures.append("开球前球/中锋/四分卫缺失")
		return
	var to_center := ball.global_position.distance_to(center.global_position)
	var to_qb := ball.global_position.distance_to(qb.global_position)
	if to_center > 1.8:
		_failures.append("开球前球不在中锋手里：距中锋 %.2f m" % to_center)
	if to_qb < 1.8:
		_failures.append("开球前球已经在四分卫手里")

	var snap_button := _main.get_node_or_null("HUD/HudRoot/SnapButton") as Button
	if snap_button == null:
		_failures.append("缺少开球按钮")
	else:
		var rect := _design_rect(snap_button)
		if rect.size.x < 180.0 or rect.size.y < 90.0:
			_failures.append("开球按钮太小：%.0f×%.0f" % [rect.size.x, rect.size.y])
		if rect.position.x < DESIGN_SIZE.x * 0.55:
			_failures.append("开球按钮不在右侧：%s" % rect)
		if rect.position.y < DESIGN_SIZE.y * 0.70:
			_failures.append("开球按钮不在下方：%s" % rect)
		if not snap_button.visible:
			_failures.append("开球前开球按钮应可见")

	var down := _main.get_node_or_null("HUD/HudRoot/StatePanel/StateColumn/DownLabel") as Label
	if down == null:
		_failures.append("缺少档数显示")
	elif not down.text.contains("DOWN"):
		_failures.append("档数显示内容不对：%s" % down.text)
	if _main.get_node_or_null("HUD/HudRoot/StatePanel/StateColumn/ClockLabel") == null:
		_failures.append("缺少倒计时显示")

	var banner := _main.get_node_or_null("HUD/HudRoot/TouchdownBanner") as Label
	if banner == null:
		_failures.append("缺少 TouchDown 横幅")
	elif banner.visible:
		_failures.append("TouchDown 横幅初始应隐藏")
	var confetti := _main.get_node_or_null("HUD/HudRoot/Confetti") as CPUParticles2D
	if confetti == null:
		_failures.append("缺少彩带粒子")
	elif confetti.emitting:
		_failures.append("彩带初始不应发射")


## 开球后：球到四分卫手上、后撤两步、外接手有路线。
func _check_dropback() -> void:
	if _main == null:
		return
	var qb := _main.get("_qb") as Node3D
	if qb == null:
		return
	var moved := _qb_before_dropback.z - qb.global_position.z
	if moved < 1.8 or moved > 3.2:
		_failures.append("四分卫后撤距离 %.2f（应约 2.4）" % moved)
	if _main.get("_holder") != _main.get("_qb"):
		_failures.append("开球后球没有到四分卫手里")
	var routes: Dictionary = _main.get("_routes")
	if routes.size() < 3:
		_failures.append("外接手路线数量 %d（应为 3）" % routes.size())

func _find_meshes(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func _has_box(meshes: Array, position: Vector3, size: Vector3) -> bool:
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.mesh as BoxMesh
		if box == null:
			continue
		if mesh_instance.position.distance_to(position) < 0.01 and box.size.distance_to(size) < 0.01:
			return true
	return false
