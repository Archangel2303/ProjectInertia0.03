extends RigidBody3D

#-------TUNABLE PROPERTIES-------
@export var spin_speed := 4.0 
@export var recoil_force := 8.0

@export var pitch_impulse := 3.0
@export var pitch_lever := 0.22

@export var backspin_impulse := 2.5
@export var backspin_lever := 0.18

#-------State-------

var spin_direction :=1

func _physics_process(_delta:float) -> void:
	apply_passive_spin()

func apply_passive_spin() -> void:
	#YAW SPIN (around y axis)-real torque
	apply_torque(global_transform.basis.y * spin_speed * spin_direction)

func _input(event):
	if event.is_action_pressed("fire"):
		fire()

func fire():
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