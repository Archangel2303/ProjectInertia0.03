extends Node

#-----SIGNALS-----
signal ammo_changed(current: int, max_ammo: int)
signal score_changed(score: int)
signal state_changed(state: int)
signal level_changed(level_path: String)
signal run_reset()
signal slow_time_changed(active: bool)

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

var max_ammo: int = 5
var ammo: int = 5

var current_level_path: String = "FiringRange.tscn" #points to debug stage

var normal_time_scale := 1.0
var slow_time_scale := 0.2 
@export var max_impact_slow_time_scale := 0.06
@export var spin_for_max_impact := 28.0
var is_slowing_time := false

@export var player_gun_path: NodePath = NodePath("")
@onready var player_gun: RigidBody3D = get_node_or_null(player_gun_path)

func _ready() -> void:
	emit_signal("state_changed", state)
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)

	# Ensure the exported path is resolved at runtime if set in the inspector
	if player_gun == null and player_gun_path != NodePath(""):
		player_gun = get_node_or_null(player_gun_path)

	if player_gun == null:
		_resolve_player_gun_from_scene()


func _physics_process(_delta: float) -> void:
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
	set_state(GameState.PLAYING)
	reset_run()
	emit_signal("level_changed", current_level_path)

func reset_run() -> void:
	score = 0
	ammo = max_ammo
	emit_signal("score_changed", score)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("run_reset")

func add_score(amount: int) -> void:
	score += amount
	emit_signal("score_changed", score)

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
	set_state(GameState.LEVEL_COMPLETE)

func restart_level() -> void:
	if current_level_path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(current_level_path)

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
	Engine.time_scale = lerpf(slow_time_scale, max_impact_slow_time_scale, t)


func _resolve_player_gun_from_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var found := scene.find_child("PlayerGun", true, false)
	if found is RigidBody3D:
		player_gun = found as RigidBody3D
