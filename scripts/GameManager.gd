extends Node
## GameManager Controller — thin orchestrator that delegates to single-responsibility services.
##
## Sub-managers (composition):
##   _score      — score value, decay, kill/star calculations
##   _shop       — shop currency, purchases, unlocks, cosmetics, persistence
##   _levels     — level navigation, progress tracking, persistence
##   _slow_time  — slow-time state + Engine.time_scale
##   audio_manager — audio playback (already extracted as Node child)
##
## All signals remain on GameManager. Public API is preserved as a façade.
## @export vars remain on GameManager for inspector visibility; values are
## passed to sub-managers as method parameters or propagated in _ready.

const ScoreManager = preload("res://scripts/score_manager.gd")
const ShopManager = preload("res://scripts/shop_manager.gd")
const LevelManager = preload("res://scripts/level_manager.gd")
const SlowTimeManager = preload("res://scripts/slow_time_manager.gd")

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
signal shop_balance_changed(balance: int)
signal shop_inventory_changed(item_id: String, owned: bool)

#------ENUMS------
enum GameState { PLAYING, PAUSED, LEVEL_COMPLETE, GAME_OVER }

# Audio/visual constants (kept for backward compat; AudioManager has its own copies)
const SFX_GUNSHOT: AudioStream = preload("res://assets/Audio/SFX/Gun/gunshot/gunshot.wav")
const SFX_BULLET_WALL_IMPACT: AudioStream = preload("res://assets/Audio/SFX/Bullet/collides with wall/446126__justinvoke__collision-1.wav")
const SFX_ENEMY_ARMOR_BREAK: AudioStream = preload("res://assets/Audio/SFX/Enemy/armour break/486068__craigsmith__r12-29-gun-shot-through-window.wav")
const SFX_ENEMY_DEATH: AudioStream = preload("res://assets/Audio/SFX/Enemy/death/661617__solar01__glass-marbles-dropping-into-singing-bowl.wav")
const SFX_UI_INTERACTION: AudioStream = preload("res://assets/Audio/SFX/UI/menu interaction/540568__eminyildirim__ui-pop-up.wav")
const MUSIC_COLD_FIRE: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/cold-fire-neozoic-main-version-37473-02-16.mp3")
const MUSIC_COSMIC_LOVE: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/cosmic-love-aavirall-main-version-27447-02-17.mp3")
const MUSIC_FEEL_THE_EARTH_SPINNING: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/feel-the-earth-spinning-euchmad-main-version-34276-03-36.mp3")
const BASE_AUDIO_GAIN_LINEAR := 0.6696
const MIX_BOOST_GAMEPLAY_SFX_DB := 3.0
const MIX_BOOST_UI_SFX_DB := 4.0
const MASTER_BASELINE_GAIN_LINEAR := 0.8

#------Sub-managers------
var _score := ScoreManager.new()
var _shop := ShopManager.new()
var _levels := LevelManager.new()
var _slow_time := SlowTimeManager.new()

#------Proxied state (transparent to external code)------
var score: int:
	get: return _score.score
	set(value): _score.score = value

var current_level_path: String:
	get: return _levels.current_level_path
	set(value): _levels.current_level_path = value

var is_slowing_time: bool:
	get: return _slow_time.is_active
	set(value): _slow_time.is_active = value

var shop_currency: int:
	get: return _shop.currency
	set(value): _shop.currency = value

var owned_shop_items: Dictionary:
	get: return _shop.owned_items
	set(value): _shop.owned_items = value

var selected_gun_skin_path: String:
	get: return _shop.selected_gun_skin_path
	set(value): _shop.selected_gun_skin_path = value

var selected_bullet_skin_path: String:
	get: return _shop.selected_bullet_skin_path
	set(value): _shop.selected_bullet_skin_path = value

var selected_bullet_trail_style: String:
	get: return _shop.selected_bullet_trail_style
	set(value): _shop.selected_bullet_trail_style = value

var unlocked_bullet_trails: Dictionary:
	get: return _shop.unlocked_bullet_trails
	set(value): _shop.unlocked_bullet_trails = value

var unlocked_gun_skin_paths: Dictionary:
	get: return _shop.unlocked_gun_skin_paths
	set(value): _shop.unlocked_gun_skin_paths = value

