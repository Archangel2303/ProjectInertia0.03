extends Node3D

@export var cam_path: NodePath
# legacy alias: some scenes use `camera_path`
@export var camera_path: NodePath

@export var gun_path: NodePath
# legacy alias: some scenes use `player_path`
@export var player_path: NodePath

@export var follow_marker_path: NodePath  # camera follows specified marker stage1
@export var cam_aim_path: NodePath # camera snaps to this marker when aiming stage2
@export var sight_path: NodePath # the gun's sight marker, used for aiming stage2
@export var muzzle_path: NodePath # gun muzzle marker used for final aim direction
@export var aim_forward_distance := 30.0


@export var follow_speed := 18.0  #higher value = faster camera movement
@export var aim_follow_speed := 60.0 #higher value = tighter stage2 lock while aiming
@export var rot_speed := 16.0 #how quickly the camera rotates to match the sight when aiming
@export var snap_distance := 3.0  # snap if gun moves too far in 1 tick
@export var aim_entry_snap_distance := 0.24 # snap quickly on slow-time start if close enough
@export var aim_entry_snap_window := 0.12 # seconds after entering slow-time where entry snap can occur
@export var aim_sustain_snap_distance := 0.75 # snap during sustained aim if lag grows too large
@export var aim_max_follow_error := 0.12 # hard cap on allowed aim positional lag
@export var aim_max_rotation_error_deg := 6.0 # hard cap on allowed aim rotational lag
@export var aim_spin_response_enabled := true
@export var aim_high_spin_reference := 24.0 # angular speed where max aim response boost is reached
@export var aim_follow_speed_high_spin := 120.0
@export var aim_rot_speed_high_spin := 30.0

@export var normal_fov := 65.0
@export var aim_fov := 45.0
@export var fov_lerp_speed := 10.0

@export var remove_roll_in_aim := true
@export var stage1_follow_translation_only := true
@export var stage1_orbit_on_fire := true
@export var stage1_orbit_blend_speed := 6.0
@export var stage1_fire_target_distance := 140.0
@export_flags_3d_physics var stage1_fire_target_mask := 1
@export var stage1_collision_avoidance := true
@export var stage1_use_custom_collision_solver := false
@export_flags_3d_physics var stage1_collision_mask := 15
@export var stage1_collision_margin := 0.2
@export var stage1_use_multi_probe := true
@export var stage1_probe_vertical_offset := 0.12
@export var stage1_probe_horizontal_offset := 0.08
@export var stage1_doorway_probe_relax := true
@export var stage1_doorway_relax_threshold := 0.14
@export var stage1_constrained_recovery_time := 0.22
@export var stage1_doorway_relax_speed := 10.0
@export var stage1_recovery_max_step_speed := 8.0
@export var stage1_shrink_max_step_speed := 12.0
@export var stage1_ignore_top_surfaces := true
@export_range(0.0, 1.0, 0.01) var stage1_top_surface_normal_dot := 0.55
@export var stage1_collision_shrink_speed := 70.0
@export var stage1_collision_release_speed := 10.0
@export var stage1_collision_hysteresis := 0.04
@export var stage2_collision_avoidance := true
@export_flags_3d_physics var stage2_collision_mask := 15
@export var stage2_collision_margin := 0.16
@export var stage2_min_anchor_distance := 0.05
@export var stage2_use_multi_probe := true
@export var stage2_probe_vertical_offset := 0.12
@export var stage2_probe_horizontal_offset := 0.08
@export var stage2_collision_shrink_speed := 80.0
@export var stage2_collision_release_speed := 12.0
@export var stage2_collision_hysteresis := 0.03
@export var stage2_disable_spring_arm_collision_while_aiming := true
@export var stage2_contact_stabilization := true
@export var stage2_contact_angvel_threshold := 1.2
@export var stage2_contact_position_smooth := 14.0
@export var stage2_contact_rotation_smooth := 8.0
@export var stage1_pitch_on_fire := true
@export var stage1_max_pitch_deg := 28.0
@export var stage1_keep_gun_in_zone := true
@export var stage1_zone_center := Vector2(0.5, 0.36)
@export var stage1_zone_size := Vector2(0.18, 0.12)
@export var stage1_zone_yaw_correction_speed := 2.8
@export var stage1_zone_pitch_correction_speed := 3.8
@export var stage1_zone_center_pull := 0.9
@export var stage1_target_smooth_speed := 16.0
@export var stage1_max_reposition_speed := 25.0
@export var stage1_max_snap_distance := 1.25
@export var stage1_velocity_response := 10.0
@export var stage1_velocity_damping := 12.0

var cam: Camera3D
var gun: RigidBody3D
var follow_marker: Marker3D
var cam_aim_marker: Marker3D
var sight_marker: Marker3D
var muzzle_marker: Marker3D

