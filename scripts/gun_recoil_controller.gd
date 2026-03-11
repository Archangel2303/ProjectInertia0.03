extends RefCounted

var _falloff_dir := Vector3.ZERO
var _falloff_time_left := 0.0
var _falloff_duration := 0.0


func apply_fire_impulses(
	body: RigidBody3D,
	xform_basis: Basis,
	recoil_force: float,
	upward_recoil_force: float,
	recoil_energy_falloff_time: float,
	fire_spin_impulse: float,
	pitch_impulse: float,
	pitch_lever: float,
	backspin_impulse: float,
	backspin_lever: float
) -> void:
	var forward := -xform_basis.z
	var up := xform_basis.y.normalized()
	var right := xform_basis.x.normalized()
	var launch_up := up
	if launch_up.dot(Vector3.UP) < 0.0:
		# If upside down, push away from the floor instead of into it.
		launch_up = Vector3.UP

	body.apply_central_impulse(-forward * recoil_force)
	body.apply_central_impulse(launch_up * upward_recoil_force)

	var linear_impulse_vec := (-forward * recoil_force) + (launch_up * upward_recoil_force)
	if linear_impulse_vec.length_squared() > 0.000001 and recoil_energy_falloff_time > 0.0:
		_falloff_dir = linear_impulse_vec.normalized()
		_falloff_duration = recoil_energy_falloff_time
		_falloff_time_left = recoil_energy_falloff_time
	else:
		_falloff_dir = Vector3.ZERO
		_falloff_duration = 0.0
		_falloff_time_left = 0.0

	body.apply_torque_impulse(up * absf(fire_spin_impulse))

	var pitch_offset := up * pitch_lever
	body.apply_impulse(-forward * pitch_impulse, pitch_offset)

	body.apply_torque_impulse(-right * backspin_impulse)
	var backspin_offset := up * backspin_lever
	body.apply_impulse(forward * (backspin_impulse * 0.35), backspin_offset)


func apply_recoil_falloff(
	body: RigidBody3D,
	delta: float,
	falloff_strength: float,
	falloff_curve: float
) -> void:
	if _falloff_time_left <= 0.0 or _falloff_duration <= 0.0:
		return
	if falloff_strength <= 0.0:
		_falloff_time_left = 0.0
		return

	_falloff_time_left = maxf(0.0, _falloff_time_left - delta)
	var t := _falloff_time_left / _falloff_duration
	var weight := pow(clampf(t, 0.0, 1.0), maxf(falloff_curve, 0.01))
	body.apply_central_force(_falloff_dir * (falloff_strength * weight))
