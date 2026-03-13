extends RefCounted


func spawn_and_fire(
	owner: Node,
	bullet_scene: PackedScene,
	muzzle: Marker3D,
	muzzle_forward_axis: String,
	shooter: CollisionObject3D
) -> Vector3:
	if bullet_scene == null or muzzle == null:
		return Vector3.ZERO

	var bullet = bullet_scene.instantiate()
	var root := owner.get_tree().get_current_scene()
	if root:
		root.add_child(bullet)
	else:
		owner.get_tree().get_root().add_child(bullet)

	bullet.global_transform = muzzle.global_transform
	var owner_body := owner as CollisionObject3D
	if shooter:
		bullet.add_collision_exception_with(shooter)
	if owner_body != null and owner_body != shooter:
		bullet.add_collision_exception_with(owner_body)
	bullet.shooter = shooter if shooter != null else owner_body

	var dir := _get_muzzle_forward(muzzle, muzzle_forward_axis).normalized()
	var up := muzzle.global_transform.basis.y.normalized()
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.UP
	bullet.look_at(bullet.global_transform.origin + dir, up)
	bullet.fire(dir)
	return dir


func _get_muzzle_forward(muzzle: Marker3D, muzzle_forward_axis: String) -> Vector3:
	var muzzle_basis := muzzle.global_transform.basis
	match muzzle_forward_axis:
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
