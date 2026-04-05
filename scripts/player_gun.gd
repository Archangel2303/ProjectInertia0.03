extends RigidBody3D
## PlayerGun Controller — thin orchestrator that delegates to single-responsibility services.
##
## Services (composition):
##   spin_controller    — passive spin physics
##   recoil_controller  — fire recoil impulses + energy falloff
##   projectile_spawner — bullet instantiation
##   gravity_armer      — post-first-shot gravity scheduling
##   impulse_rotation   — WASD impulse rotation (takes over from passive spin while active)
##   laser_sight        — laser line rendering + raycasting
##   auto_upright_svc   — roll correction physics
##   skin_applicator    — cosmetic gun skin application
##   spawn_manager      — spawn transform caching + reset lifecycle

signal fired(muzzle_origin: Vector3, fire_direction: Vector3)

const GunSpinController = preload("res://scripts/gun_spin_controller.gd")
const GunRecoilController = preload("res://scripts/gun_recoil_controller.gd")
const GunProjectileSpawner = preload("res://scripts/gun_projectile_spawner.gd")
const GunGravityArmer = preload("res://scripts/gun_gravity_armer.gd")
const GunImpulseRotation = preload("res://scripts/gun_impulse_rotation.gd")
const GunLaserSight = preload("res://scripts/gun_laser_sight.gd")
const GunAutoUpright = preload("res://scripts/gun_auto_upright.gd")
const GunSkinApplicator = preload("res://scripts/gun_skin_applicator.gd")
const GunSpawnManager = preload("res://scripts/gun_spawn_manager.gd")

#-------TUNABLE PROPERTIES-------
@export var spin_speed := 2.0
@export var fire_spin_impulse := 3.0
@export_enum("LocalUp", "WorldUp") var passive_spin_axis_mode: String = "LocalUp"
@export var passive_spin_response := 14.0
@export var cross_axis_damping := 6.0

@export var recoil_force := 8.0
@export var upward_recoil_force := 1.5
@export var recoil_energy_falloff_time := 0.25
@export var recoil_energy_falloff_strength := 20.0
@export var recoil_energy_falloff_curve := 1.25
@export var recoil_recovery_damp := 0.55

@export var pitch_impulse := 12.0
@export var pitch_lever := 0.22
@export var backspin_impulse := 2.5
@export var backspin_lever := 0.0
@export var backspin_falloff_damping := 2.2
@export var backspin_protection_time := 0.18
@export var backspin_min_after_fire := 1.1
@export var backspin_collision_cancel_resistance := 0.9

@export var passive_handoff_pitch_tolerance_deg := 5.0
@export var backspin_damping_handoff_multiplier := 4.0
@export var passive_handoff_clear_protection := true

@export var auto_upright_enabled := true
@export var auto_upright_delay_after_fire := 0.5
@export var auto_upright_linear_speed_threshold := 0.08
@export var auto_upright_roll_gain := 11.0
@export var auto_upright_roll_damping := 4.0
@export var auto_upright_min_roll_error_deg := 6.0

@export var impulse_rotation_enabled := true
@export var impulse_strength := 10.0
@export var impulse_snap_speed := 10.0
@export var impulse_damping := 2.5
@export var impulse_max_speed := 6.0
@export var impulse_input_cooldown := 0.5

@export var bullet_scene: PackedScene = preload("res://scenes/Bullet/Bullet01.tscn")
@export var muzzle_node: Marker3D
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var muzzle_forward_axis: String = "-Z"
@export var enable_gravity_after_first_shot := true
@export var gravity_scale_after_first_shot := 0.8
@onready var muzzle: Marker3D = muzzle_node if muzzle_node != null else get_node_or_null("Muzzle") as Marker3D
@export var debug_bullet_spawn := true

@export var laser_sight_enabled := true
@export var laser_max_distance := 220.0
@export_flags_3d_physics var laser_collision_mask: int = 17
@export var laser_color := Color(0.28, 1.0, 0.45, 1.0)

