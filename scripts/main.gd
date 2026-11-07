extends Node3D
## FF · 主场景（手机竖屏）
##
## 一档球的完整流程：
##   PRE_SNAP（球在中锋手里，25 秒计时）→ 点「开球」
##   → SNAP（0.5 秒把球交到四分卫手上，这段时间不能传）
##   → PLAY（四分卫后撤两步；外接手跑路线；防守跟防；7 秒计时）
##       · 按住球场瞄准，松手出手（平传 / 高球 / 弃球）
##   → FLIGHT（球在空中，镜头跟球）
##   → 接住 → RUN（接球人继续跑向对面达阵区 5 码处，防守追上来拔旗）
##           · 到达 → TOUCHDOWN（横幅 + 彩带 2 秒）
##           · 被拔旗 → 下一档从拔旗处开始
##   → 没人接住 / 弃球 / 抄截 → RESULT，下一档从原启球线开始
##
## 档数规则照搬 FFSIMU：过中场（z > 25）或达阵后回到 1 档；4 档未过则换攻。

const STADIUM_SCENE := preload("res://scenes/stadium.tscn")
const ACTOR_SCENE := preload("res://scenes/player_actor.tscn")
const FOOTBALL_SCENE := preload("res://scenes/football.tscn")
const PASS_TUNING := preload("res://scripts/pass_tuning.gd")

enum Phase { PRE_SNAP, SNAP, PLAY, FLIGHT, RUN, RESULT, TOUCHDOWN, LINEUP, HUDDLE }
enum ThrowMode { FLAT, HIGH, ABORT }
enum CatchBand { LOW, CHEST, HIGH }

# --- 场地与规则（档数/计时照搬 FFSIMU） ---------------------------------------
const FIELD_MIN_X := -13.35
const FIELD_MAX_X := 13.35
const FIELD_MIN_Z := -10.0
const FIELD_MAX_Z := 60.0
const START_LOS := 5.0
const MIDFIELD_Z := 25.0
const FIRST_DOWN_YARDS := 10.0
## 达阵区在 z 50–60；扎进去 5 码算达阵。
const TOUCHDOWN_Z := 55.0
const PRE_SNAP_CLOCK := 25.0
const PLAY_CLOCK := 7.0
const CLOCK_WARNING := 5.0

# --- 开球 / 后撤 ---------------------------------------------------------------
const SNAP_SECONDS := 0.5
const DROPBACK_SECONDS := 0.8
const DROPBACK_YARDS := 2.4

# --- 传球（与 FFSIMU 一致） -----------------------------------------------------
const QB_MAX_THROW_YARDS := 45.0
const DRAG_TRIGGER_PIXELS := 40.0
const ABORT_DRAG_PIXELS := 80.0
const CATCH_RADIUS := 1.55
const FLAT_CATCH_RADIUS := 1.95
const HIGH_CATCH_BONUS := 0.55
const DEFENDER_RADIUS_MARGIN := 0.18
const ABORT_AIR_DISTANCE := 3.0
const CATCH_HEIGHT_LOW := 0.62
const CATCH_HEIGHT_CHEST := 1.22
const CATCH_HEIGHT_HIGH := 2.34

# --- 跑动 / 防守 ---------------------------------------------------------------
const RECEIVER_SPEED := 6.4
const DEFENDER_SPEED := 5.9
const FLAG_PULL_RADIUS := 1.3
const COVER_DEPTH := 1.6

const RESULT_HOLD_SECONDS := 1.6
const TOUCHDOWN_SECONDS := 3.0
const TRAIL_MAX := 40
const TRAIL_STEP := 0.07

const OFFENSE_COLOR := Color("2f7cf6")
const DEFENSE_COLOR := Color("e2543f")
const MARGIN := 28.0
const TOP_BUTTON_WIDTH := 168.0
const TOP_BUTTON_HEIGHT := 92.0

## 阵型：相对启球线的位置（x, dz）。
const FORMATION := {
	"QB": {"x": 0.0, "dz": -2.2, "side": "offense", "speed": 5.4},
	"C": {"x": 0.0, "dz": 0.0, "side": "offense", "speed": 4.6},
	"X": {"x": -9.2, "dz": 0.3, "side": "offense", "speed": RECEIVER_SPEED},
	"Y": {"x": 7.8, "dz": 0.3, "side": "offense", "speed": RECEIVER_SPEED},
	"Z": {"x": 11.2, "dz": -0.8, "side": "offense", "speed": RECEIVER_SPEED},
	"CB1": {"x": -9.4, "dz": 5.5, "side": "defense", "speed": DEFENDER_SPEED},
	"CB2": {"x": 9.2, "dz": 5.5, "side": "defense", "speed": DEFENDER_SPEED},
	"LB": {"x": 0.0, "dz": 7.2, "side": "defense", "speed": DEFENDER_SPEED},
	"SS": {"x": -4.6, "dz": 11.0, "side": "defense", "speed": DEFENDER_SPEED},
	"FS": {"x": 4.6, "dz": 13.0, "side": "defense", "speed": DEFENDER_SPEED},
}

## 当前战术（6 套战术在 scripts/playbook.gd）
var _current_play := "mesh"
## 端区入口（进入即放庆祝）和停下位置（跑进端区 6 码）
const TD_ZONE_START := 50.0
const TD_STOP_Z := 56.0
## 接球手跑完路线后的自由跑状态：{mode, dir, timer, flip}
var _free_state: Dictionary = {}
## 每个球员起跑延迟（中锋 0.7 秒）
var _route_delay: Dictionary = {}
const CENTER_DELAY := 0.7
var _chasing: Array[PlayerActor] = []
## 防守方抄截后转为持球方回攻
var _defense_possession := false
## 攻防是否互换（回攻被拔旗后换防）
var _swapped := false
## 进攻方向：+1 = 朝 +Z，-1 = 朝 -Z
var _attack_dir := 1
var _pending_swap := false
## 跑球战术是否已经交球给跑锋
var _handoff_done := false
## PLAY 阶段计时，用于跑球战术的交接球时机
var _play_elapsed := 0.0
## 列阵：目标位置 + 计时
var _lineup_targets: Dictionary = {}
var _lineup_timer := 0.0
var _series_count := 0
var _td_celebrating := false
var _td_timer := 0.0
## 比分（达阵 +6）
var _score_blue := 0
var _score_red := 0
var _score_label: Label
var _score_boards: Array = []
## 规则引擎（阶段一：镜像真实状态供调试面板读取）
var _game: GameManager
var _debug_label: Label
var _play_buttons: Dictionary = {}
var _play_grid: Control
var _play_label: Label

## 人盯人：防守球员 → 负责的外接手。
const COVERAGE := {"CB1": "X", "CB2": "Y", "LB": "C", "SS": "Z", "FS": "QB"}

# --- 状态 ---------------------------------------------------------------------
var _actors: Dictionary = {}          # 位置名 -> PlayerActor
var _qb: PlayerActor
## 两队各 5 人（蓝 = 进攻组出身，红 = 防守组出身）
var _team_blue: Array[PlayerActor] = []
var _team_red: Array[PlayerActor] = []
## 当前进攻方
var _offense_side := "blue"
const OFF_SLOTS := ["QB", "C", "X", "Y", "Z"]
const SLOT_LABELS := {"QB": "QB", "C": "C", "X": "X", "Y": "Y", "Z": "Z",
	"CB1": "CB", "CB2": "CB", "LB": "LB", "SS": "S", "FS": "S"}
const DEF_SLOTS := ["CB1", "CB2", "LB", "SS", "FS"]                 # 四分卫（QB 是关键字，另起名）
var _center: PlayerActor
var _receivers: Array[PlayerActor] = []
var _defenders: Array[PlayerActor] = []
var _holder: PlayerActor
var _thrower: PlayerActor
var _carrier: PlayerActor

var _ball: Node3D
var _phase := Phase.PRE_SNAP

var _los_z := START_LOS
var _first_down_z := START_LOS + FIRST_DOWN_YARDS
var _down := 1
var _play_clock := PRE_SNAP_CLOCK
var _clock_running := false

var _snap_elapsed := 0.0
var _dropback_elapsed := 0.0
var _dropback_active := false
var _qb_snap_origin := Vector3.ZERO

var _routes: Dictionary = {}          # PlayerActor -> Array[Vector3]
var _route_index: Dictionary = {}     # PlayerActor -> int

var _throw_mode := ThrowMode.FLAT
var _ball_mode := ThrowMode.FLAT
var _aim_index := -1
var _aim_screen_start := Vector2.ZERO
var _aim_screen_current := Vector2.ZERO
var _aim_drag := Vector2.ZERO
var _aim_world := Vector3.ZERO
var _aim_valid := false
var _ball_start := Vector3.ZERO
var _ball_land := Vector3.ZERO
var _ball_flight_time := 0.0
var _catch_band := CatchBand.CHEST
var _result_timer := 0.0
var _resolved := false
var _physics_started := false
var _pending_result := ""
var _last_result_text := ""
var _attempts := 0
var _completions := 0
var _touchdowns := 0
var _ball_focus := false
var _touch_indices: Dictionary = {}

var _hud: CanvasLayer
var _help_overlay: Control
var _view_button: Button
var _focus_button: Button
var _snap_button: Button
var _down_label: Label
var _goal_label: Label
var _clock_label: Label
var _aim_chip: Label
var _result_label: Label
var _td_banner: Label
var _confetti: CPUParticles2D
var _reticle: MeshInstance3D
var _aim_line: MeshInstance3D
var _landing_ring: MeshInstance3D
var _ball_shadow: MeshInstance3D
var _ball_marker: MeshInstance3D
var _trail: MultiMeshInstance3D
var _trail_points: Array[Vector3] = []

@onready var stadium: Stadium = $Stadium
@onready var camera: GameCamera = $Camera


func _ready() -> void:
	_game = GameManager.new()
	_game.start_match()
	_build_environment()
	_spawn_teams()
	_spawn_ball()
	_build_aim_visuals()
	_build_trail()
	_build_hud()
	_begin_series(START_LOS, 1)
	_build_debug_panel()



# =============================================================================
# 天空穹顶
# =============================================================================

const SKY_SCENE_PATH := "res://assets/models/environment/SKYDome.glb"
## 穹顶放大到能罩住整个球场（原模型半径 18）
const SKY_RADIUS := 320.0


