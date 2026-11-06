extends RefCounted
class_name MixamoRetarget
## Mixamo 动画重定向工具（相对静止姿势 / delta retarget）
##
## 为什么不能直接套用：
##   FFfemale.fbx 和 Fast Run.fbx 虽然都是 Mixamo 骨架、骨骼名一字不差，
##   但两个文件的**静止姿势（rest pose）和单位并不相同**：
##     · FFfemale 的 Hips 静止位置是 (0, 6.29, 0)，局部旋转约 100°（Z-up 转换痕迹）
##     · Fast Run 的 Hips 静止位置是 (0, 1.04, 0)，局部旋转约 0°
##   把 FastRun 的绝对局部变换直接写到角色身上，角色会被放倒、缩成一团。
##
## 做法：
##   只取旋转轨道，并把每帧旋转换算成"相对源静止姿势的增量"，再叠加到目标骨骼的静止姿势上：
##       target = target_rest * (source_rest⁻¹ * key)
##   位置和缩放轨道全部丢弃 —— 这正是"固定 Hip"的效果：
##   髋部既不会上下起伏，也不会产生根位移，跑动在原地循环。

## 读取一个 glb 里每根骨骼的静止旋转（骨骼名 → 四元数）。
static func read_rest_rotations(resource_path: String) -> Dictionary:
	var rest := {}
	var packed := load(resource_path) as PackedScene
	if packed == null:
		push_error("MixamoRetarget: 无法加载 " + resource_path)
		return rest
	var root := packed.instantiate()
	# 带蒙皮的完整角色：骨骼在 Skeleton3D 里，不是场景节点，必须从骨架读。
	var skeleton := _find_skeleton(root)
	if skeleton != null:
		for i in skeleton.get_bone_count():
			rest[skeleton.get_bone_name(i)] = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	else:
		_collect_rests(root, rest)
	root.queue_free()
	return rest


static func _collect_rests(node: Node, out: Dictionary) -> void:
	if node is Node3D and String(node.name).begins_with("mixamorig_"):
		out[String(node.name)] = (node as Node3D).quaternion
	for child in node.get_children():
		_collect_rests(child, out)


## 从 glb 里取出第一个 Animation。
static func load_source_animation(resource_path: String) -> Animation:
	var packed := load(resource_path) as PackedScene
	if packed == null:
		push_error("MixamoRetarget: 无法加载 " + resource_path)
		return null
	var root := packed.instantiate()
	var player := _find_animation_player(root)
	var animation: Animation = null
	if player != null:
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			var list := library.get_animation_list()
			if list.size() > 0:
				animation = library.get_animation(list[0])
				break
	root.queue_free()
	if animation == null:
		push_error("MixamoRetarget: " + resource_path + " 里没有动画")
	return animation


## 生成可以直接播在目标骨架上的动画。
##   source:        源动画
##   source_rests:  源骨架的静止旋转（read_rest_rotations 的结果）
##   skeleton:      目标 Skeleton3D
##   prefix:        相对 AnimationPlayer 根节点的骨架路径
static func build_animation(source: Animation, source_rests: Dictionary, skeleton: Skeleton3D, prefix: String) -> Animation:
	var out := Animation.new()
	out.length = source.length
	out.step = source.step
	out.loop_mode = Animation.LOOP_LINEAR

	var kept := 0
	var dropped := 0
	for track_index in source.get_track_count():
		var bone := _bone_name_of(source.track_get_path(track_index))
		# 只处理旋转；位置/缩放一律丢弃（固定 Hip + 单位不一致）。
		if source.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			dropped += 1
			continue
		var bone_index := skeleton.find_bone(bone)
		if bone_index < 0 or not source_rests.has(bone):
			dropped += 1
			continue
		var target_rest: Quaternion = skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
		var source_rest: Quaternion = source_rests[bone]
		var source_rest_inverse := source_rest.inverse()

		var new_index := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(new_index, NodePath(prefix + ":" + bone))
		out.track_set_interpolation_type(new_index, source.track_get_interpolation_type(track_index))
		for key_index in source.track_get_key_count(track_index):
			var absolute: Quaternion = source.track_get_key_value(track_index, key_index)
			var delta := source_rest_inverse * absolute
			out.track_insert_key(
				new_index,
				source.track_get_key_time(track_index, key_index),
				target_rest * delta)
		kept += 1

	if kept == 0:
		push_error("MixamoRetarget: 没有任何旋转轨道匹配上目标骨架")
	return out


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var hit := _find_animation_player(child)
		if hit != null:
			return hit
	return null

