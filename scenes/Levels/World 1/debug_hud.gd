extends CanvasLayer

@onready var label: Label = $Readout

func _process(_dt: float) -> void:
	# Safely find the player gun in the scene tree instead of assuming GameManager has a reference.
	var b: RigidBody3D = get_tree().get_root().find_node("PlayerGun", true, false)
	if b == null:
		label.text = "No gun found"
		return

	label.text = "ang_vel: %s\nlin_vel: %s\nrot(deg): %s" % [
		str(b.angular_velocity),
		str(b.linear_velocity),
		str(b.rotation_degrees)
	]