var authored_basis: Basis
var authored_rotation: Vector3
var is_aiming := false
var stage1_world_offset := Vector3.ZERO
var stage1_target_offset := Vector3.ZERO
var stage1_target_yaw := 0.0
var stage1_target_pitch := 0.0
var stage1_has_target_yaw := false
var stage1_smoothed_target_pos := Vector3.ZERO
var stage1_target_initialized := false
var stage1_motion_velocity := Vector3.ZERO
var stage1_smoothed_safe_dist := -1.0
var stage1_collision_constrained := false
var stage1_constrained_time := 0.0
var stage2_smoothed_safe_dist := -1.0
var stage2_smoothed_target_pos := Vector3.ZERO
var stage2_target_pos_initialized := false
var stage2_camera_local_offset := Vector3.ZERO
var _spring_arm_node: SpringArm3D
var _spring_arm_default_collision_mask := 0
var _spring_arm_mask_cached := false
var _was_aiming := false
var _aim_time := 0.0

const STAGE1_MIN_ORBIT_RADIUS := 0.35

func _ready() -> void:
	# Resolve gun/player path (accept either `gun_path` or legacy `player_path`)
	gun = null
	if gun_path != null and gun_path != NodePath():
		gun = get_node_or_null(gun_path) as RigidBody3D
	if gun == null and player_path != null and player_path != NodePath():
		gun = get_node_or_null(player_path) as RigidBody3D
	if gun == null:
		# try common relative path
		gun = get_node_or_null("../PlayerGun") as RigidBody3D

	# Resolve camera path (accept `cam_path` or legacy `camera_path`)
	cam = null
	if cam_path != null and cam_path != NodePath():
		cam = get_node_or_null(cam_path) as Camera3D
	if cam == null and camera_path != null and camera_path != NodePath():
		cam = get_node_or_null(camera_path) as Camera3D
	if cam == null:
		cam = get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if cam != null:
		_spring_arm_node = cam.get_parent() as SpringArm3D
		stage2_camera_local_offset = global_transform.basis.inverse() * (cam.global_transform.origin - global_transform.origin)
		if _spring_arm_node != null:
			_spring_arm_default_collision_mask = int(_spring_arm_node.collision_mask)
			_spring_arm_mask_cached = true
			_spring_arm_node.collision_mask = stage1_collision_mask
			_spring_arm_node.margin = maxf(_spring_arm_node.margin, stage1_collision_margin)

	# follow marker: if not provided, fall back to PlayerGun (or rig origin)
	follow_marker = null
	if follow_marker_path != null and follow_marker_path != NodePath():
		follow_marker = get_node_or_null(follow_marker_path) as Marker3D
	if follow_marker == null and gun != null:
		follow_marker = gun.get_node_or_null("FollowMarker") as Marker3D
	if follow_marker == null:
		# last resort: use this rig's transform as a marker substitute
		follow_marker = Marker3D.new()
		follow_marker.global_transform = global_transform

	cam_aim_marker = null
	if cam_aim_path != null and cam_aim_path != NodePath():
		cam_aim_marker = get_node_or_null(cam_aim_path) as Marker3D
	if cam_aim_marker == null and sight_path != NodePath():
		# if no dedicated aim marker, reuse sight as aim anchor
		cam_aim_marker = get_node_or_null(sight_path) as Marker3D

	sight_marker = null
	if sight_path != null and sight_path != NodePath():
		sight_marker = get_node_or_null(sight_path) as Marker3D
	if sight_marker == null and gun != null:
		sight_marker = gun.get_node_or_null("Sight") as Marker3D

	muzzle_marker = null
	if muzzle_path != null and muzzle_path != NodePath():
		muzzle_marker = get_node_or_null(muzzle_path) as Marker3D
	if muzzle_marker == null and gun != null:
		muzzle_marker = gun.get_node_or_null("Muzzle") as Marker3D

	if _spring_arm_node != null and gun != null:
		_spring_arm_node.add_excluded_object(gun.get_rid())
	

	# lock in authored rotation at start
	authored_basis = global_transform.basis
	authored_rotation = global_rotation
	if gun != null and follow_marker != null:
		stage1_world_offset = follow_marker.global_transform.origin - gun.global_transform.origin
	elif gun != null:
		stage1_world_offset = global_transform.origin - gun.global_transform.origin
	stage1_target_offset = stage1_world_offset
	stage1_target_yaw = authored_rotation.y
	stage1_target_pitch = authored_rotation.x
	_snap_to_stage1_start_target()
	if cam != null:
		cam.fov = normal_fov

	if gun != null and gun.has_signal("fired"):
		var shot_callback := Callable(self, "_on_gun_fired")
		if not gun.is_connected("fired", shot_callback):
			gun.connect("fired", shot_callback)

	# warn if critical nodes are missing
	if gun == null:
		push_warning("recoil_camera_2stage: gun/player node not resolved (gun_path/player_path)")
	if cam == null:
		push_warning("recoil_camera_2stage: Camera3D not resolved (cam_path/camera_path)")
	if sight_marker == null:
		push_warning("recoil_camera_2stage: sight marker not found (sight_path)")
	if muzzle_marker == null:
		push_warning(
			"recoil_camera_2stage: muzzle marker not found (muzzle_path), using sight forward"
		)