func _build_sky_dome() -> void:
	var packed := load(SKY_SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("main: 找不到天空穹顶 " + SKY_SCENE_PATH)
		return
	var sky := packed.instantiate() as Node3D
	sky.name = "SkyDome"
	add_child(sky)

	var base_radius := 18.0
	var bounds := AABB()
	var first := true
	for node in sky.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 模型本身没有贴图/顶点色，套一个程序化天空渐变
		for surface in mesh_instance.mesh.get_surface_count():
			var sky_material := ShaderMaterial.new()
			sky_material.shader = load("res://assets/shaders/sky_dome.gdshader")
			mesh_instance.set_surface_override_material(surface, sky_material)

	if bounds.size.y > 0.01:
		base_radius = maxf(bounds.size.x, bounds.size.y) * 0.5
	var factor := SKY_RADIUS / maxf(0.01, base_radius)
	sky.scale = Vector3.ONE * factor
	# 把穹顶底边压到地面以下一点，并居中到球场中圈
	sky.position = Vector3(0.0, -6.0 - bounds.position.y * factor, 25.0)


# =============================================================================
# HDR 天空（Poliigon 棒球场全景）
# =============================================================================

const HDR_SKY_PATH := "res://assets/environment/HdrOutdoorFieldBaseballDayClear001.exr"

var _environment: Environment


## 用 HDR 全景图当天空球背景（比网格穹顶更真实，也不占几何）。
func _build_hdr_sky() -> void:
	if _environment == null:
		return
	var panorama := load(HDR_SKY_PATH) as Texture2D
	if panorama == null:
		push_warning("main: 找不到 HDR 天空 " + HDR_SKY_PATH)
		return

	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = panorama
	sky_material.energy_multiplier = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.background_energy_multiplier = 1.0
	# 天空绕 Y 转一点，让太阳落在球场侧后方
	_environment.sky_rotation = Vector3(deg_to_rad(-7.0), deg_to_rad(120.0), 0.0)


# =============================================================================
# 外围大地面 + 左右各两块训练场（没有人）
# =============================================================================

const SIDE_FIELD_X := 62.0
const GROUND_SIZE := 620.0



# =============================================================================
# 记分牌
# =============================================================================

func _build_scoreboard() -> void:
	# 两侧观众席各安装一块，牌面平行于看台、朝向球场
	for side in [-1.0, 1.0]:
		var board := MeshInstance3D.new()
		board.name = "Scoreboard"
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 3.2, 9.0)
		board.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("11151d")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		board.material_override = mat
		board.position = Vector3(side * 21.0, 5.2, 25.0)
		add_child(board)

		var left := Label3D.new()
		left.text = "蓝 0"
		left.font_size = 96
		left.pixel_size = 0.012
		left.modulate = Color("5aa9ff")
		left.position = Vector3(side * 20.6, 5.4, 22.6)
		left.no_depth_test = true
		left.rotation.y = side * PI * 0.5
		add_child(left)

		var right := Label3D.new()
		right.text = "红 0"
		right.font_size = 96
		right.pixel_size = 0.012
		right.modulate = Color("ff6b5e")
		right.position = Vector3(side * 20.6, 5.4, 27.4)
		right.no_depth_test = true
		right.rotation.y = side * PI * 0.5
		add_child(right)

		_score_boards.append([left, right])


func _add_score(team: String) -> void:
	if team == "blue":
		_score_blue += 6
	else:
		_score_red += 6
	_refresh_score()


func _refresh_score() -> void:
	if _score_label != null:
		_score_label.text = "蓝 %d : %d 红" % [_score_blue, _score_red]
	for pair in _score_boards:
		var labels: Array = pair
		if labels.size() >= 2:
			(labels[0] as Label3D).text = "蓝 %d" % _score_blue
			(labels[1] as Label3D).text = "红 %d" % _score_red

func _build_surrounding_fields() -> void:
	# 1) 一张超大的草地，把"天空"挡在地平线以外
	var ground := MeshInstance3D.new()
	ground.name = "OuterGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("123a24")
	grass.roughness = 1.0
	ground.material_override = grass
	ground.position = Vector3(0.0, -0.04, 25.0)
	add_child(ground)

	# 2) 主场上方、下方各一块空球场，和主场排成一列
	# 观众视角往远端看能看到第二座球场（和主场一样大，没有球员）
	_build_empty_field(Vector3(58.0, 0.0, 25.0))


func _build_empty_field(center: Vector3) -> void:
	var root := Node3D.new()
	root.name = "EmptyField"
	root.position = center
	add_child(root)

	var turf := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 74.0)
	turf.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("1f7a45")
	grass.roughness = 0.95
	turf.material_override = grass
	turf.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(turf)

	# 端区（蓝色）
	for zone_z in [-33.0, 33.0]:
		var zone := MeshInstance3D.new()
		var zone_plane := PlaneMesh.new()
		zone_plane.size = Vector2(30.0, 8.0)
		zone.mesh = zone_plane
		var blue := StandardMaterial3D.new()
		blue.albedo_color = Color("25406e")
		zone.material_override = blue
		zone.position = Vector3(0.0, 0.01, zone_z)
		root.add_child(zone)

	# 白线：边线 + 每 5 码一条
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("e8eef7")
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-15.0, 15.0]:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.02, 74.0)
		line.mesh = box
		line.material_override = white
		line.position = Vector3(x, 0.02, 0.0)
		root.add_child(line)
	for i in range(-6, 7):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(30.0, 0.02, 0.14)
		line.mesh = box
		line.material_override = white
		line.position = Vector3(0.0, 0.02, float(i) * 5.0)
		root.add_child(line)


# =============================================================================
# 开发者调试面板
# =============================================================================

func _build_debug_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugLayer"
	layer.layer = 20
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.name = "DebugPanel"
	_debug_label.text = ""
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.add_theme_color_override("font_color", Color("9df58f"))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_debug_label.add_theme_constant_override("outline_size", 6)
	_debug_label.position = Vector2(24.0, 300.0)
	layer.add_child(_debug_label)


func debug_toggle_panel() -> void:
	if _debug_label != null:
		_debug_label.visible = not _debug_label.visible


## 把真实状态镜像给规则引擎，并刷新面板
func _sync_debug_state() -> void:
	if _game == null or _debug_label == null:
		return
	if _debug_label.visible:
		_debug_label.text = _game.debug_lines()
func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	_environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("091525")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9cc8ff")
	environment.ambient_light_energy = 0.52
	world_environment.environment = environment
	add_child(world_environment)

	_build_surrounding_fields()
	_build_scoreboard()
	_build_sky_dome()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("ffe1b0")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)


# =============================================================================
# 球队与阵型
# =============================================================================

func _spawn_teams() -> void:
	for slot in FORMATION:
		var spec: Dictionary = FORMATION[slot]
		var actor := ACTOR_SCENE.instantiate() as PlayerActor
		actor.name = slot
		actor.actor_name = "QB" if slot == "QB" else slot
		var offense := String(spec["side"]) == "offense"
		actor.jersey_color = OFFENSE_COLOR if offense else DEFENSE_COLOR
		actor.max_speed = float(spec["speed"])
		actor.personal_outfit = offense
		# 名单里的名字和主色
		# 目前只有女球员模型，直接标位置，不用随机名字
		var label_map := {"QB": "QB", "C": "C", "X": "X", "Y": "Y", "Z": "Z",
			"CB1": "CB", "CB2": "CB", "LB": "LB", "SS": "S", "FS": "S"}
		actor.actor_name = "女" + String(SLOT_LABELS.get(slot, slot))
		actor.rotation.y = 0.0 if offense else PI
		add_child(actor)
		_actors[slot] = actor
		if offense:
			_team_blue.append(actor)
		else:
			_team_red.append(actor)
		if slot == "QB":
			_qb = actor
		elif slot == "C":
			_center = actor
		elif offense:
			_receivers.append(actor)
		else:
			_defenders.append(actor)


## 把全队摆到新的启球线上，并清掉上一档的状态。
func _begin_series(los: float, down: int) -> void:
	# 规则引擎是唯一真相：球权/方向/启球线/档数全部由它决定
	_offense_side = _game.possession_team
	_attack_dir = int(_game.get_attacking_direction())
	_swapped = _attack_dir < 0
	if camera != null:
		camera.set_flipped(_swapped)
	if stadium != null:
		stadium.set_flipped(_swapped)
	_pending_swap = false
	_apply_possession()
	# 只在真实球场边界内钳位（-10 ~ 60），不得把端区内的真实位置挪走
	_los_z = clampf(_game.field_yards_to_world(_game.line_of_scrimmage), FIELD_MIN_Z, FIELD_MAX_Z)
	_down = _game.down_number
	_first_down_z = _game.field_yards_to_world(_game.first_down_line)
	var play_formation: Dictionary = Playbook.get_play(_current_play).get("formation", {})
	for slot in FORMATION:
		var spec: Dictionary = FORMATION[slot]
		var actor: PlayerActor = _actors[slot]
		var spot_x := float(spec["x"])
		var spot_dz := float(spec["dz"])
		if play_formation.has(slot):
			var custom: Dictionary = play_formation[slot]
			spot_x = float(custom["x"])
			spot_dz = float(custom["dz"])
		spot_x = clampf(spot_x, FIELD_MIN_X + 1.0, FIELD_MAX_X - 1.0)
		var target := Vector3(spot_x * _attack_dir, 0.0, _los_z + spot_dz * _attack_dir)
		_lineup_targets[slot] = target
		if _series_count == 0:
			actor.global_position = target
		else:
			# 慢跑列阵
			actor.play_one_shot("jog", 2.5)
		actor.velocity = Vector3.ZERO
		actor.set_move_input(Vector3.ZERO)
		actor.rotation.y = 0.0 if String(spec["side"]) == "offense" else PI
		actor.set_active(false)
		# 颜色跟着"队伍"走：蓝队永远蓝、红队永远红（哪怕换了攻防）
		var is_blue := _team_blue.has(actor)
		actor.apply_colors(
			Roster.team_color("offense") if is_blue else Roster.team_color("defense"),
			Roster.player_tint(_slot_of(actor)))
		# 标签跟着"槽位"走：当前站在 QB 位就写女QB
		actor.set_display_name("女" + String(SLOT_LABELS.get(slot, slot)))
	stadium.set_line_of_scrimmage(_los_z)

	_build_routes()
	_reset_free_state()
	_chasing.clear()
	_defense_possession = false
	_td_celebrating = false
	_td_timer = 0.0

	_carrier = null
	_thrower = null
	_holder = _center
	_resolved = false
	_physics_started = false
	_pending_result = ""
	_aim_valid = false
	_aim_index = -1
	_trail_points.clear()
	_landing_ring.visible = false
	_ball_shadow.visible = false
	_ball_marker.visible = false
	_trail.visible = false
	_set_holder(_center)
	_attach_ball(_center)
	_series_count += 1
	_lineup_timer = 2.5
	# 引擎在本档开始时已经持有启球线/档数，这里只需要同步它到世界坐标（已在上面做过）
	_phase = Phase.PRE_SNAP if _series_count <= 1 else Phase.LINEUP
	_refresh_route_preview()
	_play_clock = PRE_SNAP_CLOCK
	_clock_running = true
	_dropback_active = false
	_dropback_elapsed = 0.0
	_snap_elapsed = 0.0
	if camera.is_ball_focused():
		camera.set_ball_focus(false)
	_refresh_hud()


func _spawn_ball() -> void:
	_ball = FOOTBALL_SCENE.instantiate()
	_ball.position = Vector3(0.0, 1.2, START_LOS)
	add_child(_ball)


func _hand_position(actor: PlayerActor) -> Vector3:
	if actor == null:
		return Vector3.ZERO
	# 球放在**右手**：角色朝 +Z 时右手在世界 -X 一侧。
	# 这个位置在躯干胶囊（半径 0.215）和手臂胶囊（外沿 ~0.42）之外，不会穿模。
	return actor.global_position + actor.global_transform.basis * Vector3(-0.34, 1.02, 0.32)


func _set_holder(actor: PlayerActor) -> void:
	_holder = actor
	for slot in _actors:
		(_actors[slot] as PlayerActor).set_active(_actors[slot] == actor)
	camera.set_follow(actor)


func _attach_ball(actor: PlayerActor) -> void:
	if actor == null:
		return
	# 绑在右手，跟随角色朝向（不强制水平）
	_ball.call("hold_at", _hand_position(actor), actor.global_transform.basis)


# =============================================================================
# 开球
# =============================================================================

func _on_snap_pressed() -> void:
	if _phase != Phase.PRE_SNAP:
		return
	_begin_snap()