#-------Services-------
var spin_controller := GunSpinController.new()
var recoil_controller := GunRecoilController.new()
var projectile_spawner := GunProjectileSpawner.new()
var gravity_armer := GunGravityArmer.new()
var impulse_rotation := GunImpulseRotation.new()
var laser_sight := GunLaserSight.new()
var auto_upright_svc := GunAutoUpright.new()
var skin_applicator := GunSkinApplicator.new()
var spawn_manager := GunSpawnManager.new()

#-------State-------
var passive_spin_direction := 1
var fire_queued := false
var bullet_spawn_queued := false
var backspin_protection_time_left := 0.0
var auto_upright_cooldown_left := 0.0
var has_fired := false

@onready var gun_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D


func _ready() -> void:
	spawn_manager.cache(self)
	if debug_bullet_spawn:
		print_debug("player_gun: _ready caching spawn ->", global_transform.origin)

	if gamemanager != null:
		gamemanager.player_gun = self
		if debug_bullet_spawn:
			print_debug("player_gun: registered self with gamemanager ->", global_transform.origin)

	gravity_armer.configure(enable_gravity_after_first_shot, gravity_scale_after_first_shot)
	gravity_armer.reset(self, 0.0)

	if gun_mesh != null and gamemanager != null and gamemanager.has_method("get_selected_gun_skin_path"):
		skin_applicator.apply(gun_mesh, String(gamemanager.get_selected_gun_skin_path()))

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	linear_damp = recoil_recovery_damp
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	laser_sight.setup(self, laser_color)

	if gamemanager != null:
		gamemanager.run_reset.connect(_on_run_reset)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if auto_upright_cooldown_left > 0.0:
		auto_upright_cooldown_left = maxf(0.0, auto_upright_cooldown_left - state.step)

	# --- Rotation orchestration ---
	var _impulse_active := impulse_rotation_enabled and impulse_rotation.is_active()

	if _impulse_active:
		impulse_rotation.integrate(state, impulse_snap_speed, impulse_damping, impulse_max_speed)
	else:
		var effective_backspin_damping: float = float(backspin_falloff_damping)
		var forward: Vector3 = (-state.transform.basis.z).normalized()
		var pitch_rad: float = asin(clamp(forward.y, -1.0, 1.0))
		var pitch_deg: float = abs(rad_to_deg(pitch_rad))
		if pitch_deg <= passive_handoff_pitch_tolerance_deg and backspin_protection_time_left <= 0.0:
			effective_backspin_damping = backspin_falloff_damping * maxf(1.0, backspin_damping_handoff_multiplier)

		spin_controller.integrate_angular_velocity(
			state, passive_spin_axis_mode, spin_speed, passive_spin_direction,
			passive_spin_response, cross_axis_damping, effective_backspin_damping
		)

	# Backspin protection runs regardless of impulse/passive mode
	if backspin_protection_time_left > 0.0:
		backspin_protection_time_left = maxf(0.0, backspin_protection_time_left - state.step)
		spin_controller.protect_backspin_component(
			state, passive_spin_axis_mode, -signf(backspin_impulse),
			backspin_min_after_fire, backspin_collision_cancel_resistance
		)

	# --- Fire orchestration ---
	if fire_queued:
		fire_queued = false
		has_fired = true
		_apply_fire_impulses(state.transform.basis)
		gamemanager.register_shot_fired()
		backspin_protection_time_left = maxf(0.0, backspin_protection_time)
		if _impulse_active:
			impulse_rotation.sync_from_state(state)
		else:
			spin_controller.protect_backspin_component(
				state, passive_spin_axis_mode, -signf(backspin_impulse),
				backspin_min_after_fire, backspin_collision_cancel_resistance
			)
		bullet_spawn_queued = true
		passive_spin_direction *= -1
		auto_upright_cooldown_left = maxf(0.0, auto_upright_delay_after_fire)

	# --- Roll correction ---
	auto_upright_svc.apply(
		state, auto_upright_enabled, auto_upright_cooldown_left,
		auto_upright_linear_speed_threshold, auto_upright_roll_gain,
		auto_upright_roll_damping, auto_upright_min_roll_error_deg
	)


