extends RefCounted
class_name PenaltyConfig
## 犯规配置表（集中管理，禁止散落在各处）

const PENALTIES := {
	"false_start": {"name": "早动", "probability": 0.04, "yards": 5, "side": "offense", "replay_down": true},
	"offside": {"name": "越线", "probability": 0.04, "yards": 5, "side": "defense", "replay_down": true},
	"flag_guarding": {"name": "护旗", "probability": 0.03, "yards": 5, "side": "offense", "replay_down": false},
	"delay_of_game": {"name": "拖延开球", "probability": 0.0, "yards": 5, "side": "offense", "replay_down": true},
	"pass_interference": {"name": "干扰接球", "probability": 0.03, "yards": 10, "side": "defense", "replay_down": false},
}

## 总开关（测试/演示可关闭）
static var enabled := true
## 固定种子便于复现
static var rng := RandomNumberGenerator.new()


static func config(id: String) -> Dictionary:
	return PENALTIES.get(id, {})


static func roll(id: String) -> bool:
	if not enabled:
		return false
	var c := config(id)
	if c.is_empty():
		return false
	return rng.randf() < float(c.get("probability", 0.0))