func _snap_to_stage1_start_target() -> void:
	var start_target := _get_stage_target_position(false)
	var start_basis := _get_stage1_start_basis()
	global_transform.origin = start_target
	global_transform.basis = start_basis
	_enforce_upright_basis()
	authored_basis = global_transform.basis.orthonormalized()
	authored_rotation = global_rotation
	stage1_target_yaw = authored_rotation.y
	stage1_target_pitch = authored_rotation.x
	stage1_has_target_yaw = false
	stage1_smoothed_target_pos = start_target
	stage1_target_initialized = true
	stage1_motion_velocity = Vector3.ZERO
	stage2_smoothed_target_pos = start_target
	stage2_target_pos_initialized = true


func _get_stage1_start_basis() -> Basis:
	var from := _get_stage_target_position(false)
	var look_target := Vector3.ZERO
	var has_look_target := false
	if sight_marker != null:
		look_target = sight_marker.global_transform.origin
		has_look_target = true
	elif muzzle_marker != null:
		look_target = muzzle_marker.global_transform.origin
		has_look_target = true
	elif gun != null:
		look_target = gun.global_transform.origin
		has_look_target = true

	if has_look_target and from.distance_to(look_target) > 0.001:
		var look_basis := Transform3D(Basis.IDENTITY, from).looking_at(look_target, Vector3.UP).basis
		return _basis_without_roll(look_basis)

	if follow_marker != null:
		return _basis_without_roll(follow_marker.global_transform.basis)
	if gun != null:
		return _basis_without_roll(gun.global_transform.basis)
	return global_transform.basis.orthonormalized()