func _begin_snap() -> void:
	# 中锋背对四分卫做开球动作（0.5 秒窗口内播完）
	if _center != null:
		_center.play_one_shot("snap", SNAP_SECONDS)
	_clear_route_preview()
	# 开球时把上一档被拔掉的腰旗恢复
	for slot in _actors:
		(_actors[slot] as PlayerActor).reset_flags()
	if _game != null and _game.match_state != GameManager.State.READY_TO_SNAP:
		return
	_handoff_done = false
	_play_elapsed = 0.0
	_phase = Phase.SNAP
	_snap_elapsed = 0.0
	if _game != null:
		_game.start_play()
	_holder = _center
	_qb_snap_origin = _qb.global_position
	_play_clock = PLAY_CLOCK
	_clock_running = true
	# 外接手在开球瞬间起跑。
	for receiver in _receivers:
		_route_index[receiver] = 0
	_refresh_hud()


func _advance_snap(delta: float) -> void:
	_snap_elapsed += delta
	var t := clampf(_snap_elapsed / SNAP_SECONDS, 0.0, 1.0)
	var from := _hand_position(_center)
	var to := _hand_position(_qb)
	_ball.call("hold_at", from.lerp(to, t) + Vector3(0.0, sin(t * PI) * 0.12, 0.0), _qb.global_transform.basis)
	if t >= 1.0:
		_holder = _qb
		_set_holder(_qb)
		_phase = Phase.PLAY
		_dropback_active = true
		_dropback_elapsed = 0.0


## 四分卫后撤：从开球位置往回退 DROPBACK_YARDS，全程可出手。
## 当前战术是否是跑球
func _play_is_run() -> bool:
	return String(Playbook.get_play(_current_play).get("kind", "pass")) == "run"


## QB 把球交给跑锋（Y 槽位），随后由跑锋持球推进
func _begin_handoff() -> void:
	if _handoff_done:
		return
	var rb: PlayerActor = _actors.get("Y") as PlayerActor
	if rb == null or _qb == null:
		return
	_handoff_done = true
	_begin_run_after_catch(rb)
	_show_toast("交球给跑锋", Color("9fd2ff"))
	if _game != null:
		_game.call("_log", "[PLAY %03d] HANDOFF TO RB AT %.1f" % [_game.get("play_id"), _game.get("ball_position_yards")])


func _advance_dropback(delta: float) -> void:
	if not _dropback_active:
		return
	_dropback_elapsed += delta
	var t := clampf(_dropback_elapsed / DROPBACK_SECONDS, 0.0, 1.0)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	_qb.global_position = Vector3(
		_qb_snap_origin.x,
		0.0,
		_qb_snap_origin.z - DROPBACK_YARDS * eased)
	if t >= 1.0:
		_dropback_active = false
		# 跑球战术：后撤步结束后自动交球给跑锋
		if _play_is_run() and not _handoff_done:
			_begin_handoff()


# =============================================================================
# 瞄准与出手
# =============================================================================

func _can_throw() -> bool:
	return _phase == Phase.PLAY


func _begin_aim(screen: Vector2) -> void:
	if not _can_throw():
		return
	var ground: Vector3 = camera.screen_to_ground(screen)
	if not ground.is_finite():
		return
	_aim_screen_start = screen
	_aim_screen_current = screen
	_aim_drag = Vector2.ZERO
	_aim_world = _clamp_throw_target(ground)
	_aim_valid = true
	_throw_mode = ThrowMode.FLAT
	_refresh_aim()


func _update_aim(screen: Vector2) -> void:
	if not _aim_valid:
		return
	_aim_screen_current = screen
	_aim_drag = _aim_screen_current - _aim_screen_start
	_throw_mode = _classify_throw(_aim_drag)
	var ground: Vector3 = camera.screen_to_ground(_aim_screen_start)
	if ground.is_finite():
		_aim_world = _clamp_throw_target(ground)
	_refresh_aim()


func _classify_throw(drag: Vector2) -> ThrowMode:
	if drag.y >= DRAG_TRIGGER_PIXELS:
		return ThrowMode.HIGH
	if drag.y <= -ABORT_DRAG_PIXELS:
		return ThrowMode.ABORT
	return ThrowMode.FLAT


func _clamp_throw_target(point: Vector3) -> Vector3:
	var origin := _hand_position(_holder)
	var flat := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	if flat.length() > QB_MAX_THROW_YARDS:
		flat = flat.normalized() * QB_MAX_THROW_YARDS
	var target := Vector3(origin.x + flat.x, 0.0, origin.z + flat.z)
	target.x = clampf(target.x, FIELD_MIN_X + 0.7, FIELD_MAX_X - 0.7)
	target.z = clampf(target.z, FIELD_MIN_Z + 1.0, FIELD_MAX_Z - 1.0)
	return target


func _release_throw() -> void:
	if not _aim_valid:
		return
	_aim_index = -1
	_aim_valid = false
	_release_aim_target()
	_start_throw()


func _start_throw() -> void:
	# 一出手就停下后撤。
	_dropback_active = false
	var start := _hand_position(_holder)
	_ball_mode = _throw_mode
	_thrower = _holder
	_resolved = false
	_physics_started = false
	_pending_result = ""
	_trail_points.clear()
	_clock_running = false
	camera.set_follow(_ball)

	if _throw_mode == ThrowMode.ABORT:
		var ground_release: Vector3 = camera.screen_to_ground(_aim_screen_current)
		var direction := Vector3.ZERO
		if ground_release.is_finite():
			direction = ground_release - _aim_world
			direction.y = 0.0
		if direction.length() < 0.2:
			direction = Vector3(0.0, 0.0, 1.0)
		direction = direction.normalized()
		var target := _aim_world + direction * ABORT_AIR_DISTANCE
		target.x = clampf(target.x, FIELD_MIN_X + 0.7, FIELD_MAX_X - 0.7)
		target.z = clampf(target.z, FIELD_MIN_Z + 1.0, FIELD_MAX_Z - 1.0)
		target.y = 0.20
		_ball_flight_time = clampf(start.distance_to(target) / 20.0, 0.38, 1.05)
		_catch_band = CatchBand.LOW
		_ball_start = start
		_ball_land = target
		_ball.call("start_flight", start, target, _ball_flight_time)
		_phase = Phase.FLIGHT
		_show_landing_ring()
		return

	_catch_band = _roll_catch_band(_throw_mode == ThrowMode.HIGH)
	var target := Vector3(_aim_world.x, _catch_height(_catch_band), _aim_world.z)
	_ball_flight_time = PASS_TUNING.flight_time(start.distance_to(target), _throw_mode == ThrowMode.HIGH)
	if _throw_mode == ThrowMode.HIGH:
		# 高球：拖得越远，滞空越长 → 同样落点下抛物线越高。
		var boost := clampf((_aim_drag.y - DRAG_TRIGGER_PIXELS) / 160.0, 0.0, 1.0)
		_ball_flight_time *= 1.0 + 0.9 * boost
	_ball_start = start
	_ball_land = target
	_ball.call("start_flight", start, target, _ball_flight_time)
	_phase = Phase.FLIGHT
	_show_landing_ring()


func _roll_catch_band(high_ball: bool) -> CatchBand:
	if high_ball:
		var roll := randf()
		if roll < 0.58:
			return CatchBand.HIGH
		if roll < 0.88:
			return CatchBand.CHEST
		return CatchBand.LOW
	return CatchBand.CHEST if randf() < 0.58 else CatchBand.LOW


func _catch_height(band: CatchBand) -> float:
	match band:
		CatchBand.LOW:
			return CATCH_HEIGHT_LOW
		CatchBand.HIGH:
			return CATCH_HEIGHT_HIGH
		_:
			return CATCH_HEIGHT_CHEST


# =============================================================================
# 判定
# =============================================================================

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 到达落点时的判定。返回 true 表示球已经被人接住。
func _resolve_pass() -> bool:
	_attempts += 1
	var land := Vector3(_ball_land.x, 0.0, _ball_land.z)

	var receiver_radius := CATCH_RADIUS
	if _ball_mode == ThrowMode.HIGH:
		receiver_radius += HIGH_CATCH_BONUS
	elif _ball_mode == ThrowMode.FLAT:
		receiver_radius = FLAT_CATCH_RADIUS
	var defender_radius := maxf(0.8, receiver_radius - DEFENDER_RADIUS_MARGIN)

	var receiver: PlayerActor = null
	var receiver_distance := 999.0
	for player in _receivers:
		if player == _thrower:
			continue
		var distance := _flat_distance(player.global_position, land)
		if distance < receiver_distance:
			receiver_distance = distance
			receiver = player

	var defender: PlayerActor = null
	var defender_distance := 999.0
	for player in _defenders:
		var distance := _flat_distance(player.global_position, land)
		if distance < defender_distance:
			defender_distance = distance
			defender = player

	var pressure := 0.0
	if defender != null and defender_distance < defender_radius:
		pressure = 1.0 - defender_distance / defender_radius

	if defender != null and defender_distance <= defender_radius:
		var closeness := 1.0 - defender_distance / defender_radius
		var pick_chance := clampf(
			0.15 + closeness * 0.55 + (0.08 if _ball_mode == ThrowMode.FLAT else 0.0),
			0.0, 0.9)
		if randf() < pick_chance:
			# 抄截：这一档直接结束。
			# 抄截成功：防守球员持球回攻
			_begin_interception(defender)
			return true

	if receiver != null and receiver_distance <= receiver_radius:
		var chance := clampf(0.95 - pressure * 0.35 - (0.10 if _ball_mode == ThrowMode.HIGH else 0.0), 0.30, 0.95)
		if randf() <= chance:
			_completions += 1
			_begin_run_after_catch(receiver)
			return true

	_pending_result = "传球未完成 · %d/%d" % [_completions, _attempts]
	# 四分卫懊恼一下
	if _qb != null:
		_qb.play_one_shot("defeat", RESULT_HOLD_SECONDS)
	return false


func _start_bounce() -> void:
	var velocity: Vector3 = _ball.get("flight_velocity")
	_ball.call("begin_physics", velocity * 0.85)
	if _phase == Phase.FLIGHT:
		# 统一事件入口：未完成传球交给规则引擎（档数 +1、球回开球线、不换权）
		if _ball_mode != ThrowMode.ABORT:
			_end_down(_los_z, "传球未完成")
			return
		_show_result("弃球")
		_phase = Phase.RESULT
		_result_timer = RESULT_HOLD_SECONDS


# =============================================================================
# 接球后推进 / 拔旗 / 达阵
# =============================================================================

func _begin_run_after_catch(receiver: PlayerActor) -> void:
	_carrier = receiver
	_set_holder(receiver)
	_attach_ball(receiver)
	_phase = Phase.RUN
	_result_timer = 0.0
	_clock_running = false
	# 除了接球的人，其他人站住；离接球人最近的两名防守球员继续追
	_reset_free_state()
	for player in _receivers:
		player.set_move_input(Vector3.ZERO)
	for defender in _defenders:
		defender.set_move_input(Vector3.ZERO)
	_chasing.clear()
	var ranked: Array = _defenders.duplicate()
	ranked.sort_custom(func(a, b):
		return _flat_distance(a.global_position, receiver.global_position) < _flat_distance(b.global_position, receiver.global_position))
	for i in mini(2, ranked.size()):
		_chasing.append(ranked[i] as PlayerActor)
	_show_toast("接球成功 · 继续跑向达阵区", Color("a6f7bb"))



# =============================================================================
# 抄截回攻（防守方持球，进攻方追人拔旗）
# =============================================================================

func _begin_interception(defender: PlayerActor) -> void:
	_defense_possession = true
	_carrier = defender
	_chasing.clear()
	_reset_free_state()
	# 距离最近的进攻球员去追
	var ranked: Array = _receivers.duplicate()
	if _qb != null:
		ranked.append(_qb)
	ranked.sort_custom(func(a, b):
		return _flat_distance(a.global_position, defender.global_position) < _flat_distance(b.global_position, defender.global_position))
	for i in mini(2, ranked.size()):
		_chasing.append(ranked[i] as PlayerActor)
	_ball.call("begin_physics", Vector3(0.0, 2.0, 0.0))
	_attach_ball(defender)
	_set_holder(defender)
	_phase = Phase.RUN
	_result_timer = 0.0
	_clock_running = false
	_show_toast("抄截！防守方回攻", Color("ffb27a"))


