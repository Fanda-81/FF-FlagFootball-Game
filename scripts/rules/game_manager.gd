extends Node
class_name GameManager
## 比赛规则引擎（唯一的规则真相来源）
##
## 状态机：
##   PRE_GAME → READY_TO_SNAP ⇄ BALL_IN_PLAY → (PASS_IN_AIR) → PLAY_DEAD
##                                                    ├→ TOUCHDOWN → EXTRA_POINT → READY_TO_SNAP
##                                                    └→ TURNOVER → READY_TO_SNAP
##   半场结束时 HALFTIME，时间到 GAME_OVER。
##
## 规则（USA Football 5s 基础版，可换模式）：
##   · 每队 5 人，无开球踢球
##   · 第一阶段：4 档内越过中场 → 获得新的 4 档
##   · 第二阶段：4 档内达阵，否则交换球权
##   · 达阵 6 分，安全分 2 分（第一版附加分只占位）
##
## 码数统一用「距离本方端线的码数」表示（0 = 本方端线，25 = 中场，50 = 对方端线），
## 所以进攻方向怎么翻，码数计算都不用改。

enum State {
	PRE_GAME,
	READY_TO_SNAP,
	BALL_IN_PLAY,
	PASS_IN_AIR,
	PLAY_DEAD,
	TOUCHDOWN,
	EXTRA_POINT,
	TURNOVER,
	HALFTIME,
	GAME_OVER,
}

enum RuleSet { USA_FOOTBALL_5S, NFL_FLAG }

# --- 场地（世界坐标，和 stadium.gd 保持一致）---
const FIELD_MIN_Z := -10.0
const FIELD_MAX_Z := 60.0
const PLAYING_MIN_Z := 0.0
const PLAYING_MAX_Z := 50.0
const MIDFIELD_YARDS := 25.0
const GOAL_YARDS := 50.0

# --- 规则参数（集中在这里，禁止散落）---
var rule_set := RuleSet.USA_FOOTBALL_5S
var players_per_side := 5
var downs_total := 4
var touchdown_points := 6
var safety_points := 2
var start_yards := 5.0

# --- 运行时状态 ---
var state := State.PRE_GAME
var offense := "blue"
var attack_dir := 1.0
var down := 1
var los_yards := 5.0
var first_down_yards := 25.0
var ball_yards := 5.0
var phase := 1
var blue_score := 0
var red_score := 0
var last_play := ""
var possession_reason := ""


func reset_match() -> void:
	state = State.PRE_GAME
	offense = "blue"
	attack_dir = 1.0
	down = 1
	los_yards = start_yards
	ball_yards = start_yards
	phase = 1
	first_down_yards = MIDFIELD_YARDS
	blue_score = 0
	red_score = 0
	last_play = ""
	possession_reason = ""


func start_match() -> void:
	reset_match()
	state = State.READY_TO_SNAP


# =============================================================================
# 码数换算
# =============================================================================

## 世界 z → 距离本方端线的码数（进攻方向相关）
func z_to_yards(world_z: float, direction: float) -> float:
	if direction >= 0.0:
		return world_z - PLAYING_MIN_Z
	return PLAYING_MAX_Z - world_z


## 距离本方端线的码数 → 世界 z
func yards_to_z(yards: float, direction: float) -> float:
	if direction >= 0.0:
		return PLAYING_MIN_Z + yards
	return PLAYING_MAX_Z - yards


func yards_to_go() -> int:
	return int(maxf(1.0, ceilf(first_down_yards - los_yards)))


func direction_label() -> String:
	return "RIGHT" if attack_dir > 0.0 else "LEFT"


func offense_color_name() -> String:
	return "BLUE" if offense == "blue" else "RED"


# =============================================================================
# 状态推进
# =============================================================================

func begin_series(los: float, new_down: int) -> void:
	los_yards = los
	down = new_down
	ball_yards = los
	phase = 2 if los_yards >= MIDFIELD_YARDS else 1
	first_down_yards = GOAL_YARDS if phase == 2 else MIDFIELD_YARDS
	state = State.READY_TO_SNAP


func on_snap() -> void:
	if state != State.READY_TO_SNAP:
		return
	state = State.BALL_IN_PLAY
	last_play = "SNAP"


func on_pass() -> void:
	if state == State.BALL_IN_PLAY:
		state = State.PASS_IN_AIR


func on_ball_landed() -> void:
	if state == State.PASS_IN_AIR:
		state = State.BALL_IN_PLAY


## 结束本档。返回 {"los", "down", "turnover"}
func end_play(reason: String, end_world_z: float) -> Dictionary:
	last_play = reason
	ball_yards = clampf(z_to_yards(end_world_z, attack_dir), 0.0, GOAL_YARDS)
	state = State.PLAY_DEAD

	var result := {"los": los_yards, "down": down + 1, "turnover": false}

	# 越过首攻线（第一阶段 = 中场，第二阶段 = 端线）
	if ball_yards >= first_down_yards - 0.01:
		los_yards = ball_yards
		phase = 2 if los_yards >= MIDFIELD_YARDS else 1
		first_down_yards = GOAL_YARDS if phase == 2 else MIDFIELD_YARDS
		result["los"] = los_yards
		result["down"] = 1
		last_play = reason + " · 首攻"
		state = State.READY_TO_SNAP
		return result

	# 没推进够，档数 +1
	result["los"] = los_yards
	result["down"] = down + 1
	result["turnover"] = down + 1 > downs_total
	if result["turnover"]:
		change_possession("四档未过")
	return result


func on_touchdown(scorer: String) -> void:
	state = State.TOUCHDOWN
	if scorer == "blue":
		blue_score += touchdown_points
	else:
		red_score += touchdown_points
	last_play = "TOUCHDOWN " + scorer.to_upper()
	# 第一版附加分只占位，直接进入下一档
	state = State.EXTRA_POINT


func finish_extra_point() -> void:
	state = State.READY_TO_SNAP


## 球权转换（唯一入口）
func change_possession(reason: String) -> void:
	offense = "red" if offense == "blue" else "blue"
	attack_dir = -attack_dir
	down = 1
	phase = 1
	los_yards = start_yards
	ball_yards = start_yards
	first_down_yards = MIDFIELD_YARDS
	possession_reason = reason
	last_play = reason
	state = State.TURNOVER


func on_interception() -> void:
	last_play = "INTERCEPTION"
	state = State.TURNOVER


# =============================================================================
# 调试面板文本
# =============================================================================

func debug_lines() -> String:
	return "\n".join(PackedStringArray([
		"GAME STATE: " + State.keys()[state],
		"POSSESSION: " + offense_color_name(),
		"DOWN: %d" % down,
		"YARDS TO GO: %d" % yards_to_go(),
		"BALL POSITION: %.1f" % ball_yards,
		"LINE OF SCRIMMAGE: %.1f" % los_yards,
		"FIRST DOWN LINE: %.1f" % first_down_yards,
		"DIRECTION: " + direction_label(),
		"LAST PLAY: " + last_play,
	]))
