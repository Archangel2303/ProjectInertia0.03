extends RigidBody3D

#-------TUNABLE PROPERTIES-------
@export var spin_speed := 2.0 
@export var recoil_force := 8.0

@export var pitch_impulse := 3.0
@export var pitch_lever := 0.22

@export var backspin_impulse := 2.5
@export var backspin_lever := 0.18

# Bullet spawn configuration
@export var bullet_scene: PackedScene = preload("res://scenes/Bullet/Bullet01.tscn")
@export var muzzle_node: Marker3D
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var muzzle_forward_axis: String = "-Z"
@onready var muzzle: Marker3D = muzzle_node if muzzle_node != null else get_node_or_null("Muzzle") as Marker3D

var has_fired := false
var passive_spin_speed := 4.5 #tweak later, can be faster than active spin for more visual flair
#-------State-------

var spin_direction :=1

func _ready() -> void:
	gravity_scale = 0 #gun isn't affected by gravity, only our impulses and torques
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _physics_process(_delta:float) -> void:
	if not has_fired:
		apply_passive_spin()



func apply_passive_spin() -> void:
	# YAW SPIN (around y axis) — soften assignment to avoid abrupt angular snaps
	var target_ang := Vector3(0, passive_spin_speed * spin_direction, 0)
	# smooth toward target angular velocity (reduces per-frame discontinuities)
	angular_velocity = angular_velocity.lerp(target_ang, 0.12)
	linear_velocity = Vector3.ZERO

func _input(event): #function to handle input events
	if event.is_action_pressed("fire"):
		_fire()
	
	if event.is_action_pressed("slow_time"):
		gamemanager.start_slow_time()

	if event.is_action_released("slow_time"):
		gamemanager.stop_slow_time()


func _fire():
	# reverse the spin direction
	spin_direction *= -1

	# Local axes from the gun's current orientation
	var xform_basis := global_transform.basis
	var forward := -xform_basis.z                         #godot forward = -z
	var up := xform_basis.y                               #Gun up axis
	
	#1) movement Recoil (real translation)
	apply_central_impulse(-forward * recoil_force)

	#2) Pitch recoil (real physics):
	# apply an impulse above center of mass -> creates pitch torque naturally	
	var pitch_offset := up * pitch_lever
	apply_impulse(-forward * pitch_impulse, pitch_offset)

	#3) Backspin (real physics):
	# Apply an impulse forward of center of mass -> creates backspin torque naturally
	var backspin_offset := forward * backspin_lever
	apply_impulse(forward * backspin_impulse, backspin_offset)

	# Spawn and fire the bullet (exclude the gun itself as the shooter)
	var shooter := get_parent() as CollisionObject3D
	_spawn_and_fire(shooter)


func _spawn_and_fire(shooter: CollisionObject3D) -> void:
	if muzzle == null:
		return
	var bullet = bullet_scene.instantiate()
	# add to current scene so physics and processing run
	var root = get_tree().get_current_scene()
	if root:
		root.add_child(bullet)
	else:
		get_tree().get_root().add_child(bullet)
	# place bullet at the muzzle transform
	bullet.global_transform = muzzle.global_transform
	# prevent immediate collision with the shooter and record shooter on bullet
	if shooter:
		bullet.add_collision_exception_with(shooter)
		bullet.shooter = shooter
	# fire in the configured muzzle forward direction
	var dir := _get_muzzle_forward().normalized()
	var up := muzzle.global_transform.basis.y.normalized()
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.UP
	bullet.look_at(bullet.global_transform.origin + dir, up)
	bullet.fire(dir.normalized())


func _get_muzzle_forward() -> Vector3:
	var basis := muzzle.global_transform.basis
	match muzzle_forward_axis:
		"+X":
			return basis.x
		"-X":
			return -basis.x
		"+Y":
			return basis.y
		"-Y":
			return -basis.y
		"+Z":
			return basis.z
		_:
			return -basis.z

	
