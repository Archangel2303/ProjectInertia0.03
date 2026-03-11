extends RefCounted


func integrate_angular_velocity(
	state: PhysicsDirectBodyState3D,
	passive_spin_axis_mode: String,
	spin_speed: float,
	passive_spin_direction: int,
	passive_spin_response: float,
	cross_axis_damping: float,
	backspin_falloff_damping: float
) -> void:
	var spin_axis := _get_spin_axis(state.transform.basis, passive_spin_axis_mode)
	var current_ang := state.angular_velocity

	# Build an orthonormal angular basis so passive spin, backspin, and roll stay decoupled.
	var raw_backspin_axis := state.transform.basis.x.normalized()
	var backspin_axis := raw_backspin_axis - spin_axis * raw_backspin_axis.dot(spin_axis)
	if backspin_axis.length_squared() < 0.000001:
		var raw_fallback := state.transform.basis.z.normalized()
		backspin_axis = raw_fallback - spin_axis * raw_fallback.dot(spin_axis)
	if backspin_axis.length_squared() < 0.000001:
		backspin_axis = spin_axis.cross(Vector3.FORWARD)
		if backspin_axis.length_squared() < 0.000001:
			backspin_axis = spin_axis.cross(Vector3.RIGHT)
	backspin_axis = backspin_axis.normalized()

	var roll_axis := spin_axis.cross(backspin_axis)
	if roll_axis.length_squared() < 0.000001:
		roll_axis = spin_axis.cross(Vector3.UP)
		if roll_axis.length_squared() < 0.000001:
			roll_axis = spin_axis.cross(Vector3.RIGHT)
	roll_axis = roll_axis.normalized()

	var current_spin := spin_axis * current_ang.dot(spin_axis)
	var current_backspin := backspin_axis * current_ang.dot(backspin_axis)
	var current_roll := roll_axis * current_ang.dot(roll_axis)
	var target_parallel := spin_axis * (spin_speed * passive_spin_direction)

	var parallel_blend := 1.0 - exp(-passive_spin_response * state.step)
	var backspin_keep := exp(-backspin_falloff_damping * state.step)
	var perpendicular_keep := exp(-cross_axis_damping * state.step)

	var new_parallel := current_spin.lerp(target_parallel, parallel_blend)
	var new_backspin := current_backspin * backspin_keep
	var new_roll := current_roll * perpendicular_keep
	state.angular_velocity = new_parallel + new_backspin + new_roll


func _get_spin_axis(xform_basis: Basis, passive_spin_axis_mode: String) -> Vector3:
	if passive_spin_axis_mode == "WorldUp":
		return Vector3.UP
	var axis := xform_basis.y.normalized()
	if axis.length_squared() < 0.000001:
		return Vector3.UP
	return axis
