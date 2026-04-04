extends RefCounted


func apply(
	state: PhysicsDirectBodyState3D,
	enabled: bool,
	cooldown_left: float,
	linear_speed_threshold: float,
	roll_gain: float,
	roll_damping: float,
	min_error_deg: float
) -> void:
	if not enabled:
		return
	if cooldown_left > 0.0:
		return
	if state.linear_velocity.length() > linear_speed_threshold:
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
	var min_error_rad := deg_to_rad(maxf(0.0, min_error_deg))
	if absf(roll_error) < min_error_rad:
		return

	var roll_speed := state.angular_velocity.dot(forward)
	var correction_accel := (-roll_error * roll_gain) - (roll_speed * roll_damping)
	state.angular_velocity += forward * (correction_accel * state.step)
