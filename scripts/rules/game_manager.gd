extends Node
class_name GameManager
## 比赛规则引擎（唯一权威）。本次聚焦：PLAY ID 生命周期 + 事件校验。

signal state_changed(state_name: String)
signal event_logged(line: String)

enum State {
	PRE_GAME, READY_TO_SNAP, BALL_IN_PLAY, PASS_IN_AIR,
	PLAY_DEAD, RETURN_IN_PROGRESS, TOUCHDOWN, EXTRA_POINT, TURNOVER, HALFTIME, GAME_OVER,
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
var last_turnover_reason := ""          ## 历史：最近一次换权原因
var series_turnover_reason := ""        ## 当前系列是由哪种换权开创的
var play_id := 0
var phase := 1
var play_already_ended := false
var awaiting_return := false
## 附加分（达阵后一次进攻机会，成功 +1）
var extra_point_pending := false
var extra_point_team := ""
const EXTRA_POINT_POINTS := 1
var play_started_at := 0.0
var play_history: Array = []


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


## 统一的"还差多少码"计算（HUD / 调试 / 规则判断必须共用这一个）
func yards_to_go_from(team: String, ball_yards: float, target_yards: float) -> int:
	var direction := 1.0 if team == "blue" else -1.0
	var distance := (target_yards - ball_yards) * direction
	if distance <= 0.001:
		return 0
	return int(ceil(distance - 0.001))


func get_yards_to_go() -> int:
	return yards_to_go_from(possession_team, line_of_scrimmage, first_down_line)


func target_line_for(team: String, yards: float) -> float:
	if team == "blue":
		return RED_GOAL if yards >= MIDFIELD else MIDFIELD
	return BLUE_GOAL if yards <= MIDFIELD else MIDFIELD


func is_own_endzone(team: String, yards: float) -> bool:
	return yards <= BLUE_GOAL if team == "blue" else yards >= RED_GOAL


func is_opponent_endzone(team: String, yards: float) -> bool:
	return yards >= RED_GOAL if team == "blue" else yards <= BLUE_GOAL


# =============================================================================
# 生命周期
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
	play_already_ended = true
	awaiting_return = false
	extra_point_pending = false
	extra_point_team = ""
	play_history.clear()


func start_match() -> void:
	reset_match()
	begin_down()


## 新的一档正式开始：这里才把 PLAY ID +1
func begin_down() -> void:
	play_id += 1
	play_already_ended = false
	# 当前档事件清空；换权原因只作为历史保留（不再冒充当前状态）
	last_event = ""
	awaiting_return = false
	play_started_at = Time.get_ticks_msec() / 1000.0
	match_state = State.READY_TO_SNAP
	_log("[PLAY %03d] %s DOWN %d START AT %.1f (TARGET %.1f)" % [
		play_id, possession_team.to_upper(), down_number, line_of_scrimmage, first_down_line])
	field_debug("DOWN START")


func debug_setup(team: String, yards: float, down: int) -> void:
	possession_team = team
	line_of_scrimmage = yards
	ball_position_yards = yards
	down_number = down
	first_down_line = target_line_for(team, yards)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	play_id = 0
	begin_down()


## 坐标诊断：每次开档/换权/回攻结束都打印
func field_debug(tag: String) -> void:
	var ball_world := field_yards_to_world(ball_position_yards)
	var spawn_world := field_yards_to_world(line_of_scrimmage)
	_log("[FIELD DEBUG] " + tag)
	_log("  PLAY ID: %d" % play_id)
	_log("  POSSESSION TEAM: %s" % possession_team.to_upper())
	_log("  DOWN: %d" % down_number)
	_log("  WORLD BALL POSITION Z: %.2f" % ball_world)
	_log("  LOGICAL BALL YARD: %.2f" % ball_position_yards)
	_log("  OFFENSE DIRECTION: %+.0f" % get_attacking_direction())
	_log("  LOS YARD: %.2f" % line_of_scrimmage)
	_log("  FIRST DOWN TARGET: %.2f" % first_down_line)
	_log("  BLUE ENDZONE WORLD RANGE: [%.1f, %.1f]" % [field_yards_to_world(0.0), field_yards_to_world(BLUE_GOAL)])
	_log("  RED ENDZONE WORLD RANGE: [%.1f, %.1f]" % [field_yards_to_world(RED_GOAL), field_yards_to_world(FIELD_LENGTH)])
	_log("  BALL IN BLUE ENDZONE: %s" % is_own_endzone("blue", ball_position_yards))
	_log("  BALL IN RED ENDZONE: %s" % is_own_endzone("red", ball_position_yards))
	_log("  OFFENSE SPAWN WORLD POSITION: %.2f" % spawn_world)


func _log(line: String) -> void:
	print(line)
	event_logged.emit(line)


func _set_state(s: State) -> void:
	if match_state == s:
		return
	match_state = s
	state_changed.emit(State.keys()[s])


## 开球：只有 READY_TO_SNAP 合法
func start_play(pid := -1) -> bool:
	if pid >= 0 and pid != play_id:
		_log("[PLAY %03d] REJECTED STALE EVENT: SNAP (pid %d)" % [play_id, pid])
		return false
	if match_state != State.READY_TO_SNAP:
		_log("[PLAY %03d] REJECTED SNAP — STATE %s" % [play_id, State.keys()[match_state]])
		return false
	match_state = State.BALL_IN_PLAY
	_log("[PLAY %03d] SNAP" % play_id)
	return true


func on_pass() -> void:
	if match_state == State.BALL_IN_PLAY:
		match_state = State.PASS_IN_AIR


## 结束本档。reason 必须是合法事件；pid 用来拒绝上一档的延迟事件。
func end_play(reason: String, final_yards: float, pid := -1) -> bool:
	if pid >= 0 and pid != play_id:
		_log("[PLAY %03d] REJECTED STALE EVENT: %s (pid %d)" % [play_id, reason, pid])
		return false
	if play_already_ended:
		_log("[PLAY %03d] REJECTED DUPLICATE: %s" % [play_id, reason])
		return false
	if match_state == State.RETURN_IN_PROGRESS:
		if reason in ["FLAG_PULL", "OUT_OF_BOUNDS", "TOUCHDOWN"]:
			play_already_ended = true
			ball_position_yards = final_yards
			_log("[PLAY %03d] %s AT YARD %.1f (RETURN END)" % [play_id, reason, final_yards])
			if reason == "TOUCHDOWN":
				if not process_touchdown():
					finish_return(final_yards)
			else:
				finish_return(final_yards)
			return true
		_log("[PLAY %03d] REJECTED IN RETURN_TURNOVER: %s" % [play_id, reason])
		return false
	if match_state != State.BALL_IN_PLAY and match_state != State.PASS_IN_AIR:
		_log("[PLAY %03d] REJECTED EVENT %s — STATE %s" % [play_id, reason, State.keys()[match_state]])
		return false

