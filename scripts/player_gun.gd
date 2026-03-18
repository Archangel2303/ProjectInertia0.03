extends RigidBody3D

signal fired(muzzle_origin: Vector3, fire_direction: Vector3)

const GunSpinController = preload("res://scripts/gun_spin_controller.gd")
const GunRecoilController = preload("res://scripts/gun_recoil_controller.gd")
const GunProjectileSpawner = preload("res://scripts/gun_projectile_spawner.gd")
const GunGravityArmer = preload("res://scripts/gun_gravity_armer.gd")

#-------TUNABLE PROPERTIES-------
# Target angular speed used by the passive spin controller.
@export var spin_speed := 2.0 

# Shot-time recoil spin torque magnitude.
# Applied on the gun's local up axis and independent from passive spin direction.
@export var fire_spin_impulse := 3.0

# Axis used by passive spin controller.
@export_enum("LocalUp", "WorldUp") var passive_spin_axis_mode: String = "LocalUp"

# Rate at which passive spin converges toward target spin speed.
@export var passive_spin_response := 14.0

# Damps angular velocity components outside the passive spin axis.
# Lower default preserves more natural tilt so local-up recoil is more visible.
@export var cross_axis_damping := 6.0

# Linear recoil impulse applied to the gun's center in `_apply_fire_impulses()`;
# increases backward translation (felt recoil / displacement).
@export var recoil_force := 8.0

# Extra upward recoil impulse added on fire (linear translation).
@export var upward_recoil_force := 1.5

# Post-shot translational energy tail so movement decays over time instead of stopping abruptly.
@export var recoil_energy_falloff_time := 0.25
@export var recoil_energy_falloff_strength := 20.0
@export var recoil_energy_falloff_curve := 1.25

# Extra linear damping for recoil settle. Higher values recover faster,
# lower values let the gun drift longer after each shot.
@export var recoil_recovery_damp := 0.55

# Off-center recoil impulse magnitude used to create pitch (muzzle rise)
# around the custom COM/origin.
@export var pitch_impulse := 12.0

# Moment arm (offset from custom COM/origin) used with `pitch_impulse`
# to control pitch torque magnitude.
@export var pitch_lever := 0.22

# Direct torque impulse magnitude used to produce backward pitch rotation
# (backflip-like spin) on fire.
@export var backspin_impulse := 2.5

# Optional moment arm for a supplemental off-center backspin impulse.
# Set to 0.0 for pure torque-driven backspin around the body COM.
@export var backspin_lever := 0.0

# Damping rate for shot-time backspin axis only.
# Higher values make backspin settle faster back into passive spin control.
@export var backspin_falloff_damping := 2.2

# Short post-shot window that resists wall-impact counter-spin so recoil remains controllable
# in tight spaces.
@export var backspin_protection_time := 0.18
@export var backspin_min_after_fire := 1.1
@export var backspin_collision_cancel_resistance := 0.9

# Rest-state roll correction so the gun settles right-side up before the next shot.
@export var auto_upright_enabled := true
@export var auto_upright_delay_after_fire := 0.5
@export var auto_upright_linear_speed_threshold := 0.08
@export var auto_upright_roll_gain := 11.0
@export var auto_upright_roll_damping := 4.0
@export var auto_upright_min_roll_error_deg := 6.0

# Bullet spawn configuration
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet/Bullet01.tscn")
@export var muzzle_node: Marker3D
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var muzzle_forward_axis: String = "-Z"
@export var enable_gravity_after_first_shot := true
@export var gravity_scale_after_first_shot := 0.8
@onready var muzzle: Marker3D = muzzle_node if muzzle_node != null else get_node_or_null("Muzzle") as Marker3D

# Laser sight prediction
@export var laser_sight_enabled := true
@export var laser_max_distance := 220.0
@export_flags_3d_physics var laser_collision_mask: int = 17
@export var laser_color := Color(0.28, 1.0, 0.45, 1.0)

#-------State-------

