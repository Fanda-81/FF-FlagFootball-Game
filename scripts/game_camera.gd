extends Camera3D
class_name GameCamera
## FF · 双视角镜头（竖屏）
##
## 两种视角，都跟随**持球人**：
##   * TOP_DOWN  —— 正交、正上方俯瞰，战术板视角。
##   * SPECTATOR —— 透视、从左看台上方斜看（"观众视角"），跟随持球人平移。
##
## 方向约定（顶视）：屏幕右 = 世界 -X，屏幕上 = 世界 +Z。
##
## 缩到最小时的居中规则：可视范围一旦超过球场本身，该轴就自动锁定在球场中心。
## 所以缩到最小（size = 96）时球场中纵线正好落在屏幕正中；放大后才会跟着持球人移动。
##
## 手势：双指拖动平移（松手后自动回中）、双指捏合缩放。

enum ViewMode { TOP_DOWN, SPECTATOR }

## 球场草坪边界（不含达阵区外的空地）。
const FIELD_MIN_X := -13.35
const FIELD_MAX_X := 13.35
const FIELD_MIN_Z := -10.0
const FIELD_MAX_Z := 60.0
const FIELD_CENTER := Vector3(0.0, 0.0, 25.0)

## 观众视角机位方向（从目标指向相机）。
## 只在 X 轴和高度上有分量：正侧方机位，没有 Z 方向斜角。
const SPECTATOR_DIR := Vector3(-24.0, 15.0, 0.0)

@export var mode: ViewMode = ViewMode.TOP_DOWN
## 跟随目标（持球人）。为空时退回球场中心。
@export var follow: Node3D

@export_group("顶视")
@export var top_view_size := 54.0
@export var top_min_size := 16.0
@export var top_max_size := 96.0

@export_group("观众视角")
@export var spectator_base_distance := 30.0
@export var spectator_min_zoom := 0.55
@export var spectator_max_zoom := 1.8
@export var spectator_fov := 55.0

@export_group("手感")
@export var smoothing := 8.0
@export var wheel_zoom_step := 1.15
## 松手后平移量回到持球人身上的速度（每秒）。
@export var pan_return_rate := 1.8

@export_group("聚焦球")
## 机位落在球正后方多远。
@export var chase_distance := 3.4
@export var chase_height := 1.1
@export var chase_fov := 34.0

## 是否处于"聚焦球"模式（由 main 的按钮控制）。
var ball_focus := false
var chase_target: Node3D
var chase_velocity := Vector3.ZERO

var _focus_target: Vector3
var _focus_current: Vector3
var _size_target: float
var _size_current: float
var _zoom_target: float
var _zoom_current: float
var _pan_offset := Vector3.ZERO
## 攻防转换时把俯视画面整体转 180°（屏幕上方永远是进攻方向）
var flipped := false
var _panning := false

var _touches: Dictionary = {}
var _pinch_mid := Vector2.ZERO
var _pinch_distance := 0.0
var _pinch_valid := false
var _mouse_panning := false
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	near = 0.1
	far = 600.0
	_size_target = clampf(top_view_size, top_min_size, top_max_size)
	_size_current = _size_target
	_zoom_target = 1.0
	_zoom_current = 1.0
	_focus_target = _carrier_position()
	_focus_current = _focus_target
	_apply_projection()
	_apply_transform()


func _process(delta: float) -> void:
	# 聚焦球：完全由球的位置和速度决定机位，不再走跟随/平滑。
	if ball_focus and chase_target != null and is_instance_valid(chase_target):
		_apply_projection()
		_apply_transform()
		return

	var blend := 1.0 - exp(-smoothing * delta)
	if not _panning:
		_pan_offset = _pan_offset.lerp(Vector3.ZERO, 1.0 - exp(-pan_return_rate * delta))

	_focus_target = _clamped_focus(_carrier_position() + _pan_offset)
	_focus_current = _focus_current.lerp(_focus_target, blend)
	_size_current = lerpf(_size_current, _size_target, blend)
	_zoom_current = lerpf(_zoom_current, _zoom_target, blend)
	_apply_projection()
	_apply_transform()