func _physics_process(delta: float) -> void:
	is_aiming = Input.is_action_pressed("slow_time")
	if is_aiming and not _was_aiming:
		_aim_time = 0.0
	elif is_aiming:
		_aim_time += maxf(delta, 0.0)
	else:
		_aim_time = 0.0
	_was_aiming = is_aiming
	_update_stage2_spring_arm_collision_mode(is_aiming)

	if not is_aiming and stage1_follow_translation_only and gun != null:
		stage2_smoothed_safe_dist = -1.0
		var offset_t := 1.0 - exp(-stage1_orbit_blend_speed * delta)
		# Orbit in cylindrical space so stage-1 reposition arcs around the gun.
		var current_height := stage1_world_offset.y
		var target_height := stage1_target_offset.y

		var current_flat := Vector2(stage1_world_offset.x, stage1_world_offset.z)
		var target_flat := Vector2(stage1_target_offset.x, stage1_target_offset.z)

		var current_radius := maxf(current_flat.length(), STAGE1_MIN_ORBIT_RADIUS)
		var target_radius := maxf(target_flat.length(), STAGE1_MIN_ORBIT_RADIUS)

		var current_angle := atan2(current_flat.x, current_flat.y)
		if current_flat.length_squared() < 0.000001:
			current_angle = atan2(target_flat.x, target_flat.y)

		var target_angle := atan2(target_flat.x, target_flat.y)
		if target_flat.length_squared() < 0.000001:
			target_angle = current_angle

		var orbit_angle := lerp_angle(current_angle, target_angle, offset_t)
		var orbit_radius := lerpf(current_radius, target_radius, offset_t)
		var orbit_height := lerpf(current_height, target_height, offset_t)
		var orbit_flat := Vector2(sin(orbit_angle), cos(orbit_angle)) * orbit_radius

		stage1_world_offset = Vector3(orbit_flat.x, orbit_height, orbit_flat.y)
		_apply_stage1_zone_correction(delta)

	var target_pos := _get_stage_target_position(is_aiming)
	if is_aiming and stage2_contact_stabilization:
		target_pos = _get_stage2_stabilized_target_position(target_pos, delta)
	if not is_aiming:
		stage2_target_pos_initialized = false
		if stage1_use_custom_collision_solver:
			target_pos = _resolve_stage1_collision_target(target_pos, delta)
		else:
			stage1_collision_constrained = false
			stage1_constrained_time = 0.0
			stage1_smoothed_safe_dist = -1.0
		if not (stage1_follow_translation_only and gun != null):
			if not stage1_target_initialized:
				stage1_smoothed_target_pos = target_pos
				stage1_target_initialized = true
			var stage1_target_t := 1.0 - exp(-stage1_target_smooth_speed * delta)
			stage1_smoothed_target_pos = stage1_smoothed_target_pos.lerp(target_pos, stage1_target_t)
			target_pos = stage1_smoothed_target_pos
	
	# Position follow with snap projection.
	# During the first moments of slow-time, allow a tighter snap threshold so ADS enters immediately.
	var active_follow_speed := follow_speed
	var active_aim_rot_speed := rot_speed
	if is_aiming:
		active_follow_speed = aim_follow_speed
		active_aim_rot_speed = rot_speed
		if aim_spin_response_enabled and gun != null:
			var spin_t := clampf(gun.angular_velocity.length() / maxf(aim_high_spin_reference, 0.001), 0.0, 1.0)
			active_follow_speed = lerpf(aim_follow_speed, aim_follow_speed_high_spin, spin_t)
			active_aim_rot_speed = lerpf(rot_speed, aim_rot_speed_high_spin, spin_t)

	var active_snap_distance := snap_distance
	if is_aiming and _aim_time <= aim_entry_snap_window:
		active_snap_distance = minf(active_snap_distance, aim_entry_snap_distance)
	elif is_aiming:
		active_snap_distance = minf(active_snap_distance, aim_sustain_snap_distance)

	if is_aiming and global_transform.origin.distance_to(target_pos) > active_snap_distance:
		global_transform.origin = _resolve_stage2_collision_target(target_pos, delta)
		stage1_motion_velocity = Vector3.ZERO
	else:
		#smoothly move toward target position
		var t := 1.0 - exp(-active_follow_speed * delta)
		var desired_origin := global_transform.origin.lerp(target_pos, t)
		if not is_aiming:
			if stage1_follow_translation_only and gun != null:
				# In stage-1 translation mode, follow the orbit-driven target directly so
				# large retargets move around the gun instead of cutting through it.
				desired_origin = target_pos
				stage1_motion_velocity = Vector3.ZERO
			else:
				var from: Vector3 = global_transform.origin
				var to_target: Vector3 = target_pos - from
				var vel_t := 1.0 - exp(-stage1_velocity_response * delta)
				var target_velocity := to_target * stage1_velocity_response
				stage1_motion_velocity = stage1_motion_velocity.lerp(target_velocity, vel_t)
				var damp_t := 1.0 - exp(-stage1_velocity_damping * delta)
				stage1_motion_velocity = stage1_motion_velocity.lerp(Vector3.ZERO, damp_t)
				if stage1_max_reposition_speed > 0.0:
					stage1_motion_velocity = stage1_motion_velocity.limit_length(stage1_max_reposition_speed)
				desired_origin = from + stage1_motion_velocity * delta
				if to_target.length() < 0.02:
					stage1_motion_velocity = stage1_motion_velocity.lerp(Vector3.ZERO, damp_t)
				if stage1_use_custom_collision_solver:
					desired_origin = _resolve_stage1_collision_target(desired_origin, delta)
		else:
			desired_origin = _resolve_stage2_collision_target(desired_origin, delta)
			if aim_max_follow_error > 0.0:
				var remain := target_pos - desired_origin
				var remain_len := remain.length()
				if remain_len > aim_max_follow_error:
					desired_origin = target_pos - (remain / remain_len) * aim_max_follow_error
			stage1_motion_velocity = Vector3.ZERO
		global_transform.origin = desired_origin
	if is_aiming:
		stage1_collision_constrained = false
		stage1_constrained_time = 0.0
		stage1_smoothed_safe_dist = -1.0

	# rotation behaviour
	if is_aiming:
		# Aim: smoothly rotate to match sight orientation
		_aim_rotation_(delta, active_aim_rot_speed)
	else:
		_restore_authoured_rotation(delta)
	_enforce_upright_basis()

	# FOV blend
	var target_fov := aim_fov if is_aiming else normal_fov
	if cam != null:
		cam.fov = lerp(cam.fov, target_fov, 1.0 - exp(-fov_lerp_speed * delta))

func _get_stage_target_anchor(aiming: bool) -> Node3D:
	if aiming:
		if cam_aim_marker != null:
			return cam_aim_marker
		if muzzle_marker != null:
			return muzzle_marker
		if sight_marker != null:
			return sight_marker
		if gun != null:
			return gun
	else:
		if follow_marker != null:
			return follow_marker
		if gun != null:
			return gun
	return self

func _get_stage_target_position(aiming: bool) -> Vector3:
	if not aiming and stage1_follow_translation_only and gun != null:
		return gun.global_transform.origin + stage1_world_offset
	return _get_stage_target_anchor(aiming).global_transform.origin