var passive_spin_direction := 1
var fire_queued := false
var bullet_spawn_queued := false
var backspin_protection_time_left := 0.0
var auto_upright_cooldown_left := 0.0

var spin_controller := GunSpinController.new()
var recoil_controller := GunRecoilController.new()
var projectile_spawner := GunProjectileSpawner.new()
var gravity_armer := GunGravityArmer.new()
var _laser_mesh_instance: MeshInstance3D = null
var _laser_mesh := ImmediateMesh.new()
var _laser_material := StandardMaterial3D.new()
var _gun_skin_material: StandardMaterial3D = null

@onready var gun_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

func _ready() -> void:
	gravity_armer.configure(enable_gravity_after_first_shot, gravity_scale_after_first_shot)
	gravity_armer.reset(self, 0.0)
	_apply_selected_gun_skin()
	# Ensure recoil/passive spin pivot is the gun's local origin.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	linear_damp = recoil_recovery_damp
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_setup_laser_sight()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if auto_upright_cooldown_left > 0.0:
		auto_upright_cooldown_left = maxf(0.0, auto_upright_cooldown_left - state.step)

	spin_controller.integrate_angular_velocity(
		state,
		passive_spin_axis_mode,
		spin_speed,
		passive_spin_direction,
		passive_spin_response,
		cross_axis_damping,
		backspin_falloff_damping
	)

	if backspin_protection_time_left > 0.0:
		backspin_protection_time_left = maxf(0.0, backspin_protection_time_left - state.step)
		spin_controller.protect_backspin_component(
			state,
			passive_spin_axis_mode,
			-signf(backspin_impulse),
			backspin_min_after_fire,
			backspin_collision_cancel_resistance
		)

	if fire_queued:
		fire_queued = false
		_apply_fire_impulses(state.transform.basis)
		gamemanager.register_shot_fired()
		backspin_protection_time_left = maxf(0.0, backspin_protection_time)
		spin_controller.protect_backspin_component(
			state,
			passive_spin_axis_mode,
			-signf(backspin_impulse),
			backspin_min_after_fire,
			backspin_collision_cancel_resistance
		)
		bullet_spawn_queued = true
		passive_spin_direction *= -1
		auto_upright_cooldown_left = maxf(0.0, auto_upright_delay_after_fire)

	_apply_auto_upright_roll(state)


func _physics_process(delta: float) -> void:
	recoil_controller.apply_recoil_falloff(
		self,
		delta,
		recoil_energy_falloff_strength,
		recoil_energy_falloff_curve
	)

	if bullet_spawn_queued:
		bullet_spawn_queued = false
		var shooter := self as CollisionObject3D
		_spawn_and_fire(shooter)

	_update_laser_sight()

func _input(event): #function to handle input events
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
	
	if event.is_action_pressed("slow_time"):
		gamemanager.start_slow_time()

	if event.is_action_released("slow_time"):
		gamemanager.stop_slow_time()


func _apply_fire_impulses(xform_basis: Basis) -> void:
	gravity_armer.arm_if_needed(self)
	recoil_controller.apply_fire_impulses(
		self,
		xform_basis,
		recoil_force,
		upward_recoil_force,
		recoil_energy_falloff_time,
		fire_spin_impulse,
		pitch_impulse,
		pitch_lever,
		backspin_impulse,
		backspin_lever
	)


func _spawn_and_fire(shooter: CollisionObject3D) -> void:
	if muzzle == null:
		return
	var fire_dir := projectile_spawner.spawn_and_fire(self, bullet_scene, muzzle, muzzle_forward_axis, shooter)
	if fire_dir.length_squared() > 0.000001:
		if gamemanager != null and gamemanager.has_method("play_gunshot_at"):
			gamemanager.play_gunshot_at(global_transform.origin)
		emit_signal("fired", muzzle.global_transform.origin, fire_dir)


