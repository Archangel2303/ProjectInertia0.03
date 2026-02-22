extends Node3D

# CameraRig 2-stage controller (rig-driven only)
# - State A: regular stable follow from editor-established spawn framing
# - State B: slow-time aim, aligned from Sight marker with smooth transition
#
# IMPORTANT: this script moves/rotates CameraRig in global space.
# It does NOT write Camera3D global transform directly.

@export var player_gun_path: NodePath
@export var camera_path: NodePath
@export var sight_path: NodePath
@export var pivot_path: NodePath

# Slow-time input sources
@export var read_from_gamemanager := true
@export var read_from_player_gun := true

# Transition smoothing
@export var transition_speed := 10.0
@export var regular_follow_smooth := 12.0
@export var regular_rotate_smooth := 8.0
@export var aim_follow_smooth := 14.0 # how quickly aim camera position catches target
@export var aim_rotate_smooth := 14.0 # how quickly aim camera rotation aligns to target

# FOV zoom (aim should be lower than regular for zoom-in)
@export var regular_fov := 75.0
@export var aim_fov := 60.0 # lower = more zoom-in during aim mode
@export var fov_smooth := 10.0

# Aim pose tuning
@export var aim_distance := 0.0 # forward/back distance from aim origin (Sight)
@export var aim_height := 0.0 # vertical offset in aim mode (positive = higher)
@export var aim_side_offset := 0.0 # lateral offset in aim mode (positive = right)
@export var aim_yaw_offset_deg := 180.0 # rotates aim reference around Y (180 flips side)
@export var aim_look_ahead := 8.0 # look-at distance down aim direction
@export var aim_origin_smooth := 18.0 # smoothing for aim origin (higher = tighter)
@export var aim_origin_deadzone := 0.01 # ignore tiny aim-origin jitter below this value
# Note: `aim_closer_than_regular` and `aim_distance_ratio` removed —
# `aim_distance` is the single authoritative zoom parameter.
@export var aim_midpoint := 0.5 # 0 = regular distance, 1 = full aim_distance, 0.5 = midpoint

var is_slow_time := false

var player_gun: RigidBody3D
var cam: Camera3D
var sight: Node3D
var pivot: Node3D

var _blend := 0.0

# Captured at spawn to preserve user-established regular camera framing.
var _regular_rig_offset := Vector3.ZERO
var _regular_rig_basis := Basis.IDENTITY

# Camera local transform relative to rig (captured once, preserved).
var _cam_local_from_rig := Transform3D.IDENTITY

# Smoothed aim anchor.
var _aim_origin := Vector3.ZERO

func _ready() -> void:
	player_gun = get_node_or_null(player_gun_path) as RigidBody3D
	cam = get_node_or_null(camera_path) as Camera3D

	if player_gun == null:
		push_warning("CameraRig: `player_gun_path` not found")
		return

	if cam == null:
		push_warning("CameraRig: `camera_path` not found")
	else:
		cam.make_current()

	_resolve_sight()
	_resolve_pivot()
	_refresh_slow_time_flag()

	# Capture camera-local-from-rig first (needed to derive rig from camera pose).
	if cam != null:
		_cam_local_from_rig = global_transform.affine_inverse() * cam.global_transform
		# Derive the rig transform that would produce the editor Camera3D world transform
		# by inverting the local relationship: rig_tf = cam_tf * local.inverse()
		var cam_tf: Transform3D = cam.global_transform
		var local_inv: Transform3D = _cam_local_from_rig.affine_inverse()
		var desired_rig_tf: Transform3D = cam_tf * local_inv
		_regular_rig_offset = desired_rig_tf.origin - player_gun.global_position
		_regular_rig_basis = _basis_no_roll(desired_rig_tf.basis.orthonormalized())
	else:
		_cam_local_from_rig = Transform3D.IDENTITY
		# fallback to previous behavior (use rig's current global as baseline)
		_regular_rig_offset = global_position - player_gun.global_position
		_regular_rig_basis = _basis_no_roll(global_transform.basis.orthonormalized())

	_aim_origin = _get_raw_aim_origin()
	_blend = 1.0 if is_slow_time else 0.0

