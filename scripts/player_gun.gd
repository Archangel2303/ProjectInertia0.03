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
@export var recoil_recovery_damp := 2.0

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
@export var backspin_lever := 0.18

# Damping rate for shot-time backspin axis only.
# Higher values make backspin settle faster back into passive spin control.
@export var backspin_falloff_damping := 2.2

# Short post-shot window that resists wall-impact counter-spin so recoil remains controllable
# in tight spaces.
@export var backspin_protection_time := 0.18
@export var backspin_min_after_fire := 1.1
@export var backspin_collision_cancel_resistance := 0.72

# Bullet spawn configuration
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet/Bullet01.tscn")
@export var muzzle_node: Marker3D
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var muzzle_forward_axis: String = "-Z"
@export var enable_gravity_after_first_shot := true
@export var gravity_scale_after_first_shot := 0.8
@onready var muzzle: Marker3D = muzzle_node if muzzle_node != null else get_node_or_null("Muzzle") as Marker3D

#-------State-------

var passive_spin_direction := 1
var fire_queued := false
var bullet_spawn_queued := false
var backspin_protection_time_left := 0.0

var spin_controller := GunSpinController.new()
var recoil_controller := GunRecoilController.new()
var projectile_spawner := GunProjectileSpawner.new()
var gravity_armer := GunGravityArmer.new()

func _ready() -> void:
	gravity_armer.configure(enable_gravity_after_first_shot, gravity_scale_after_first_shot)
	gravity_armer.reset(self, 0.0)
	# Assumes RigidBody3D center_of_mass_mode is Custom and center_of_mass is Vector3.ZERO.
	linear_damp = recoil_recovery_damp
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
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

func _input(event): #function to handle input events
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
		emit_signal("fired", muzzle.global_transform.origin, fire_dir)

	
 