## 同一套骨架的动画（例如模型自带的跑步）：保留原始旋转，但剥掉位移和缩放轨道。
## 这样髋部固定、不会产生根位移，角色在原地跑。
static func strip_to_rotations(source: Animation) -> Animation:
	var out := Animation.new()
	out.length = source.length
	out.step = source.step
	out.loop_mode = Animation.LOOP_LINEAR
	for track_index in source.get_track_count():
		if source.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		var new_index := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(new_index, source.track_get_path(track_index))
		out.track_set_interpolation_type(new_index, source.track_get_interpolation_type(track_index))
		for key_index in source.track_get_key_count(track_index):
			out.track_insert_key(
				new_index,
				source.track_get_key_time(track_index, key_index),
				source.track_get_key_value(track_index, key_index))
	return out

# =============================================================================
# 世界空间重定向（两套骨架局部轴不一致时用这个）
# =============================================================================

## 读取骨骼父子关系（子骨骼名 -> 父骨骼名，只保留 mixamorig_* ）。
static func read_hierarchy(resource_path: String) -> Dictionary:
	var parents := {}
	var packed := load(resource_path) as PackedScene
	if packed == null:
		return parents
	var scene_root := packed.instantiate()
	var skeleton := _find_skeleton(scene_root)
	if skeleton != null:
		for i in skeleton.get_bone_count():
			var parent_index := skeleton.get_bone_parent(i)
			parents[skeleton.get_bone_name(i)] = skeleton.get_bone_name(parent_index) if parent_index >= 0 else ""
	else:
		_collect_parents(scene_root, "", parents)
	scene_root.queue_free()
	return parents


static func _collect_parents(node: Node, parent_name: String, out: Dictionary) -> void:
	var name := String(node.name)
	var is_bone := name.begins_with("mixamorig_")
	if is_bone:
		out[name] = parent_name if parent_name.begins_with("mixamorig_") else ""
	for child in node.get_children():
		_collect_parents(child, name if is_bone else parent_name, out)


