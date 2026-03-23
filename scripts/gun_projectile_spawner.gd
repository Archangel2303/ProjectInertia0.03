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

	var owner_body := owner as CollisionObject3D
	# Apply collision exceptions before placing the bullet so it won't immediately collide on the first physics step.
	if shooter:
		bullet.add_collision_exception_with(shooter)
	if owner_body != null and owner_body != shooter:
		bullet.add_collision_exception_with(owner_body)
	bullet.shooter = shooter if shooter != null else owner_body

	var dir := _get_muzzle_forward(muzzle, muzzle_forward_axis).normalized()
	var up := muzzle.global_transform.basis.y.normalized()
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.UP
	# Small forward offset to avoid spawning inside geometry.
	var spawn_offset := dir * 0.12
	var spawn_xform := muzzle.global_transform
	spawn_xform.origin = muzzle.global_transform.origin + spawn_offset

	# Debug: log spawn parameters to help diagnose immediate-despawn issues
	print("spawn_and_fire: muzzle_origin=", muzzle.global_transform.origin, " dir=", dir, " spawn_origin=", spawn_xform.origin)

	bullet.global_transform = spawn_xform
	bullet.look_at(bullet.global_transform.origin + dir, up)
	bullet.fire(dir)
	print("spawn_and_fire: fired bullet with dir.length=", dir.length())

	if dir.length_squared() > 0.000001 and gamemanager != null and gamemanager.has_method("play_gunshot_at"):
		var sound_origin := muzzle.global_transform.origin
		var owner_3d := owner as Node3D
		if owner_3d != null:
			sound_origin = owner_3d.global_transform.origin
		gamemanager.play_gunshot_at(sound_origin)

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
