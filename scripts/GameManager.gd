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
signal shop_balance_changed(balance: int)
signal shop_inventory_changed(item_id: String, owned: bool)

#------ENUMS------
enum GameState { 
	PLAYING, 
	PAUSED, 
	LEVEL_COMPLETE, 
	GAME_OVER 
	}

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

const SHOP_BUNDLE_GUN_TEST_SKINS: Array[String] = [
	"res://assets/visual/magnum/test_skin_magnum_neon_grid.png",
	"res://assets/visual/magnum/test_skin_magnum_cyber_rings.png",
	"res://assets/visual/magnum/test_skin_magnum_dark_hextech.png",
	"res://assets/visual/magnum/test_skin_magnum_void_circuit.png"
]

const SHOP_BUNDLE_BULLET_TEST_SKINS: Array[String] = [
	"res://assets/visual/Bullet/test_skin_bullet_neon_core.png",
	"res://assets/visual/Bullet/test_skin_bullet_toxic_hex.png",
	"res://assets/visual/Bullet/test_skin_bullet_pulsewave.png",
	"res://assets/visual/Bullet/test_skin_bullet_tracer_stripe.png"
]

#------Vars------

var state: int = GameState.PLAYING

var score: int = 0
var _score_decay_accumulator := 0.0
var _last_scene_path := ""
var _score_zero_game_over_triggered := false
var _level_clear_processed := false
var _current_level_reward_doubled := false
var _ad_continue_used_this_level := false
var _level_progress: Dictionary = {}
var pending_title_screen: String = ""
var selected_gun_skin_path: String = ""
var selected_bullet_skin_path: String = ""
var selected_bullet_trail_style: String = "Default Trail"
var shop_currency: int = 1000
var owned_shop_items: Dictionary = {}
var unlocked_bullet_trails: Dictionary = {"Default Trail": true, "Tracer": true}
var unlocked_gun_skin_paths: Dictionary = {}
var unlocked_bullet_skin_paths: Dictionary = {}
var last_daily_claim_date: String = ""

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

var _music_player: AudioStreamPlayer = null
var _menu_music_playlist: Array[AudioStream] = []
var _menu_last_track_index: int = -1
var _music_mode: String = ""
var _active_sfx_players: Array[AudioStreamPlayer3D] = []
var _music_default_volume_db: float = linear_to_db(BASE_AUDIO_GAIN_LINEAR)
var _sfx_default_volume_db: float = linear_to_db(BASE_AUDIO_GAIN_LINEAR)
var _music_volume_percent: float = 100.0
var _transition_layer: CanvasLayer = null
var _transition_rect: ColorRect = null
var _transition_in_progress: bool = false
var _last_victory_stats: Dictionary = {}

@export var player_gun_path: NodePath = NodePath("")
@onready var player_gun: RigidBody3D = get_node_or_null(player_gun_path)

func _ready() -> void:
	_load_level_progress()
	_load_shop_profile()
	_apply_master_baseline_gain()
	_setup_transition_overlay()
	_setup_audio()
	emit_signal("state_changed", state)
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("shop_balance_changed", shop_currency)

	# Ensure the exported path is resolved at runtime if set in the inspector
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
	_stop_all_sfx()
	# Retrying can reload the same scene path, so clear cached path to force context re-init.
	_last_scene_path = ""
	if current_level_path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(current_level_path)


func continue_to_next_level() -> bool:
	var next_level := _get_next_level_path(current_level_path)
	if next_level.is_empty():
		return false
	_stop_all_sfx()
	get_tree().change_scene_to_file(next_level)
	return true


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


func get_last_victory_stats() -> Dictionary:
	return _last_victory_stats.duplicate(true)


func set_selected_cosmetics(gun_skin_path: String, bullet_skin_path: String, bullet_trail_style: String = "Default Trail") -> void:
	selected_gun_skin_path = _sanitize_texture_path(gun_skin_path)
	selected_bullet_skin_path = _sanitize_texture_path(bullet_skin_path)
	selected_bullet_trail_style = _sanitize_bullet_trail_style(bullet_trail_style)