func _physics_process(delta: float) -> void:
	if player_gun == null:
		return

	_refresh_slow_time_flag()
	var blend_target: float = 1.0 if is_slow_time else 0.0
	var blend_alpha: float = _exp_alpha(transition_speed, delta)
	_blend = lerp(_blend, blend_target, blend_alpha)

	var regular_tf: Transform3D = _compute_regular_rig_target()
	var aim_tf: Transform3D = _compute_aim_rig_target(delta)
	var target_tf: Transform3D = _blend_transform(regular_tf, aim_tf, _blend)

	var pos_speed: float = lerp(regular_follow_smooth, aim_follow_smooth, _blend)
	var rot_speed: float = lerp(regular_rotate_smooth, aim_rotate_smooth, _blend)
	var pos_alpha: float = _exp_alpha(pos_speed, delta)
	var rot_alpha: float = _exp_alpha(rot_speed, delta)

	var out_pos: Vector3 = global_position.lerp(target_tf.origin, pos_alpha)
	var current_basis: Basis = global_transform.basis.orthonormalized()
	var target_basis: Basis = target_tf.basis.orthonormalized()
	var out_basis: Basis = _slerp_basis(current_basis, target_basis, rot_alpha)

	global_transform = Transform3D(out_basis, out_pos)
	_update_fov(delta)

func set_slow_time(active: bool) -> void:
	is_slow_time = active

func _resolve_sight() -> void:
	sight = null

	if sight_path != NodePath():
		sight = get_node_or_null(sight_path) as Node3D

	if sight == null and player_gun != null:
		sight = player_gun.get_node_or_null("Sight") as Node3D

	if sight == null and player_gun != null:
		sight = player_gun.find_node("Sight", true, false) as Node3D

	if sight == null:
		push_warning("CameraRig: `Sight` not found; aim falls back to gun origin")

func _resolve_pivot() -> void:
	pivot = null

	if pivot_path != NodePath():
		pivot = get_node_or_null(pivot_path) as Node3D

	if pivot == null and player_gun != null:
		pivot = player_gun.get_node_or_null("Pivot") as Node3D

	if pivot == null and player_gun != null:
		pivot = player_gun.find_node("Pivot", true, false) as Node3D

	if pivot == null:
		# not an error; pivot is optional — Sight or gun origin will be used
		return

func _refresh_slow_time_flag() -> void:
	var resolved := false

	if read_from_gamemanager and gamemanager != null:
		if "is_slowing_time" in gamemanager:
			is_slow_time = gamemanager.is_slowing_time
			resolved = true
		elif "is_slow_time" in gamemanager:
			is_slow_time = gamemanager.is_slow_time
			resolved = true

	if not resolved and read_from_player_gun and player_gun != null:
		if "is_slow_time" in player_gun:
			is_slow_time = player_gun.is_slow_time
			resolved = true
		elif "is_slowing_time" in player_gun:
			is_slow_time = player_gun.is_slowing_time

func _compute_regular_rig_target() -> Transform3D:
	# Preserve editor-established rest framing relative to gun translation.
	var pos: Vector3 = player_gun.global_position + _regular_rig_offset
	return Transform3D(_regular_rig_basis, pos)

