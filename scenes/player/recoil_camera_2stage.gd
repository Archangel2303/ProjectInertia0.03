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
@export_flags_3d_physics var stage1_collision_mask := 15
@export var stage1_collision_margin := 0.2
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
var stage2_smoothed_safe_dist := -1.0
var stage2_smoothed_target_pos := Vector3.ZERO
var stage2_target_pos_initialized := false
var stage2_camera_local_offset := Vector3.ZERO
var _spring_arm_node: SpringArm3D
var _spring_arm_default_collision_mask := 0
var _spring_arm_mask_cached := false

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
	stage1_smoothed_target_pos = global_transform.origin
	stage1_target_initialized = true
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

func _physics_process(delta: float) -> void:
	is_aiming = Input.is_action_pressed("slow_time")
	# Editor-side SpringArm tuning mode:
	# disable runtime stage-2 spring-arm collision overrides so editor settings drive behavior.
	# _update_stage2_spring_arm_collision_mode(is_aiming)

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
	# Editor-side SpringArm tuning mode:
	# disable runtime stage-2 stabilization to avoid fighting editor collision behavior.
	# if is_aiming and stage2_contact_stabilization:
	# 	target_pos = _get_stage2_stabilized_target_position(target_pos, delta)
	if not is_aiming:
		# stage2_target_pos_initialized = false
		target_pos = _resolve_stage1_collision_target(target_pos)
		if not (stage1_follow_translation_only and gun != null):
			if not stage1_target_initialized:
				stage1_smoothed_target_pos = target_pos
				stage1_target_initialized = true
			var stage1_target_t := 1.0 - exp(-stage1_target_smooth_speed * delta)
			stage1_smoothed_target_pos = stage1_smoothed_target_pos.lerp(target_pos, stage1_target_t)
			target_pos = stage1_smoothed_target_pos
	
	#Position follow with snap projection
	if is_aiming and global_transform.origin.distance_to(target_pos) > snap_distance:
		# Editor-side SpringArm tuning mode:
		# bypass runtime stage-2 collision solver and use direct aim target.
		global_transform.origin = target_pos
		stage1_motion_velocity = Vector3.ZERO
	else:
		#smoothly move toward target position
		var active_follow_speed := aim_follow_speed if is_aiming else follow_speed
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
				desired_origin = _resolve_stage1_collision_target(desired_origin)
		else:
			# Editor-side SpringArm tuning mode:
			# bypass runtime stage-2 collision solver so SpringArm handles contact response.
			desired_origin = desired_origin
			stage1_motion_velocity = Vector3.ZERO
		global_transform.origin = desired_origin

	# rotation behaviour
	if is_aiming:
		# Aim: smoothly rotate to match sight orientation
		_aim_rotation_(delta)
	else:
		_restore_authoured_rotation(delta)

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


func _resolve_stage1_collision_target(target_pos: Vector3) -> Vector3:
	if not stage1_collision_avoidance:
		return target_pos

	var anchor_node := _get_stage_target_anchor(false)
	if anchor_node == null:
		return target_pos

	var from := anchor_node.global_transform.origin
	var to := target_pos
	var segment := to - from
	if segment.length_squared() < 0.000001:
		return target_pos

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = stage1_collision_mask
	var exclude_nodes: Array = [self]
	if gun != null:
		exclude_nodes.append(gun)
	if cam != null:
		exclude_nodes.append(cam)
	query.exclude = exclude_nodes

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target_pos

	var dir := segment.normalized()
	var hit_position: Vector3 = hit["position"] as Vector3
	var safe: Vector3 = hit_position - dir * stage1_collision_margin
	var projected := (safe - from).dot(dir)
	if projected < 0.05:
		safe = from + dir * 0.05
	return safe


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
		var rt := 1.0 - exp(-rot_speed * delta)
		var current_rot := global_rotation
		var target_rot := authored_rotation
		if stage1_orbit_on_fire and stage1_has_target_yaw:
			target_rot.y = stage1_target_yaw
			if stage1_pitch_on_fire:
				target_rot.x = stage1_target_pitch
		global_rotation = Vector3(
			lerp_angle(current_rot.x, target_rot.x, rt),
			lerp_angle(current_rot.y, target_rot.y, rt),
			lerp_angle(current_rot.z, target_rot.z, rt)
		)

func _apply_stage1_zone_correction(delta: float) -> void:
	if not stage1_keep_gun_in_zone:
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

   
func _aim_rotation_(delta: float) -> void:
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

	var active_rot_speed := rot_speed
	if stage2_contact_stabilization and _is_stage2_spin_contact_active():
		active_rot_speed = minf(rot_speed, stage2_contact_rotation_smooth)
	var rt := 1.0 - exp(-maxf(active_rot_speed, 0.001) * maxf(delta, 0.0))
	var current_basis := global_transform.basis.orthonormalized()
	var target_basis := desired_basis.orthonormalized()
	var current_q := current_basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var blended_q := current_q.slerp(target_q, rt)
	global_transform = Transform3D(Basis(blended_q), global_transform.origin)

func _basis_without_roll(b: Basis) -> Basis:
	#Build a basis from forward + world up to eliminate roll
	var forward := (-b.z).normalized()
	var up_axis := Vector3.UP
	if abs(forward.dot(up_axis)) > 0.999:
		up_axis = Vector3.FORWARD
	var right := up_axis.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	return Basis(right, up, -forward).orthonormalized()