func set_selected_gun_skin_path(path: String) -> void:
	selected_gun_skin_path = _sanitize_texture_path(path)


func set_selected_bullet_skin_path(path: String) -> void:
	selected_bullet_skin_path = _sanitize_texture_path(path)


func get_selected_gun_skin_path() -> String:
	return selected_gun_skin_path


func get_selected_bullet_skin_path() -> String:
	return selected_bullet_skin_path


func set_selected_bullet_trail_style(style: String) -> void:
	selected_bullet_trail_style = _sanitize_bullet_trail_style(style)


func get_selected_bullet_trail_style() -> String:
	return selected_bullet_trail_style


func get_shop_currency() -> int:
	return max(0, shop_currency)


func has_shop_item(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	return bool(owned_shop_items.get(item_id, false))


func is_bullet_trail_unlocked(style: String) -> bool:
	if style == "Default Trail":
		return true
	if style == "Tracer":
		return true
	return bool(unlocked_bullet_trails.get(style, false))


func is_gun_skin_unlocked(path: String) -> bool:
	if path.is_empty():
		return true
	if not _is_shop_managed_gun_skin(path):
		return true
	return bool(unlocked_gun_skin_paths.get(path, false))


func is_bullet_skin_unlocked(path: String) -> bool:
	if path.is_empty():
		return true
	if not _is_shop_managed_bullet_skin(path):
		return true
	return bool(unlocked_bullet_skin_paths.get(path, false))


func purchase_shop_item(item_id: String, cost: int) -> Dictionary:
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid_item", "balance": shop_currency}
	if cost < 0:
		return {"ok": false, "reason": "invalid_cost", "balance": shop_currency}
	if has_shop_item(item_id):
		return {"ok": false, "reason": "already_owned", "balance": shop_currency}
	if shop_currency < cost:
		return {"ok": false, "reason": "insufficient_funds", "balance": shop_currency}

	shop_currency -= cost
	owned_shop_items[item_id] = true
	_apply_shop_item_unlock_effect(item_id)
	_save_shop_profile()
	emit_signal("shop_balance_changed", shop_currency)
	emit_signal("shop_inventory_changed", item_id, true)
	return {"ok": true, "reason": "purchased", "balance": shop_currency}


func claim_daily_shop_credits(amount: int = 200) -> Dictionary:
	var today: String = Time.get_date_string_from_system()
	if last_daily_claim_date == today:
		return {"ok": false, "reason": "already_claimed", "amount": 0, "balance": shop_currency}

	var grant: int = maxi(0, amount)
	shop_currency += grant
	last_daily_claim_date = today
	_save_shop_profile()
	emit_signal("shop_balance_changed", shop_currency)
	return {"ok": true, "reason": "claimed", "amount": grant, "balance": shop_currency}


func get_last_daily_claim_date() -> String:
	return last_daily_claim_date


func add_shop_currency(amount: int) -> void:
	if amount <= 0:
		return
	shop_currency += amount
	_save_shop_profile()
	emit_signal("shop_balance_changed", shop_currency)


func _apply_shop_item_unlock_effect(item_id: String) -> void:
	match item_id:
		"trail_neon_unlock":
			unlocked_bullet_trails["Neon"] = true
		"trail_smoke_unlock":
			unlocked_bullet_trails["Smoke"] = true
		"gun_skin_bundle_test":
			for path in SHOP_BUNDLE_GUN_TEST_SKINS:
				unlocked_gun_skin_paths[path] = true
		"bullet_skin_bundle_test":
			for path in SHOP_BUNDLE_BULLET_TEST_SKINS:
				unlocked_bullet_skin_paths[path] = true
		_:
			pass


func _save_shop_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shop", "currency", shop_currency)
	cfg.set_value("shop", "owned_items", owned_shop_items)
	cfg.set_value("shop", "unlocked_bullet_trails", unlocked_bullet_trails)
	cfg.set_value("shop", "unlocked_gun_skin_paths", unlocked_gun_skin_paths)
	cfg.set_value("shop", "unlocked_bullet_skin_paths", unlocked_bullet_skin_paths)
	cfg.set_value("shop", "last_daily_claim_date", last_daily_claim_date)
	cfg.save("user://shop_profile.cfg")


func _load_shop_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://shop_profile.cfg") != OK:
		shop_currency = 1000
		owned_shop_items = {}
		unlocked_bullet_trails = {"Default Trail": true, "Tracer": true}
		unlocked_gun_skin_paths = {}
		unlocked_bullet_skin_paths = {}
		last_daily_claim_date = ""
		_save_shop_profile()
		return

	shop_currency = max(0, int(cfg.get_value("shop", "currency", 1000)))
	var loaded_items: Variant = cfg.get_value("shop", "owned_items", {})
	owned_shop_items = loaded_items if loaded_items is Dictionary else {}
	var loaded_trails: Variant = cfg.get_value("shop", "unlocked_bullet_trails", {"Default Trail": true, "Tracer": true})
	unlocked_bullet_trails = loaded_trails if loaded_trails is Dictionary else {}
	var loaded_gun_skins: Variant = cfg.get_value("shop", "unlocked_gun_skin_paths", {})
	unlocked_gun_skin_paths = loaded_gun_skins if loaded_gun_skins is Dictionary else {}
	var loaded_bullet_skins: Variant = cfg.get_value("shop", "unlocked_bullet_skin_paths", {})
	unlocked_bullet_skin_paths = loaded_bullet_skins if loaded_bullet_skins is Dictionary else {}
	last_daily_claim_date = String(cfg.get_value("shop", "last_daily_claim_date", ""))

	# Keep baseline free trails available even if profile data was edited externally.
	unlocked_bullet_trails["Default Trail"] = true
	unlocked_bullet_trails["Tracer"] = true
	_reapply_shop_unlocks_from_inventory()


func _reapply_shop_unlocks_from_inventory() -> void:
	# Re-derive unlock effects from inventory for backwards compatibility and save migration safety.
	unlocked_bullet_trails["Default Trail"] = true
	unlocked_bullet_trails["Tracer"] = true
	for item_id in owned_shop_items.keys():
		if bool(owned_shop_items[item_id]):
			_apply_shop_item_unlock_effect(String(item_id))


func _is_shop_managed_gun_skin(path: String) -> bool:
	return SHOP_BUNDLE_GUN_TEST_SKINS.has(path)


func _is_shop_managed_bullet_skin(path: String) -> bool:
	return SHOP_BUNDLE_BULLET_TEST_SKINS.has(path)

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

	_stop_all_sfx()
	_last_scene_path = path
	if _is_level_scene(path):
		start_level(path)
		_resolve_player_gun_from_scene()
		_play_level_music_for_path(path)
	else:
		current_level_path = ""
		_score_zero_game_over_triggered = false
		_level_clear_processed = false
		_ad_continue_used_this_level = false
		_ensure_menu_music_playing()


func _setup_audio() -> void:
	randomize()
	_menu_music_playlist = [MUSIC_COLD_FIRE, MUSIC_COSMIC_LOVE, MUSIC_FEEL_THE_EARTH_SPINNING]
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = _get_existing_bus_or_default("Music")
	add_child(_music_player)
	_apply_music_volume_setting()
	if not _music_player.finished.is_connected(_on_music_finished):
		_music_player.finished.connect(_on_music_finished)


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


func _fade_out_music_and_stop(duration: float) -> void:
	if _music_player == null or not _music_player.playing:
		return
	if duration <= 0.0:
		_music_player.stop()
		_apply_music_volume_setting()
		return

	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -60.0, duration)
	tween.finished.connect(func() -> void:
		if _music_player == null:
			return
		_music_player.stop()
		_apply_music_volume_setting())