func _apply_projection() -> void:
	if ball_focus and chase_target != null:
		projection = PROJECTION_PERSPECTIVE
		fov = chase_fov
	elif mode == ViewMode.TOP_DOWN:
		projection = PROJECTION_ORTHOGONAL
		keep_aspect = KEEP_HEIGHT
		size = _size_current
	else:
		projection = PROJECTION_PERSPECTIVE
		fov = spectator_fov


func _apply_transform() -> void:
	# 聚焦球：站在球的正后方看球，能看清拖尾和自转。
	if ball_focus and chase_target != null and is_instance_valid(chase_target):
		var target := chase_target.global_position
		var horizontal := Vector3(chase_velocity.x, 0.0, chase_velocity.z)
		if horizontal.length() < 0.5:
			horizontal = Vector3(0.0, 0.0, 1.0)
		var back := -horizontal.normalized()
		position = target + back * chase_distance + Vector3.UP * chase_height
		look_at(target, Vector3.UP)
		return

	if mode == ViewMode.TOP_DOWN:
		position = Vector3(_focus_current.x, 60.0, _focus_current.z)
		# 正下方目标 + up=+Z：屏幕右 = -X、屏幕上 = +Z，且不会万向节翻转。
		look_at(Vector3(_focus_current.x, 0.0, _focus_current.z), Vector3(0.0, 0.0, 1.0))
		if flipped:
			# 绕视线轴滚转 180°，图像上下左右整体翻转
			rotate_object_local(Vector3(0, 0, -1), PI)
	else:
		var direction := SPECTATOR_DIR.normalized()
		position = _focus_current + direction * (spectator_base_distance * _zoom_current)
		look_at(_focus_current + Vector3(0.0, 1.2, 0.0), Vector3.UP)


func _carrier_position() -> Vector3:
	if follow != null and is_instance_valid(follow):
		var position := follow.global_position
		return Vector3(position.x, 0.0, position.z)
	return FIELD_CENTER


## 可视范围超过球场时锁定球场中心，否则限制在球场内。
## 这就是"缩到最小时球场中纵线在屏幕正中"的实现。
func _clamped_focus(value: Vector3) -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var half_w: float
	var half_h: float
	if mode == ViewMode.TOP_DOWN:
		half_w = _size_target * aspect * 0.5
		half_h = _size_target * 0.5
	else:
		var distance := spectator_base_distance * _zoom_target
		half_h = distance * tan(deg_to_rad(spectator_fov * 0.5))
		half_w = half_h * aspect
	return Vector3(
		_clamp_axis(value.x, FIELD_MIN_X, FIELD_MAX_X, half_w),
		0.0,
		_clamp_axis(value.z, FIELD_MIN_Z, FIELD_MAX_Z, half_h)
	)


func _clamp_axis(value: float, field_min: float, field_max: float, half: float) -> float:
	var low := field_min + half
	var high := field_max - half
	if low > high:
		# 视野比球场还大：直接居中。
		return (field_min + field_max) * 0.5
	return clampf(value, low, high)


