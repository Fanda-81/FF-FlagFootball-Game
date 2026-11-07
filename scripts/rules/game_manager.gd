extends Node
class_name GameManager
## 比赛规则引擎 —— **唯一**可以修改比赛状态的地方。
##
## 逻辑坐标：球场 70 码，用「码」表示纵向位置，与 Godot 世界坐标完全分离。
##   0 = 蓝方底线   10 = 蓝方达阵线   35 = 中场   60 = 红方达阵线   70 = 红方底线
##   蓝方进攻：码数增大；红方进攻：码数减小。
##
## 世界坐标映射（固定，与攻防方向无关）：
##   world_z = yards - 10        yards = world_z + 10
##   （我们的球场 z 从 -10 到 60，正好 70 码）
##
## 外部脚本只能调用本类的事件函数，不能直接改状态字段。

signal state_changed(state_name: String)
signal event_logged(line: String)

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

# --- 球场（逻辑码）---
const FIELD_LENGTH := 70.0
const BLUE_GOAL := 10.0
const MIDFIELD := 35.0
const RED_GOAL := 60.0
const WORLD_Z_OFFSET := 10.0   ## world_z = yards - 10

# --- 规则参数 ---
var players_per_side := 5
var downs_total := 4
var touchdown_points := 6
var safety_points := 2

# --- 独占状态（只允许本类修改）---
var match_state: State = State.PRE_GAME
var possession_team := "blue"
var ball_position_yards := 15.0
var line_of_scrimmage := 15.0
var first_down_line := 35.0
var down_number := 1
var score_blue := 0
var score_red := 0
var last_event := ""
var last_turnover_reason := ""
var play_id := 0
var phase := 1                  ## 1 = 冲击中场，2 = 冲击达阵


func _init() -> void:
	reset_match()


# =============================================================================
# 坐标换算（唯一入口）
# =============================================================================

func world_to_field_yards(world_z: float) -> float:
	return world_z + WORLD_Z_OFFSET


func field_yards_to_world(yards: float) -> float:
	return yards - WORLD_Z_OFFSET


func get_attacking_direction() -> float:
	return 1.0 if possession_team == "blue" else -1.0


func get_ball_yards() -> float:
	return ball_position_yards


func get_defense_team() -> String:
	return "red" if possession_team == "blue" else "blue"


## 距首攻还差多少码
func get_yards_to_go() -> int:
	return int(maxf(1.0, ceilf(absf(first_down_line - line_of_scrimmage))))


func is_in_own_endzone(yards: float) -> bool:
	return yards <= BLUE_GOAL if possession_team == "blue" else yards >= RED_GOAL


func is_in_opponent_endzone(yards: float) -> bool:
	return yards >= RED_GOAL if possession_team == "blue" else yards <= BLUE_GOAL


# =============================================================================
# 基础
# =============================================================================

func reset_match() -> void:
	match_state = State.PRE_GAME
	possession_team = "blue"
	ball_position_yards = 15.0
	line_of_scrimmage = 15.0
	down_number = 1
	phase = 1
	first_down_line = MIDFIELD
	score_blue = 0
	score_red = 0
	last_event = ""
	last_turnover_reason = ""
	play_id = 0


func start_match() -> void:
	reset_match()
	play_id = 1
	match_state = State.READY_TO_SNAP
	_log("[PLAY %03d] %s OFFENSE START" % [play_id, possession_team.to_upper()])


func _log(line: String) -> void:
	print(line)
	event_logged.emit(line)


func _set_state(new_state: State) -> void:
	if match_state == new_state:
		return
	match_state = new_state
	state_changed.emit(State.keys()[new_state])


# =============================================================================
# 回合流程
# =============================================================================

## 合法时才允许开球
func start_play() -> bool:
	if match_state != State.READY_TO_SNAP:
		return false
	play_id += 1
	match_state = State.BALL_IN_PLAY
	_log("[PLAY %03d] SNAP" % play_id)
	return true


## 统一结束本档。final_yards = 死球位置的逻辑码数。
func end_play(reason: String, final_yards: float) -> void:
	if match_state == State.PLAY_DEAD or match_state == State.TOUCHDOWN:
		return   # 同一回合只允许结束一次
	ball_position_yards = final_yards
	match_state = State.PLAY_DEAD
	_log("[PLAY %03d] %s AT YARD %.1f" % [play_id, reason, final_yards])
	match reason:
		"INCOMPLETE_PASS":
			process_incomplete_pass()
		"FLAG_PULL":
			process_flag_pull()
		"OUT_OF_BOUNDS":
			process_out_of_bounds()
		"TURNOVER_ON_DOWNS":
			process_turnover_on_downs()
		_:
			process_flag_pull()


