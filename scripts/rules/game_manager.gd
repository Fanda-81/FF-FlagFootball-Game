extends Node
class_name GameManager
## 比赛规则引擎 —— **唯一**允许修改比赛状态的地方。
##
## 逻辑坐标：球场 70 码（0 蓝底线 / 10 蓝达阵线 / 35 中场 / 60 红达阵线 / 70 红底线）
##   world_z = yards - 10      yards = world_z + 10
##   蓝方进攻码数增大，红方进攻码数减小。

signal state_changed(state_name: String)
signal event_logged(line: String)

enum State {
	PRE_GAME, READY_TO_SNAP, BALL_IN_PLAY, PASS_IN_AIR,
	PLAY_DEAD, TOUCHDOWN, EXTRA_POINT, TURNOVER, HALFTIME, GAME_OVER,
}

const FIELD_LENGTH := 70.0
const BLUE_GOAL := 10.0
const MIDFIELD := 35.0
const RED_GOAL := 60.0
const WORLD_Z_OFFSET := 10.0

var players_per_side := 5
var downs_total := 4
var touchdown_points := 6
var safety_points := 2

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
var phase := 1
var play_already_ended := false
## 截球后正在回攻，回攻结束才开始新系列
var awaiting_return := false


func _init() -> void:
	reset_match()


# =============================================================================
# 坐标
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


func get_yards_to_go() -> int:
	var diff := (first_down_line - line_of_scrimmage) * get_attacking_direction()
	return int(maxf(1.0, ceilf(diff)))


func target_line_for(team: String, yards: float) -> float:
	if team == "blue":
		return RED_GOAL if yards >= MIDFIELD else MIDFIELD
	return BLUE_GOAL if yards <= MIDFIELD else MIDFIELD


func is_own_endzone(team: String, yards: float) -> bool:
	return yards <= BLUE_GOAL if team == "blue" else yards >= RED_GOAL


func is_opponent_endzone(team: String, yards: float) -> bool:
	return yards >= RED_GOAL if team == "blue" else yards <= BLUE_GOAL


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
	play_already_ended = false


func start_match() -> void:
	reset_match()
	play_id = 1
	match_state = State.READY_TO_SNAP
	_log("[PLAY %03d] %s OFFENSE START AT %.1f" % [play_id, possession_team.to_upper(), line_of_scrimmage])


func debug_setup(team: String, yards: float, down: int) -> void:
	possession_team = team
	line_of_scrimmage = yards
	ball_position_yards = yards
	down_number = down
	first_down_line = target_line_for(team, yards)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	match_state = State.READY_TO_SNAP
	play_already_ended = false


func _log(line: String) -> void:
	print(line)
	event_logged.emit(line)


func _set_state(new_state: State) -> void:
	if match_state == new_state:
		return
	match_state = new_state
	state_changed.emit(State.keys()[new_state])


# =============================================================================
# 回合
# =============================================================================

func start_play() -> bool:
	if match_state != State.READY_TO_SNAP:
		return false
	play_id += 1
	play_already_ended = false
	match_state = State.BALL_IN_PLAY
	_log("[PLAY %03d] SNAP FROM %.1f  DOWN %d" % [play_id, line_of_scrimmage, down_number])
	return true


## 回攻结束：在死球位置开始新系列（down 1）
func finish_return(final_yards: float) -> void:
	awaiting_return = false
	ball_position_yards = clampf(final_yards, 0.0, FIELD_LENGTH)
	line_of_scrimmage = ball_position_yards
	down_number = 1
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	_log("[PLAY %03d] RETURN ENDED AT %.1f — NEW SERIES" % [play_id, ball_position_yards])
	_set_state(State.READY_TO_SNAP)


