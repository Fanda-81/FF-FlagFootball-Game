extends RefCounted
class_name OutfitSaveManager
## 穿搭存档：JSON 存在 user://outfit_save.json
##
## 存档内容：
##   equipped = { "shirt": "shirt_home", "pants": "pants_short", ... }
##   colors   = { "shirt:shirt_home": ["ff0000", ...], ... }
##
## 读档时把状态交给 OutfitManager.restore()，颜色和穿着都会恢复。

const SAVE_PATH := "user://outfit_save.json"
const FORMAT_VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func save(manager: OutfitManager) -> bool:
	if manager == null:
		return false
	var payload := {
		"version": FORMAT_VERSION,
		"outfit": manager.state(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("OutfitSaveManager: 无法写入 %s" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


## 读档并应用；没有存档或解析失败时，回退到默认穿搭并返回 false。
static func load_into(manager: OutfitManager) -> bool:
	if manager == null:
		return false
	if not has_save():
		manager.reset_outfit()
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		manager.reset_outfit()
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("OutfitSaveManager: 存档格式不对，使用默认穿搭")
		manager.reset_outfit()
		return false
	var data: Dictionary = parsed
	var outfit: Variant = data.get("outfit", {})
	if typeof(outfit) != TYPE_DICTIONARY:
		manager.reset_outfit()
		return false
	manager.restore(outfit)
	return true


static func delete_save() -> bool:
	if not has_save():
		return false
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var directory := DirAccess.open("user://")
	if directory == null:
		return false
	return directory.remove("outfit_save.json") == OK


## 存档文件所在路径（UI 上显示用）
static func save_path() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)