func _advance_return(delta: float) -> void:
	if _carrier == null:
		return
	_clamp_defenders()
	# 往进攻方那一侧的端区跑（z 负方向）
	var return_dir := -_attack_dir
	var goal_z := 55.0 if return_dir > 0 else -5.0
	var goal := Vector3(_carrier.global_position.x * 0.6, 0.0, goal_z)
	var to_goal := goal - _carrier.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.4:
		_carrier.set_move_input(to_goal.normalized())
	else:
		_carrier.set_move_input(Vector3.ZERO)

	var closest := 999.0
	for chaser in _chasing:
		var to_carrier := _carrier.global_position - chaser.global_position
		to_carrier.y = 0.0
		if to_carrier.length() > 0.4:
			chaser.set_move_input(to_carrier.normalized())
		else:
			chaser.set_move_input(Vector3.ZERO)
		closest = minf(closest, to_carrier.length())
	for other in _defenders:
		if other == _carrier:
			continue
		if not _chasing.has(other):
			other.set_move_input(Vector3.ZERO)
	for receiver in _receivers:
		if not _chasing.has(receiver):
			receiver.set_move_input(Vector3.ZERO)
	if _qb != null and not _chasing.has(_qb):
		_qb.set_move_input(Vector3.ZERO)

	_attach_ball(_carrier)

	# 防守方达阵（进攻方那一侧端区）
	var return_yards := _game.world_to_field_yards(_carrier.global_position.z)
	# 截球后引擎已把球权给回攻方，达阵判定必须用当前持球方
	var return_team := _game.possession_team
	if not _td_celebrating and _game.is_opponent_endzone(return_team, return_yards):
		_touchdowns += 1
		# 防守方（非当前进攻方）得分
		var scorer := "blue" if _offense_side == "red" else "red"
		if _game != null:
			_game.end_play("TOUCHDOWN", _game.world_to_field_yards(_carrier.global_position.z))
		_score_blue = _game.score_blue
		_score_red = _game.score_red
		_refresh_score()
		if scorer == _offense_side:
			_pending_swap = true
		_show_touchdown()
		_td_timer = TOUCHDOWN_SECONDS
		_td_celebrating = true
		_carrier.set_move_input(Vector3.ZERO)
		return
	if _td_celebrating:
		_td_timer -= delta
		if _td_timer <= 0.0:
			_td_celebrating = false
			_hide_touchdown()
			_next_los = START_LOS
			_next_down = 1
			_turnover = false
			_finish_reset()
		return
	if closest <= FLAG_PULL_RADIUS:
		var mode := randi() % 3
		_carrier.pull_flags(mode)
		_show_toast("腰旗被拔掉（%s）· 交换球权" % ["左侧", "右侧", "两侧"][mode], Color("ffb27a"))
		# 截球时球权已经换给防守方，回攻结束只是开新系列（不能再次换权）
		_game.end_play("FLAG_PULL", _game.world_to_field_yards(_carrier.global_position.z))
		_phase = Phase.RESULT
		_result_timer = RESULT_HOLD_SECONDS
		_defense_possession = false


## 列阵过渡：球员慢跑到各自位置
func _advance_lineup(delta: float) -> void:
	_lineup_timer -= delta
	var all_arrived := true
	for slot in _lineup_targets:
		var actor: PlayerActor = _actors[slot]
		var target: Vector3 = _lineup_targets[slot]
		var to_target := target - actor.global_position
		to_target.y = 0.0
		if to_target.length() > 0.6:
			actor.set_move_input(to_target.normalized())
			all_arrived = false
		else:
			actor.set_move_input(Vector3.ZERO)
	if _center != null:
		_attach_ball(_center)
	if all_arrived or _lineup_timer <= 0.0:
		for slot in _lineup_targets:
			var actor: PlayerActor = _actors[slot]
			actor.global_position = _lineup_targets[slot]
			actor.set_move_input(Vector3.ZERO)
		_phase = Phase.PRE_SNAP
		_refresh_hud()

func _advance_run(delta: float) -> void:
	if _carrier == null:
		return
	# 接球人朝达阵区跑；防守全力追。
	var goal_z := 55.0 if _attack_dir > 0 else -5.0
	var goal := Vector3(_carrier.global_position.x * 0.6, 0.0, goal_z)
	var to_goal := goal - _carrier.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.4:
		_carrier.set_move_input(to_goal.normalized())
	else:
		_carrier.set_move_input(Vector3.ZERO)

	var closest := 999.0
	for defender in _defenders:
		if _chasing.has(defender):
			var to_carrier := _carrier.global_position - defender.global_position
			to_carrier.y = 0.0
			if to_carrier.length() > 0.4:
				defender.set_move_input(to_carrier.normalized())
			else:
				defender.set_move_input(Vector3.ZERO)
		else:
			defender.set_move_input(Vector3.ZERO)
		closest = minf(closest, _flat_distance(defender.global_position, _carrier.global_position))
	_clamp_defenders()

	_attach_ball(_carrier)

	# 进入端区立刻放庆祝动画，但人继续往端区里跑
	var carrier_yards := _game.world_to_field_yards(_carrier.global_position.z)
	if not _td_celebrating and _game.is_opponent_endzone(_game.possession_team, carrier_yards):
		_td_celebrating = true
		_td_timer = TOUCHDOWN_SECONDS
		_touchdowns += 1
		if _game != null:
			_game.end_play("TOUCHDOWN", _game.world_to_field_yards(_carrier.global_position.z))
		_score_blue = _game.score_blue
		_score_red = _game.score_red
		_refresh_score()
		_pending_swap = true
		_clock_running = false
		_show_touchdown()
		for player in _receivers:
			player.set_move_input(Vector3.ZERO)
		for defender in _defenders:
			defender.set_move_input(Vector3.ZERO)
	if _td_celebrating:
		_td_timer -= delta
		var stop_z := 55.0 if _attack_dir > 0 else -5.0
		if (stop_z - _carrier.global_position.z) * _attack_dir <= 0.0:
			_carrier.set_move_input(Vector3.ZERO)
		if _td_timer <= 0.0:
			_td_celebrating = false
			_hide_touchdown()
			_next_los = START_LOS
			_next_down = 1
			_turnover = false
			_finish_reset()
		return
	if closest <= FLAG_PULL_RADIUS:
		# 随机拔掉左 / 右 / 两边的腰旗，拔掉的就隐藏
		var mode := randi() % 3
		_carrier.pull_flags(mode)
		var side: String = ["左侧", "右侧", "两侧"][mode]
		_show_toast("腰旗被拔掉（%s）" % side, Color("ffb27a"))
		_finish_carrier_play()
		return
	# 兜底：跑太久也算死球
	_result_timer += delta
	if _result_timer > 12.0:
		_end_down(clampf(_carrier.global_position.z, FIELD_MIN_Z + 0.5, FIELD_MAX_Z - 0.5), "死球")


func _trigger_touchdown() -> void:
	if _phase == Phase.TOUCHDOWN:
		return
	_touchdowns += 1
	_phase = Phase.TOUCHDOWN
	_result_timer = TOUCHDOWN_SECONDS
	_clock_running = false
	_carrier.set_move_input(Vector3.ZERO)
	for defender in _defenders:
		defender.set_move_input(Vector3.ZERO)
	_show_touchdown()
	# 达阵后回到本方 5 码线、1 档；真正的复位等 2 秒庆祝播完再做。
	_next_los = START_LOS
	_next_down = 1
	_turnover = false


## 普通进攻持球人死球：先判是否在本方端区（Safety），再走普通拔旗
func _finish_carrier_play() -> void:
	var z := clampf(_carrier.global_position.z, FIELD_MIN_Z + 0.5, FIELD_MAX_Z - 0.5)
	var yards := _game.world_to_field_yards(z)
	if _game.is_own_endzone(_game.possession_team, yards):
		_end_down(z, "安全分")
	else:
		_end_down(z, "被拔旗")


func _end_down(spot: float, reason: String) -> void:
	# 本档已经结束（引擎已锁定）→ 不再提交任何本档事件
	if _game != null and _game.play_already_ended:
		return
	if _game != null and _game.match_state not in [GameManager.State.BALL_IN_PLAY, GameManager.State.PASS_IN_AIR, GameManager.State.RETURN_IN_PROGRESS]:
		return
	if _phase == Phase.RESULT or _phase == Phase.TOUCHDOWN:
		return
	_show_result(reason)
	_phase = Phase.RESULT
	_result_timer = RESULT_HOLD_SECONDS
	_clock_running = false
	for player in _receivers:
		player.set_move_input(Vector3.ZERO)
	for defender in _defenders:
		defender.set_move_input(Vector3.ZERO)
	if _carrier != null:
		_carrier.set_move_input(Vector3.ZERO)
	if _qb != null:
		_qb.set_move_input(Vector3.ZERO)

	# 档数规则照搬 FFSIMU：被拔旗才推进启球线；过中场回到 1 档；4 档不过换攻。
	var next_down := _down + 1
	var next_los := _los_z
	if reason == "被拔旗":
		next_los = spot
		next_down = 1 if next_los > MIDFIELD_Z else _down + 1
	var turnover := false
	if next_down > 4:
		next_los = START_LOS
		next_down = 1
		turnover = true
	# 统一交给规则引擎处理（事件类型决定行为）
	var event := "FLAG_PULL"
	if reason == "传球未完成":
		event = "INCOMPLETE_PASS"
	elif reason == "安全分":
		event = "SAFETY"
	elif reason == "死球":
		event = "OUT_OF_BOUNDS"
	_game.end_play(event, _game.world_to_field_yards(spot))
	next_los = _game.field_yards_to_world(_game.line_of_scrimmage)
	next_down = _game.down_number
	turnover = false
	_next_los = next_los
	_next_down = next_down
	_turnover = turnover
	_pending_series = true


var _next_los := START_LOS
var _next_down := 1
var _turnover := false
var _pending_series := false


# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)

	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# 左上：档数 + 计时器
	var state_panel := PanelContainer.new()
	state_panel.name = "StatePanel"
	state_panel.anchor_left = 0.0
	state_panel.anchor_top = 0.0
	state_panel.anchor_right = 0.0
	state_panel.anchor_bottom = 0.0
	state_panel.offset_left = MARGIN
	state_panel.offset_top = MARGIN
	state_panel.offset_right = MARGIN + 232.0
	state_panel.offset_bottom = MARGIN + 132.0
	state_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(state_panel)

	var state_column := VBoxContainer.new()
	state_column.name = "StateColumn"
	state_column.add_theme_constant_override("separation", 2)
	state_panel.add_child(state_column)

	_down_label = Label.new()
	_down_label.name = "DownLabel"
	_down_label.text = "1ST DOWN"
	_down_label.add_theme_font_size_override("font_size", 28)
	_down_label.add_theme_color_override("font_color", Color("ff6b78"))
	state_column.add_child(_down_label)

	_goal_label = Label.new()
	_goal_label.name = "GoalLabel"
	_goal_label.text = "距首攻 10 码"
	_goal_label.add_theme_font_size_override("font_size", 18)
	_goal_label.add_theme_color_override("font_color", Color("9fb3cd"))
	state_column.add_child(_goal_label)

	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.text = "蓝 0 : 0 红"
	_score_label.add_theme_font_size_override("font_size", 26)
	_score_label.add_theme_color_override("font_color", Color("ffe27a"))
	root.add_child(_score_label)
	_score_label.anchor_left = 0.0
	_score_label.anchor_top = 0.0
	_score_label.offset_left = MARGIN + 244.0
	_score_label.offset_top = MARGIN + 6.0
	_score_label.offset_right = MARGIN + 520.0
	_score_label.offset_bottom = MARGIN + 46.0

	_clock_label = Label.new()
	_clock_label.name = "ClockLabel"
	_clock_label.text = "25"
	_clock_label.add_theme_font_size_override("font_size", 42)
	_clock_label.add_theme_color_override("font_color", Color("6df58f"))
	state_column.add_child(_clock_label)

	# 右上：可下拉的菜单（收起时只露出一个标签）
	_menu_tab = _make_button("菜单 ▾", TOP_BUTTON_WIDTH, 72.0, 24)
	_menu_tab.name = "MenuTab"
	_menu_tab.anchor_left = 1.0
	_menu_tab.anchor_right = 1.0
	_menu_tab.offset_left = -MARGIN - TOP_BUTTON_WIDTH
	_menu_tab.offset_right = -MARGIN
	_menu_tab.offset_top = 0.0
	_menu_tab.offset_bottom = 72.0
	_menu_tab.gui_input.connect(_on_menu_tab_input)
	root.add_child(_menu_tab)

	_menu_drawer = Control.new()
	_menu_drawer.name = "TopDrawer"
	_menu_drawer.anchor_left = 1.0
	_menu_drawer.anchor_right = 1.0
	_menu_drawer.offset_left = -MARGIN - TOP_BUTTON_WIDTH
	_menu_drawer.offset_right = -MARGIN
	_menu_drawer.offset_top = -410.0
	_menu_drawer.offset_bottom = -410.0
	_menu_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu_drawer)

	var menu_items := [
		{"name": "HelpButton", "text": "帮助", "size": 28, "callable": Callable(self, "show_help")},
		{"name": "ViewButton", "text": "观众视角", "size": 26, "callable": Callable(self, "_toggle_view")},
		{"name": "FocusButton", "text": "聚焦球", "size": 26, "callable": Callable(self, "_toggle_ball_focus")},
		{"name": "WardrobeButton", "text": "衣柜", "size": 26, "callable": Callable(self, "open_wardrobe")},
	]
	for index in menu_items.size():
		var spec: Dictionary = menu_items[index]
		var item := _make_button(String(spec["text"]), TOP_BUTTON_WIDTH, TOP_BUTTON_HEIGHT, int(spec["size"]))
		item.name = String(spec["name"])
		item.anchor_left = 0.0
		item.anchor_right = 0.0
		item.anchor_top = 0.0
		item.anchor_bottom = 0.0
		item.offset_left = 0.0
		item.offset_right = TOP_BUTTON_WIDTH
		item.offset_top = index * (TOP_BUTTON_HEIGHT + 10.0)
		item.offset_bottom = item.offset_top + TOP_BUTTON_HEIGHT
		item.pressed.connect(spec["callable"])
		_menu_drawer.add_child(item)
		match String(spec["name"]):
			"ViewButton":
				_view_button = item
			"FocusButton":
				_focus_button = item

	# 开球：大圆形、半透明，位置往左上挪
	_snap_button = _make_button("开球", 200.0, 200.0, 40)
	_snap_button.name = "SnapButton"
	_snap_button.add_theme_stylebox_override("normal", _circle_style(Color(0.16, 0.45, 0.75, 0.45)))
	_snap_button.add_theme_stylebox_override("hover", _circle_style(Color(0.22, 0.58, 0.92, 0.62)))
	_snap_button.add_theme_stylebox_override("pressed", _circle_style(Color(0.12, 0.34, 0.58, 0.75)))
	_snap_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_snap_button.anchor_left = 1.0
	_snap_button.anchor_top = 1.0
	_snap_button.anchor_right = 1.0
	_snap_button.anchor_bottom = 1.0
	_snap_button.offset_left = -MARGIN - 200.0 - 80.0
	_snap_button.offset_top = -MARGIN - 200.0 - 80.0
	_snap_button.offset_right = -MARGIN - 80.0
	_snap_button.offset_bottom = -MARGIN - 80.0
	_snap_button.pressed.connect(_on_snap_pressed)
	root.add_child(_snap_button)

	# 左下：可右拉展开的战术板
	_play_tab = _make_button("战术板", 120.0, 96.0, 24)
	_play_tab.name = "PlayTab"
	_play_tab.anchor_bottom = 1.0
	_play_tab.anchor_top = 1.0
	_play_tab.offset_left = 0.0
	_play_tab.offset_right = 120.0
	_play_tab.offset_top = -MARGIN - 108.0 - 40.0 - 96.0
	_play_tab.offset_bottom = -MARGIN - 108.0 - 40.0
	_play_tab.gui_input.connect(_on_play_tab_input)
	root.add_child(_play_tab)

	_play_grid = VBoxContainer.new()
	_play_grid.name = "PlayDrawer"
	_play_grid.anchor_bottom = 1.0
	_play_grid.anchor_top = 1.0
	_play_grid.offset_left = -220.0
	_play_grid.offset_right = 0.0
	_play_grid.offset_top = -MARGIN - 108.0 - 40.0 - 390.0
	_play_grid.offset_bottom = -MARGIN - 108.0 - 40.0
	_play_grid.add_theme_constant_override("separation", 8)
	root.add_child(_play_grid)

	_play_buttons.clear()
	for play in Playbook.PLAYS:
		var play_button := _make_button(String(play["name"]), 210.0, 58.0, 22)
		play_button.custom_minimum_size = Vector2(210, 58)
		play_button.pressed.connect(_select_play.bind(String(play["id"])))
		_play_grid.add_child(play_button)
		_play_buttons[String(play["id"])] = play_button
	_refresh_play_buttons()

	_aim_chip = Label.new()
	_aim_chip.name = "AimChip"
	_aim_chip.visible = false
	_aim_chip.add_theme_font_size_override("font_size", 30)
	_aim_chip.add_theme_color_override("font_color", Color("e8f4ff"))
	_aim_chip.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.09, 0.95))
	_aim_chip.add_theme_constant_override("outline_size", 10)
	root.add_child(_aim_chip)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.visible = false
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 34)
	_result_label.add_theme_color_override("font_color", Color("ffe8a8"))
	_result_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.09, 0.95))
	_result_label.add_theme_constant_override("outline_size", 12)
	_result_label.offset_left = -280.0
	_result_label.offset_right = 280.0
	_result_label.offset_top = 200.0
	_result_label.offset_bottom = 252.0
	root.add_child(_result_label)

	_build_touchdown_overlay(root)
	_build_help_overlay(root)


func _build_touchdown_overlay(root: Control) -> void:
	_td_banner = Label.new()
	_td_banner.name = "TouchdownBanner"
	_td_banner.visible = false
	_td_banner.text = "TouchDown"
	_td_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_td_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_td_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_td_banner.offset_left = -320.0
	_td_banner.offset_right = 320.0
	_td_banner.offset_top = -70.0
	_td_banner.offset_bottom = 70.0
	_td_banner.pivot_offset = Vector2(320.0, 70.0)
	_td_banner.add_theme_font_size_override("font_size", 84)
	_td_banner.add_theme_color_override("font_color", Color("ffe27a"))
	_td_banner.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02, 0.95))
	_td_banner.add_theme_constant_override("outline_size", 14)
	_td_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_td_banner)

	# 从字样四周爆出、落向屏幕底端的彩带
	_confetti = CPUParticles2D.new()
	_confetti.name = "Confetti"
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 220
	_confetti.lifetime = 3.2
	_confetti.explosiveness = 0.95
	_confetti.direction = Vector2(0.0, -1.0)
	_confetti.spread = 180.0
	_confetti.initial_velocity_min = 480.0
	_confetti.initial_velocity_max = 980.0
	_confetti.gravity = Vector2(0.0, 620.0)
	_confetti.scale_amount_min = 2.5
	_confetti.scale_amount_max = 6.5
	# 每个粒子从这条渐变里随机取一个颜色 → 各种颜色的彩带
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.36, 0.54, 0.72, 0.9, 1.0])
	ramp.colors = PackedColorArray([
		Color("ff4d5e"), Color("ffa23a"), Color("ffe23a"),
		Color("4dd97a"), Color("4db8ff"), Color("b478ff"), Color("ff6fd8"),
	])
	_confetti.color = Color.WHITE
	_confetti.color_initial_ramp = ramp
	_confetti.angular_velocity_min = -540.0
	_confetti.angular_velocity_max = 540.0
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_confetti.emission_sphere_radius = 12.0
	_confetti.position = Vector2(360.0, 640.0)
	root.add_child(_confetti)


func _show_touchdown() -> void:
	if _td_banner != null:
		_td_banner.visible = true
		_td_banner.modulate = Color(1, 1, 1, 1)
		_td_banner.scale = Vector2(0.55, 0.55)
		var tween := create_tween()
		tween.tween_property(_td_banner, "scale", Vector2.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _confetti != null:
		_confetti.emitting = false
		_confetti.restart()
		_confetti.emitting = true


func _hide_touchdown() -> void:
	if _td_banner != null:
		_td_banner.visible = false
	if _confetti != null:
		_confetti.emitting = false


func _refresh_hud() -> void:
	if _down_label == null:
		return
	var ordinals := ["1ST", "2ND", "3RD", "4TH"]
	_down_label.text = "%s DOWN" % ordinals[clampi(_down - 1, 0, 3)]
	if _first_down_z >= FIELD_MAX_Z - 0.5:
		_goal_label.text = "冲向达阵区"
	else:
		_goal_label.text = "距首攻 %d 码" % _game.get_yards_to_go()
	_snap_button.visible = _phase == Phase.PRE_SNAP
	_snap_button.disabled = _phase != Phase.PRE_SNAP
	if _play_grid != null:
		_play_grid.visible = _phase == Phase.PRE_SNAP



# =============================================================================
# 会飘的白云
# =============================================================================

const CLOUD_COUNT := 26
const CLOUD_SPEED := 5.5
const CLOUD_LOW_Y := 42.0
const CLOUD_HIGH_Y := 95.0

var _clouds: Array[Node3D] = []


func _build_clouds() -> void:
	var root := Node3D.new()
	root.name = "Clouds"
	add_child(root)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.88)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true

	for i in CLOUD_COUNT:
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		var puffs := randi_range(3, 6)
		for j in puffs:
			var puff := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 12
			sphere.rings = 6
			puff.mesh = sphere
			puff.material_override = material
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var size := randf_range(11.0, 24.0)
			puff.scale = Vector3(size, size * 0.38, size * 0.75)
			puff.position = Vector3(
				randf_range(-1.4, 1.4) * size,
				randf_range(-0.25, 0.25) * size,
				randf_range(-0.9, 0.9) * size)
			cloud.add_child(puff)
		cloud.position = _cloud_spawn_position(true)
		root.add_child(cloud)
		_clouds.append(cloud)


## 围着球场中圈撒一圈，保证任何朝向都能看到云
func _cloud_spawn_position(_anywhere: bool) -> Vector3:
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(130.0, 290.0)
	return Vector3(
		cos(angle) * radius,
		randf_range(CLOUD_LOW_Y, CLOUD_HIGH_Y),
		25.0 + sin(angle) * radius)


## 白云整体朝端区方向（+Z）飘，飘出去就从另一头绕回来。
func _advance_clouds(delta: float) -> void:
	for cloud in _clouds:
		cloud.position.z += CLOUD_SPEED * delta
		if cloud.position.z > 320.0:
			cloud.position = _cloud_spawn_position(false)

