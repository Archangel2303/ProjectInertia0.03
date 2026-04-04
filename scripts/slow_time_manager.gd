extends RefCounted
## Manages slow-time state and Engine.time_scale.
## Configuration (scale values, curves) lives on the GameManager controller.

var is_active: bool = false


func start() -> bool:
	if is_active:
		return false
	is_active = true
	return true


func stop(normal_time_scale: float) -> bool:
	if not is_active:
		return false
	is_active = false
	Engine.time_scale = normal_time_scale
	return true


func update_dynamic_scale(
	spin_strength: float,
	slow_scale: float,
	max_impact_scale: float,
	spin_ref: float,
	curve_power: float
) -> void:
	if not is_active:
		return
	var denom := maxf(spin_ref, 0.001)
	var t := clampf(spin_strength / denom, 0.0, 1.0)
	var curve := maxf(curve_power, 1.0)
	var curved_t := 1.0 - pow(1.0 - t, curve)
	Engine.time_scale = lerpf(slow_scale, max_impact_scale, curved_t)