func _on_music_finished() -> void:
	if _music_mode == "menu":
		_play_random_menu_track()


func _ensure_menu_music_playing() -> void:
	_music_mode = "menu"
	if _music_player == null:
		return
	if _music_player.playing:
		return
	_play_random_menu_track()


func _play_random_menu_track() -> void:
	if _music_player == null:
		return
	if _menu_music_playlist.is_empty():
		return

	var next_index := 0
	if _menu_music_playlist.size() == 1:
		next_index = 0
	else:
		next_index = randi_range(0, _menu_music_playlist.size() - 1)
		if next_index == _menu_last_track_index:
			next_index = (next_index + 1) % _menu_music_playlist.size()

	_menu_last_track_index = next_index
	var stream := _menu_music_playlist[next_index]
	if stream == null:
		return
	_music_player.stream = stream
	_apply_music_volume_setting()
	_music_player.play()


func _play_level_music_for_path(level_path: String) -> void:
	if _music_player == null:
		return

	var stream := _select_level_music_stream(level_path)
	if stream == null:
		return

	var should_switch := (_music_mode != "level") or (_music_player.stream != stream)
	_music_mode = "level"
	if not should_switch and _music_player.playing:
		return
	_music_player.stream = stream
	_apply_music_volume_setting()
	_music_player.play()