func _update_clock(delta: float) -> void:
	if _clock_running:
		_play_clock = maxf(0.0, _play_clock - delta)
		if _play_clock <= 0.0:
			_play_clock = 0.0
			_clock_running = false
	if _clock_label == null:
		return
	_clock_label.text = "%02d" % int(ceilf(_play_clock))
	var warn := _play_clock <= CLOCK_WARNING
	_clock_label.add_theme_color_override("font_color",
		Color("ff5b6b") if warn else Color("6df58f"))


func _place_top_right(control: Control, top: float) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 0.0
	control.offset_left = -MARGIN - TOP_BUTTON_WIDTH
	control.offset_top = top
	control.offset_right = -MARGIN
	control.offset_bottom = top + TOP_BUTTON_HEIGHT


func _make_button(text: String, width: float, height: float, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, height)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color("e8eef7"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffffff"))
	var radius := 22
	button.add_theme_stylebox_override("normal", _button_style(
		Color(0.07, 0.10, 0.15, 0.82), Color(0.36, 0.50, 0.72, 0.55), radius))
	button.add_theme_stylebox_override("hover", _button_style(
		Color(0.11, 0.16, 0.23, 0.9), Color(0.52, 0.68, 0.92, 0.85), radius))
	button.add_theme_stylebox_override("pressed", _button_style(
		Color(0.05, 0.08, 0.12, 0.95), Color(0.62, 0.78, 1.0, 0.95), radius))
	button.add_theme_stylebox_override("focus", _button_style(
		Color(0, 0, 0, 0), Color(0.62, 0.78, 1.0, 0.6), radius))
	return button


func _button_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.11, 0.88)
	style.border_color = Color(0.30, 0.42, 0.60, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _toggle_view() -> void:
	camera.toggle_view_mode()
	_view_button.text = "比赛视角" if not camera.is_top_down() else "观众视角"


func _toggle_ball_focus() -> void:
	_ball_focus = not _ball_focus
	_focus_button.text = "取消聚焦" if _ball_focus else "聚焦球"
	_sync_ball_focus()


func _sync_ball_focus() -> void:
	var flying := bool(_ball.get("manual_flight")) or _phase == Phase.RUN
	if _ball_focus and flying:
		camera.set_chase_velocity(_ball.get("flight_velocity"))
		if not camera.is_ball_focused():
			camera.set_ball_focus(true, _ball)
	else:
		if camera.is_ball_focused():
			camera.set_ball_focus(false)


# =============================================================================
# 结果提示
# =============================================================================

func _show_result(text: String) -> void:
	_last_result_text = text
	if _result_label != null:
		_result_label.text = text
		_result_label.modulate = Color(1, 1, 1, 1)
		_result_label.visible = true


func _show_toast(text: String, color: Color) -> void:
	_last_result_text = text
	if _result_label != null:
		_result_label.text = text
		_result_label.modulate = color
		_result_label.visible = true


# =============================================================================
# 每帧
# =============================================================================

func _physics_process(delta: float) -> void:
	_sync_debug_state()
	_update_clock(delta)

	match _phase:
		Phase.PRE_SNAP:
			_attach_ball(_center)
		Phase.SNAP:
			_advance_snap(delta)
		Phase.PLAY:
			_advance_dropback(delta)
			_play_elapsed += delta
			# 跑球战术：开球后 0.7 秒交球给跑锋（与后撤步解耦，避免依赖内部标志）
			if _play_is_run() and not _handoff_done and _play_elapsed >= 0.7:
				_begin_handoff()
			_advance_receivers()
			_advance_coverage()
			if not _aim_valid:
				_attach_ball(_qb)
		Phase.FLIGHT:
			_advance_receivers()
			_advance_coverage()
			if not _resolved and bool(_ball.get("reached_target")):
				_resolved = true
				if _ball_mode == ThrowMode.ABORT:
					_pending_result = "弃球"
				else:
					_resolve_pass()
			if bool(_ball.get("landed")) and not _physics_started:
				_physics_started = true
				_start_bounce()
		Phase.HUDDLE:
			for actor in _actors.values():
				(actor as PlayerActor).set_move_input(Vector3.ZERO)
			_attach_ball(_center)
		Phase.LINEUP:
			_advance_lineup(delta)
		Phase.RUN:
			if _defense_possession:
				_advance_return(delta)
			else:
				_advance_run(delta)
		Phase.RESULT:
			_result_timer -= delta
			if _result_label != null:
				_result_label.modulate.a = clampf(_result_timer / 0.5, 0.0, 1.0)
			if _result_timer <= 0.0:
				_finish_reset()
		Phase.TOUCHDOWN:
			_result_timer -= delta
			if _result_label != null:
				_result_label.visible = false
			if _result_timer <= 0.0:
				_hide_touchdown()
				_finish_reset()

	if _phase == Phase.FLIGHT or _phase == Phase.RUN:
		_update_ball_markers()
		_update_trail()

	_sync_ball_focus()


func _finish_reset() -> void:
	if _result_label != null:
		_result_label.visible = false
	_hide_touchdown()
	_begin_series(_next_los, _next_down)
	# 阶段 A：每档结束后进入 Huddle（玩家选战术后才列阵）
	if _series_count > 1 and _game != null and _game.match_state == GameManager.State.READY_TO_SNAP:
		_phase = Phase.HUDDLE
		_open_huddle()
	if _turnover:
		_show_toast("4 档未过，换攻", Color("ffb27a"))
		_turnover = false
	_next_los = _los_z
	_next_down = _down


func _process(_delta: float) -> void:
	if _aim_chip != null and _aim_chip.visible and _aim_valid:
		_aim_chip.position = _aim_screen_current + Vector2(24.0, -72.0)


# =============================================================================
# 路线与防守
# =============================================================================

func _advance_receivers() -> void:
	var delta := get_physics_process_delta_time()
	for receiver in _receivers:
		if receiver == _carrier:
			continue
		var state: Dictionary = _free_state.get(receiver, {})
		if state.is_empty():
			receiver.set_move_input(Vector3.ZERO)
			continue

		var delay: float = _route_delay.get(receiver, 0.0)
		if delay > 0.0:
			_route_delay[receiver] = delay - delta
			receiver.set_move_input(Vector3.ZERO)
			continue
		var mode := int(state["mode"])

		# --- 第一阶段：跑战术路线 ---
		if mode == 0:
			var route: Array = _routes.get(receiver, [])
			var index: int = _route_index.get(receiver, 0)
			if index < route.size():
				var target: Vector3 = route[index]
				var to_target := target - receiver.global_position
				to_target.y = 0.0
				if to_target.length() < 0.6:
					_route_index[receiver] = index + 1
				else:
					receiver.set_move_input(_steer_around(receiver, to_target.normalized()))
					if not _at_boundary(receiver.global_position):
						continue
			# 路线跑完（或已经撞线）→ 沿最后一段的方向一直跑
			state["mode"] = 1
			state["dir"] = _route_exit_direction(receiver)

		# --- 第二阶段：撞线后停一秒 ---
		elif mode == 2:
			state["timer"] = float(state["timer"]) - delta
			receiver.set_move_input(Vector3.ZERO)
			if float(state["timer"]) <= 0.0:
				state["mode"] = 3
			continue

		# --- 第三阶段：直线 / 横向，撞线就换向 ---
		var direction: Vector3 = state["dir"]
		receiver.set_move_input(_steer_around(receiver, direction))
		if _at_boundary(receiver.global_position):
			state["mode"] = 2
			state["timer"] = 1.0
			var position := receiver.global_position
			var flip := int(state["flip"])
			var lateral := Vector3.ZERO
			if position.x <= FIELD_MIN_X + 0.8 or position.x >= FIELD_MAX_X - 0.8:
				lateral = Vector3(0.0, 0.0, 1.0) if flip % 2 == 0 else Vector3(0.0, 0.0, -1.0)
			else:
				lateral = Vector3(1.0, 0.0, 0.0) if flip % 2 == 0 else Vector3(-1.0, 0.0, 0.0)
			state["flip"] = flip + 1
			state["dir"] = lateral


## 防守球员不许越过启球线（z 不能小于启球线）
## 防守方合法一侧的启球线位置（永远在进攻方的对面）
func defender_los_z() -> float:
	return _los_z + 0.15 if _attack_dir > 0 else _los_z - 0.15


## 防守方是否还在合法一侧
func defender_on_side(z: float) -> bool:
	return z >= defender_los_z() - 0.001 if _attack_dir > 0 else z <= defender_los_z() + 0.001


func _clamp_defenders() -> void:
	# 截球回攻时不限制
	if _defense_possession:
		return
	# 开球后允许正常追球/盯人，只在开球前约束
	if _phase != Phase.PRE_SNAP and _phase != Phase.LINEUP:
		return
	var line := defender_los_z()
	for defender in _defenders:
		if _attack_dir > 0:
			if defender.global_position.z < line:
				defender.global_position.z = line
		else:
			if defender.global_position.z > line:
				defender.global_position.z = line

func _advance_coverage() -> void:
	for defender in _defenders:
		# 开球前防守方不许移动（从输入源头阻止越线，而不是事后拉回）
		if _phase == Phase.PRE_SNAP or _phase == Phase.LINEUP:
			defender.set_move_input(Vector3.ZERO)
			continue
		var mark: PlayerActor = null
		if _carrier != null:
			mark = _carrier
		else:
			var slot := ""
			for key in COVERAGE:
				if _actors[key] == defender:
					slot = COVERAGE[key]
			mark = _actors.get(slot)
		if mark == null:
			defender.set_move_input(Vector3.ZERO)
			continue
		var goal := mark.global_position - Vector3(0.0, 0.0, COVER_DEPTH)
		var to_mark := goal - defender.global_position
		to_mark.y = 0.0
		if to_mark.length() > 0.45:
			defender.set_move_input(to_mark.normalized())
		else:
			defender.set_move_input(Vector3.ZERO)


# =============================================================================
# 瞄准视觉 / 球标记 / 拖尾
# =============================================================================

func _build_aim_visuals() -> void:
	_reticle = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.05
	ring.outer_radius = 1.22
	ring.rings = 32
	ring.ring_segments = 8
	_reticle.mesh = ring
	_reticle.material_override = _unshaded(Color("7fe3ff"))
	_reticle.visible = false
	add_child(_reticle)

	_aim_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.10, 0.02, 1.0)
	_aim_line.mesh = box
	_aim_line.material_override = _unshaded(Color("7fe3ff"))
	_aim_line.visible = false
	add_child(_aim_line)

	_landing_ring = MeshInstance3D.new()
	var landing := TorusMesh.new()
	landing.inner_radius = 0.75
	landing.outer_radius = 0.92
	landing.rings = 28
	landing.ring_segments = 8
	_landing_ring.mesh = landing
	_landing_ring.material_override = _unshaded(Color("ffd84b"))
	_landing_ring.visible = false
	add_child(_landing_ring)

	_ball_shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.20
	shadow_mesh.bottom_radius = 0.20
	shadow_mesh.height = 0.01
	shadow_mesh.radial_segments = 16
	_ball_shadow.mesh = shadow_mesh
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0, 0, 0, 0.42)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ball_shadow.material_override = shadow_material
	_ball_shadow.visible = false
	add_child(_ball_shadow)

	_ball_marker = MeshInstance3D.new()
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.40
	marker_mesh.outer_radius = 0.50
	marker_mesh.rings = 24
	marker_mesh.ring_segments = 6
	_ball_marker.mesh = marker_mesh
	_ball_marker.material_override = _unshaded(Color("eaf6ff"))
	_ball_marker.visible = false
	add_child(_ball_marker)


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.9
	return material


