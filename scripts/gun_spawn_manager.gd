extends RefCounted

var global_tf: Transform3D = Transform3D.IDENTITY
var local_tf: Transform3D = Transform3D.IDENTITY
var cached: bool = false


func cache(body: Node3D) -> void:
	global_tf = body.global_transform
	local_tf = body.transform
	cached = true


func apply(body: Node3D) -> void:
	if not cached:
		return
	body.transform = local_tf
	body.global_transform = global_tf