func _process(_delta: float) -> void:
	if not impulse_rotation_enabled:
		return
	if gamemanager == null:
		return
	if not has_fired:
		return
	var is_playing := int(gamemanager.state) == int(gamemanager.GameState.PLAYING)
	if get_tree().paused or not is_playing:
		return
	impulse_rotation.handle_input(impulse_strength, impulse_input_cooldown, global_transform.basis)


func _physics_process(delta: float) -> void:
	recoil_controller.apply_recoil_falloff(
		self, delta, recoil_energy_falloff_strength, recoil_energy_falloff_curve
	)

	if bullet_spawn_queued:
		bullet_spawn_queued = false
		_spawn_and_fire(self as CollisionObject3D)

	laser_sight.update(
		self, muzzle, muzzle_forward_axis,
		laser_sight_enabled, laser_max_distance, laser_collision_mask
	)


func _unhandled_input(event):
	if gamemanager == null:
		return
	var is_playing := int(gamemanager.state) == int(gamemanager.GameState.PLAYING)
	if get_tree().paused or not is_playing:
		fire_queued = false
		if event.is_action_released("slow_time") and gamemanager.is_slowing_time:
			gamemanager.stop_slow_time()
		return

	if event.is_action_pressed("fire"):
		fire_queued = true
		if debug_bullet_spawn:
			print_debug("player_gun: fire input - queued")

	if event.is_action_pressed("slow_time"):
		gamemanager.start_slow_time()

	if event.is_action_released("slow_time"):
		gamemanager.stop_slow_time()


func _apply_fire_impulses(xform_basis: Basis) -> void:
	gravity_armer.arm_if_needed(self)
	recoil_controller.apply_fire_impulses(
		self, xform_basis, recoil_force, upward_recoil_force,
		recoil_energy_falloff_time, fire_spin_impulse,
		pitch_impulse, pitch_lever, backspin_impulse, backspin_lever
	)


func _spawn_and_fire(shooter: CollisionObject3D) -> void:
	if muzzle == null:
		if debug_bullet_spawn:
			print_debug("player_gun: muzzle is null, cannot spawn bullet")
		return
	var fire_dir := projectile_spawner.spawn_and_fire(self, bullet_scene, muzzle, muzzle_forward_axis, shooter)
	if debug_bullet_spawn:
		print_debug("player_gun: spawn_and_fire returned dir length", fire_dir.length())
	if fire_dir.length_squared() > 0.000001:
		emit_signal("fired", muzzle.global_transform.origin, fire_dir)


func reset_to_spawn_state() -> void:
	if spawn_manager.cached:
		sleeping = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		call_deferred("_apply_cached_spawn")
	else:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	freeze = false


func _apply_cached_spawn() -> void:
	if not spawn_manager.cached:
		return
	spawn_manager.apply(self)
	if debug_bullet_spawn:
		print_debug("player_gun: _apply_cached_spawn ->", spawn_manager.global_tf.origin)
	sleeping = false
	passive_spin_direction = 1
	fire_queued = false
	bullet_spawn_queued = false
	backspin_protection_time_left = 0.0
	auto_upright_cooldown_left = 0.0
	has_fired = false
	impulse_rotation.reset()
	gravity_armer.configure(enable_gravity_after_first_shot, gravity_scale_after_first_shot)
	gravity_armer.reset(self, 0.0)


func _cache_spawn_transform() -> void:
	spawn_manager.cache(self)
	if debug_bullet_spawn:
		print_debug("player_gun: _cache_spawn_transform ->", global_transform.origin)


func _on_run_reset() -> void:
	call_deferred("_cache_spawn_transform")