func _refresh_aim() -> void:
	if not _aim_valid:
		_release_aim_target()
		return
	var tint := Color("7fe3ff")
	match _throw_mode:
		ThrowMode.HIGH:
			tint = Color("9df58f")
		ThrowMode.ABORT:
			tint = Color("ffab6b")
	(_reticle.material_override as StandardMaterial3D).albedo_color = Color(tint, 0.9)
	(_aim_line.material_override as StandardMaterial3D).albedo_color = Color(tint, 0.75)

	_reticle.visible = true
	_reticle.position = Vector3(_aim_world.x, 0.035, _aim_world.z)

	var start := _hand_position(_holder)
	var target := Vector3(_aim_world.x, 0.05, _aim_world.z)
	var length := start.distance_to(target)
	_aim_line.visible = length > 0.5
	if _aim_line.visible:
		_aim_line.position = (start + target) * 0.5
		_aim_line.look_at(target, Vector3.UP)
		_aim_line.scale = Vector3(1.0, 1.0, maxf(0.01, length))

	if _aim_chip != null:
		_aim_chip.visible = true
		_aim_chip.text = "%s · %d 码" % [_throw_mode_name(), int(length)]


func _release_aim_target() -> void:
	if _reticle != null:
		_reticle.visible = false
	if _aim_line != null:
		_aim_line.visible = false
	if _aim_chip != null:
		_aim_chip.visible = false


func _throw_mode_name() -> String:
	match _throw_mode:
		ThrowMode.HIGH:
			return "高球"
		ThrowMode.ABORT:
			return "弃球"
		_:
			return "平传"


func _show_landing_ring() -> void:
	_landing_ring.visible = true
	_landing_ring.position = Vector3(_ball_land.x, 0.035, _ball_land.z)
	var tint := Color("7fe3ff")
	match _ball_mode:
		ThrowMode.HIGH:
			tint = Color("9df58f")
		ThrowMode.ABORT:
			tint = Color("ffab6b")
	(_landing_ring.material_override as StandardMaterial3D).albedo_color = Color(tint, 0.9)


func _update_ball_markers() -> void:
	var ball_position: Vector3 = _ball.global_position
	_ball_shadow.visible = true
	_ball_shadow.position = Vector3(ball_position.x, 0.025, ball_position.z)
	var height := maxf(0.0, ball_position.y)
	var shrink := clampf(1.0 - height * 0.06, 0.45, 1.0)
	_ball_shadow.scale = Vector3(shrink, 1.0, shrink)
	(_ball_shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0.42 * shrink)

	_ball_marker.visible = true
	_ball_marker.position = Vector3(ball_position.x, 0.045, ball_position.z)
	var fade := clampf(1.0 - height * 0.05, 0.35, 1.0)
	(_ball_marker.material_override as StandardMaterial3D).albedo_color = Color(0.92, 0.97, 1.0, 0.85 * fade)


func _build_trail() -> void:
	_trail = MultiMeshInstance3D.new()
	_trail.name = "BallTrail"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.instance_count = TRAIL_MAX
	var dot := SphereMesh.new()
	dot.radius = 0.022
	dot.height = 0.044
	dot.radial_segments = 6
	dot.rings = 3
	multi.mesh = dot
	_trail.multimesh = multi
	_trail.material_override = _unshaded(Color("d6ecff"))
	_trail.visible = false
	add_child(_trail)


func _update_trail() -> void:
	if _trail == null:
		return
	var ball_position: Vector3 = _ball.global_position
	if _trail_points.is_empty():
		_trail_points.append(ball_position)
	else:
		var previous: Vector3 = _trail_points[_trail_points.size() - 1]
		var gap := previous.distance_to(ball_position)
		if gap > TRAIL_STEP:
			var steps := mini(int(gap / TRAIL_STEP), 10)
			for step in range(1, steps + 1):
				_trail_points.append(previous.lerp(ball_position, float(step) / float(steps)))
			while _trail_points.size() > TRAIL_MAX:
				_trail_points.pop_front()
	_trail.visible = _trail_points.size() > 1
	if not _trail.visible:
		return
	var multi := _trail.multimesh
	var hidden := Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0.0, -60.0, 0.0))
	for i in range(TRAIL_MAX):
		var index := _trail_points.size() - 1 - i
		if index < 0:
			multi.set_instance_transform(i, hidden)
			continue
		var age := float(i) / float(TRAIL_MAX)
		var dot_scale := lerpf(1.0, 0.22, age)
		multi.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * dot_scale), _trail_points[index]))


# =============================================================================
# 帮助窗口
# =============================================================================

func _build_help_overlay(root: Control) -> void:
	_help_overlay = Control.new()
	_help_overlay.name = "HelpOverlay"
	_help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.visible = false
	root.add_child(_help_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_help_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320.0
	panel.offset_top = -520.0
	panel.offset_right = 320.0
	panel.offset_bottom = 520.0
	panel.add_theme_stylebox_override("panel", _help_panel_style())
	_help_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "游戏帮助"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("eef3fb"))
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_color_override("default_color", Color("dbe4f0"))
	body.text = HELP_TEXT
	scroll.add_child(body)

	var close_button := _make_button("关闭", 0.0, 88.0, 28)
	close_button.custom_minimum_size = Vector2(0, 88)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(hide_help)
	column.add_child(close_button)


func _help_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.11, 0.98)
	style.border_color = Color(0.30, 0.42, 0.60, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 18
	return style


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		hide_help()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		hide_help()


func show_help() -> void:
	if _help_overlay == null:
		return
	_cancel_aim()
	_help_overlay.visible = true


func hide_help() -> void:
	if _help_overlay == null:
		return
	_help_overlay.visible = false


func is_help_open() -> bool:
	return _help_overlay != null and _help_overlay.visible


func _cancel_aim() -> void:
	_aim_index = -1
	_aim_valid = false
	_release_aim_target()


# =============================================================================
# 输入
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if is_help_open():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_on_snap_pressed()
			KEY_V:
				_toggle_view()
			KEY_F:
				_toggle_ball_focus()
			KEY_H:
				show_help()
			KEY_R:
				_begin_series(START_LOS, 1)
				camera.reset_view()
			KEY_ESCAPE:
				get_tree().quit()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_indices[touch.index] = true
			if _touch_indices.size() == 1:
				_aim_index = touch.index
				_begin_aim(touch.position)
			elif _touch_indices.size() >= 2:
				_cancel_aim()
		else:
			_touch_indices.erase(touch.index)
			if touch.index == _aim_index:
				if _aim_valid:
					_aim_screen_current = touch.position
					_update_aim(touch.position)
					_release_throw()
				_aim_index = -1
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _aim_index:
			_update_aim(drag.position)
		return

	# 电脑调试：左键 = 触摸
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_aim_index = 0
			_begin_aim(button.position)
		elif _aim_index == 0:
			var was_valid := _aim_valid
			_aim_screen_current = button.position
			if was_valid:
				_update_aim(button.position)
				_release_throw()
			_aim_index = -1
		return

	if event is InputEventMouseMotion and _aim_valid and _aim_index == 0:
		_update_aim((event as InputEventMouseMotion).position)


# =============================================================================
# QA 辅助
# =============================================================================


## 打开衣柜（独立 CanvasLayer，不影响主场景相机）
var _wardrobe_layer: CanvasLayer
var _wardrobe: Control

func open_wardrobe() -> void:
	if _wardrobe != null:
		return
	_wardrobe_layer = CanvasLayer.new()
	_wardrobe_layer.name = "WardrobeLayer"
	_wardrobe_layer.layer = 10
	add_child(_wardrobe_layer)
	_wardrobe = preload("res://scenes/customization/character_customization.tscn").instantiate()
	_wardrobe_layer.add_child(_wardrobe)
	_wardrobe.closed.connect(_close_wardrobe)
	# 关掉瞄准，避免在 UI 上拖动时误传球
	_cancel_aim()


func _close_wardrobe() -> void:
	if _wardrobe_layer != null:
		_wardrobe_layer.queue_free()
		_wardrobe_layer = null
	_wardrobe = null
	# 穿搭可能变了，自己队的角色重新读一次存档
	for slot in _actors:
		var actor: PlayerActor = _actors[slot]
		if actor.personal_outfit:
			actor.refresh_outfit()

# =============================================================================
# 战术板 / 自由跑
# =============================================================================

## 按当前战术给每个接球手生成绝对路线点。


## 按当前球权把两支队伍分配到进攻/防守槽位
func _apply_possession() -> void:
	var offense_team: Array = _team_blue if _offense_side == "blue" else _team_red
	var defense_team: Array = _team_red if _offense_side == "blue" else _team_blue
	if offense_team.size() < 5 or defense_team.size() < 5:
		return
	_actors.clear()
	for i in OFF_SLOTS.size():
		_actors[OFF_SLOTS[i]] = offense_team[i]
	for i in DEF_SLOTS.size():
		_actors[DEF_SLOTS[i]] = defense_team[i]
	_qb = _actors["QB"]
	_center = _actors["C"]
	_receivers = [_actors["X"], _actors["Y"], _actors["Z"]]
	_defenders = [_actors["CB1"], _actors["CB2"], _actors["LB"], _actors["SS"], _actors["FS"]]


## 反查某个 actor 当前占的是哪个槽位
func _slot_of(actor: PlayerActor) -> String:
	for slot in _actors:
		if _actors[slot] == actor:
			return String(slot)
	return String(actor.name)

func _build_routes() -> void:
	_routes.clear()
	_route_index.clear()
	var play := Playbook.get_play(_current_play)
	var route_table: Dictionary = play["routes"]
	var actors: Array = _receivers.duplicate()
	if _center != null:
		actors.append(_center)
	for actor_v in actors:
		var actor: PlayerActor = actor_v as PlayerActor
		var slot := _slot_of(actor)
		var route_id := String(route_table.get(slot, ""))
		if route_id == "":
			continue
		var points := RouteLibrary.build(route_id, actor.global_position, float(_attack_dir))
		_routes[actor] = points
		_route_index[actor] = 0


func _reset_free_state() -> void:
	_free_state.clear()
	for actor in _receivers + [_center]:
		if actor == null:
			continue
		_free_state[actor] = {
			"mode": 0,
			"dir": Vector3(0.0, 0.0, 1.0),
			"timer": 0.0,
			"flip": 0,
		}
		_route_delay[actor] = CENTER_DELAY if actor == _center else 0.0


## 路线最后一段的方向，跑完路线后沿这个方向继续冲。
func _route_exit_direction(receiver: PlayerActor) -> Vector3:
	var route: Array = _routes.get(receiver, [])
	if route.size() >= 2:
		var direction: Vector3 = (route[route.size() - 1] as Vector3) - (route[route.size() - 2] as Vector3)
		direction.y = 0.0
		if direction.length() > 0.05:
			return direction.normalized()
	return Vector3(0.0, 0.0, 1.0)


func _at_boundary(position: Vector3) -> bool:
	return (position.x <= FIELD_MIN_X + 0.8 or position.x >= FIELD_MAX_X - 0.8
		or position.z <= FIELD_MIN_Z + 0.8 or position.z >= FIELD_MAX_Z - 0.8)


## 进入 Huddle：双方停住，弹出战术板
func _open_huddle() -> void:
	for actor in _actors.values():
		(actor as PlayerActor).set_move_input(Vector3.ZERO)
	_attach_ball(_center)
	_show_toast("选择战术后列阵", Color("9fd2ff"))
	debug_open_play_drawer()


func _select_play(play_id: String) -> void:
	_current_play = play_id
	if _phase == Phase.PRE_SNAP or _phase == Phase.HUDDLE:
		_build_routes()
		_reset_free_state()
	if _phase == Phase.HUDDLE:
		_phase = Phase.LINEUP
		_lineup_timer = 2.5
	_refresh_play_buttons()
	_refresh_route_preview()
	_show_toast("战术：%s" % Playbook.play_name(play_id), Color("9fd2ff"))


func _refresh_play_buttons() -> void:
	for id in _play_buttons:
		var button: Button = _play_buttons[id]
		var active := String(id) == _current_play
		var style := (button.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.bg_color = Color(0.20, 0.34, 0.55, 0.95) if active else Color(0.07, 0.10, 0.15, 0.82)
		style.border_color = Color(0.45, 0.66, 0.95, 1.0) if active else Color(0.36, 0.50, 0.72, 0.55)
		button.add_theme_stylebox_override("normal", style)
	if _play_label != null:
		_play_label.text = "战术：%s" % Playbook.play_name(_current_play)


# =============================================================================
# 抽屉 / 战术路线预览
# =============================================================================

var _menu_tab: Button
var _menu_drawer: Control
var _menu_open := false
var _play_tab: Button
var _play_open := false
var _route_lines: Array[MeshInstance3D] = []


func _circle_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(120)
	style.border_color = Color(0.78, 0.92, 1.0, 0.55)
	style.set_border_width_all(2)
	return style


## 右上菜单：下拉展开 / 上推收起
func _toggle_menu() -> void:
	_menu_open = not _menu_open
	_slide_menu(78.0 if _menu_open else -410.0)


func _slide_menu(target_y: float) -> void:
	if _menu_drawer == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_menu_drawer, "offset_top", target_y, 0.22)
	tween.parallel().tween_property(_menu_drawer, "offset_bottom", target_y, 0.22)
	if _menu_tab != null:
		_menu_tab.text = "菜单 ▴" if _menu_open else "菜单 ▾"


## 左下战术板：右拉展开 / 左滑收起
func _toggle_play_drawer() -> void:
	_play_open = not _play_open
	_slide_play(110.0 if _play_open else -220.0)


func _slide_play(target_x: float) -> void:
	if _play_grid == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_play_grid, "offset_left", target_x, 0.22)
	tween.parallel().tween_property(_play_grid, "offset_right", target_x + 220.0, 0.22)
	if _play_tab != null:
		_play_tab.text = "战术板 ◀" if _play_open else "战术板 ▶"


