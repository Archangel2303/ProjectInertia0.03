extends Node

#-----SIGNALS-----
signal ammo_changed(current: int, max_ammo: int)
signal score_changed(score: int)
signal state_changed(state: int)
signal level_changed(level_path: String)
signal run_reset()
signal slow_time_changed(active: bool)
signal game_over_prompt_requested(payload: Dictionary)
signal victory_prompt_requested(payload: Dictionary)
signal level_progress_changed(level_path: String, high_score: int, best_stars: int, passed: bool)

#------ENUMS------
enum GameState { 
	PLAYING, 
	PAUSED, 
	LEVEL_COMPLETE, 
	GAME_OVER 
	}

#------Vars------

var state: int = GameState.PLAYING

var score: int = 0
var _score_decay_accumulator := 0.0
var _last_scene_path := ""
var _score_zero_game_over_triggered := false
var _level_clear_processed := false
var _current_level_reward_doubled := false
var _level_progress: Dictionary = {}
var pending_title_screen: String = ""

@export_group("Scoring")
@export var starting_score: int = 2000
@export var score_decay_per_second: float = 30.0
@export var score_cost_per_shot: int = 45
@export var kill_score_head: int = 500
@export var kill_score_torso: int = 350
@export var kill_score_limb: int = 250
@export var kill_score_extremity: int = 140
@export var star_1_score: int = 900
@export var star_2_score: int = 1400
@export var star_3_score: int = 1900
@export var ad_continue_score: int = 500

var max_ammo: int = 5
var ammo: int = 5

@export var levels_root_prefix := "res://scenes/Levels/"
@export_file("*.tscn") var title_screen_scene_path := "res://scenes/TitleScreen.tscn"
var current_level_path: String = ""

var normal_time_scale := 1.0
var slow_time_scale := 0.2 
@export var max_impact_slow_time_scale := 0.06
@export var spin_for_max_impact := 28.0
@export var slow_time_spin_curve_power := 2.2
var is_slowing_time := false

@export var player_gun_path: NodePath = NodePath("")
@onready var player_gun: RigidBody3D = get_node_or_null(player_gun_path)

func _ready() -> void:
	_load_level_progress()
	emit_signal("state_changed", state)
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)

	# Ensure the exported path is resolved at runtime if set in the inspector
	if player_gun == null and player_gun_path != NodePath(""):
		player_gun = get_node_or_null(player_gun_path)

	if player_gun == null:
		_resolve_player_gun_from_scene()


func _physics_process(delta: float) -> void:
	_update_scene_context()
	_apply_score_decay(delta)
	_check_score_fail_state()

	if not is_slowing_time:
		return

	if player_gun == null:
		_resolve_player_gun_from_scene()

	_update_dynamic_slow_time_scale()

func set_state(value: int) -> void:
	if state == value:
		return
	state = value
	emit_signal("state_changed", state)

func start_level(level_path: String) -> void:
	current_level_path = level_path
	_level_clear_processed = false
	_score_zero_game_over_triggered = false
	_current_level_reward_doubled = false
	set_state(GameState.PLAYING)
	reset_run()
	emit_signal("level_changed", current_level_path)

func reset_run() -> void:
	score = max(0, starting_score)
	_score_decay_accumulator = 0.0
	_score_zero_game_over_triggered = false
	_level_clear_processed = false
	_current_level_reward_doubled = false
	ammo = max_ammo
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("run_reset")

func add_score(amount: int) -> void:
	score = max(0, score + amount)
	emit_signal("score_changed", score)


func spend_score(amount: int) -> void:
	if amount <= 0:
		return
	add_score(-amount)


func register_shot_fired() -> void:
	spend_score(score_cost_per_shot)


func register_kill(hit_type: String) -> void:
	if state != GameState.PLAYING:
		return
	add_score(_get_kill_score_for_hit(hit_type))
	_register_enemy_defeated()


func _get_kill_score_for_hit(hit_type: String) -> int:
	if hit_type == "head":
		return kill_score_head
	if hit_type == "torso":
		return kill_score_torso
	if hit_type == "arm" or hit_type == "leg":
		return kill_score_limb
	if hit_type == "hand" or hit_type == "foot":
		return kill_score_extremity
	return kill_score_torso

