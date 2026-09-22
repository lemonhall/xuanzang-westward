extends Node
## Progress, resources and persistence (REQ-0001-003, REQ-0001-010).

const SAVE_PATH := "user://save.json"
const MAX_COMPOSURE := 3
const MAX_FOCUS := 100

signal composure_changed(value: int)
signal focus_changed(value: int)
signal level_completed(level_id: String)

var composure: int = MAX_COMPOSURE
var focus: int = MAX_FOCUS
var unlocked_levels: Array[String] = ["l01"]
var completed_levels: Array[String] = []
var collected: Dictionary = {}
var checkpoint_id: String = "start"
var current_level: String = "l01"


func reset_run() -> void:
	composure = MAX_COMPOSURE
	focus = MAX_FOCUS
	checkpoint_id = "start"
	composure_changed.emit(composure)
	focus_changed.emit(focus)


func spend_focus(amount: int) -> bool:
	if focus < amount:
		return false
	focus -= amount
	focus_changed.emit(focus)
	return true


func gain_focus(amount: int) -> void:
	focus = clampi(focus + amount, 0, MAX_FOCUS)
	focus_changed.emit(focus)


func damage_composure(amount: int = 1) -> void:
	composure = clampi(composure - amount, 0, MAX_COMPOSURE)
	composure_changed.emit(composure)


func complete_level(level_id: String) -> void:
	if not completed_levels.has(level_id):
		completed_levels.append(level_id)
	var index := _level_index(level_id)
	var next := "l%02d" % (index + 1)
	if index < 7 and not unlocked_levels.has(next):
		unlocked_levels.append(next)
	level_completed.emit(level_id)
	save_progress()


func collect(item_id: String) -> void:
	collected[item_id] = int(collected.get(item_id, 0)) + 1


func to_dict() -> Dictionary:
	return {
		"unlocked_levels": unlocked_levels,
		"completed_levels": completed_levels,
		"collected": collected,
		"current_level": current_level,
		"checkpoint_id": checkpoint_id,
	}


func apply_dict(data: Dictionary) -> void:
	unlocked_levels.assign(data.get("unlocked_levels", ["l01"]))
	completed_levels.assign(data.get("completed_levels", []))
	collected = data.get("collected", {})
	current_level = data.get("current_level", "l01")
	checkpoint_id = data.get("checkpoint_id", "start")


func save_progress(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("save failed: %s" % path)
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


func load_progress(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("save file is not a JSON object: %s" % path)
		return false
	apply_dict(parsed)
	return true


func _level_index(level_id: String) -> int:
	return int(level_id.substr(1))