func _resolve_stage1_collision_target(target_pos: Vector3, delta: float) -> Vector3:
	if not stage1_collision_avoidance:
		stage1_smoothed_safe_dist = -1.0
		stage1_collision_constrained = false
		stage1_constrained_time = 0.0
		return target_pos

	var anchor_node := _get_stage_target_anchor(false)
	if anchor_node == null:
		stage1_collision_constrained = false
		stage1_constrained_time = 0.0
		return target_pos

	var from := anchor_node.global_transform.origin
	var to := target_pos
	var segment := to - from
	if segment.length_squared() < 0.000001:
		stage1_smoothed_safe_dist = -1.0
		stage1_collision_constrained = false
		stage1_constrained_time = 0.0
		return target_pos

	var dir := segment.normalized()
	var desired_dist := segment.length()
	var safe_dist := desired_dist

	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude_nodes: Array = [self]
	if gun != null:
		exclude_nodes.append(gun)
	if cam != null:
		exclude_nodes.append(cam)

	var probe_offsets: Array[Vector3] = [Vector3.ZERO]
	if stage1_use_multi_probe:
		var probe_basis := anchor_node.global_transform.basis.orthonormalized()
		if stage1_probe_vertical_offset > 0.0:
			probe_offsets.append(probe_basis.y * stage1_probe_vertical_offset)
		if stage1_probe_horizontal_offset > 0.0:
			probe_offsets.append(probe_basis.x * stage1_probe_horizontal_offset)
			probe_offsets.append(-probe_basis.x * stage1_probe_horizontal_offset)

	var center_safe_dist := desired_dist
	query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = stage1_collision_mask
	query.exclude = exclude_nodes
	query.hit_from_inside = true
	var center_hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not center_hit.is_empty():
		if stage1_ignore_top_surfaces:
			var center_normal: Vector3 = center_hit["normal"] as Vector3
			if center_normal.dot(Vector3.UP) <= stage1_top_surface_normal_dot:
				var center_hit_position: Vector3 = center_hit["position"] as Vector3
				center_safe_dist = (center_hit_position - from).dot(dir) - stage1_collision_margin
		else:
			var center_hit_position: Vector3 = center_hit["position"] as Vector3
			center_safe_dist = (center_hit_position - from).dot(dir) - stage1_collision_margin

	var side_safe_dist := desired_dist
	for i in range(1, probe_offsets.size()):
		var offset: Vector3 = probe_offsets[i]
		query = PhysicsRayQueryParameters3D.create(from + offset, to + offset)
		query.collision_mask = stage1_collision_mask
		query.exclude = exclude_nodes
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		if stage1_ignore_top_surfaces:
			var hit_normal: Vector3 = hit["normal"] as Vector3
			if hit_normal.dot(Vector3.UP) > stage1_top_surface_normal_dot:
				continue
		var hit_position: Vector3 = hit["position"] as Vector3
		var hit_dist := (hit_position - (from + offset)).dot(dir) - stage1_collision_margin
		side_safe_dist = minf(side_safe_dist, hit_dist)

	safe_dist = minf(center_safe_dist, side_safe_dist)
	if stage1_doorway_probe_relax and side_safe_dist < center_safe_dist:
		var side_penalty := center_safe_dist - side_safe_dist
		if side_penalty > stage1_doorway_relax_threshold:
			var relax_alpha := 1.0 - exp(-maxf(stage1_doorway_relax_speed, 0.001) * maxf(delta, 0.0))
			safe_dist = lerpf(safe_dist, center_safe_dist, relax_alpha)

	safe_dist = maxf(safe_dist, 0.05)

	if stage1_smoothed_safe_dist < 0.0:
		stage1_smoothed_safe_dist = safe_dist
	else:
		var hysteresis_target := safe_dist
		if absf(hysteresis_target - stage1_smoothed_safe_dist) <= stage1_collision_hysteresis:
			hysteresis_target = stage1_smoothed_safe_dist
		var previous_safe := stage1_smoothed_safe_dist
		var speed := stage1_collision_release_speed
		if hysteresis_target < stage1_smoothed_safe_dist:
			speed = stage1_collision_shrink_speed
		var alpha := 1.0 - exp(-maxf(speed, 0.001) * maxf(delta, 0.0))
		stage1_smoothed_safe_dist = lerpf(stage1_smoothed_safe_dist, hysteresis_target, alpha)
		if stage1_smoothed_safe_dist < previous_safe:
			var max_shrink_step := maxf(stage1_shrink_max_step_speed, 0.001) * maxf(delta, 0.0)
			stage1_smoothed_safe_dist = maxf(stage1_smoothed_safe_dist, previous_safe - max_shrink_step)

	stage1_smoothed_safe_dist = clampf(stage1_smoothed_safe_dist, 0.05, desired_dist)
	var solved := from + dir * stage1_smoothed_safe_dist
	var constrained_now := stage1_smoothed_safe_dist < (desired_dist - 0.01)
	if constrained_now:
		stage1_constrained_time += maxf(delta, 0.0)
		if stage1_constrained_time >= stage1_constrained_recovery_time:
			var bailout_dist := clampf(center_safe_dist, 0.05, desired_dist)
			if bailout_dist > stage1_smoothed_safe_dist + 0.01:
				var max_step := maxf(stage1_recovery_max_step_speed, 0.001) * maxf(delta, 0.0)
				stage1_smoothed_safe_dist = minf(bailout_dist, stage1_smoothed_safe_dist + max_step)
				solved = from + dir * stage1_smoothed_safe_dist
		var recovered := _recover_stage1_same_side_position(from, solved, probe_offsets, exclude_nodes)
		if recovered.distance_to(solved) > 0.0001:
			var recovered_dist := clampf((recovered - from).length(), 0.05, desired_dist)
			if recovered_dist > stage1_smoothed_safe_dist:
				var recover_step := maxf(stage1_recovery_max_step_speed, 0.001) * maxf(delta, 0.0)
				stage1_smoothed_safe_dist = minf(recovered_dist, stage1_smoothed_safe_dist + recover_step)
			else:
				stage1_smoothed_safe_dist = recovered_dist
			solved = from + dir * stage1_smoothed_safe_dist
	else:
		stage1_constrained_time = 0.0

	stage1_collision_constrained = stage1_smoothed_safe_dist < (desired_dist - 0.01)
	return solved


