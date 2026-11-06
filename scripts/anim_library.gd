extends RefCounted
class_name AnimLibrary
## FF 动作库
##
## 所有外部动作（从 FFSIMU 的 FBX 转成的 glb）统一放在 res://assets/models/anims/，
## 在这里登记一次，游戏里就按名字取用：
##
##     AnimLibrary.install(player, skeleton, prefix, ["idle_huddle", "idle_stand"])
##     player.play("ff/idle_huddle")
##
## 新增动作的步骤：
##   1. FBX2glTF 转成 glb，放进 assets/models/anims/；
##   2. 在 CLIPS 里加一行 { "file": "xxx.glb" }；
##   3. 需要时在 player_actor.gd 里调用。
##
## retarget = true 表示该 glb 的骨架和你的人物骨架不是同一份导出，
## 需要按"静止姿势"做世界空间重定向；同一套骨架的动画可以填 false 直接播。

const CLIP_DIR := "res://assets/models/anims/"

const CLIPS := {
	# 合练站姿（FFSIMU 图片模型/球员模型/最新/Huddle Posture01.fbx）
	"idle_huddle": {"file": "HuddlePosture01.glb", "retarget": true, "mode": "delta"},
	# 静止站立（FFSIMU 动作合集/静止站立.fbx）
	"idle_stand": {"file": "Idle.glb", "retarget": true},
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
			# 两套骨架局部轴相近时用这个：按静止姿势做局部增量
			return MixamoRetarget.build_animation(source, rests, skeleton, prefix)
		var parents := MixamoRetarget.read_hierarchy(path)
		return MixamoRetarget.build_world_animation(source, rests, parents, skeleton, prefix)
	# 同一套骨架：只保留旋转（固定髋部）
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