func _setup_laser_sight() -> void:
	_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_material.albedo_color = laser_color
	_laser_material.emission_enabled = true
	_laser_material.emission = laser_color
	_laser_material.emission_energy_multiplier = 2.2
	_laser_material.no_depth_test = true

	_laser_mesh_instance = MeshInstance3D.new()
	_laser_mesh_instance.name = "LaserSight"
	_laser_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser_mesh_instance.mesh = _laser_mesh
	add_child(_laser_mesh_instance)


func _update_laser_sight() -> void:
	if _laser_mesh_instance == null:
		return
	if not laser_sight_enabled or muzzle == null:
		_laser_mesh_instance.visible = false
		return

	var origin := muzzle.global_transform.origin
	var dir := _get_muzzle_forward(muzzle.global_transform.basis, muzzle_forward_axis).normalized()
	if dir.length_squared() < 0.000001:
		_laser_mesh_instance.visible = false
		return

	var cast_distance := maxf(0.5, laser_max_distance)
	var target := origin + dir * cast_distance

	var query := PhysicsRayQueryParameters3D.create(origin, target, laser_collision_mask, [get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var space_state := get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.get("position", target)

	_laser_mesh.clear_surfaces()
	_laser_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _laser_material)
	_laser_mesh.surface_add_vertex(to_local(origin))
	_laser_mesh.surface_add_vertex(to_local(target))
	_laser_mesh.surface_end()
	_laser_mesh_instance.visible = true


func _get_muzzle_forward(muzzle_basis: Basis, axis_mode: String) -> Vector3:
	match axis_mode:
		"+X":
			return muzzle_basis.x
		"-X":
			return -muzzle_basis.x
		"+Y":
			return muzzle_basis.y
		"-Y":
			return -muzzle_basis.y
		"+Z":
			return muzzle_basis.z
		_:
			return -muzzle_basis.z


func _apply_auto_upright_roll(state: PhysicsDirectBodyState3D) -> void:
	if not auto_upright_enabled:
		return
	if auto_upright_cooldown_left > 0.0:
		return
	if state.linear_velocity.length() > auto_upright_linear_speed_threshold:
		return

	var basis := state.transform.basis
	var forward := (-basis.z).normalized()
	if forward.length_squared() < 0.000001:
		return

	var world_up := Vector3.UP
	var desired_up := world_up - forward * world_up.dot(forward)
	if desired_up.length_squared() < 0.000001:
		return
	desired_up = desired_up.normalized()

	var current_up := basis.y.normalized()
	var current_up_flat := current_up - forward * current_up.dot(forward)
	if current_up_flat.length_squared() < 0.000001:
		return
	current_up_flat = current_up_flat.normalized()

	var sin_error := forward.dot(current_up_flat.cross(desired_up))
	var cos_error := clampf(current_up_flat.dot(desired_up), -1.0, 1.0)
	var roll_error := atan2(sin_error, cos_error)
	var min_error_rad := deg_to_rad(maxf(0.0, auto_upright_min_roll_error_deg))
	if absf(roll_error) < min_error_rad:
		return

	var roll_speed := state.angular_velocity.dot(forward)
	var correction_accel := (-roll_error * auto_upright_roll_gain) - (roll_speed * auto_upright_roll_damping)
	state.angular_velocity += forward * (correction_accel * state.step)


func _apply_selected_gun_skin() -> void:
	if gun_mesh == null:
		return
	if gamemanager == null or not gamemanager.has_method("get_selected_gun_skin_path"):
		return

	var texture_path: String = String(gamemanager.get_selected_gun_skin_path())
	if texture_path.is_empty():
		return

	var skin_texture := load(texture_path) as Texture2D
	if skin_texture == null:
		return

	if _gun_skin_material == null:
		var base_material := gun_mesh.get_active_material(0)
		if base_material is StandardMaterial3D:
			_gun_skin_material = (base_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_gun_skin_material = StandardMaterial3D.new()

	_gun_skin_material.albedo_texture = skin_texture
	gun_mesh.set_surface_override_material(0, _gun_skin_material)

	
 