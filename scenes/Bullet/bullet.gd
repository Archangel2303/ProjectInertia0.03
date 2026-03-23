extends RigidBody3D

@export var speed: float = 140.0
@export var damage: int = 1
@export var lifetime: float = 3.0
@export var max_penetrations: int = 0 # 0 = stop on first enemy hitbox
@export var despawn_on_enemy_hit: bool = true
@export_flags_3d_physics var enemy_hitbox_mask: int = 8

var _penetrations_used: int = 0
var _already_hit: Dictionary = {} # area instance_id -> true

# shooter reference set by the spawner so we can ignore accidental collisions
var shooter: CollisionObject3D = null

@onready var bullet_hitbox: Area3D = $BulletHitbox
@onready var bullet_mesh: MeshInstance3D = get_node_or_null("Bullet_bullet_0") as MeshInstance3D

var _bullet_skin_material: StandardMaterial3D = null
var _trail_mesh_instance: MeshInstance3D = null
var _trail_mesh: ImmediateMesh = ImmediateMesh.new()
var _trail_material: StandardMaterial3D = null
var _trail_points: Array[Vector3] = []
var _trail_max_points: int = 10
var _trail_min_segment_distance: float = 0.08


func _ready() -> void:
	_apply_selected_bullet_skin()
	_setup_bullet_trail()
	bullet_hitbox.monitoring = true
	bullet_hitbox.collision_mask = enemy_hitbox_mask
	# Enemy hit detection via Area overlap
	bullet_hitbox.area_entered.connect(_on_bullet_hitbox_area_entered)

	# World collision via rigidbody contacts
	contact_monitor = true
	max_contacts_reported = 8
	
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(_delta: float) -> void:
	_update_bullet_trail()


func fire(direction: Vector3) -> void:
	var dir := direction.normalized()
	if dir == Vector3.ZERO:
		return
	linear_velocity = dir * speed
	look_at(global_transform.origin + dir, global_transform.basis.y)


func _find_damage_target(start_node: Node) -> Node:
	var current: Node = start_node
	while current != null:
		if current.has_method("apply_damage"):
			return current
		current = current.get_parent()
	return null


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Stop when hitting world geometry (put world bodies in group "world")
	for i in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		# ignore collisions that originate from the shooter or its children
		if _is_collider_from_shooter(collider):
			continue
		if collider.is_in_group("world"):
			print("bullet: immediate world contact at ", global_transform.origin, " collider=", collider)
			if gamemanager != null and gamemanager.has_method("play_bullet_wall_impact_at"):
				var impact_point := state.get_contact_collider_position(i)
				gamemanager.play_bullet_wall_impact_at(impact_point)
			queue_free()
			return


func _is_collider_from_shooter(collider: Object) -> bool:
	if shooter == null:
		return false
	var node := collider as Node
	if node == null:
		return false
	while node != null:
		if node == shooter:
			return true
		node = node.get_parent()
	return false


func _on_bullet_hitbox_area_entered(hit_area: Area3D) -> void:
	# Prevent multi-hit spam on the same hitbox area
	var id := hit_area.get_instance_id()
	if _already_hit.has(id):
		return
	_already_hit[id] = true

	# We expect hit_area is one of the enemy hitboxes (HeadHitbox, etc.)
	var enemy_root := _find_damage_target(hit_area)
	if enemy_root == null:
		return

	var hit_type := "torso"
	if hit_area.has_method("get_hit_type"):
		hit_type = hit_area.get_hit_type()

	# Damage (enemy_root should implement apply_damage(damage, hit_type))
	var was_killed := false
	if enemy_root.has_method("apply_damage"):
		var result: Variant = enemy_root.apply_damage(damage, hit_type)
		if result is bool:
			was_killed = bool(result)

	if was_killed and gamemanager != null:
		if gamemanager.has_method("register_kill"):
			gamemanager.register_kill(hit_type)
		if gamemanager.has_method("play_enemy_death_at"):
			gamemanager.play_enemy_death_at(hit_area.global_transform.origin)

	if despawn_on_enemy_hit:
		queue_free()
		return

	# Penetration handling
	if _penetrations_used >= max_penetrations:
		queue_free()
		return

	_penetrations_used += 1

	# Optional: prevent repeated physical collisions with enemy root if it has collision
	if enemy_root is CollisionObject3D:
		add_collision_exception_with(enemy_root)


func _apply_selected_bullet_skin() -> void:
	if bullet_mesh == null:
		return
	if gamemanager == null or not gamemanager.has_method("get_selected_bullet_skin_path"):
		return

	var texture_path: String = String(gamemanager.get_selected_bullet_skin_path())
	if texture_path.is_empty():
		return

	var skin_texture := load(texture_path) as Texture2D
	if skin_texture == null:
		return

	if _bullet_skin_material == null:
		var base_material := bullet_mesh.get_active_material(0)
		if base_material is StandardMaterial3D:
			_bullet_skin_material = (base_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_bullet_skin_material = StandardMaterial3D.new()

	_bullet_skin_material.albedo_texture = skin_texture
	bullet_mesh.set_surface_override_material(0, _bullet_skin_material)


func _setup_bullet_trail() -> void:
	if gamemanager == null or not gamemanager.has_method("get_selected_bullet_trail_style"):
		return

	var trail_style := String(gamemanager.get_selected_bullet_trail_style())
	if trail_style == "Default Trail":
		return

	_trail_mesh_instance = MeshInstance3D.new()
	_trail_mesh_instance.name = "BulletTrail"
	_trail_mesh_instance.top_level = true
	_trail_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mesh_instance.mesh = _trail_mesh
	add_child(_trail_mesh_instance)

	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_material.no_depth_test = true
	_trail_material.emission_enabled = true

	var trail_color := Color(1.0, 0.9, 0.25, 0.95)

	match trail_style:
		"Tracer":
			_trail_max_points = 8
			_trail_min_segment_distance = 0.12
			trail_color = Color(1.0, 0.85, 0.15, 0.95)
		"Neon":
			_trail_max_points = 12
			_trail_min_segment_distance = 0.08
			trail_color = Color(0.15, 1.0, 0.65, 1.0)
		"Smoke":
			_trail_max_points = 14
			_trail_min_segment_distance = 0.05
			trail_color = Color(0.4, 0.4, 0.4, 0.72)
		_:
			_trail_mesh_instance.queue_free()
			_trail_mesh_instance = null
			return

	_trail_material.albedo_color = trail_color
	_trail_material.emission = trail_color
	_trail_material.emission_energy_multiplier = 1.8


func _update_bullet_trail() -> void:
	if _trail_mesh_instance == null or _trail_material == null:
		return

	var pos := global_transform.origin
	if _trail_points.is_empty():
		_trail_points.append(pos)
	else:
		var last := _trail_points[_trail_points.size() - 1]
		if last.distance_to(pos) < _trail_min_segment_distance:
			return
		_trail_points.append(pos)

	while _trail_points.size() > _trail_max_points:
		_trail_points.remove_at(0)

	if _trail_points.size() < 2:
		return

	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _trail_material)
	for i in range(1, _trail_points.size()):
		var p0 := _trail_points[i - 1]
		var p1 := _trail_points[i]
		_trail_mesh.surface_add_vertex(p0)
		_trail_mesh.surface_add_vertex(p1)
	_trail_mesh.surface_end()