## 世界空间重定向：
##   1. 分别算出源骨架和目标骨架在静止姿势下每根骨骼的"世界旋转"；
##   2. 每根骨骼记一个固定偏移 K = 目标世界静止 × 源世界静止⁻¹；
##   3. 播放时：目标世界 = K × 源世界(t)，再转回局部。
## 这样即使两套骨架的局部轴系不同（本工程的 FFfemale 髋部带有 100° 轴转换残留），
## 动作方向也不会翻掉。
static func build_world_animation(source: Animation, rests: Dictionary, parents: Dictionary,
		skeleton: Skeleton3D, prefix: String, sample_rate := 30.0) -> Animation:
	var bone_names: Array[String] = []
	var bone_index := {}
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		bone_names.append(name)
		bone_index[name] = i

	# 源骨架静止世界旋转
	var source_rest_world := {}
	for name in bone_names:
		if not rests.has(name):
			continue
		var parent: String = parents.get(name, "")
		var parent_rot: Quaternion = source_rest_world.get(parent, Quaternion.IDENTITY)
		source_rest_world[name] = parent_rot * (rests[name] as Quaternion)

	# 目标骨架静止世界旋转
	var target_rest_world := {}
	for name in bone_names:
		var index: int = bone_index[name]
		var parent_index := skeleton.get_bone_parent(index)
		var parent_rot := Quaternion.IDENTITY
		if parent_index >= 0:
			parent_rot = target_rest_world.get(skeleton.get_bone_name(parent_index), Quaternion.IDENTITY)
		target_rest_world[name] = parent_rot * skeleton.get_bone_rest(index).basis.get_rotation_quaternion()

	# 每根骨骼的固定偏移
	var offset := {}
	for name in bone_names:
		if not source_rest_world.has(name) or not target_rest_world.has(name):
			continue
		offset[name] = (target_rest_world[name] as Quaternion) * (source_rest_world[name] as Quaternion).inverse()

	# 源动画里每根骨骼的旋转轨道
	var tracks := {}
	for t in source.get_track_count():
		if source.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := _bone_name_of(source.track_get_path(t))
		if bone_index.has(bone):
			tracks[bone] = t

	var out := Animation.new()
	out.length = source.length
	out.step = source.step
	out.loop_mode = Animation.LOOP_LINEAR
	var out_tracks := {}
	for name in bone_names:
		if offset.has(name):
			out_tracks[name] = out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(out_tracks[name], NodePath(prefix + ":" + name))

	var samples := maxi(2, int(ceil(source.length * sample_rate)) + 1)
	for s in samples:
		var time := source.length * float(s) / float(samples - 1)
		# 源骨架当前帧的世界旋转
		var source_world := {}
		for name in bone_names:
			var local: Quaternion = rests.get(name, Quaternion.IDENTITY)
			if tracks.has(name):
				local = _sample_rotation(source, tracks[name], time)
			var parent: String = parents.get(name, "")
			var parent_rot: Quaternion = source_world.get(parent, Quaternion.IDENTITY)
			source_world[name] = parent_rot * local
		# 目标世界 -> 局部
		for name in bone_names:
			if not out_tracks.has(name):
				continue
			var target_world: Quaternion = (offset[name] as Quaternion) * (source_world.get(name, Quaternion.IDENTITY) as Quaternion)
			var parent: String = parents.get(name, "")
			var parent_world := Quaternion.IDENTITY
			if parent != "" and offset.has(parent):
				parent_world = (offset[parent] as Quaternion) * (source_world.get(parent, Quaternion.IDENTITY) as Quaternion)
			out.track_insert_key(out_tracks[name], time, parent_world.inverse() * target_world)
	return out


static func _sample_rotation(animation: Animation, track: int, time: float) -> Quaternion:
	var keys := animation.track_get_key_count(track)
	if keys == 0:
		return Quaternion.IDENTITY
	var first_time: float = animation.track_get_key_time(track, 0)
	if time <= first_time:
		return animation.track_get_key_value(track, 0)
	var last_time: float = animation.track_get_key_time(track, keys - 1)
	if time >= last_time:
		return animation.track_get_key_value(track, keys - 1)
	for i in range(keys - 1):
		var t0: float = animation.track_get_key_time(track, i)
		var t1: float = animation.track_get_key_time(track, i + 1)
		if time >= t0 and time <= t1:
			var a: Quaternion = animation.track_get_key_value(track, i)
			var b: Quaternion = animation.track_get_key_value(track, i + 1)
			var span := maxf(0.0001, t1 - t0)
			return a.slerp(b, (time - t0) / span)
	return animation.track_get_key_value(track, keys - 1)
## 从轨道路径里取出骨骼名：兼容 "RootNode/mixamorig_Hips" 和 "RootNode/HIFER/Skeleton3D:mixamorig_Hips"。
static func _bone_name_of(path: NodePath) -> String:
	if path.get_subname_count() > 0:
		return String(path.get_concatenated_subnames())
	var count := path.get_name_count()
	return String(path.get_name(count - 1)) if count > 0 else ""


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var hit := _find_skeleton(child)
		if hit != null:
			return hit
	return null