var unlocked_bullet_skin_paths: Dictionary:
	get: return _shop.unlocked_bullet_skin_paths
	set(value): _shop.unlocked_bullet_skin_paths = value

var last_daily_claim_date: String:
	get: return _shop.last_daily_claim_date
	set(value): _shop.last_daily_claim_date = value

#------Direct state------
var state: int = GameState.PLAYING
var normal_time_scale := 1.0
var slow_time_scale := 0.2
var max_ammo: int = 5
var ammo: int = 5
var pending_title_screen: String = ""
var audio_manager: Node = null

var _last_scene_path := ""
var _score_zero_game_over_triggered := false
var _level_clear_processed := false
var _current_level_reward_doubled := false
var _ad_continue_used_this_level := false
var _last_victory_stats: Dictionary = {}
var _transition_layer: CanvasLayer = null
var _transition_rect: ColorRect = null
var _transition_in_progress: bool = false

#------Exports------
@export_group("Scoring")
@export var starting_score: int = 2000
@export var score_decay_per_second: float = 30.0
@export var score_cost_per_shot: int = 45
@export var score_cost_reset_gun: int = 500
@export var kill_score_head: int = 500
@export var kill_score_torso: int = 350
@export var kill_score_limb: int = 250
@export var kill_score_extremity: int = 140
@export var star_1_score: int = 900
@export var star_2_score: int = 1400
@export var star_3_score: int = 1900
@export var ad_continue_score: int = 500

@export var levels_root_prefix := "res://scenes/Levels/"
@export_file("*.tscn") var title_screen_scene_path := "res://scenes/TitleScreen.tscn"

@export var max_impact_slow_time_scale := 0.06
@export var spin_for_max_impact := 28.0
@export var slow_time_spin_curve_power := 2.2
@export var debug_mode: bool = false

@export var player_gun_path: NodePath = NodePath("")
@onready var player_gun: RigidBody3D = get_node_or_null(player_gun_path)


func _ready() -> void:
	_levels.levels_root_prefix = levels_root_prefix
	_levels.load_progress()
	_shop.load_profile()
	_apply_master_baseline_gain()
	_setup_transition_overlay()
	_setup_audio()
	emit_signal("state_changed", state)
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("shop_balance_changed", shop_currency)

	if player_gun == null and player_gun_path != NodePath(""):
		player_gun = get_node_or_null(player_gun_path)
	if player_gun == null:
		_resolve_player_gun_from_scene()

	_update_scene_context()


func _physics_process(delta: float) -> void:
	_update_scene_context()
	_apply_score_decay(delta)
	_check_score_fail_state()

	if not is_slowing_time:
		return
	if player_gun == null:
		_resolve_player_gun_from_scene()
	_update_dynamic_slow_time_scale()

# ---- State machine ----

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
	_ad_continue_used_this_level = false
	set_state(GameState.PLAYING)
	reset_run()
	emit_signal("level_changed", current_level_path)


func reset_run() -> void:
	_score.reset(starting_score)
	_score_zero_game_over_triggered = false
	_level_clear_processed = false
	_current_level_reward_doubled = false
	ammo = max_ammo
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("run_reset")

# ---- Score façade ----

func add_score(amount: int) -> void:
	_score.add(amount)
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
	var bonus := ScoreManager.get_kill_score(hit_type, kill_score_head, kill_score_torso, kill_score_limb, kill_score_extremity)
	add_score(bonus)
	_register_enemy_defeated()


