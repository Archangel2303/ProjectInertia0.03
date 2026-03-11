extends RefCounted

var enabled := true
var target_gravity_scale := 0.0
var armed := false


func configure(is_enabled: bool, gravity_scale_target: float) -> void:
	enabled = is_enabled
	target_gravity_scale = gravity_scale_target


func reset(body: RigidBody3D, initial_gravity_scale: float = 0.0) -> void:
	armed = false
	body.gravity_scale = initial_gravity_scale


func arm_if_needed(body: RigidBody3D) -> void:
	if not enabled or armed:
		return
	armed = true
	body.gravity_scale = target_gravity_scale