func _recover_stage1_same_side_position(
	anchor_pos: Vector3,
	candidate_pos: Vector3,
	probe_offsets: Array[Vector3],
	exclude_nodes: Array
) -> Vector3:
	var candidate_dist := anchor_pos.distance_to(candidate_pos)
	if candidate_dist <= 0.05:
		return candidate_pos

	var dir := (candidate_pos - anchor_pos).normalized()
	var corrected_dist := candidate_dist
	var invalid := false

	for offset in probe_offsets:
		var query := PhysicsRayQueryParameters3D.create(anchor_pos + offset, candidate_pos + offset)
		query.collision_mask = stage1_collision_mask
		query.exclude = exclude_nodes
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		invalid = true
		var hit_position: Vector3 = hit["position"] as Vector3
		var hit_dist := (hit_position - (anchor_pos + offset)).dot(dir) - stage1_collision_margin
		corrected_dist = minf(corrected_dist, hit_dist)

	if not invalid:
		return candidate_pos

	corrected_dist = clampf(corrected_dist, 0.05, candidate_dist)
	return anchor_pos + dir * corrected_dist


func _resolve_stage2_collision_target(target_rig_pos: Vector3, delta: float) -> Vector3:
	if not stage2_collision_avoidance:
		stage2_smoothed_safe_dist = -1.0
		return target_rig_pos
	if cam == null:
		stage2_smoothed_safe_dist = -1.0
		return target_rig_pos

	var anchor_node := _get_stage_target_anchor(true)
	if anchor_node == null:
		return target_rig_pos

	# Use the authored camera offset relative to rig to avoid feedback jitter from dynamic spring-arm compression.
	var cam_world_offset := global_transform.basis * stage2_camera_local_offset
	var desired_cam_pos := target_rig_pos + cam_world_offset
	var anchor_pos := anchor_node.global_transform.origin
	var segment := desired_cam_pos - anchor_pos
	if segment.length_squared() < 0.000001:
		return target_rig_pos
	var dir := segment.normalized()
	var desired_dist := segment.length()
	var safe_dist := desired_dist

	var probe_offsets: Array[Vector3] = [Vector3.ZERO]
	if stage2_use_multi_probe:
		var probe_basis := anchor_node.global_transform.basis.orthonormalized()
		if stage2_probe_vertical_offset > 0.0:
			probe_offsets.append(probe_basis.y * stage2_probe_vertical_offset)
		if stage2_probe_horizontal_offset > 0.0:
			probe_offsets.append(probe_basis.x * stage2_probe_horizontal_offset)
			probe_offsets.append(-probe_basis.x * stage2_probe_horizontal_offset)

	var exclude_nodes: Array = [self]
	if gun != null:
		exclude_nodes.append(gun)
	if cam != null:
		exclude_nodes.append(cam)
	var spring_arm := cam.get_parent()
	if spring_arm != null:
		exclude_nodes.append(spring_arm)

	for offset in probe_offsets:
		var query := PhysicsRayQueryParameters3D.create(anchor_pos + offset, desired_cam_pos + offset)
		query.collision_mask = stage2_collision_mask
		query.exclude = exclude_nodes
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit["position"] as Vector3
		var hit_dist := (hit_position - (anchor_pos + offset)).dot(dir)
		safe_dist = minf(safe_dist, hit_dist - stage2_collision_margin)

	if safe_dist >= desired_dist:
		stage2_smoothed_safe_dist = desired_dist
		return target_rig_pos

	safe_dist = maxf(safe_dist, stage2_min_anchor_distance)

	if stage2_smoothed_safe_dist < 0.0:
		stage2_smoothed_safe_dist = safe_dist
	else:
		var hysteresis_target := safe_dist
		if absf(hysteresis_target - stage2_smoothed_safe_dist) <= stage2_collision_hysteresis:
			hysteresis_target = stage2_smoothed_safe_dist
		var speed := stage2_collision_release_speed
		if hysteresis_target < stage2_smoothed_safe_dist:
			speed = stage2_collision_shrink_speed
		var alpha := 1.0 - exp(-maxf(speed, 0.001) * maxf(delta, 0.0))
		stage2_smoothed_safe_dist = lerpf(stage2_smoothed_safe_dist, hysteresis_target, alpha)
		stage2_smoothed_safe_dist = clampf(stage2_smoothed_safe_dist, stage2_min_anchor_distance, desired_dist)

	var safe_cam_pos := anchor_pos + dir * stage2_smoothed_safe_dist

	return safe_cam_pos - cam_world_offset