func _apply_score_decay(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	if current_level_path.is_empty():
		return
	if score <= 0:
		return
	var prev := score
	_score.apply_decay(delta, score_decay_per_second)
	if score != prev:
		emit_signal("score_changed", score)


func _get_star_count_for_score(value: int) -> int:
	return ScoreManager.get_star_count(value, star_1_score, star_2_score, star_3_score)

# ---- Ammo ----

func spend_ammo(amount: int = 1) -> bool:
	if ammo < amount:
		return false
	ammo -= amount
	emit_signal("ammo_changed", ammo, max_ammo)
	return true


func restore_ammo(amount: int = 1) -> void:
	ammo = min(ammo + amount, max_ammo)
	emit_signal("ammo_changed", ammo, max_ammo)


func on_player_out_of_ammo() -> void:
	set_state(GameState.GAME_OVER)

# ---- Player gun reset ----

func try_reset_player_gun() -> bool:
	if debug_mode:
		print_debug("GameManager: try_reset_player_gun called; state=", state, " score=", score)
	if state != GameState.PLAYING:
		if debug_mode:
			print_debug("GameManager: try_reset_player_gun - rejected (not playing)")
		return false
	if score < score_cost_reset_gun:
		if debug_mode:
			print_debug("GameManager: try_reset_player_gun - rejected (insufficient score)")
		return false

	if player_gun == null:
		if debug_mode:
			print_debug("GameManager: player_gun is null, attempting resolve from scene")
		_resolve_player_gun_from_scene()
	if player_gun == null:
		if debug_mode:
			print_debug("GameManager: try_reset_player_gun - failed (no player_gun found)")
		return false
	if not player_gun.has_method("reset_to_spawn_state"):
		if debug_mode:
			print_debug("GameManager: try_reset_player_gun - failed (player_gun missing method)")
		return false

	spend_score(score_cost_reset_gun)
	if debug_mode:
		print_debug("GameManager: triggering player_gun.reset_to_spawn_state (deferred)")
	player_gun.call_deferred("reset_to_spawn_state")
	return true

# ---- Level navigation ----

func on_level_complete() -> void:
	_set_level_complete_and_emit_victory_prompt()


func restart_level() -> void:
	_stop_all_sfx()
	_last_scene_path = ""
	if current_level_path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(current_level_path)


func continue_to_next_level() -> bool:
	var next_level := _levels.get_next_level_path(current_level_path)
	if next_level.is_empty():
		return false
	_stop_all_sfx()
	get_tree().change_scene_to_file(next_level)
	return true

# ---- Ad / continue ----

func watch_ad_continue_from_game_over() -> bool:
	if state != GameState.GAME_OVER:
		return false
	if not _score_zero_game_over_triggered:
		return false
	if _ad_continue_used_this_level:
		return false

	score = max(score, ad_continue_score)
	_score_zero_game_over_triggered = false
	_ad_continue_used_this_level = true
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
	var stars := _get_star_count_for_score(score)
	var progress := _levels.update_progress(current_level_path, score, stars)
	emit_signal("level_progress_changed", current_level_path, int(progress["high_score"]), int(progress["best_stars"]), bool(progress["passed"]))
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


func get_last_victory_stats() -> Dictionary:
	return _last_victory_stats.duplicate(true)

# ---- Slow-time façade ----

func start_slow_time() -> void:
	if not _slow_time.start():
		return
	_update_dynamic_slow_time_scale()
	emit_signal("slow_time_changed", true)


func stop_slow_time() -> void:
	if not _slow_time.stop(normal_time_scale):
		return
	emit_signal("slow_time_changed", false)


func _update_dynamic_slow_time_scale() -> void:
	var spin_strength := 0.0
	if player_gun != null:
		spin_strength = player_gun.angular_velocity.length()
	_slow_time.update_dynamic_scale(
		spin_strength, slow_time_scale, max_impact_slow_time_scale,
		spin_for_max_impact, slow_time_spin_curve_power
	)

# ---- Shop façade ----

func set_selected_cosmetics(gun_skin_path_val: String, bullet_skin_path_val: String, bullet_trail_style_val: String = "Default Trail") -> void:
	_shop.set_cosmetics(gun_skin_path_val, bullet_skin_path_val, bullet_trail_style_val)


func set_selected_gun_skin_path(path: String) -> void:
	_shop.set_gun_skin(path)


func set_selected_bullet_skin_path(path: String) -> void:
	_shop.set_bullet_skin(path)


func get_selected_gun_skin_path() -> String:
	return _shop.selected_gun_skin_path


func get_selected_bullet_skin_path() -> String:
	return _shop.selected_bullet_skin_path


func set_selected_bullet_trail_style(style: String) -> void:
	_shop.set_bullet_trail(style)


func get_selected_bullet_trail_style() -> String:
	return _shop.selected_bullet_trail_style


func get_shop_currency() -> int:
	return _shop.get_currency()


func has_shop_item(item_id: String) -> bool:
	return _shop.has_item(item_id)


func is_bullet_trail_unlocked(style: String) -> bool:
	return _shop.is_bullet_trail_unlocked(style)


func is_gun_skin_unlocked(path: String) -> bool:
	return _shop.is_gun_skin_unlocked(path)


func is_bullet_skin_unlocked(path: String) -> bool:
	return _shop.is_bullet_skin_unlocked(path)


func purchase_shop_item(item_id: String, cost: int) -> Dictionary:
	var result := _shop.purchase_item(item_id, cost)
	if bool(result.get("ok", false)):
		emit_signal("shop_balance_changed", shop_currency)
		emit_signal("shop_inventory_changed", item_id, true)
	return result


func claim_daily_shop_credits(amount: int = 200) -> Dictionary:
	var result := _shop.claim_daily_credits(amount)
	if bool(result.get("ok", false)):
		emit_signal("shop_balance_changed", shop_currency)
	return result


func get_last_daily_claim_date() -> String:
	return _shop.last_daily_claim_date


func add_shop_currency(amount: int) -> void:
	_shop.add_currency(amount)
	emit_signal("shop_balance_changed", shop_currency)

# ---- Level progress façade ----

func get_level_progress(level_path: String) -> Dictionary:
	return _levels.get_progress(level_path)


func _extract_level_number(level_path: String) -> int:
	return _levels.extract_level_number(level_path)

# ---- Internal: scene context ----

func _update_scene_context() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path == _last_scene_path:
		return

	_stop_all_sfx()
	_last_scene_path = path
	if _levels.is_level_scene(path):
		start_level(path)
		_resolve_player_gun_from_scene()
		_play_level_music_for_path(path)
	else:
		current_level_path = ""
		_score_zero_game_over_triggered = false
		_level_clear_processed = false
		_ad_continue_used_this_level = false
		_ensure_menu_music_playing()


func _resolve_player_gun_from_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var found := scene.find_child("PlayerGun", true, false)
	if found is RigidBody3D:
		player_gun = found as RigidBody3D

# ---- Internal: fail state ----

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
	var options: Array[String] = ["retry_level", "world_select", "main_menu"]
	if not _ad_continue_used_this_level:
		options.push_front("watch_ad_continue")
	emit_signal("game_over_prompt_requested", {
		"reason": "score_zero",
		"title": "Out of Score",
		"message": "Your score reached zero.",
		"continue_score": ad_continue_score,
		"options": options
	})

# ---- Internal: enemy tracking ----

func _register_enemy_defeated() -> void:
	if _level_clear_processed:
		return
	if _count_live_enemies() > 0:
		return
	_level_clear_processed = true
	_set_level_complete_and_emit_victory_prompt()


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

# ---- Internal: victory ----

func _set_level_complete_and_emit_victory_prompt() -> void:
	stop_slow_time()
	set_state(GameState.LEVEL_COMPLETE)
	var stars := _get_star_count_for_score(score)
	var passed := stars >= 1
	var progress := _levels.update_progress(current_level_path, score, stars)
	var next_level := _levels.get_next_level_path(current_level_path)
	emit_signal("level_progress_changed", current_level_path, int(progress["high_score"]), int(progress["best_stars"]), bool(progress["passed"]))
	_last_victory_stats = {
		"timestamp_unix": Time.get_unix_time_from_system(),
		"level_path": current_level_path,
		"score": score,
		"stars": stars,
		"passed": passed,
		"high_score": int(progress.get("high_score", score)),
		"best_stars": int(progress.get("best_stars", stars)),
		"next_level_path": next_level
	}
	emit_signal("victory_prompt_requested", {
		"score": score,
		"high_score": progress.get("high_score", score),
		"stars": stars,
		"best_stars": progress.get("best_stars", stars),
		"passed": passed,
		"next_level_path": next_level,
		"options": ["watch_ad_double_rewards", "continue_next_level", "retry_level", "world_select", "main_menu"]
	})

# ---- Transition overlay ----

func _setup_transition_overlay() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "GlobalTransitionLayer"
	_transition_layer.layer = 256
	_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_transition_layer)

	_transition_rect = ColorRect.new()
	_transition_rect.name = "ScreenFade"
	_transition_rect.anchor_left = 0.0
	_transition_rect.anchor_top = 0.0
	_transition_rect.anchor_right = 1.0
	_transition_rect.anchor_bottom = 1.0
	_transition_rect.offset_left = 0.0
	_transition_rect.offset_top = 0.0
	_transition_rect.offset_right = 0.0
	_transition_rect.offset_bottom = 0.0
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_transition_rect.visible = false
	_transition_layer.add_child(_transition_rect)