func spend_ammo(amount: int=1) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	emit_signal("ammo_changed", ammo, max_ammo)
	return true

func restore_ammo(amount: int=1) -> void:
	ammo = min(ammo + amount, max_ammo)
	emit_signal("ammo_changed", ammo, max_ammo)

func on_player_out_of_ammo() -> void:
	set_state(GameState.GAME_OVER)

func on_level_complete() -> void:
	_set_level_complete_and_emit_victory_prompt()

func restart_level() -> void:
	if current_level_path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(current_level_path)


func continue_to_next_level() -> bool:
	var next_level := _get_next_level_path(current_level_path)
	if next_level.is_empty():
		return false
	get_tree().change_scene_to_file(next_level)
	return true


func watch_ad_continue_from_game_over() -> bool:
	if state != GameState.GAME_OVER:
		return false
	if not _score_zero_game_over_triggered:
		return false

	score = max(score, ad_continue_score)
	_score_zero_game_over_triggered = false
	set_state(GameState.PLAYING)
	emit_signal("score_changed", score)
	return true


func watch_ad_double_victory_rewards() -> bool:
	if state != GameState.LEVEL_COMPLETE:
		return false
	if not _level_clear_processed:
		return false
	if _current_level_reward_doubled:
		return false

	_current_level_reward_doubled = true
	add_score(score)
	_update_level_progress(current_level_path, score)
	return true


func return_to_world_select() -> void:
	pending_title_screen = "world_select"
	_return_to_title_screen()


func return_to_main_menu() -> void:
	pending_title_screen = "main_menu"
	_return_to_title_screen()


func consume_pending_title_screen() -> String:
	var requested := pending_title_screen
	pending_title_screen = ""
	return requested

func start_slow_time() -> void:
	if is_slowing_time:
		return
	is_slowing_time = true
	_update_dynamic_slow_time_scale()
	emit_signal("slow_time_changed", true)
	
func stop_slow_time() -> void:
	if not is_slowing_time:
		return
	is_slowing_time = false
	Engine.time_scale = normal_time_scale
	emit_signal("slow_time_changed", false)


func _update_dynamic_slow_time_scale() -> void:
	var spin_strength := 0.0
	if player_gun != null:
		spin_strength = player_gun.angular_velocity.length()

	var denom: float = maxf(spin_for_max_impact, 0.001)
	var t := clampf(spin_strength / denom, 0.0, 1.0)
	# Accelerate the slow-time response as spin rises so high-spin moments feel more dramatic.
	var curve_power := maxf(slow_time_spin_curve_power, 1.0)
	var curved_t := 1.0 - pow(1.0 - t, curve_power)
	Engine.time_scale = lerpf(slow_time_scale, max_impact_slow_time_scale, curved_t)


func _resolve_player_gun_from_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var found := scene.find_child("PlayerGun", true, false)
	if found is RigidBody3D:
		player_gun = found as RigidBody3D