func _select_level_music_stream(level_path: String) -> AudioStream:
	var tracks: Array[AudioStream] = _menu_music_playlist
	if tracks.is_empty():
		tracks = [MUSIC_COLD_FIRE, MUSIC_COSMIC_LOVE, MUSIC_FEEL_THE_EARTH_SPINNING]
	if tracks.is_empty():
		return null

	var level_number := _extract_level_number(level_path)
	if level_number > 0:
		var numbered_index := posmod(level_number - 1, tracks.size())
		return tracks[numbered_index]

	# If scene names change (for example no W1Lxx format), still pick a stable track per level.
	var stable_index := posmod(level_path.hash(), tracks.size())
	return tracks[stable_index]


func set_music_volume_percent(value: float) -> void:
	_music_volume_percent = clampf(value, 0.0, 100.0)
	_apply_music_volume_setting()


func get_music_volume_percent() -> float:
	return _music_volume_percent


func _extract_level_number(level_path: String) -> int:
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


func _get_existing_bus_or_default(bus_name: String) -> String:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	return "Master"


func _apply_music_volume_setting() -> void:
	var target_db := _volume_percent_to_db(_music_volume_percent)
	var music_bus_index := AudioServer.get_bus_index("Music")
	if music_bus_index != -1:
		AudioServer.set_bus_volume_db(music_bus_index, target_db)
		if _music_player != null:
			_music_player.volume_db = _music_default_volume_db
		return
	if _music_player != null:
		_music_player.volume_db = _music_default_volume_db + target_db


func _volume_percent_to_db(value: float) -> float:
	if value <= 0.0:
		return -80.0
	return linear_to_db(clampf(value / 100.0, 0.0, 1.0))


func _apply_master_baseline_gain() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus == -1:
		return
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(MASTER_BASELINE_GAIN_LINEAR))


func _track_sfx_player(player: AudioStreamPlayer3D) -> void:
	_active_sfx_players.append(player)
	if not player.finished.is_connected(func() -> void:
		_active_sfx_players.erase(player)
		if is_instance_valid(player):
			player.queue_free()):
		player.finished.connect(func() -> void:
			_active_sfx_players.erase(player)
			if is_instance_valid(player):
				player.queue_free())


func _stop_all_sfx() -> void:
	for player in _active_sfx_players:
		if not is_instance_valid(player):
			continue
		player.stop()
		player.queue_free()
	_active_sfx_players.clear()


func _play_sfx_3d(
	stream: AudioStream,
	origin: Vector3,
	bus_name: String,
	volume_db: float = 0.0,
	pitch_min: float = 0.98,
	pitch_max: float = 1.02,
	volume_jitter_db: float = 0.6,
	start_time: float = 0.0
) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.top_level = true
	player.stream = stream
	player.bus = _get_existing_bus_or_default(bus_name)
	player.volume_db = _sfx_default_volume_db + volume_db + randf_range(-absf(volume_jitter_db), absf(volume_jitter_db))
	player.pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	add_child(player)
	player.global_position = origin
	_track_sfx_player(player)
	player.play(maxf(0.0, start_time))


