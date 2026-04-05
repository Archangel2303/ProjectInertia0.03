extends RefCounted

var _impulse_velocity: Vector3 = Vector3.ZERO
var _target_angular_velocity: Vector3 = Vector3.ZERO
var _last_input_time: float = 0.0


## gun_basis: the gun's current global basis. A/D rotate around local up, W/S around local right.
func handle_input(impulse_strength: float, input_cooldown: float, gun_basis: Basis) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_input_time < input_cooldown:
		return

	var yaw_axis := gun_basis.y.normalized()   # local up — A/D spin axis
	var pitch_axis := gun_basis.x.normalized() # local right — W/S pitch axis

	var dir := Vector3.ZERO

	if Input.is_action_just_pressed("move_forward"):
		dir = -pitch_axis
	elif Input.is_action_just_pressed("move_back"):
		dir = pitch_axis
	elif Input.is_action_just_pressed("move_left"):
		dir = yaw_axis
	elif Input.is_action_just_pressed("move_right"):
		dir = -yaw_axis

	if dir != Vector3.ZERO:
		# Each new WASD press immediately replaces the current impulse.
		_target_angular_velocity = dir * impulse_strength
		_impulse_velocity = dir * impulse_strength
		_last_input_time = now


## Replaces state.angular_velocity while the impulse is active.
func integrate(
	state: PhysicsDirectBodyState3D,
	snap_speed: float,
	damping: float,
	max_speed: float
) -> void:
	var dt := state.step

	# Smooth toward target
	_impulse_velocity = _impulse_velocity.lerp(_target_angular_velocity, snap_speed * dt)

	# Clamp speed
	_impulse_velocity = _impulse_velocity.limit_length(max_speed)

	# Replace angular velocity
	state.angular_velocity = _impulse_velocity

	# Decay target velocity
	_target_angular_velocity = _target_angular_velocity.lerp(Vector3.ZERO, damping * dt)

	# Cut off long decay tail so passive spin resumes promptly
	if _target_angular_velocity.length_squared() < 4.0:
		_target_angular_velocity = Vector3.ZERO
	if _target_angular_velocity == Vector3.ZERO and _impulse_velocity.length_squared() < 1.0:
		_impulse_velocity = Vector3.ZERO


## Absorb current physics angular velocity (e.g. after fire recoil) so it decays naturally.
## Clears the old WASD target so the new velocity (recoil) isn't fought.
func sync_from_state(state: PhysicsDirectBodyState3D) -> void:
	_impulse_velocity = state.angular_velocity
	_target_angular_velocity = state.angular_velocity


func is_active() -> bool:
	return _target_angular_velocity.length_squared() > 0.001 or _impulse_velocity.length_squared() > 0.001


func reset() -> void:
	_impulse_velocity = Vector3.ZERO
	_target_angular_velocity = Vector3.ZERO
	_last_input_time = 0.0