func end_play(reason: String, final_yards: float) -> void:
	if play_already_ended:
		_log("[PLAY %03d] IGNORED %s (PLAY ALREADY ENDED)" % [play_id, reason])
		return
	play_already_ended = true
	ball_position_yards = final_yards
	match_state = State.PLAY_DEAD
	_log("[PLAY %03d] %s AT YARD %.1f" % [play_id, reason, final_yards])
	if awaiting_return and reason in ["FLAG_PULL", "OUT_OF_BOUNDS"]:
		finish_return(final_yards)
		return
	match reason:
		"INCOMPLETE_PASS":
			process_incomplete_pass()
		"INTERCEPTION":
			process_interception()
		"TOUCHDOWN":
			process_touchdown()
		"SAFETY":
			process_safety()
		"OUT_OF_BOUNDS":
			process_out_of_bounds()
		"TURNOVER_ON_DOWNS":
			process_turnover_on_downs()
		_:
			process_flag_pull()


func process_incomplete_pass() -> void:
	ball_position_yards = line_of_scrimmage
	last_event = "INCOMPLETE_PASS"
	_log("[PLAY %03d] INCOMPLETE — BALL BACK TO %.1f" % [play_id, line_of_scrimmage])
	_advance_down()


func process_flag_pull() -> void:
	last_event = "FLAG_PULL"
	_advance_down()


func process_out_of_bounds() -> void:
	last_event = "OUT_OF_BOUNDS"
	_advance_down()


func process_turnover_on_downs() -> void:
	last_event = "TURNOVER_ON_DOWNS"
	change_possession("TURNOVER_ON_DOWNS", ball_position_yards)


func process_interception() -> void:
	last_event = "INTERCEPTION"
	change_possession("INTERCEPTION", ball_position_yards)
	# 允许回攻：等回攻结束（拔旗/出界/达阵）才确定新系列的位置
	awaiting_return = true


func process_safety() -> void:
	last_event = "SAFETY"
	if possession_team == "blue":
		score_red += safety_points
	else:
		score_blue += safety_points
	_log("[PLAY %03d] SAFETY (+%d)" % [play_id, safety_points])
	change_possession("SAFETY", line_of_scrimmage)


func process_touchdown() -> void:
	if match_state == State.TOUCHDOWN:
		return
	if not is_opponent_endzone(possession_team, ball_position_yards):
		_log("[PLAY %03d] TD REJECTED — BALL %.1f NOT IN ENDZONE" % [play_id, ball_position_yards])
		_advance_down()
		return
	match_state = State.TOUCHDOWN
	last_event = "TOUCHDOWN"
	if possession_team == "blue":
		score_blue += touchdown_points
	else:
		score_red += touchdown_points
	_log("[PLAY %03d] TOUCHDOWN %s (+%d)" % [play_id, possession_team.to_upper(), touchdown_points])
	match_state = State.EXTRA_POINT
	_after_score(possession_team)


func _after_score(scorer: String) -> void:
	var receiver := "red" if scorer == "blue" else "blue"
	possession_team = receiver
	var start_yards := 15.0 if receiver == "blue" else 55.0
	ball_position_yards = start_yards
	line_of_scrimmage = start_yards
	down_number = 1
	phase = 1
	first_down_line = MIDFIELD
	last_turnover_reason = "AFTER_TOUCHDOWN"
	_log("[PLAY %03d] RESTART — %s FROM OWN 5 (%.1f)" % [play_id, receiver.to_upper(), start_yards])
	_set_state(State.READY_TO_SNAP)


func _advance_down() -> void:
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


func award_first_down() -> void:
	line_of_scrimmage = ball_position_yards
	down_number = 1
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	_log("[PLAY %03d] FIRST DOWN AT %.1f (TARGET %.1f)" % [play_id, line_of_scrimmage, first_down_line])
	_set_state(State.READY_TO_SNAP)


func change_possession(reason: String, turnover_yards: float) -> void:
	possession_team = get_defense_team()
	last_turnover_reason = reason
	down_number = 1
	ball_position_yards = clampf(turnover_yards, 0.0, FIELD_LENGTH)
	line_of_scrimmage = ball_position_yards
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	_log("[PLAY %03d] POSSESSION -> %s (%s) AT %.1f  TARGET %.1f" % [
		play_id, possession_team.to_upper(), reason, ball_position_yards, first_down_line])
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