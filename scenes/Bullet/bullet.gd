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


func _ready() -> void:
	bullet_hitbox.monitoring = true
	bullet_hitbox.collision_mask = enemy_hitbox_mask
	# Enemy hit detection via Area overlap
	bullet_hitbox.area_entered.connect(_on_bullet_hitbox_area_entered)

	# World collision via rigidbody contacts
	contact_monitor = true
	max_contacts_reported = 8
	
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


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
	if enemy_root.has_method("apply_damage"):
		enemy_root.apply_damage(damage, hit_type)

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