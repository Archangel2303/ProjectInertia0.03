extends CanvasLayer

@onready var label: Label = $Readout

func _process(_dt: float) -> void:
	var b: RigidBody3D = null

	# Prefer GameManager's reference if available (recommended pattern).
	if Engine.has_singleton("GameManager"):
		var gm := Engine.get_singleton("GameManager")
		if gm and gm.player_gun != null:
			b = gm.player_gun

	# Fallback: search the current scene (safer than searching the Window root)
	if b == null:
		var root_scene := get_tree().get_current_scene()
		if root_scene == null and get_tree().get_root().get_child_count() > 0:
			root_scene = get_tree().get_root().get_child(0)
		if root_scene != null:
			var candidate: Node = _find_node_recursive(root_scene, "PlayerGun")
			if candidate != null:
				b = candidate as RigidBody3D

	if b == null:
		label.text = "No gun found"
		return

	label.text = "ang_vel: %s\nlin_vel: %s\nrot(deg): %s" % [
		str(b.angular_velocity),
		str(b.linear_velocity),
		str(b.rotation_degrees)
	]

func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found: Node = _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null