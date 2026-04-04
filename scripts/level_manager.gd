extends RefCounted
## Manages level navigation, progress tracking, and persistence.

# Preloads force these levels into exported builds where directory scanning can be incomplete.
const WORLD_1_LEVEL_SCENES: Array[PackedScene] = [
	preload("res://scenes/Levels/World 1/W1L01.tscn"),
	preload("res://scenes/Levels/World 1/W1L02.tscn"),
	preload("res://scenes/Levels/World 1/W1L03.tscn"),
	preload("res://scenes/Levels/World 1/W1L04.tscn"),
	preload("res://scenes/Levels/World 1/W1L05.tscn"),
	preload("res://scenes/Levels/World 1/W1L06.tscn"),
	preload("res://scenes/Levels/World 1/W1L07.tscn"),
	preload("res://scenes/Levels/World 1/W1L08.tscn"),
	preload("res://scenes/Levels/World 1/W1L09.tscn"),
	preload("res://scenes/Levels/World 1/W1L10.tscn"),
	preload("res://scenes/Levels/World 1/W1L11.tscn"),
	preload("res://scenes/Levels/World 1/W1L12.tscn"),
	preload("res://scenes/Levels/World 1/W1L13.tscn"),
	preload("res://scenes/Levels/World 1/W1L14.tscn"),
	preload("res://scenes/Levels/World 1/W1L15.tscn")
]

const WORLD_LEVEL_CATALOG := {
	"World 1": WORLD_1_LEVEL_SCENES
}

var current_level_path: String = ""
var levels_root_prefix: String = "res://scenes/Levels/"
var _progress: Dictionary = {}


func get_progress(level_path: String) -> Dictionary:
	return _progress.get(level_path, {
		"high_score": 0,
		"best_stars": 0,
		"passed": false
	})


func update_progress(level_path: String, achieved_score: int, star_count: int) -> Dictionary:
	if level_path.is_empty():
		return {"high_score": achieved_score, "best_stars": star_count, "passed": star_count >= 1}

	var entry: Dictionary = _progress.get(level_path, {
		"high_score": 0,
		"best_stars": 0,
		"passed": false
	})

	entry["high_score"] = max(int(entry.get("high_score", 0)), achieved_score)
	entry["best_stars"] = max(int(entry.get("best_stars", 0)), star_count)
	entry["passed"] = bool(entry.get("passed", false)) or star_count >= 1

	_progress[level_path] = entry
	save_progress()
	return entry


func get_next_level_path(level_path: String) -> String:
	if level_path.is_empty():
		return ""
	var world_path := level_path.get_base_dir()
	var current_name := level_path.get_file()
	var dir := DirAccess.open(world_path)
	var levels: Array[String] = []
	if dir != null:
		dir.list_dir_begin()
		while true:
			var file_name := dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			if file_name.ends_with(".tscn"):
				levels.append("%s/%s" % [world_path, file_name])
		dir.list_dir_end()

	if levels.is_empty():
		levels = _get_catalog_paths_for_world(world_path)

	if levels.is_empty():
		return ""
	levels.sort()
	var idx := levels.find(level_path)
	if idx == -1:
		idx = levels.find("%s/%s" % [world_path, current_name])
	if idx == -1:
		return ""
	if idx + 1 >= levels.size():
		return ""
	return levels[idx + 1]


func is_level_scene(path: String) -> bool:
	if path.is_empty() or not path.ends_with(".tscn"):
		return false
	if path.begins_with(levels_root_prefix):
		return true
	return path.contains("/Levels/")


func extract_level_number(level_path: String) -> int:
	if level_path.is_empty():
		return -1
	var file_name := level_path.get_file().trim_suffix(".tscn")
	var marker := file_name.rfind("L")
	if marker == -1:
		return -1
	var suffix := file_name.substr(marker + 1)
	if not suffix.is_valid_int():
		return -1
	return int(suffix)


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "levels", _progress)
	cfg.save("user://level_progress.cfg")


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://level_progress.cfg") != OK:
		_progress = {}
		return
	var data: Variant = cfg.get_value("progress", "levels", {})
	if data is Dictionary:
		_progress = data
	else:
		_progress = {}


func _get_catalog_paths_for_world(world_path: String) -> Array[String]:
	var result: Array[String] = []
	var world_name := world_path.get_file()
	if not WORLD_LEVEL_CATALOG.has(world_name):
		return result

	for scene: PackedScene in WORLD_LEVEL_CATALOG[world_name]:
		if scene == null:
			continue
		var path := scene.resource_path
		if path.is_empty():
			continue
		if not ResourceLoader.exists(path):
			continue
		result.append(path)

	result.sort()
	return result