func _apply_score_decay(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	if current_level_path.is_empty():
		return
	if score <= 0:
		_score_decay_accumulator = 0.0
		return
	if score_decay_per_second <= 0.0:
		return

	_score_decay_accumulator += score_decay_per_second * maxf(delta, 0.0)
	var decay_whole := int(floor(_score_decay_accumulator))
	if decay_whole <= 0:
		return

	_score_decay_accumulator -= float(decay_whole)
	spend_score(decay_whole)


func _check_score_fail_state() -> void:
	if state != GameState.PLAYING:
		return
	if current_level_path.is_empty():
		return
	if score > 0:
		return
	if _score_zero_game_over_triggered:
		return

	_score_zero_game_over_triggered = true
	stop_slow_time()
	set_state(GameState.GAME_OVER)
	emit_signal("game_over_prompt_requested", {
		"reason": "score_zero",
		"title": "Out of Score",
		"message": "Your score reached zero.",
		"continue_score": ad_continue_score,
		"options": ["watch_ad_continue", "retry_level", "world_select", "main_menu"]
	})


func _register_enemy_defeated() -> void:
	if _level_clear_processed:
		return
	if _count_live_enemies() > 0:
		return
	_level_clear_processed = true
	_set_level_complete_and_emit_victory_prompt()


func _set_level_complete_and_emit_victory_prompt() -> void:
	stop_slow_time()
	set_state(GameState.LEVEL_COMPLETE)
	var stars := _get_star_count_for_score(score)
	var passed := stars >= 1
	var progress := _update_level_progress(current_level_path, score)
	var next_level := _get_next_level_path(current_level_path)
	emit_signal("victory_prompt_requested", {
		"score": score,
		"high_score": progress.get("high_score", score),
		"stars": stars,
		"best_stars": progress.get("best_stars", stars),
		"passed": passed,
		"next_level_path": next_level,
		"options": ["watch_ad_double_rewards", "continue_next_level", "world_select", "main_menu"]
	})


func _count_live_enemies() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return 0
	return _count_live_enemies_recursive(scene)


func _count_live_enemies_recursive(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Node:
			if child.has_method("apply_damage") and child.is_inside_tree() and not child.is_queued_for_deletion():
				count += 1
			count += _count_live_enemies_recursive(child)
	return count


func _get_star_count_for_score(value: int) -> int:
	var stars := 0
	if value >= star_1_score:
		stars = 1
	if value >= star_2_score:
		stars = 2
	if value >= star_3_score:
		stars = 3
	return stars


func _update_level_progress(level_path: String, achieved_score: int) -> Dictionary:
	if level_path.is_empty():
		return {"high_score": achieved_score, "best_stars": _get_star_count_for_score(achieved_score), "passed": _get_star_count_for_score(achieved_score) >= 1}

	var entry: Dictionary = _level_progress.get(level_path, {
		"high_score": 0,
		"best_stars": 0,
		"passed": false
	})

	var stars := _get_star_count_for_score(achieved_score)
	entry["high_score"] = max(int(entry.get("high_score", 0)), achieved_score)
	entry["best_stars"] = max(int(entry.get("best_stars", 0)), stars)
	entry["passed"] = bool(entry.get("passed", false)) or stars >= 1

	_level_progress[level_path] = entry
	_save_level_progress()
	emit_signal("level_progress_changed", level_path, int(entry["high_score"]), int(entry["best_stars"]), bool(entry["passed"]))
	return entry


func get_level_progress(level_path: String) -> Dictionary:
	return _level_progress.get(level_path, {
		"high_score": 0,
		"best_stars": 0,
		"passed": false
	})


func _save_level_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "levels", _level_progress)
	cfg.save("user://level_progress.cfg")


func _load_level_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://level_progress.cfg") != OK:
		_level_progress = {}
		return
	var data: Variant = cfg.get_value("progress", "levels", {})
	if data is Dictionary:
		_level_progress = data
	else:
		_level_progress = {}


func _update_scene_context() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path == _last_scene_path:
		return

	_last_scene_path = path
	if _is_level_scene(path):
		start_level(path)
		_resolve_player_gun_from_scene()
	else:
		current_level_path = ""
		_score_zero_game_over_triggered = false
		_level_clear_processed = false


func _is_level_scene(path: String) -> bool:
	return not path.is_empty() and path.begins_with(levels_root_prefix)


func _get_next_level_path(level_path: String) -> String:
	if level_path.is_empty():
		return ""
	var world_path := level_path.get_base_dir()
	var current_name := level_path.get_file()
	var dir := DirAccess.open(world_path)
	if dir == null:
		return ""

	var levels: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if name.ends_with(".tscn"):
			levels.append(name)
	dir.list_dir_end()

	if levels.is_empty():
		return ""
	levels.sort()
	var idx := levels.find(current_name)
	if idx == -1:
		return ""
	if idx + 1 >= levels.size():
		return ""
	return "%s/%s" % [world_path, levels[idx + 1]]


func _return_to_title_screen() -> void:
	if title_screen_scene_path.is_empty() or not ResourceLoader.exists(title_screen_scene_path):
		return
	get_tree().change_scene_to_file(title_screen_scene_path)