# 1. 传球未完成 —— 球回到开球线，档数 +1，球权/方向/首攻线都不变
func process_incomplete_pass() -> void:
	ball_position_yards = line_of_scrimmage
	last_event = "INCOMPLETE_PASS"
	_log("[PLAY %03d] INCOMPLETE PASS — BALL BACK TO LOS %.1f" % [play_id, line_of_scrimmage])
	_advance_down(true)


# 2. 拔旗 —— 用死球位置推进
func process_flag_pull() -> void:
	last_event = "FLAG_PULL"
	_advance_down(false)


# 3. 出界 —— 同拔旗，按死球位置推进
func process_out_of_bounds() -> void:
	last_event = "OUT_OF_BOUNDS"
	_advance_down(false)


# 4. 四档失败 —— 在实际位置换权，不重置位置
func process_turnover_on_downs() -> void:
	last_event = "TURNOVER_ON_DOWNS"
	change_possession("TURNOVER_ON_DOWNS", ball_position_yards)


# 5. 抄截 —— 防守方成为持球方，球场位置不变
func process_interception() -> void:
	last_event = "INTERCEPTION"
	change_possession("INTERCEPTION", ball_position_yards)


# 6. 达阵
func process_touchdown() -> void:
	if match_state == State.TOUCHDOWN:
		return
	match_state = State.TOUCHDOWN
	last_event = "TOUCHDOWN"
	if possession_team == "blue":
		score_blue += touchdown_points
	else:
		score_red += touchdown_points
	_log("[PLAY %03d] TOUCHDOWN %s (+%d)" % [play_id, possession_team.to_upper(), touchdown_points])
	# 第一版附加分只占位
	match_state = State.EXTRA_POINT
	last_turnover_reason = "TOUCHDOWN"
	change_possession("AFTER_TOUCHDOWN", line_of_scrimmage)


## 档数推进（incomplete = 球回开球线）
func _advance_down(_incomplete: bool) -> void:
	# 到达首攻线 → 新首攻
	var direction := get_attacking_direction()
	var reached := (ball_position_yards - first_down_line) * direction >= -0.01
	if reached:
		award_first_down()
		return
	down_number += 1
	_log("[PLAY %03d] DOWN %d -> DOWN %d" % [play_id, down_number - 1, down_number])
	if down_number > downs_total:
		process_turnover_on_downs()
		return
	line_of_scrimmage = ball_position_yards
	_set_state(State.READY_TO_SNAP)


## 授予新首攻
func award_first_down() -> void:
	line_of_scrimmage = ball_position_yards
	down_number = 1
	phase = 2 if (line_of_scrimmage - MIDFIELD) * get_attacking_direction() >= 0.0 else 1
	first_down_line = RED_GOAL if possession_team == "blue" else BLUE_GOAL
	_log("[PLAY %03d] FIRST DOWN AT %.1f" % [play_id, line_of_scrimmage])
	_set_state(State.READY_TO_SNAP)


## 球权转换（唯一入口）
func change_possession(reason: String, turnover_yards: float) -> void:
	possession_team = get_defense_team()
	last_turnover_reason = reason
	down_number = 1
	phase = 1
	ball_position_yards = clampf(turnover_yards, 0.0, FIELD_LENGTH)
	line_of_scrimmage = ball_position_yards
	first_down_line = MIDFIELD if possession_team == "blue" else MIDFIELD
	_log("[PLAY %03d] POSSESSION -> %s (%s) AT %.1f" % [play_id, possession_team.to_upper(), reason, ball_position_yards])
	_set_state(State.READY_TO_SNAP)


# =============================================================================
# 调试面板
# =============================================================================

func debug_lines() -> String:
	return "\n".join(PackedStringArray([
		"STATE: " + State.keys()[match_state],
		"OFFENSE: " + possession_team.to_upper() + "   DEFENSE: " + get_defense_team().to_upper(),
		"DOWN: %d   YARDS TO GO: %d" % [down_number, get_yards_to_go()],
		"BALL: %.1f   LOS: %.1f   FIRST DOWN: %.1f" % [ball_position_yards, line_of_scrimmage, first_down_line],
		"DIRECTION: " + ("+" if get_attacking_direction() > 0.0 else "-"),
		"LAST EVENT: " + last_event,
		"TURNOVER: " + last_turnover_reason,
	]))
