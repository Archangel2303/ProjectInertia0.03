extends CharacterBody3D

@export var max_health: int = 1
@export var despawn_on_any_hit: bool = true

@export_group("Damage Multipliers")
@export var head_multiplier: float = 2.0
@export var torso_multiplier: float = 1.0
@export var limb_multiplier: float = 0.75

@export_group("Helmet")
@export var helmet_enabled: bool = false
@export var helmet_durability_hits: int = 0
@export_range(0.0, 1.0) var helmet_damage_reduction: float = 0.8

@export_group("Armor")
@export var armor_enabled: bool = false
@export var armor_durability_hits: int = 0
@export_range(0.0, 1.0) var armor_damage_reduction: float = 0.5

var health: int = 0
var _helmet_hits_left: int = 0
var _armor_hits_left: int = 0


func _ready() -> void:
	health = max_health
	_helmet_hits_left = helmet_durability_hits if helmet_enabled else 0
	_armor_hits_left = armor_durability_hits if armor_enabled else 0


func _get_multiplier_for_hit(hit_type: String) -> float:
	if hit_type == "head":
		return head_multiplier
	if hit_type == "torso":
		return torso_multiplier
	return limb_multiplier

func apply_damage(amount: int, hit_type: String = "torso") -> void:
	if amount <= 0:
		return

	var scaled_damage := float(amount) * _get_multiplier_for_hit(hit_type)

	if hit_type == "head" and _helmet_hits_left > 0:
		scaled_damage *= (1.0 - helmet_damage_reduction)
		_helmet_hits_left -= 1

	if hit_type != "head" and _armor_hits_left > 0:
		scaled_damage *= (1.0 - armor_damage_reduction)
		_armor_hits_left -= 1

	var final_damage: int = max(0, int(round(scaled_damage)))
	health -= final_damage
	print("HIT:", hit_type, " dmg:", final_damage, " health:", health, " helmet_hits_left:", _helmet_hits_left, " armor_hits_left:", _armor_hits_left)

	if despawn_on_any_hit:
		queue_free()
		return

	if health <= 0:
		print("DUMMY DEAD")
		queue_free()
