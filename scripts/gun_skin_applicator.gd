extends RefCounted

var _material: StandardMaterial3D = null


func apply(gun_mesh: MeshInstance3D, skin_path: String) -> void:
	if gun_mesh == null:
		return
	if skin_path.is_empty():
		return

	var skin_texture := load(skin_path) as Texture2D
	if skin_texture == null:
		return

	if _material == null:
		var base_material := gun_mesh.get_active_material(0)
		if base_material is StandardMaterial3D:
			_material = (base_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_material = StandardMaterial3D.new()

	_material.albedo_texture = skin_texture
	gun_mesh.set_surface_override_material(0, _material)
