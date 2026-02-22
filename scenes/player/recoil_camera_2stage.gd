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
@export var rot_speed := 16.0 #how quickly the camera rotates to match the sight when aiming
@export var snap_distance := 3.0  # snap if gun moves too far in 1 tick

@export var normal_fov := 65.0
@export var aim_fov := 45.0
@export var fov_lerp_speed := 10.0

@export var remove_roll_in_aim := true

var cam: Camera3D
var gun: RigidBody3D
var follow_marker: Marker3D
var cam_aim_marker: Marker3D
var sight_marker: Marker3D
var muzzle_marker: Marker3D

var authored_basis: Basis
var authored_rotation: Vector3
var is_aiming := false

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
	if cam != null:
		cam.fov = normal_fov

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

	var target_anchor: Node3D = _get_stage_target_anchor(is_aiming)
	var target_pos := target_anchor.global_transform.origin
	
	#Position follow with snap projection
	if global_transform.origin.distance_to(target_pos) > snap_distance:
		#snap if gun moves too far in 1 tick (prevents extreme warping)
		global_transform.origin = target_pos
	else:
		#smoothly move toward target position
		var t := 1.0 - exp(-follow_speed * delta)
		global_transform.origin = global_transform.origin.lerp(target_pos, t)

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

func _restore_authoured_rotation(delta: float) -> void:
		var rt := 1.0 - exp(-rot_speed * delta)
		var current_rot := global_rotation
		global_rotation = Vector3(
			lerp_angle(current_rot.x, authored_rotation.x, rt),
			lerp_angle(current_rot.y, authored_rotation.y, rt),
			lerp_angle(current_rot.z, authored_rotation.z, rt)
		)

   
func _aim_rotation_(delta: float) -> void:
	# always face gun-forward while orbiting to stage 2 anchor position
	var desired_basis: Basis

	if muzzle_marker != null:
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

	var rt := 1.0 - exp(-rot_speed * delta)
	var forward := (-desired_basis.z).normalized()
	if forward.length_squared() < 0.000001:
		return

	var up_axis := Vector3.UP
	if abs(forward.dot(up_axis)) > 0.999:
		up_axis = Vector3.FORWARD

	var desired_transform := global_transform.looking_at(
		global_transform.origin + forward,
		up_axis
	)
	var desired_rot := desired_transform.basis.get_euler()
	var current_rot := global_rotation
	global_rotation = Vector3(
		lerp_angle(current_rot.x, desired_rot.x, rt),
		lerp_angle(current_rot.y, desired_rot.y, rt),
		0.0 if remove_roll_in_aim else lerp_angle(current_rot.z, desired_rot.z, rt)
	)

func _basis_without_roll(b: Basis) -> Basis:
	#Build a basis from forward + world up to eliminate roll
	var forward := (-b.z).normalized()
	var up_axis := Vector3.UP
	if abs(forward.dot(up_axis)) > 0.999:
		up_axis = Vector3.FORWARD
	var right := up_axis.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	return Basis(right, up, -forward).orthonormalized()