func run_screen_transition(
	action: Callable,
	fade_out_duration: float = 0.3,
	fade_in_duration: float = 0.25,
	fade_out_music: bool = true,
	keep_level_music_until_loop_end: bool = false
) -> void:
	if _transition_in_progress:
		return
	_transition_in_progress = true

	if keep_level_music_until_loop_end:
		fade_out_music = false
	if fade_out_music:
		_fade_out_music_and_stop(maxf(0.0, fade_out_duration))

	await _fade_screen_to_alpha(1.0, maxf(0.0, fade_out_duration))
	if action.is_valid():
		action.call()
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_screen_to_alpha(0.0, maxf(0.0, fade_in_duration))

	_transition_in_progress = false


func _fade_screen_to_alpha(target_alpha: float, duration: float) -> void:
	if _transition_rect == null:
		return
	_transition_rect.visible = true
	if duration <= 0.0:
		_transition_rect.color = Color(0.0, 0.0, 0.0, clampf(target_alpha, 0.0, 1.0))
		if target_alpha <= 0.001:
			_transition_rect.visible = false
		return

	var tween := create_tween()
	tween.tween_property(_transition_rect, "color:a", clampf(target_alpha, 0.0, 1.0), duration)
	await tween.finished
	if target_alpha <= 0.001:
		_transition_rect.visible = false

