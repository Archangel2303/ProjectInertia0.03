extends RefCounted
## Manages shop state: currency, purchases, unlocks, cosmetics, persistence.

const SHOP_BUNDLE_GUN_TEST_SKINS: Array[String] = [
	"res://assets/visual/magnum/test_skin_magnum_neon_grid.png",
	"res://assets/visual/magnum/test_skin_magnum_cyber_rings.png",
	"res://assets/visual/magnum/test_skin_magnum_dark_hextech.png",
	"res://assets/visual/magnum/test_skin_magnum_void_circuit.png"
]

const SHOP_BUNDLE_BULLET_TEST_SKINS: Array[String] = [
	"res://assets/visual/Bullet/test_skin_bullet_neon_core.png",
	"res://assets/visual/Bullet/test_skin_bullet_toxic_hex.png",
	"res://assets/visual/Bullet/test_skin_bullet_pulsewave.png",
	"res://assets/visual/Bullet/test_skin_bullet_tracer_stripe.png"
]

var selected_gun_skin_path: String = ""
var selected_bullet_skin_path: String = ""
var selected_bullet_trail_style: String = "Default Trail"
var currency: int = 1000
var owned_items: Dictionary = {}
var unlocked_bullet_trails: Dictionary = {"Default Trail": true, "Tracer": true}
var unlocked_gun_skin_paths: Dictionary = {}
var unlocked_bullet_skin_paths: Dictionary = {}
var last_daily_claim_date: String = ""


func get_currency() -> int:
	return max(0, currency)


func has_item(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	return bool(owned_items.get(item_id, false))


func is_bullet_trail_unlocked(style: String) -> bool:
	if style == "Default Trail" or style == "Tracer":
		return true
	return bool(unlocked_bullet_trails.get(style, false))


func is_gun_skin_unlocked(path: String) -> bool:
	if path.is_empty():
		return true
	if not _is_shop_managed_gun_skin(path):
		return true
	return bool(unlocked_gun_skin_paths.get(path, false))


func is_bullet_skin_unlocked(path: String) -> bool:
	if path.is_empty():
		return true
	if not _is_shop_managed_bullet_skin(path):
		return true
	return bool(unlocked_bullet_skin_paths.get(path, false))


func purchase_item(item_id: String, cost: int) -> Dictionary:
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid_item", "balance": currency}
	if cost < 0:
		return {"ok": false, "reason": "invalid_cost", "balance": currency}
	if has_item(item_id):
		return {"ok": false, "reason": "already_owned", "balance": currency}
	if currency < cost:
		return {"ok": false, "reason": "insufficient_funds", "balance": currency}

	currency -= cost
	owned_items[item_id] = true
	_apply_unlock_effect(item_id)
	save_profile()
	return {"ok": true, "reason": "purchased", "balance": currency}


func claim_daily_credits(amount: int = 200) -> Dictionary:
	var today: String = Time.get_date_string_from_system()
	if last_daily_claim_date == today:
		return {"ok": false, "reason": "already_claimed", "amount": 0, "balance": currency}

	var grant: int = maxi(0, amount)
	currency += grant
	last_daily_claim_date = today
	save_profile()
	return {"ok": true, "reason": "claimed", "amount": grant, "balance": currency}


func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	currency += amount
	save_profile()


func set_cosmetics(gun_skin: String, bullet_skin: String, trail_style: String = "Default Trail") -> void:
	selected_gun_skin_path = _sanitize_texture_path(gun_skin)
	selected_bullet_skin_path = _sanitize_texture_path(bullet_skin)
	selected_bullet_trail_style = _sanitize_trail_style(trail_style)


func set_gun_skin(path: String) -> void:
	selected_gun_skin_path = _sanitize_texture_path(path)


func set_bullet_skin(path: String) -> void:
	selected_bullet_skin_path = _sanitize_texture_path(path)


func set_bullet_trail(style: String) -> void:
	selected_bullet_trail_style = _sanitize_trail_style(style)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shop", "currency", currency)
	cfg.set_value("shop", "owned_items", owned_items)
	cfg.set_value("shop", "unlocked_bullet_trails", unlocked_bullet_trails)
	cfg.set_value("shop", "unlocked_gun_skin_paths", unlocked_gun_skin_paths)
	cfg.set_value("shop", "unlocked_bullet_skin_paths", unlocked_bullet_skin_paths)
	cfg.set_value("shop", "last_daily_claim_date", last_daily_claim_date)
	cfg.save("user://shop_profile.cfg")


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://shop_profile.cfg") != OK:
		currency = 1000
		owned_items = {}
		unlocked_bullet_trails = {"Default Trail": true, "Tracer": true}
		unlocked_gun_skin_paths = {}
		unlocked_bullet_skin_paths = {}
		last_daily_claim_date = ""
		save_profile()
		return

	currency = max(0, int(cfg.get_value("shop", "currency", 1000)))
	var loaded_items: Variant = cfg.get_value("shop", "owned_items", {})
	owned_items = loaded_items if loaded_items is Dictionary else {}
	var loaded_trails: Variant = cfg.get_value("shop", "unlocked_bullet_trails", {"Default Trail": true, "Tracer": true})
	unlocked_bullet_trails = loaded_trails if loaded_trails is Dictionary else {}
	var loaded_gun_skins: Variant = cfg.get_value("shop", "unlocked_gun_skin_paths", {})
	unlocked_gun_skin_paths = loaded_gun_skins if loaded_gun_skins is Dictionary else {}
	var loaded_bullet_skins: Variant = cfg.get_value("shop", "unlocked_bullet_skin_paths", {})
	unlocked_bullet_skin_paths = loaded_bullet_skins if loaded_bullet_skins is Dictionary else {}
	last_daily_claim_date = String(cfg.get_value("shop", "last_daily_claim_date", ""))

	unlocked_bullet_trails["Default Trail"] = true
	unlocked_bullet_trails["Tracer"] = true
	_reapply_unlocks_from_inventory()


func _apply_unlock_effect(item_id: String) -> void:
	match item_id:
		"trail_neon_unlock":
			unlocked_bullet_trails["Neon"] = true
		"trail_smoke_unlock":
			unlocked_bullet_trails["Smoke"] = true
		"gun_skin_bundle_test":
			for path in SHOP_BUNDLE_GUN_TEST_SKINS:
				unlocked_gun_skin_paths[path] = true
		"bullet_skin_bundle_test":
			for path in SHOP_BUNDLE_BULLET_TEST_SKINS:
				unlocked_bullet_skin_paths[path] = true
		_:
			pass


func _reapply_unlocks_from_inventory() -> void:
	unlocked_bullet_trails["Default Trail"] = true
	unlocked_bullet_trails["Tracer"] = true
	for item_id in owned_items.keys():
		if bool(owned_items[item_id]):
			_apply_unlock_effect(String(item_id))


func _is_shop_managed_gun_skin(path: String) -> bool:
	return SHOP_BUNDLE_GUN_TEST_SKINS.has(path)


func _is_shop_managed_bullet_skin(path: String) -> bool:
	return SHOP_BUNDLE_BULLET_TEST_SKINS.has(path)


func _sanitize_texture_path(path: String) -> String:
	if path.is_empty():
		return ""
	if not path.begins_with("res://"):
		return ""
	if not ResourceLoader.exists(path):
		return ""
	return path


func _sanitize_trail_style(style: String) -> String:
	if not is_bullet_trail_unlocked(style):
		return "Default Trail"
	match style:
		"Tracer", "Neon", "Smoke":
			return style
		_:
			return "Default Trail"
