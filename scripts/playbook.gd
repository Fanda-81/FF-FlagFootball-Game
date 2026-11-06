extends RefCounted
class_name Playbook
## 战术板：6 套腰旗战术（每套有自己的站位）
##
## 每套战术包含：
##   formation —— 5 名进攻球员相对启球线的站位 {slot: {x, dz}}
##   routes    —— X / Y / Z 的路线（相对各自站位的偏移，z 正 = 朝端区）
##
## 所有路线点在 main.gd 的 _build_routes() 里会被夹进白色边线以内。

const PLAYS := [
	{
		"id": "mesh",
		"name": "网式",
		"hint": "深柱 + 浅交叉 + 外切",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -10.0, "dz": 0.3}, "Y": {"x": 6.8, "dz": 0.3}, "Z": {"x": 10.4, "dz": -0.8},
		},
		"routes": {
			"X": [Vector3(-0.4, 0.0, 10.0), Vector3(-0.4, 0.0, 20.0), Vector3(0.6, 0.0, 29.0)],
			"Y": [Vector3(-0.4, 0.0, 8.0), Vector3(-4.0, 0.0, 16.0), Vector3(-8.5, 0.0, 23.0)],
			"Z": [Vector3(0.8, 0.0, 6.0), Vector3(-0.3, 0.0, 14.0), Vector3(-3.4, 0.0, 22.0)],
		},
	},
	{
		"id": "verticals",
		"name": "全线冲刺",
		"hint": "三人拉开齐冲前场",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -11.6, "dz": 0.2}, "Y": {"x": -1.5, "dz": 0.2}, "Z": {"x": 10.6, "dz": 0.2},
		},
		"routes": {
			"X": [Vector3(0.2, 0.0, 12.0), Vector3(0.2, 0.0, 23.0), Vector3(0.0, 0.0, 33.0)],
			"Y": [Vector3(0.1, 0.0, 12.0), Vector3(0.1, 0.0, 24.0), Vector3(0.0, 0.0, 35.0)],
			"Z": [Vector3(-0.2, 0.0, 12.0), Vector3(-0.2, 0.0, 25.0), Vector3(0.0, 0.0, 37.0)],
		},
	},
	{
		"id": "slants",
		"name": "斜插",
		"hint": "三个人从不同位置快速内切",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -7.0, "dz": 0.4}, "Y": {"x": 2.5, "dz": 0.4}, "Z": {"x": 9.0, "dz": -0.4},
		},
		"routes": {
			"X": [Vector3(1.8, 0.0, 4.5), Vector3(4.0, 0.0, 8.0), Vector3(6.2, 0.0, 11.0)],
			"Y": [Vector3(-2.0, 0.0, 4.5), Vector3(-4.2, 0.0, 8.5), Vector3(-6.4, 0.0, 11.5)],
			"Z": [Vector3(-2.4, 0.0, 5.5), Vector3(-4.8, 0.0, 9.5), Vector3(-7.2, 0.0, 12.5)],
		},
	},
	{
		"id": "curl",
		"name": "回身",
		"hint": "跑到位置再折回来接球",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -9.4, "dz": 0.4}, "Y": {"x": 6.0, "dz": 0.4}, "Z": {"x": 11.4, "dz": -0.6},
		},
		"routes": {
			"X": [Vector3(-0.3, 0.0, 9.0), Vector3(-0.3, 0.0, 14.0), Vector3(0.3, 0.0, 8.5)],
			"Y": [Vector3(0.2, 0.0, 9.0), Vector3(0.2, 0.0, 14.0), Vector3(-0.2, 0.0, 8.5)],
			"Z": [Vector3(-0.4, 0.0, 10.0), Vector3(-0.4, 0.0, 15.0), Vector3(0.2, 0.0, 9.0)],
		},
	},
	{
		"id": "flood",
		"name": "洪泛",
		"hint": "三人集中一侧，一深两浅",
		"formation": {
			"QB": {"x": -1.0, "dz": -2.2}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -11.0, "dz": 0.2}, "Y": {"x": 3.0, "dz": 0.3}, "Z": {"x": 8.5, "dz": -0.6},
		},
		"routes": {
			"X": [Vector3(-0.2, 0.0, 11.0), Vector3(-0.2, 0.0, 21.0), Vector3(0.4, 0.0, 30.0)],
			"Y": [Vector3(-1.2, 0.0, 5.0), Vector3(0.8, 0.0, 9.0), Vector3(2.6, 0.0, 12.0)],
			"Z": [Vector3(0.6, 0.0, 7.0), Vector3(-0.4, 0.0, 12.0), Vector3(-1.6, 0.0, 7.5)],
		},
	},
	{
		"id": "screen",
		"name": "屏风",
		"hint": "快速外切，球到人到",
		"formation": {
			"QB": {"x": 0.0, "dz": -2.4}, "C": {"x": 0.0, "dz": 0.0},
			"X": {"x": -6.5, "dz": 0.5}, "Y": {"x": 5.5, "dz": 0.5}, "Z": {"x": 10.0, "dz": 0.0},
		},
		"routes": {
			"X": [Vector3(-2.6, 0.0, 3.0), Vector3(-4.2, 0.0, 5.5), Vector3(-5.0, 0.0, 8.0)],
			"Y": [Vector3(2.6, 0.0, 3.0), Vector3(4.2, 0.0, 5.5), Vector3(5.0, 0.0, 8.0)],
			"Z": [Vector3(1.6, 0.0, 4.0), Vector3(1.8, 0.0, 6.5), Vector3(1.2, 0.0, 9.0)],
		},
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