func _update_stage2_spring_arm_collision_mode(aiming: bool) -> void:
	if _spring_arm_node == null:
		return
	if not _spring_arm_mask_cached:
		_spring_arm_default_collision_mask = int(_spring_arm_node.collision_mask)
		_spring_arm_mask_cached = true

	if aiming and stage2_collision_avoidance and stage2_disable_spring_arm_collision_while_aiming:
		_spring_arm_node.collision_mask = 0
	else:
		_spring_arm_node.collision_mask = _spring_arm_default_collision_mask


func _get_stage2_stabilized_target_position(raw_target_pos: Vector3, delta: float) -> Vector3:
	if not stage2_target_pos_initialized:
		stage2_smoothed_target_pos = raw_target_pos
		stage2_target_pos_initialized = true
		return raw_target_pos

	if not _is_stage2_spin_contact_active():
		stage2_smoothed_target_pos = raw_target_pos
		return raw_target_pos

	var alpha := 1.0 - exp(-maxf(stage2_contact_position_smooth, 0.001) * maxf(delta, 0.0))
	stage2_smoothed_target_pos = stage2_smoothed_target_pos.lerp(raw_target_pos, alpha)
	return stage2_smoothed_target_pos


func _is_stage2_spin_contact_active() -> bool:
	if gun == null:
		return false
	if gun.get_contact_count() <= 0:
		return false
	return gun.angular_velocity.length() >= stage2_contact_angvel_threshold


func _on_gun_fired(muzzle_origin: Vector3, fire_direction: Vector3) -> void:
	if not stage1_orbit_on_fire:
		return
	if gun == null:
		return
	if fire_direction.length_squared() < 0.000001:
		return

	var hit_target := _get_stage1_fire_target(muzzle_origin, fire_direction.normalized())
	var look_dir := (hit_target - gun.global_transform.origin).normalized()
	if look_dir.length_squared() < 0.000001:
		return

	var current_offset := stage1_target_offset
	if current_offset.length_squared() < 0.000001:
		current_offset = stage1_world_offset
	if current_offset.length_squared() < 0.000001:
		current_offset = Vector3(0.0, 1.2, 2.8)

	var current_height := current_offset.dot(Vector3.UP)
	var horizontal_offset := current_offset - Vector3.UP * current_height
	var horizontal_radius := horizontal_offset.length()
	if horizontal_radius < 0.05:
		horizontal_radius = 2.6

	var desired_flat := -Vector3(look_dir.x, 0.0, look_dir.z)
	if desired_flat.length_squared() < 0.000001:
		desired_flat = horizontal_offset.normalized() if horizontal_offset.length_squared() > 0.000001 else Vector3.BACK
	desired_flat = desired_flat.normalized()
	stage1_target_yaw = atan2(-look_dir.x, -look_dir.z)
	if stage1_pitch_on_fire:
		stage1_target_pitch = -asin(clamp(look_dir.y, -1.0, 1.0))
		var max_pitch := deg_to_rad(stage1_max_pitch_deg)
		stage1_target_pitch = clamp(stage1_target_pitch, -max_pitch, max_pitch)
	stage1_has_target_yaw = true

	stage1_target_offset = desired_flat * horizontal_radius + Vector3.UP * current_height


func _get_stage1_fire_target(muzzle_origin: Vector3, fire_direction: Vector3) -> Vector3:
	var from := muzzle_origin
	var to := muzzle_origin + fire_direction * stage1_fire_target_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = stage1_fire_target_mask
	if gun != null:
		query.exclude = [gun]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]

func _restore_authoured_rotation(delta: float) -> void:
	var rt := 1.0 - exp(-maxf(rot_speed, 0.001) * maxf(delta, 0.0))
	var current_basis := global_transform.basis.orthonormalized()
	var target_basis := authored_basis.orthonormalized()
	if stage1_orbit_on_fire and stage1_has_target_yaw:
		var pitch := stage1_target_pitch if stage1_pitch_on_fire else 0.0
		var forward := Vector3(
			-sin(stage1_target_yaw) * cos(pitch),
			-sin(pitch),
			-cos(stage1_target_yaw) * cos(pitch)
		).normalized()
		target_basis = _basis_from_forward_no_roll(forward)

	var current_q := current_basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var blended_q := current_q.slerp(target_q, rt)
	global_transform = Transform3D(Basis(blended_q), global_transform.origin)


func _basis_from_forward_no_roll(forward: Vector3) -> Basis:
	var dir := forward
	if dir.length_squared() < 0.000001:
		dir = Vector3.FORWARD
	var synthetic := Basis.IDENTITY.looking_at(dir.normalized(), Vector3.UP)
	return _basis_without_roll(synthetic)