	play_already_ended = true
	ball_position_yards = final_yards
	match_state = State.PLAY_DEAD
	_log("[PLAY %03d] %s AT YARD %.1f" % [play_id, reason, final_yards])

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
	return true


# =============================================================================
# 事件实现
# =============================================================================

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


## 截球：球权立刻给防守方，但**本档不结束**，进入回攻
func process_interception() -> void:
	last_event = "INTERCEPTION"
	possession_team = get_defense_team()
	last_turnover_reason = "INTERCEPTION"
	awaiting_return = true
	match_state = State.RETURN_IN_PROGRESS
	play_already_ended = false
	_log("[PLAY %03d] INTERCEPTION — %s RETURN IN PROGRESS" % [play_id, possession_team.to_upper()])


## 安全分：防守方 +2，并由得分方从自己 5 码线开始下一次进攻
func process_safety() -> void:
	last_event = "SAFETY"
	var scorer := get_defense_team()
	if scorer == "blue":
		score_blue += safety_points
	else:
		score_red += safety_points
	_log("[PLAY %03d] SAFETY (+%d) — %s SCORES" % [play_id, safety_points, scorer.to_upper()])
	possession_team = scorer
	var start_yards := 15.0 if scorer == "blue" else 55.0
	ball_position_yards = start_yards
	line_of_scrimmage = start_yards
	down_number = 1
	phase = 1
	first_down_line = MIDFIELD
	last_turnover_reason = "SAFETY"
	series_turnover_reason = "SAFETY"
	_archive(play_id, "SAFETY", start_yards)
	begin_down()

func process_touchdown() -> bool:
	if not is_opponent_endzone(possession_team, ball_position_yards):
		# 拒绝：不加分、不换权、不改档数、不推进比赛
		_log("[PLAY %03d] TD REJECTED — BALL %.1f NOT IN ENDZONE (NO SIDE EFFECT)" % [play_id, ball_position_yards])
		last_event = "TD_REJECTED"
		return false
	if match_state == State.TOUCHDOWN:
		return false
	match_state = State.TOUCHDOWN
	last_event = "TOUCHDOWN"
	if extra_point_pending:
		# 附加分成功
		if extra_point_team == "blue":
			score_blue += EXTRA_POINT_POINTS
		else:
			score_red += EXTRA_POINT_POINTS
		_log("[PLAY %03d] EXTRA POINT GOOD — %s (+%d)" % [play_id, extra_point_team.to_upper(), EXTRA_POINT_POINTS])
		extra_point_pending = false
		_after_score(extra_point_team)
		return true
	if possession_team == "blue":
		score_blue += touchdown_points
	else:
		score_red += touchdown_points
	_log("[PLAY %03d] TOUCHDOWN %s (+%d)" % [play_id, possession_team.to_upper(), touchdown_points])
	extra_point_team = possession_team
	extra_point_pending = true
	_start_extra_point(extra_point_team)
	return true


## 达阵后：得分方从对方 5 码线尝试一次附加分
func _start_extra_point(team: String) -> void:
	possession_team = team
	line_of_scrimmage = 55.0 if team == "blue" else 5.0
	ball_position_yards = line_of_scrimmage
	down_number = 1
	phase = 2
	first_down_line = target_line_for(team, line_of_scrimmage)
	# 状态保持 READY_TO_SNAP 以便开球；附加分用 extra_point_pending 标记
	_log("[PLAY %03d] EXTRA POINT ATTEMPT — %s FROM %.1f" % [play_id, team.to_upper(), line_of_scrimmage])
	begin_down()


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
	series_turnover_reason = "AFTER_TOUCHDOWN"
	_log("[PLAY %03d] RESTART — %s FROM OWN 5 (%.1f)" % [play_id, receiver.to_upper(), start_yards])
	_archive(play_id, "TOUCHDOWN", start_yards)
	begin_down()


func _advance_down() -> void:
	# 附加分没打成 → 不加分，直接进入重新开球
	if extra_point_pending:
		extra_point_pending = false
		_log("[PLAY %03d] EXTRA POINT FAILED" % play_id)
		_after_score(extra_point_team)
		return
	var direction := get_attacking_direction()
	# 只要真正进入对方端区，无论第几阶段都先判达阵
	if is_opponent_endzone(possession_team, ball_position_yards):
		if process_touchdown():
			return
	if phase == 1:
		# 第一阶段：目标线是中场，到达即新首攻
		var reached := (ball_position_yards - first_down_line) * direction >= -0.01
		if reached:
			award_first_down()
			return
	# 其它情况一律按死球正常推进档数（phase 2 绝不 award_first_down）
	down_number += 1
	if down_number > downs_total:
		_archive(play_id, "TURNOVER_ON_DOWNS", ball_position_yards)
		process_turnover_on_downs()
		return
	line_of_scrimmage = ball_position_yards
	_log("[PLAY %03d] PLAY ENDED — NEXT: DOWN %d" % [play_id, down_number])
	_archive(play_id, last_event, ball_position_yards)
	begin_down()


func award_first_down() -> void:
	line_of_scrimmage = ball_position_yards
	down_number = 1
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	_log("[PLAY %03d] FIRST DOWN AT %.1f (TARGET %.1f)" % [play_id, line_of_scrimmage, first_down_line])
	_archive(play_id, "FIRST_DOWN", ball_position_yards)
	begin_down()


func finish_return(final_yards: float) -> void:
	ball_position_yards = clampf(final_yards, 0.0, FIELD_LENGTH)
	line_of_scrimmage = ball_position_yards
	down_number = 1
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	awaiting_return = false
	_log("[PLAY %03d] RETURN ENDED AT %.1f — NEW SERIES" % [play_id, ball_position_yards])
	_archive(play_id, "RETURN_END", ball_position_yards)
	begin_down()


func change_possession(reason: String, turnover_yards: float) -> void:
	possession_team = get_defense_team()
	last_turnover_reason = reason
	series_turnover_reason = reason
	down_number = 1
	var spot := clampf(turnover_yards, 0.0, FIELD_LENGTH)
	# 四档失败：新进攻方从本方 5 码线重新开球（不再原地换权）
	if reason == "TURNOVER_ON_DOWNS":
		spot = 15.0 if possession_team == "blue" else 55.0
	ball_position_yards = spot
	line_of_scrimmage = spot
	first_down_line = target_line_for(possession_team, line_of_scrimmage)
	phase = 1 if is_equal_approx(first_down_line, MIDFIELD) else 2
	_log("[PLAY %03d] POSSESSION -> %s (%s) AT %.1f TARGET %.1f" % [
		play_id, possession_team.to_upper(), reason, ball_position_yards, first_down_line])
	_archive(play_id, reason, ball_position_yards)
	begin_down()


func _archive(pid: int, reason: String, final_yards: float) -> void:
	play_history.append({
		"play_id": pid,
		"possession": possession_team,
		"down": down_number,
		"los": line_of_scrimmage,
		"first_down": first_down_line,
		"direction": get_attacking_direction(),
		"ball": ball_position_yards,
		"final": final_yards,
		"reason": reason,
		"start": play_started_at,
	})


func debug_lines() -> String:
	return "\n".join(PackedStringArray([
		"PLAY: %03d   STATE: %s" % [play_id, State.keys()[match_state]],
		"OFFENSE: " + possession_team.to_upper() + "   DEFENSE: " + get_defense_team().to_upper(),
		"DOWN: %d   YARDS TO GO: %d" % [down_number, get_yards_to_go()],
		"BALL: %.1f   LOS: %.1f   FIRST DOWN: %.1f" % [ball_position_yards, line_of_scrimmage, first_down_line],
		"DIRECTION: " + ("+" if get_attacking_direction() > 0.0 else "-"),
		"CURRENT EVENT: " + ("—" if last_event == "" else last_event),
		"SERIES START: " + ("—" if series_turnover_reason == "" else series_turnover_reason),
		"TURNOVER HISTORY: " + ("—" if last_turnover_reason == "" else last_turnover_reason),
	]))