func _play_sfx_ui(
	stream: AudioStream,
	bus_name: String,
	volume_db: float = 0.0,
	pitch_min: float = 0.98,
	pitch_max: float = 1.02,
	volume_jitter_db: float = 0.6,
	start_time: float = 0.0
) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _get_existing_bus_or_default(bus_name)
	player.volume_db = _sfx_default_volume_db + volume_db + randf_range(-absf(volume_jitter_db), absf(volume_jitter_db))
	player.pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	add_child(player)
	if not player.finished.is_connected(player.queue_free):
		player.finished.connect(player.queue_free)
	player.play(maxf(0.0, start_time))


func play_gunshot_at(origin: Vector3) -> void:
	_play_sfx_3d(SFX_GUNSHOT, origin, "SFX", -3.0 + MIX_BOOST_GAMEPLAY_SFX_DB, 0.98, 1.02, 0.6, 0.57)


func play_bullet_wall_impact_at(origin: Vector3) -> void:
	_play_sfx_3d(SFX_BULLET_WALL_IMPACT, origin, "SFX", -2.0 + MIX_BOOST_GAMEPLAY_SFX_DB)


func play_enemy_death_at(origin: Vector3) -> void:
	if SFX_ENEMY_DEATH == null:
		return

	var start_time := 1.18
	var fade_anchor_time := 4.0
	var fade_delay := maxf(0.0, fade_anchor_time - start_time)
	var fade_duration := 0.55

	var player := AudioStreamPlayer3D.new()
	player.top_level = true
	player.stream = SFX_ENEMY_DEATH
	player.bus = _get_existing_bus_or_default("SFX")
	player.volume_db = _sfx_default_volume_db - 1.0 + MIX_BOOST_GAMEPLAY_SFX_DB + randf_range(-0.5, 0.5)
	player.pitch_scale = randf_range(0.98, 1.02)
	add_child(player)
	player.global_position = origin
	_track_sfx_player(player)
	player.play(start_time)

	get_tree().create_timer(fade_delay).timeout.connect(func() -> void:
		if not is_instance_valid(player):
			return
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -60.0, fade_duration))

	get_tree().create_timer(fade_delay + fade_duration + 0.05).timeout.connect(func() -> void:
		if not is_instance_valid(player):
			return
		_active_sfx_players.erase(player)
		player.stop()
		player.queue_free())


func play_enemy_armor_break_at(origin: Vector3) -> void:
	_play_sfx_3d(SFX_ENEMY_ARMOR_BREAK, origin, "SFX", -3.0 + MIX_BOOST_GAMEPLAY_SFX_DB)


func play_ui_interaction() -> void:
	_play_sfx_ui(SFX_UI_INTERACTION, "UI", -8.0 + MIX_BOOST_UI_SFX_DB, 0.98, 1.02, 0.5)


func _is_level_scene(path: String) -> bool:
	if path.is_empty() or not path.ends_with(".tscn"):
		return false
	if path.begins_with(levels_root_prefix):
		return true
	# Keep level music working if world folders are reorganized but still live under a Levels segment.
	return path.contains("/Levels/")


func _sanitize_texture_path(path: String) -> String:
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		return ""
	if not ResourceLoader.exists(path):
		return ""
	return path


func _sanitize_bullet_trail_style(style: String) -> String:
	if not is_bullet_trail_unlocked(style):
		return "Default Trail"
	match style:
		"Tracer", "Neon", "Smoke":
			return style
		_:
			return "Default Trail"


func _get_next_level_path(level_path: String) -> String:
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
		levels = _get_catalog_level_paths_for_world_path(world_path)

	if levels.is_empty():
		return ""
	levels.sort()
	var idx := levels.find(level_path)
	if idx == -1:
		# Keep compatibility with any stale list entries that might only have file names.
		idx = levels.find("%s/%s" % [world_path, current_name])
	if idx == -1:
		return ""
	if idx + 1 >= levels.size():
		return ""
	return levels[idx + 1]


func _get_catalog_level_paths_for_world_path(world_path: String) -> Array[String]:
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


func _return_to_title_screen() -> void:
	if title_screen_scene_path.is_empty() or not ResourceLoader.exists(title_screen_scene_path):
		return
	_stop_all_sfx()
	get_tree().change_scene_to_file(title_screen_scene_path)
