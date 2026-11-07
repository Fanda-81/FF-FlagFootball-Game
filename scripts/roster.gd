extends RefCounted
class_name Roster
## 球员名单：每个位置的名字 + 装备主色，存在 user://roster.json
##
## 首次运行随机生成名字；玩家改名/改色后保存，下次进游戏自动读回。

const SAVE_PATH := "user://roster.json"
const SLOTS := ["QB", "C", "X", "Y", "Z", "CB", "LB", "S"]

const SURNAMES := ["林", "陈", "张", "王", "李", "赵", "周", "吴", "徐", "孙", "马", "高", "何", "罗", "梁", "宋"]
const GIVEN := ["小北", "一鸣", "子豪", "雨晨", "嘉树", "思远", "若雪", "一诺", "天佑", "明轩", "星辰", "可欣", "书航", "泽宇"]

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _load_from_disk()


static func _random_name() -> String:
	return SURNAMES[randi() % SURNAMES.size()] + GIVEN[randi() % GIVEN.size()]


static func _random_tint(index: int) -> String:
	var palette := ["#2f7cf6", "#37c26a", "#ffb03a", "#d9333f", "#8c5cf6", "#12b3c4", "#e2543f", "#f2f5fa"]
	return palette[index % palette.size()]


static func _load_from_disk() -> Dictionary:
	var out := {"teams": {"offense": "#2f7cf6", "defense": "#e2543f"}}
	for i in SLOTS.size():
		out[SLOTS[i]] = {"name": _random_name(), "tint": _random_tint(i)}

	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return out
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = parsed
	for slot in SLOTS:
		if not data.has(slot):
			continue
		var entry: Variant = data[slot]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		out[slot]["name"] = String(dict.get("name", out[slot]["name"]))
		out[slot]["tint"] = String(dict.get("tint", out[slot]["tint"]))
	return out


static func save() -> bool:
	_ensure()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Roster: 无法写入 " + SAVE_PATH)
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true


static func team_color(team: String) -> Color:
	_ensure()
	var teams: Dictionary = _data.get("teams", {})
	var fallback := "#2f7cf6" if team == "offense" else "#e2543f"
	return Color.html(String(teams.get(team, fallback)))


static func set_team_color(team: String, color: Color) -> void:
	_ensure()
	if not _data.has("teams"):
		_data["teams"] = {"offense": "#2f7cf6", "defense": "#e2543f"}
	(_data["teams"] as Dictionary)[team] = color.to_html(false)


static func player_name(slot: String) -> String:
	_ensure()
	if not _data.has(slot):
		return slot
	return String((_data[slot] as Dictionary).get("name", slot))


static func player_tint(slot: String) -> Color:
	_ensure()
	if not _data.has(slot):
		return Color.WHITE
	return Color.html(String((_data[slot] as Dictionary).get("tint", "#ffffff")))


static func set_player_name(slot: String, value: String) -> void:
	_ensure()
	if not _data.has(slot):
		return
	(_data[slot] as Dictionary)["name"] = value.strip_edges()


static func set_player_tint(slot: String, color: Color) -> void:
	_ensure()
	if not _data.has(slot):
		return
	(_data[slot] as Dictionary)["tint"] = color.to_html(false)


static func slot_label(slot: String) -> String:
	match slot:
		"QB":
			return "四分卫 QB"
		"C":
			return "中锋 C"
		"CB":
			return "角卫 CB"
		"LB":
			return "线卫 LB"
		"S":
			return "安全卫 S"
		_:
			return "外接手 " + slot