func _compute_aim_rig_target(delta: float) -> Transform3D:
	var source_tf: Transform3D = _get_aim_source_transform()
	var source_basis: Basis = source_tf.basis.orthonormalized()
	var source_origin: Vector3 = source_tf.origin
	source_basis = source_basis.rotated(Vector3.UP, deg_to_rad(aim_yaw_offset_deg))

	var d: float = source_origin.distance_to(_aim_origin)
	if d < aim_origin_deadzone:
		source_origin = _aim_origin

	var origin_alpha: float = _exp_alpha(aim_origin_smooth, delta)
	_aim_origin = _aim_origin.lerp(source_origin, origin_alpha)

	var forward: Vector3 = -source_basis.z
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	# Desired camera world position in aim mode:
	# fixed close distance from Sight along the current aim direction.
	var fixed_dist: float = abs(aim_distance)

	# Determine regular camera's forward distance from the aim pivot so we can
	# compute a sensible midpoint target (so aim mode moves inward from regular).
	var regular_tf: Transform3D = _compute_regular_rig_target()
	var regular_cam_tf: Transform3D = regular_tf * _cam_local_from_rig
	var regular_cam_pos: Vector3 = regular_cam_tf.origin
	var to_regular: Vector3 = regular_cam_pos - source_origin
	var regular_forward_dist: float = to_regular.dot(forward)
	if regular_forward_dist < 0.01:
		regular_forward_dist = _regular_rig_offset.length()

	# Blend between regular forward distance and configured aim distance so that
	# entering slow time moves the camera inward toward a midpoint rather than
	# always jumping to the full `aim_distance` (which could be farther out).
	var midpoint_alpha: float = clamp(aim_midpoint, 0.0, 1.0)
	var target_aim_dist: float = lerp(regular_forward_dist, fixed_dist, midpoint_alpha)
	var desired_cam_pos: Vector3 = _aim_origin
	desired_cam_pos += source_basis.y * aim_height
	desired_cam_pos += source_basis.x * aim_side_offset
	desired_cam_pos -= forward * target_aim_dist

	var focus: Vector3 = _aim_origin + forward * aim_look_ahead
	var desired_cam_basis: Basis = _look_basis(desired_cam_pos, focus)
	desired_cam_basis = _basis_no_roll(desired_cam_basis)

	# No additional clamping: `aim_distance` controls how close the aim camera sits.

	# Convert desired camera world transform into required rig world transform,
	# respecting the existing camera local transform under the rig.
	var local_basis: Basis = _cam_local_from_rig.basis.orthonormalized()
	var local_origin: Vector3 = _cam_local_from_rig.origin
	var rig_basis: Basis = desired_cam_basis * local_basis.inverse()
	var rig_pos: Vector3 = desired_cam_pos - rig_basis * local_origin

	return Transform3D(rig_basis.orthonormalized(), rig_pos)

func _get_aim_source_transform() -> Transform3D:
	# Position prefers Sight marker when available.
	var source_origin: Vector3 = player_gun.global_position

	# prefer explicit pivot when present (more stable center of rotation)
	if pivot != null:
		source_origin = pivot.global_position
	elif sight != null:
		source_origin = sight.global_position

	# Rotation should follow the gun during slow-time aim.
	# Prefer pivot basis if it's a child of the gun; else fall back to sight when on-gun.
	var source_basis: Basis = player_gun.global_transform.basis.orthonormalized()
	if pivot != null:
		var pivot_on_gun := player_gun.is_ancestor_of(pivot)
		if pivot_on_gun:
			source_basis = pivot.global_transform.basis.orthonormalized()
	elif sight != null:
		var sight_on_gun := player_gun.is_ancestor_of(sight)
		if sight_on_gun:
			source_basis = sight.global_transform.basis.orthonormalized()

	return Transform3D(source_basis, source_origin)

func _get_raw_aim_origin() -> Vector3:
	if sight != null:
		return sight.global_position
	return player_gun.global_position

func _blend_transform(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	var pos: Vector3 = a.origin.lerp(b.origin, t)
	var blended_basis: Basis = _slerp_basis(
		a.basis.orthonormalized(),
		b.basis.orthonormalized(),
		t
	)
	return Transform3D(blended_basis, pos)

func _slerp_basis(a: Basis, b: Basis, t: float) -> Basis:
	var qa: Quaternion = a.get_rotation_quaternion()
	var qb: Quaternion = b.get_rotation_quaternion()
	var q: Quaternion = qa.slerp(qb, t)
	return Basis(q)

func _look_basis(from_pos: Vector3, to_pos: Vector3) -> Basis:
	var tf := Transform3D(Basis.IDENTITY, from_pos)
	return tf.looking_at(to_pos, Vector3.UP).basis

func _basis_no_roll(input_basis: Basis) -> Basis:
	var forward: Vector3 = -input_basis.z
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	# Build right from forward x up (not up x forward), otherwise handedness flips
	# and can rotate the view upside down.
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var up: Vector3 = forward.cross(right).normalized()
	return Basis(right, up, -forward).orthonormalized()

func _exp_alpha(speed: float, delta: float) -> float:
	if speed <= 0.0:
		return 1.0
	return 1.0 - exp(-speed * delta)

func _update_fov(delta: float) -> void:
	if cam == null:
		return

	# Safety guard: keep aim FOV <= regular FOV to prevent accidental zoom-out in aim mode.
	if aim_fov > regular_fov:
		aim_fov = regular_fov

	var target_fov: float = lerp(regular_fov, aim_fov, _blend)
	var alpha: float = _exp_alpha(fov_smooth, delta)
	cam.fov = lerp(cam.fov, target_fov, alpha)