func _enforce_upright_basis() -> void:
	var b := global_transform.basis.orthonormalized()
	var up_dot := b.y.dot(Vector3.UP)
	if up_dot >= 0.85:
		return
	var corrected := _basis_without_roll(b)
	global_transform = Transform3D(corrected, global_transform.origin)

func _apply_stage1_zone_correction(delta: float) -> void:
	if not stage1_keep_gun_in_zone:
		return
	if stage1_collision_constrained:
		return
	if not stage1_orbit_on_fire:
		return
	if not stage1_has_target_yaw:
		return
	if cam == null or gun == null:
		return
	if cam.is_position_behind(gun.global_transform.origin):
		return

	var viewport_rect := cam.get_viewport().get_visible_rect()
	var viewport_size := viewport_rect.size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return

	var zone_size := Vector2(clamp(stage1_zone_size.x, 0.05, 1.0), clamp(stage1_zone_size.y, 0.05, 1.0))
	var zone_center := Vector2(clamp(stage1_zone_center.x, 0.0, 1.0), clamp(stage1_zone_center.y, 0.0, 1.0))
	var half_zone := zone_size * 0.5
	var zone_min := zone_center - half_zone
	var zone_max := zone_center + half_zone

	var gun_screen := cam.unproject_position(gun.global_transform.origin)
	var screen_norm := Vector2(gun_screen.x / viewport_size.x, gun_screen.y / viewport_size.y)

	var error_x := 0.0
	if screen_norm.x < zone_min.x:
		error_x = screen_norm.x - zone_min.x
	elif screen_norm.x > zone_max.x:
		error_x = screen_norm.x - zone_max.x
	else:
		error_x = (screen_norm.x - zone_center.x) * stage1_zone_center_pull

	var error_y := 0.0
	if screen_norm.y < zone_min.y:
		error_y = screen_norm.y - zone_min.y
	elif screen_norm.y > zone_max.y:
		error_y = screen_norm.y - zone_max.y
	else:
		error_y = (screen_norm.y - zone_center.y) * stage1_zone_center_pull

	if abs(error_x) > 0.0001:
		stage1_target_yaw += -error_x * stage1_zone_yaw_correction_speed * delta

	if stage1_pitch_on_fire and abs(error_y) > 0.0001:
		stage1_target_pitch += -error_y * stage1_zone_pitch_correction_speed * delta
		var max_pitch := deg_to_rad(stage1_max_pitch_deg)
		stage1_target_pitch = clamp(stage1_target_pitch, -max_pitch, max_pitch)

   
func _aim_rotation_(delta: float, rot_speed_override: float = -1.0) -> void:
	# always face gun-forward while orbiting to stage 2 anchor position
	var desired_basis: Basis

	if cam_aim_marker != null:
		desired_basis = cam_aim_marker.global_transform.basis
	elif muzzle_marker != null:
		desired_basis = muzzle_marker.global_transform.basis
	elif gun != null:
		desired_basis = gun.global_transform.basis
	elif sight_marker != null:
		desired_basis = sight_marker.global_transform.basis
	else:
		return

	if remove_roll_in_aim:
		# remove roll while preserving aim forward direction
		desired_basis = _basis_without_roll(desired_basis)

	var active_rot_speed := rot_speed_override if rot_speed_override > 0.0 else rot_speed
	if stage2_contact_stabilization and _is_stage2_spin_contact_active():
		active_rot_speed = maxf(active_rot_speed, stage2_contact_rotation_smooth)
	var rt := 1.0 - exp(-maxf(active_rot_speed, 0.001) * maxf(delta, 0.0))
	var current_basis := global_transform.basis.orthonormalized()
	var target_basis := desired_basis.orthonormalized()
	var current_q := current_basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var blended_q := current_q.slerp(target_q, rt)
	if aim_max_rotation_error_deg > 0.0:
		var max_error_rad := deg_to_rad(aim_max_rotation_error_deg)
		var remaining_error := blended_q.angle_to(target_q)
		if remaining_error > max_error_rad:
			var correction_t := 1.0 - (max_error_rad / remaining_error)
			blended_q = blended_q.slerp(target_q, correction_t)
	global_transform = Transform3D(Basis(blended_q), global_transform.origin)

func _basis_without_roll(b: Basis) -> Basis:
	# Rebuild from forward using a world-up reference to strip roll deterministically.
	var forward := (-b.z).normalized()
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	if abs(forward.dot(Vector3.UP)) > 0.999:
		forward = (forward + Vector3(0.001, 0.0, 0.0)).normalized()
	var look_basis := Basis.IDENTITY.looking_at(forward, Vector3.UP)
	if look_basis.y.dot(Vector3.UP) < 0.0:
		look_basis.x = -look_basis.x
		look_basis.y = -look_basis.y
	return look_basis.orthonormalized()