# ---- Audio delegation ----

func _setup_audio() -> void:
	var AudioManagerClass := preload("res://scripts/AudioManager.gd")
	audio_manager = AudioManagerClass.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	audio_manager.setup()


func _apply_master_baseline_gain() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus == -1:
		return
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(MASTER_BASELINE_GAIN_LINEAR))


func _fade_out_music_and_stop(duration: float) -> void:
	if audio_manager != null and audio_manager.has_method("fade_out_music_and_stop"):
		audio_manager.fade_out_music_and_stop(duration)


func _on_music_finished() -> void:
	if audio_manager != null and audio_manager.has_method("_on_music_finished"):
		audio_manager._on_music_finished()


func _ensure_menu_music_playing() -> void:
	if audio_manager != null and audio_manager.has_method("_ensure_menu_music_playing"):
		audio_manager._ensure_menu_music_playing()


func _play_level_music_for_path(level_path: String) -> void:
	if audio_manager != null and audio_manager.has_method("play_level_music_for_path"):
		audio_manager.play_level_music_for_path(level_path)


func set_music_volume_percent(value: float) -> void:
	if audio_manager != null and audio_manager.has_method("set_music_volume_percent"):
		audio_manager.set_music_volume_percent(value)


func get_music_volume_percent() -> float:
	if audio_manager != null and audio_manager.has_method("get_music_volume_percent"):
		return audio_manager.get_music_volume_percent()
	return 100.0


func _stop_all_sfx() -> void:
	if audio_manager != null and audio_manager.has_method("_stop_all_sfx"):
		audio_manager._stop_all_sfx()


func play_gunshot_at(origin: Vector3) -> void:
	if audio_manager != null and audio_manager.has_method("play_gunshot_at"):
		audio_manager.play_gunshot_at(origin)


func play_bullet_wall_impact_at(origin: Vector3) -> void:
	if audio_manager != null and audio_manager.has_method("play_bullet_wall_impact_at"):
		audio_manager.play_bullet_wall_impact_at(origin)


func play_enemy_death_at(origin: Vector3) -> void:
	if audio_manager != null and audio_manager.has_method("play_enemy_death_at"):
		audio_manager.play_enemy_death_at(origin)


func play_enemy_armor_break_at(origin: Vector3) -> void:
	if audio_manager != null and audio_manager.has_method("play_enemy_armor_break_at"):
		audio_manager.play_enemy_armor_break_at(origin)


func play_ui_interaction() -> void:
	if audio_manager != null and audio_manager.has_method("play_ui_interaction"):
		audio_manager.play_ui_interaction()

# ---- Navigation helpers ----

func _return_to_title_screen() -> void:
	if title_screen_scene_path.is_empty() or not ResourceLoader.exists(title_screen_scene_path):
		return
	_stop_all_sfx()
	get_tree().change_scene_to_file(title_screen_scene_path)
