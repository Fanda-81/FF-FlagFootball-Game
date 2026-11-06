extends SceneTree
## 诊断：不同动画模式下，角色脚底（ToeBase/Foot 骨骼）的世界高度。

const CHARACTER := preload("res://assets/models/characters/FFfemale.glb")
const RUN_PATH := "res://assets/models/characters/FastRun.glb"
const IDLE_PATH := "res://assets/models/characters/Idle.glb"
const TARGET_HEIGHT := 1.82
const MODES := ["bind", "own", "idle", "fastrun"]

var _index := 0
var _frames := 0
var _holder: Node3D
var _model: Node3D
var _skeleton: Skeleton3D
var _scale := 1.0


func _initialize() -> void:
	_spawn(MODES[0])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	_measure(MODES[_index])
	_holder.queue_free()
	_index += 1
	_frames = 0
	if _index >= MODES.size():
		quit(0)
		return true
	_spawn(MODES[_index])
	return false


func _spawn(mode: String) -> void:
	_holder = Node3D.new()
	root.add_child(_holder)
	_model = CHARACTER.instantiate() as Node3D
	_holder.add_child(_model)

	var bounds := _model_bounds(_model)
	_scale = TARGET_HEIGHT / maxf(0.001, bounds.size.y)
	_model.scale = Vector3.ONE * _scale
	_model.position.y = -bounds.position.y * _scale

	_skeleton = _find_skeleton(_model)
	var player := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	match mode:
		"own":
			player.play(player.get_animation_library("").get_animation_list()[0])
		"idle", "fastrun":
			var path := IDLE_PATH if mode == "idle" else RUN_PATH
			var source := MixamoRetarget.load_source_animation(path)
			var rests := MixamoRetarget.read_rest_rotations(path)
			var clip := MixamoRetarget.build_animation(source, rests, _skeleton, "RootNode/HIFER/Skeleton3D")
			var library := AnimationLibrary.new()
			library.add_animation("clip", clip)
			player.add_animation_library("ff", library)
			player.play("ff/clip")


func _measure(mode: String) -> void:
	var lowest := INF
	var highest := -INF
	for bone_name in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin
		lowest = minf(lowest, world.y)
		highest = maxf(highest, world.y)
	print("  [%-7s] 脚部骨骼世界高度 min=%+.3f max=%+.3f  (缩放 %.4f)" % [mode, lowest, highest, _scale])


func _model_bounds(root_node: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null