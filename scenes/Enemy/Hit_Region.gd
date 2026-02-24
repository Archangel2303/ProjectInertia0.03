extends Area3D

@export_enum("head", "torso", "arm", "leg", "hand", "foot") var hit_type := "torso"

func get_hit_type() -> String:
    return hit_type