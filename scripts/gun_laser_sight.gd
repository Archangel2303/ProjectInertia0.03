extends RefCounted

var _mesh_instance: MeshInstance3D = null
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func setup(parent: Node3D, color: Color) -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 2.2
	_material.no_depth_test = true

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "LaserSight"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.mesh = _mesh
	parent.add_child(_mesh_instance)


func update(
	gun: RigidBody3D,
	muzzle: Marker3D,
	muzzle_forward_axis: String,
	enabled: bool,
	max_distance: float,
	collision_mask: int
) -> void:
	if _mesh_instance == null:
		return
	if not enabled or muzzle == null:
		_mesh_instance.visible = false
		return

	var origin := muzzle.global_transform.origin
	var dir := get_muzzle_forward(muzzle.global_transform.basis, muzzle_forward_axis).normalized()
	if dir.length_squared() < 0.000001:
		_mesh_instance.visible = false
		return

	var cast_distance := maxf(0.5, max_distance)
	var target := origin + dir * cast_distance

	var query := PhysicsRayQueryParameters3D.create(origin, target, collision_mask, [gun.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var space_state := gun.get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.get("position", target)

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_mesh.surface_add_vertex(gun.to_local(origin))
	_mesh.surface_add_vertex(gun.to_local(target))
	_mesh.surface_end()
	_mesh_instance.visible = true


func get_muzzle_forward(muzzle_basis: Basis, axis_mode: String) -> Vector3:
	match axis_mode:
		"+X":
			return muzzle_basis.x
		"-X":
			return -muzzle_basis.x
		"+Y":
			return muzzle_basis.y
		"-Y":
			return -muzzle_basis.y
		"+Z":
			return muzzle_basis.z
		_:
			return -muzzle_basis.z
