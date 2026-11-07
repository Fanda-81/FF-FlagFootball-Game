extends RefCounted
class_name AnimLibrary
## FF 动作库：所有外部动作（从 FFSIMU / Mixamo 的 FBX 转成的 glb）统一登记在这里。
##
##     AnimLibrary.install(player, skeleton, prefix, ["idle_huddle"])
##     player.play("ff/idle_huddle")
##
## 新增动作：FBX → glb 放进 assets/models/anims/ → 在 CLIPS 里加一行。

const CLIP_DIR := "res://assets/models/anims/"

const CLIPS := {
	# 合练站姿（Huddle Posture01.fbx）
	"idle_huddle": {"file": "HuddlePosture01.glb", "retarget": true, "mode": "delta"},
	# 静止站立（静止站立.fbx）
	"idle_stand": {"file": "Idle.glb", "retarget": true},
	# 沮丧/失败动作（Defeated.fbx，6.7 秒）
	"defeat": {"file": "Defeated.glb", "retarget": true},
	# 跑步循环（111111.glb，自带根位移，重定时会剥掉）
	"run": {"file": "RunClip.glb", "retarget": true},
}


static func has_clip(clip_name: String) -> bool:
	return CLIPS.has(clip_name)


static func clip_names() -> Array:
	return CLIPS.keys()


## 取一个动作，重定向到目标骨架，返回可以直接播的 Animation。
static func load_clip(clip_name: String, skeleton: Skeleton3D, prefix: String) -> Animation:
	if not CLIPS.has(clip_name):
		push_error("AnimLibrary: 没有登记动作 " + clip_name)
		return null
	var entry: Dictionary = CLIPS[clip_name]
	var path := CLIP_DIR + String(entry["file"])
	var source := MixamoRetarget.load_source_animation(path)
	if source == null:
		return null
	if bool(entry.get("retarget", true)):
		var rests := MixamoRetarget.read_rest_rotations(path)
		if String(entry.get("mode", "world")) == "delta":
			return MixamoRetarget.build_animation(source, rests, skeleton, prefix)
		var parents := MixamoRetarget.read_hierarchy(path)
		return MixamoRetarget.build_world_animation(source, rests, parents, skeleton, prefix)
	return MixamoRetarget.strip_to_rotations(source)


## 把动作库里指定的几个动作装进 AnimationPlayer，命名规则 "ff/<动作名>"。
static func install(player: AnimationPlayer, skeleton: Skeleton3D, prefix: String, names: Array) -> int:
	var library := AnimationLibrary.new()
	var count := 0
	for clip_name in names:
		var animation := load_clip(String(clip_name), skeleton, prefix)
		if animation == null:
			continue
		library.add_animation(String(clip_name), animation)
		count += 1
	if player.has_animation_library("ff"):
		player.remove_animation_library("ff")
	if count > 0:
		player.add_animation_library("ff", library)
	return count