# =============================================================================
# 输入
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_refresh_pinch_baseline()
		_panning = _touches.size() >= 2
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			_handle_two_finger_drag()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_by(1.0 / wheel_zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_by(wheel_zoom_step)
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_mouse_panning = button.pressed
				_panning = button.pressed
				_last_mouse = button.position
		return

	if event is InputEventMouseMotion and _mouse_panning:
		var motion := event as InputEventMouseMotion
		_pan_by_pixels(_last_mouse, motion.position)
		_last_mouse = motion.position
		return

	if event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		if magnify.factor > 0.01:
			_zoom_by(1.0 / magnify.factor)


func _refresh_pinch_baseline() -> void:
	if _touches.size() >= 2:
		var points := _first_two_touches()
		_pinch_mid = (points[0] + points[1]) * 0.5
		_pinch_distance = points[0].distance_to(points[1])
		_pinch_valid = _pinch_distance > 1.0
	else:
		_pinch_valid = false


func _first_two_touches() -> Array:
	var points: Array = []
	for key in _touches:
		points.append(_touches[key])
		if points.size() == 2:
			break
	return points


func _handle_two_finger_drag() -> void:
	var points := _first_two_touches()
	if points.size() < 2:
		return
	var mid: Vector2 = (points[0] + points[1]) * 0.5
	var distance: float = points[0].distance_to(points[1])
	if not _pinch_valid or _pinch_distance < 1.0 or distance < 1.0:
		_pinch_mid = mid
		_pinch_distance = distance
		_pinch_valid = true
		return

	_pan_by_pixels(_pinch_mid, mid)
	if absf(distance - _pinch_distance) > 0.01:
		_zoom_by(_pinch_distance / distance)

	_pinch_mid = mid
	_pinch_distance = distance


func _pan_by_pixels(from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to):
		return
	var before := screen_to_ground(from)
	var after := screen_to_ground(to)
	if not before.is_finite() or not after.is_finite():
		return
	_pan_offset += Vector3(before.x - after.x, 0.0, before.z - after.z)


func _zoom_by(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	if mode == ViewMode.TOP_DOWN:
		_size_target = clampf(_size_target * factor, top_min_size, top_max_size)
	else:
		_zoom_target = clampf(_zoom_target * factor, spectator_min_zoom, spectator_max_zoom)


# =============================================================================
# 对外接口
# =============================================================================

## 屏幕坐标 → 地面（y = 0）。正交和透视都适用。
func screen_to_ground(point: Vector2) -> Vector3:
	var origin := project_ray_origin(point)
	var normal := project_ray_normal(point)
	if absf(normal.y) < 0.0001:
		return Vector3.INF
	var travel := -origin.y / normal.y
	if travel < 0.0:
		return Vector3.INF
	return origin + normal * travel


func set_view_mode(next: ViewMode) -> void:
	if mode == next:
		return
	mode = next
	_pan_offset = Vector3.ZERO
	_panning = false
	_focus_target = _clamped_focus(_carrier_position())
	_focus_current = _focus_target
	_apply_projection()
	_apply_transform()


func set_flipped(value: bool) -> void:
	flipped = value


func toggle_view_mode() -> void:
	set_view_mode(ViewMode.SPECTATOR if mode == ViewMode.TOP_DOWN else ViewMode.TOP_DOWN)


func is_top_down() -> bool:
	return mode == ViewMode.TOP_DOWN


func set_follow(node: Node3D) -> void:
	follow = node
	_pan_offset = Vector3.ZERO


func zoom_to_top(value: float) -> void:
	_size_target = clampf(value, top_min_size, top_max_size)


func reset_view() -> void:
	mode = ViewMode.TOP_DOWN
	_size_target = top_view_size
	_zoom_target = 1.0
	_pan_offset = Vector3.ZERO
	_focus_target = _clamped_focus(_carrier_position())
	_focus_current = _focus_target
	_apply_projection()
	_apply_transform()


## 缩到最小（用于检查整块球场是否居中）。
func zoom_fully_out() -> void:
	_size_target = top_max_size
	_zoom_target = spectator_max_zoom


## 聚焦球：机位切到球的正后方（能看清拖尾和自转）。enabled=false 恢复原视角。
func set_ball_focus(enabled: bool, target: Node3D = null) -> void:
	if enabled and target != null and is_instance_valid(target):
		ball_focus = true
		chase_target = target
	else:
		ball_focus = false
		chase_target = null
		_focus_current = _clamped_focus(_carrier_position())
		_focus_target = _focus_current
	_apply_projection()
	_apply_transform()


func is_ball_focused() -> bool:
	return ball_focus


## 每帧由 main 喂入球的当前速度，决定"正后方"是哪一侧。
func set_chase_velocity(velocity: Vector3) -> void:
	chase_velocity = velocity


## 当前顶视可视高度，供验证脚本断言。
func current_view_size() -> float:
	return _size_current


## 当前取景点（跟随后的实际位置），供验证脚本断言。
func current_focus() -> Vector3:
	return _focus_current


## 当前可视范围（世界单位），供验证脚本断言"缩到最小时球场居中"。
func current_view_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var half_h: float
	if mode == ViewMode.TOP_DOWN:
		half_h = _size_current * 0.5
	else:
		half_h = spectator_base_distance * _zoom_current * tan(deg_to_rad(spectator_fov * 0.5))
	var half_w := half_h * aspect
	return Rect2(
		Vector2(_focus_current.x - half_w, _focus_current.z - half_h),
		Vector2(half_w * 2.0, half_h * 2.0))