func debug_open_menu() -> void:
	_menu_open = true
	_slide_menu(78.0)


func debug_open_play_drawer() -> void:
	_play_open = true
	_slide_play(110.0)


## 把当前战术的路线画在球场上（开球后清除）
func _refresh_route_preview() -> void:
	for line in _route_lines:
		if is_instance_valid(line):
			line.queue_free()
	_route_lines.clear()
	if _phase != Phase.PRE_SNAP:
		return
	var play := Playbook.get_play(_current_play)
	var route_table: Dictionary = play["routes"]
	for receiver in _receivers:
		var slot := String(receiver.name)
		if not route_table.has(slot):
			continue
		var points: Array[Vector3] = []
		var start := receiver.global_position
		points.append(start)
		var built: Array = _routes.get(receiver, [])
		if built.size() > 0:
			for point in built:
				points.append(point)
		else:
			for offset in route_table[slot]:
				var raw: Vector3 = start + offset
				raw.x = clampf(raw.x, FIELD_MIN_X + 0.6, FIELD_MAX_X - 0.6)
				raw.z = clampf(raw.z, FIELD_MIN_Z + 0.8, FIELD_MAX_Z - 0.8)
				points.append(raw)
		for i in range(points.size() - 1):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var length := a.distance_to(b)
			if length < 0.1:
				continue
			var segment := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.04, length)
			segment.mesh = box
			segment.material_override = _unshaded(Color("8fe0ff"))
			add_child(segment)
			segment.global_position = (a + b) * 0.5 + Vector3(0.0, 0.08, 0.0)
			segment.look_at(b + Vector3(0.0, 0.08, 0.0), Vector3.UP)
			_route_lines.append(segment)


func _clear_route_preview() -> void:
	for line in _route_lines:
		if is_instance_valid(line):
			line.queue_free()
	_route_lines.clear()


# =============================================================================
# 标签拖拽 / 规避防守
# =============================================================================

## 横向拖动阈值（像素）
const DRAG_OPEN_PIXELS := 36.0
const DRAG_TAP_PIXELS := 10.0
## 绕开防守的感知半径与力度
const AVOID_RADIUS := 3.2
const AVOID_STRENGTH := 0.85

var _play_tab_drag := false
var _play_tab_start := Vector2.ZERO
var _menu_tab_drag := false
var _menu_tab_start := Vector2.ZERO


func _on_play_tab_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_play_tab_drag = true
			_play_tab_start = button.position
		elif _play_tab_drag:
			_play_tab_drag = false
			if absf(button.position.x - _play_tab_start.x) < DRAG_TAP_PIXELS:
				_toggle_play_drawer()
	elif event is InputEventMouseMotion and _play_tab_drag:
		var delta_x := (event as InputEventMouseMotion).position.x - _play_tab_start.x
		if not _play_open and delta_x > DRAG_OPEN_PIXELS:
			_play_tab_drag = false
			_play_open = true
			_slide_play(110.0)
		elif _play_open and delta_x < -DRAG_OPEN_PIXELS:
			_play_tab_drag = false
			_play_open = false
			_slide_play(-220.0)


func _on_menu_tab_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_menu_tab_drag = true
			_menu_tab_start = button.position
		elif _menu_tab_drag:
			_menu_tab_drag = false
			if absf(button.position.y - _menu_tab_start.y) < DRAG_TAP_PIXELS:
				_toggle_menu()
	elif event is InputEventMouseMotion and _menu_tab_drag:
		var delta_y := (event as InputEventMouseMotion).position.y - _menu_tab_start.y
		if not _menu_open and delta_y > DRAG_OPEN_PIXELS:
			_menu_tab_drag = false
			_menu_open = true
			_slide_menu(78.0)
		elif _menu_open and delta_y < -DRAG_OPEN_PIXELS:
			_menu_tab_drag = false
			_menu_open = false
			_slide_menu(-410.0)


## 快撞上防守球员时，往侧前方偏一点继续跑。
func _steer_around(actor: PlayerActor, direction: Vector3) -> Vector3:
	if _defenders.is_empty():
		return direction
	var steer := Vector3.ZERO
	for defender in _defenders:
		var to_defender := defender.global_position - actor.global_position
		to_defender.y = 0.0
		var distance := to_defender.length()
		if distance < 0.01 or distance > AVOID_RADIUS:
			continue
		var heading := to_defender / distance
		if direction.dot(heading) < 0.15:
			continue
		var side := Vector3(-heading.z, 0.0, heading.x)
		# 从球员的左/右侧穿过去，选离得近的那边
		var offset := defender.global_position - actor.global_position
		if direction.cross(offset).y > 0.0:
			side = -side
		steer += side * (1.0 - distance / AVOID_RADIUS) * AVOID_STRENGTH
	if steer.length() < 0.01:
		return direction
	return (direction + steer).normalized()

## QA：直接强制一次抄截，用来看回攻流程
func debug_force_interception() -> void:
	if _defenders.is_empty():
		return
	debug_snap_now()
	_begin_interception(_defenders[0])


## QA：强制换防，验证球权状态机
func debug_swap_possession() -> void:
	_pending_swap = true
	_begin_series(START_LOS, 1)


## QA：在指定逻辑码数处触发一次拔旗（走真实的 _end_down 路径）
func debug_sim_flag_pull(yards: float) -> void:
	var z := _game.field_yards_to_world(yards)
	_end_down(z, "被拔旗")


## QA：在指定逻辑码数处触发达阵（走真实的规则引擎校验）
func debug_sim_touchdown(yards: float) -> void:
	var z := _game.field_yards_to_world(yards)
	_game.end_play("TOUCHDOWN", _game.world_to_field_yards(z))
	_score_blue = _game.score_blue
	_score_red = _game.score_red
	_refresh_score()


func debug_zoom_out() -> void:
	camera.zoom_fully_out()


func debug_zoom_in() -> void:
	camera.zoom_to_top(25.0)


func debug_spectator() -> void:
	camera.set_view_mode(GameCamera.ViewMode.SPECTATOR)
	if _view_button != null:
		_view_button.text = "比赛视角"


func debug_focus_ball() -> bool:
	_toggle_ball_focus()
	return camera.is_ball_focused()


func is_ball_focus_on() -> bool:
	return camera.is_ball_focused()


func debug_last_result() -> String:
	return _last_result_text


func debug_pending_result() -> String:
	return _pending_result


## QA：直接放一次达阵庆祝。
func debug_touchdown() -> void:
	if _carrier == null:
		_carrier = _qb
	_trigger_touchdown()


func debug_thrower() -> Node3D:
	return _thrower


## QA：跳过开球动画，直接进入可传球状态。
func debug_snap_now() -> void:
	if _phase == Phase.PRE_SNAP:
		_begin_snap()
	_snap_elapsed = SNAP_SECONDS
	_advance_snap(0.0)
	if _phase == Phase.SNAP:
		_phase = Phase.PLAY
	_holder = _qb
	_set_holder(_qb)
	_attach_ball(_qb)


## QA：直接以给定模式发起一次传球（先把球交到四分卫手上）。
func debug_throw_at(world_point: Vector3, mode: int) -> void:
	debug_snap_now()
	_dropback_active = false
	_throw_mode = mode
	_aim_world = _clamp_throw_target(world_point)
	_aim_screen_current = Vector2.ZERO
	_aim_drag = Vector2.ZERO
	_aim_valid = true
	_aim_index = -1
	_start_throw()


const HELP_TEXT := """[font_size=22][color=#8fa6c4]一档球：开球 → 四分卫后撤 → 传球 → 接球人往达阵区跑。
防守会跟防外接手并拔旗；被拔旗就从拔旗处打下一档。[/color][/font_size]

[font_size=26][b]开球[/b][/font_size]
· 开球前球在中锋手里，右下角「开球」按钮起球
· 开球 0.5 秒内球还在传递中，不能出手
· 球到四分卫手上后，他会自己后撤两步（约 2.4 码）
· 后撤途中出手，四分卫立刻停住

[font_size=26][b]传球[/b][/font_size]
· 按住球场瞄准，松手出手
· 平传：球速快、弧线低
· 向下拖：高球，拖得越远抛物线越高
· 向上拖：弃球，不算传球

[font_size=26][b]接球与推进[/b][/font_size]
· 接球半径 1.55 / 1.95（平传）/ 2.10（高球）码
· 防守人抄截半径比接球半径小 0.18 码
· 接球后接球人自动往对面达阵区跑，防守全力追
· 被追上（1.3 码内）就拔旗，本档结束
· 跑进达阵区 5 码处 → TouchDown

[font_size=26][b]档数与计时[/b][/font_size]
· 1ST / 2ND / 3RD / 4TH DOWN，每档 10 码
· 过中场或达阵后回到 1 档；4 档未过换攻
· 开球前 25 秒倒计时，开球后 7 秒；剩 5 秒变红

[font_size=26][b]镜头[/b][/font_size]
· 跟随持球人；出手后跟球
· 双指拖动平移（松手回中）、双指捏合缩放
· 「观众视角」正侧方机位；「聚焦球」贴到球正后方
· 缩到最小时球场中纵线在屏幕正中

[font_size=26][b]电脑调试[/b][/font_size]
· 左键拖拽传球、空格开球、V 视角、F 聚焦球、R 重开、H 帮助
"""
