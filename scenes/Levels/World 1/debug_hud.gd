extends CanvasLayer

@onready var label: Label = $Readout

func _process(_dt: float) -> void:
	var b: RigidBody3D = null

	# Prefer GameManager's reference if available (recommended pattern).
	if Engine.has_singleton("GameManager"):
		var gm := Engine.get_singleton("GameManager")
		if gm and gm.player_gun != null:
			b = gm.player_gun

	# Fallback: search the scene tree by node name.
	if b == null:
		b = get_tree().get_root().find_node("PlayerGun", true, false)

	if b == null:
		label.text = "No gun found"
		return

	label.text = "ang_vel: %s\nlin_vel: %s\nrot(deg): %s" % [
		str(b.angular_velocity),
		str(b.linear_velocity),
		str(b.rotation_degrees)
	]