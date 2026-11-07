extends RefCounted
class_name Playbook
## 战术板：战术 = **路线的组合**
##
## 每套战术给 5 名进攻球员各指定一条 RouteLibrary 里的标准路线，
## 路线点由 RouteLibrary.build() 生成，main.gd 只负责让球员沿点跑。

const PLAYS := [
	{
		"id": "mesh", "name": "网式", "hint": "纵深 + 斜插 + 外切",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -10.0, "dz": 0.3}, "Y": {"x": 6.8, "dz": 0.3}, "Z": {"x": 10.4, "dz": -0.8},
		},
		"routes": {"X": "go", "Y": "post", "Z": "out", "C": "short_out"},
	},
	{
		"id": "verticals", "name": "全线冲刺", "hint": "三个人都跑纵深",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -11.6, "dz": 0.2}, "Y": {"x": -1.5, "dz": 0.2}, "Z": {"x": 10.6, "dz": 0.2},
		},
		"routes": {"X": "go", "Y": "go", "Z": "go", "C": "short_out"},
	},
	{
		"id": "slants", "name": "斜插", "hint": "快速内切，适合短传",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -7.0, "dz": 0.4}, "Y": {"x": 2.5, "dz": 0.4}, "Z": {"x": 9.0, "dz": -0.4},
		},
		"routes": {"X": "slant", "Y": "slant", "Z": "in", "C": "short_out"},
	},
	{
		"id": "curl", "name": "回身", "hint": "跑到点折回来接球",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -9.4, "dz": 0.4}, "Y": {"x": 6.0, "dz": 0.4}, "Z": {"x": 11.4, "dz": -0.6},
		},
		"routes": {"X": "curl", "Y": "curl", "Z": "curl", "C": "in"},
	},
	{
		"id": "flood", "name": "洪泛", "hint": "一深两浅，拉开防守",
		"formation": {
			"QB": {"x": -1.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -11.0, "dz": 0.2}, "Y": {"x": 3.0, "dz": 0.3}, "Z": {"x": 8.5, "dz": -0.6},
		},
		"routes": {"X": "go", "Y": "out", "Z": "drag", "C": "short_out"},
	},
	{
		"id": "screen", "name": "屏风", "hint": "快速外切，球到人到",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.4}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -6.5, "dz": 0.5}, "Y": {"x": 5.5, "dz": 0.5}, "Z": {"x": 10.0, "dz": 0.0},
		},
		"routes": {"X": "short_out", "Y": "short_out", "Z": "corner", "C": "short_out"},
	},
	{
		"id": "inside_run", "name": "中路跑球", "hint": "交球给跑锋，中路突破", "kind": "run",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -10.5, "dz": 0.3}, "Y": {"x": 0.6, "dz": -4.6}, "Z": {"x": 10.2, "dz": 0.2},
		},
		"routes": {"X": "go", "Y": "short_out", "Z": "out", "C": "short_out"},
	},
	{
		"id": "outside_run", "name": "外侧跑球", "hint": "交球给跑锋，外线突破", "kind": "run",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -10.5, "dz": 0.3}, "Y": {"x": -0.6, "dz": -4.6}, "Z": {"x": 10.2, "dz": 0.2},
		},
		"routes": {"X": "go", "Y": "out", "Z": "go", "C": "short_out"},
	},
]


static func play_ids() -> Array:
	var ids: Array = []
	for play in PLAYS:
		ids.append(String(play["id"]))
	return ids


static func get_play(play_id: String) -> Dictionary:
	for play in PLAYS:
		if String(play["id"]) == play_id:
			return play
	return PLAYS[0]


static func play_name(play_id: String) -> String:
	return String(get_play(play_id)["name"])


static func count() -> int:
	return PLAYS.size()