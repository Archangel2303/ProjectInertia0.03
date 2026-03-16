extends Control

enum Screen {
	TITLE,
	MAIN_MENU,
	PLAY_MENU,
	WORLD_SELECT,
	LEVEL_SELECT,
	GUN_LOCKER,
	SETTINGS
}

enum AppTier {
	FREE,
	PREMIUM
}

const MENU_PROFILE_PATH := "user://menu_profile.cfg"

@export var levels_root_path := "res://scenes/Levels"
@export_file("*.tscn") var fallback_level_scene := "res://scenes/Levels/World 1/FiringRange.tscn"

@onready var menu_title: Label = $Center/Panel/Margin/VBox/MenuTitle
@onready var menu_subtitle: Label = $Center/Panel/Margin/VBox/MenuSubtitle
@onready var notification_label: Label = $Center/Panel/Margin/VBox/Notification
@onready var content: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Content
@onready var hint_label: Label = $Center/Panel/Margin/VBox/Hint
@onready var banner_ad_panel: PanelContainer = $Center/Panel/Margin/VBox/BannerAdPlaceholder
@onready var banner_ad_badge: Label = $Center/Panel/Margin/VBox/BannerAdPlaceholder/Margin/BannerRow/AdBadge
@onready var banner_ad_button: Button = $Center/Panel/Margin/VBox/BannerAdPlaceholder/Margin/BannerRow/BannerButton
@onready var banner_dismiss_button: Button = $Center/Panel/Margin/VBox/BannerAdPlaceholder/Margin/BannerRow/DismissButton

var current_screen: Screen = Screen.TITLE
var selected_world_path := ""
var selected_world_name := ""
var menu_banner_ads_enabled := true
var app_tier: AppTier = AppTier.FREE
var entitlement_source := "default"
var _ad_rotation_index := 0
var _ad_rotation_timer: Timer
var _banner_popup: AcceptDialog
var _dismissed_banner_screens: Dictionary = {}

var gun_skin_options: Array[String] = []
var bullet_skin_options: Array[String] = []
var bullet_trail_options: Array[String] = ["Default Trail", "Tracer", "Neon", "Smoke"]


func _ready() -> void:
	_setup_banner_ad_placeholders()
	_load_menu_profile()
	_apply_entitlement_policy()
	_cache_cosmetic_options()
	var requested := ""
	if gamemanager != null and gamemanager.has_method("consume_pending_title_screen"):
		requested = gamemanager.consume_pending_title_screen()

	if requested == "main_menu":
		_show_main_menu()
		return
	if requested == "world_select":
		_show_world_select()
		return

	_show_title_screen()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _set_header(title: String, subtitle: String, hint: String = "") -> void:
	menu_title.text = title
	menu_subtitle.text = subtitle
	hint_label.text = hint
	_update_banner_ad_placeholder()


func _update_banner_ad_placeholder() -> void:
	if banner_ad_panel == null or banner_ad_button == null:
		return
	if _is_premium_user():
		banner_ad_panel.visible = false
		return

	var screen_key := int(current_screen)
	var dismissed := _can_dismiss_banner_ads() and bool(_dismissed_banner_screens.get(screen_key, false))
	banner_ad_panel.visible = not dismissed
	if dismissed:
		return

	if not menu_banner_ads_enabled:
		banner_ad_button.text = "[ Banner Ads Disabled ]"
		banner_ad_button.disabled = true
		if banner_ad_badge != null:
			banner_ad_badge.text = "OFF"
		if banner_dismiss_button != null:
			banner_dismiss_button.disabled = true
		return

	banner_ad_button.disabled = false
	if banner_ad_badge != null:
		banner_ad_badge.text = "AD"
	if banner_dismiss_button != null:
		banner_dismiss_button.disabled = not _can_dismiss_banner_ads()
		banner_dismiss_button.tooltip_text = "Dismiss banner" if _can_dismiss_banner_ads() else "Free tier cannot dismiss banner ads"
	banner_ad_button.text = _get_current_banner_copy()


func _setup_banner_ad_placeholders() -> void:
	if banner_ad_button != null:
		banner_ad_button.pressed.connect(_on_banner_ad_pressed)
	if banner_dismiss_button != null:
		banner_dismiss_button.pressed.connect(_on_banner_dismiss_pressed)

	_ad_rotation_timer = Timer.new()
	_ad_rotation_timer.wait_time = 5.0
	_ad_rotation_timer.one_shot = false
	_ad_rotation_timer.autostart = true
	_ad_rotation_timer.timeout.connect(_on_banner_ad_rotation_timeout)
	add_child(_ad_rotation_timer)

	_banner_popup = AcceptDialog.new()
	_banner_popup.title = "Promo Placeholder"
	add_child(_banner_popup)


func _get_current_banner_copy() -> String:
	var ads := _get_banner_ads_for_screen(current_screen)
	if ads.is_empty():
		return "[ Banner Ad Placeholder 320x50 ]"
	var idx := posmod(_ad_rotation_index, ads.size())
	return String(ads[idx])


func _get_banner_ads_for_screen(screen: Screen) -> Array[String]:
	match screen:
		Screen.TITLE:
			return [
				"[ Banner Ad Placeholder | Welcome Bundle ]",
				"[ Banner Ad Placeholder | Free Daily Credits ]",
				"[ Banner Ad Placeholder | Starter Pack Offer ]"
			]
		Screen.MAIN_MENU:
			return [
				"[ Banner Ad Placeholder | New Weapon Skin Pack ]",
				"[ Banner Ad Placeholder | 2x XP Weekend ]",
				"[ Banner Ad Placeholder | Season Pass Preview ]"
			]
		Screen.PLAY_MENU:
			return [
				"[ Banner Ad Placeholder | Unlimited Endless Boost ]",
				"[ Banner Ad Placeholder | Continue Token Bundle ]",
				"[ Banner Ad Placeholder | Accuracy Training Pack ]"
			]
		Screen.WORLD_SELECT:
			return [
				"[ Banner Ad Placeholder | World Progress Booster ]",
				"[ Banner Ad Placeholder | Bonus Star Offer ]",
				"[ Banner Ad Placeholder | Map Reveal Bundle ]"
			]
		Screen.LEVEL_SELECT:
			return [
				"[ Banner Ad Placeholder | Score Multiplier Trial ]",
				"[ Banner Ad Placeholder | Precision Challenge Pass ]",
				"[ Banner Ad Placeholder | Weekly Milestone Reward ]"
			]
		Screen.GUN_LOCKER:
			return [
				"[ Banner Ad Placeholder | Cosmetic Crate Offer ]",
				"[ Banner Ad Placeholder | Magnum Wrap Collection ]",
				"[ Banner Ad Placeholder | Tracer Color Bundle ]"
			]
		Screen.SETTINGS:
			return [
				"[ Banner Ad Placeholder | Premium UI Theme ]",
				"[ Banner Ad Placeholder | Profile Flair Pack ]",
				"[ Banner Ad Placeholder | Soundtrack Sample ]"
			]
		_:
			return ["[ Banner Ad Placeholder 320x50 ]"]


func _on_banner_ad_rotation_timeout() -> void:
	if _is_premium_user():
		return
	if not menu_banner_ads_enabled:
		return
	_ad_rotation_index += 1
	_update_banner_ad_placeholder()


func _on_banner_ad_pressed() -> void:
	if _is_premium_user():
		return
	if not menu_banner_ads_enabled:
		return
	if _banner_popup == null:
		return
	_banner_popup.dialog_text = "Ad click simulation only.\n\nCurrent Creative:\n%s" % _get_current_banner_copy()
	_banner_popup.popup_centered(Vector2i(460, 210))


func _on_menu_banner_ads_toggled(enabled: bool) -> void:
	menu_banner_ads_enabled = enabled
	if enabled:
		_dismissed_banner_screens.clear()
	_apply_entitlement_policy()
	_save_menu_profile()
	if _ad_rotation_timer != null:
		_ad_rotation_timer.paused = not menu_banner_ads_enabled
	_update_banner_ad_placeholder()
	_set_notification("Menu Banner Ads: %s" % ("On" if menu_banner_ads_enabled else "Off"))


func _on_banner_dismiss_pressed() -> void:
	if not _can_dismiss_banner_ads():
		_set_notification("Free tier cannot dismiss banner ads.")
		return
	_dismissed_banner_screens[int(current_screen)] = true
	_save_menu_profile()
	_update_banner_ad_placeholder()


func _load_menu_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(MENU_PROFILE_PATH) != OK:
		app_tier = AppTier.PREMIUM if _build_is_premium() else AppTier.FREE
		entitlement_source = "build"
		menu_banner_ads_enabled = true
		_dismissed_banner_screens = {}
		_save_menu_profile()
		return

	var saved_premium := bool(cfg.get_value("entitlement", "premium_unlocked", false))
	if _build_is_premium():
		app_tier = AppTier.PREMIUM
		entitlement_source = "build"
	else:
		app_tier = AppTier.PREMIUM if saved_premium else AppTier.FREE
		entitlement_source = "save"

	menu_banner_ads_enabled = bool(cfg.get_value("ads", "menu_banner_ads_enabled", true))
	var saved_dismissed: Variant = cfg.get_value("ads", "dismissed_screens", {})
	if saved_dismissed is Dictionary:
		_dismissed_banner_screens = saved_dismissed
	else:
		_dismissed_banner_screens = {}


func _save_menu_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("entitlement", "premium_unlocked", _is_premium_user())
	cfg.set_value("entitlement", "source", entitlement_source)
	cfg.set_value("ads", "menu_banner_ads_enabled", menu_banner_ads_enabled)
	cfg.set_value("ads", "dismissed_screens", _dismissed_banner_screens)
	cfg.save(MENU_PROFILE_PATH)


func _apply_entitlement_policy() -> void:
	if _is_premium_user():
		menu_banner_ads_enabled = false
	else:
		menu_banner_ads_enabled = true
		_dismissed_banner_screens.clear()

	if _ad_rotation_timer != null:
		_ad_rotation_timer.paused = not menu_banner_ads_enabled


func _build_is_premium() -> bool:
	return OS.has_feature("premium") or OS.has_feature("adfree")


func _is_premium_user() -> bool:
	return app_tier == AppTier.PREMIUM


func _can_dismiss_banner_ads() -> bool:
	return _is_premium_user()


func set_premium_entitlement(enabled: bool) -> void:
	app_tier = AppTier.PREMIUM if enabled else AppTier.FREE
	entitlement_source = "save"
	_apply_entitlement_policy()
	_save_menu_profile()
	_update_banner_ad_placeholder()


func _set_notification(message: String) -> void:
	notification_label.text = message
	notification_label.visible = not message.is_empty()


func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func _add_menu_button(text: String, callback: Callable, should_grab_focus := false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(300, 44)
	button.text = text
	button.pressed.connect(callback)
	content.add_child(button)
	if should_grab_focus:
		button.grab_focus()
	return button


func _add_section_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	content.add_child(label)


func _add_row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(260, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(label)
	row.add_child(control)
	content.add_child(row)


func _make_info_label(text: String) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(240, 0)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _make_checkbox(pressed: bool, callback: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.button_pressed = pressed
	box.toggled.connect(callback)
	return box


func _make_slider(min_value: float, max_value: float, step: float, value: float, callback: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(240, 0)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.value_changed.connect(callback)
	return slider


func _make_options(items: Array[String], selected_index: int, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(240, 0)
	for item in items:
		option.add_item(item)
	option.select(clampi(selected_index, 0, max(option.item_count - 1, 0)))
	option.item_selected.connect(callback)
	return option


func _show_title_screen() -> void:
	current_screen = Screen.TITLE
	_clear_content()
	_set_header("Project Inertia", "Prototype 0.03", "Enter/Space/LMB: Confirm   Esc: Back")
	_set_notification("")

	_add_menu_button("Enter", _show_main_menu, true)
	_add_menu_button("Quit", _quit_game)


func _show_main_menu() -> void:
	current_screen = Screen.MAIN_MENU
	_clear_content()
	_set_header("Main Menu", "Choose your destination", "Esc: Back to Title")
	_set_notification("")

	_add_menu_button("Play", _show_play_menu, true)
	_add_menu_button("Gun Locker (Cosmetic Hub)", _show_gun_locker)
	_add_menu_button("Settings", _show_settings)
	_add_menu_button("Quit", _quit_game)


func _show_play_menu() -> void:
	current_screen = Screen.PLAY_MENU
	_clear_content()
	_set_header("Play", "Select a game mode", "Esc: Back to Main Menu")
	_set_notification("")

	_add_menu_button("World Select", _show_world_select, true)
	_add_menu_button("Endless Mode", _start_endless_mode)
	_add_menu_button("Return to Menu", _show_main_menu)


func _show_world_select() -> void:
	current_screen = Screen.WORLD_SELECT
	_clear_content()
	_set_header("World Select", "Pick a world", "Esc: Back to Play")
	_set_notification("")

	var worlds := _get_worlds()
	if worlds.is_empty():
		_set_notification("No worlds found in %s" % levels_root_path)
		_add_menu_button("Return to Play Menu", _show_play_menu, true)
		return

	var first := true
	for world in worlds:
		var world_name: String = world["name"]
		var world_path: String = world["path"]
		_add_menu_button(world_name, func() -> void: _show_level_select(world_name, world_path), first)
		first = false

	_add_menu_button("Return to Play Menu", _show_play_menu)


func _show_level_select(world_name: String, world_path: String) -> void:
	current_screen = Screen.LEVEL_SELECT
	selected_world_name = world_name
	selected_world_path = world_path

	_clear_content()
	_set_header("Level Select", "%s" % world_name, "Esc: Back to World Select")
	_set_notification("")

	var levels := _get_levels_for_world(world_path)
	if levels.is_empty():
		_set_notification("No levels found for %s" % world_name)
		_add_menu_button("Return to World Select", _show_world_select, true)
		return

	var first := true
	var previous_level_passed := true
	for i in range(levels.size()):
		var level: Dictionary = levels[i]
		var level_name: String = level["name"]
		var level_path: String = level["path"]

		var progress := {"high_score": 0, "best_stars": 0, "passed": false}
		if gamemanager != null and gamemanager.has_method("get_level_progress"):
			progress = gamemanager.get_level_progress(level_path)

		var best_stars := int(progress.get("best_stars", 0))
		var high_score := int(progress.get("high_score", 0))
		var is_unlocked := i == 0 or previous_level_passed
		var label := "%s  |  %d★  |  HS %d" % [level_name, best_stars, high_score]

		if is_unlocked:
			_add_menu_button(label, func() -> void: _start_level(level_path), first)
			first = false
		else:
			var locked := _add_menu_button("%s  |  LOCKED" % level_name, func() -> void: _set_notification("Clear the previous level with at least 1 star to unlock this level."), first)
			locked.disabled = true

		previous_level_passed = bool(progress.get("passed", false))

	_add_menu_button("Return to World Select", _show_world_select)


func _show_gun_locker() -> void:
	current_screen = Screen.GUN_LOCKER
	_clear_content()
	_set_header("Gun Locker", "Select and preview cosmetics", "Esc: Back to Main Menu")
	_set_notification("")

	_add_section_title("Cosmetic Selection")

	var gun_skin_picker := _make_options(gun_skin_options, 0, func(index: int) -> void: _set_notification("Gun Skin: %s" % gun_skin_options[index]))
	_add_row("Gun Skin", gun_skin_picker)

	var bullet_skin_picker := _make_options(bullet_skin_options, 0, func(index: int) -> void: _set_notification("Bullet Skin: %s" % bullet_skin_options[index]))
	_add_row("Bullet Skin", bullet_skin_picker)

	var trail_picker := _make_options(bullet_trail_options, 0, func(index: int) -> void: _set_notification("Bullet Trail Skin: %s" % bullet_trail_options[index]))
	_add_row("Bullet Trail Skin", trail_picker)

	_add_section_title("Preview")
	var preview := Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.text = "Preview updates in this hub as cosmetics are selected.\n(Integration to in-game materials can be added next.)"
	content.add_child(preview)

	_add_menu_button("Return to Main Menu", _show_main_menu, true)


func _show_settings() -> void:
	current_screen = Screen.SETTINGS
	_clear_content()
	_set_header("Settings", "Slay-the-Spire-style complete menu set", "Esc: Back to Main Menu")
	_set_notification("")

	_add_section_title("Display")
	_add_row("Display Mode", _make_options(["Windowed", "Borderless", "Fullscreen"], 0, _on_display_mode_selected))
	_add_row("VSync", _make_checkbox(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, _on_vsync_toggled))
	_add_row("FPS Cap", _make_options(["30", "60", "120", "144", "Uncapped"], 1, _on_fps_cap_selected))
	_add_row("Resolution Scale", _make_slider(50, 100, 5, 100, _on_resolution_scale_changed))

	_add_section_title("Audio")
	_add_row("Master Volume", _make_slider(0, 100, 1, 80, func(v: float) -> void: _set_bus_volume("Master", v)))
	_add_row("Music Volume", _make_slider(0, 100, 1, 70, func(v: float) -> void: _set_bus_volume("Music", v)))
	_add_row("SFX Volume", _make_slider(0, 100, 1, 80, func(v: float) -> void: _set_bus_volume("SFX", v)))
	_add_row("UI Volume", _make_slider(0, 100, 1, 80, func(v: float) -> void: _set_bus_volume("UI", v)))
	_add_row("Ambient Volume", _make_slider(0, 100, 1, 70, func(v: float) -> void: _set_bus_volume("Ambience", v)))

	_add_section_title("Gameplay")
	_add_row("Screen Shake", _make_slider(0, 100, 1, 70, func(v: float) -> void: _set_notification("Screen Shake: %d%%" % int(v))))
	_add_row("Fast Mode", _make_checkbox(false, func(on: bool) -> void: _set_notification("Fast Mode: %s" % ("On" if on else "Off"))))
	_add_row("Tutorial Prompts", _make_checkbox(true, func(on: bool) -> void: _set_notification("Tutorial Prompts: %s" % ("On" if on else "Off"))))
	_add_row("Show Damage Numbers", _make_checkbox(true, func(on: bool) -> void: _set_notification("Damage Numbers: %s" % ("On" if on else "Off"))))

	_add_section_title("Controls")
	_add_row("Mouse Sensitivity", _make_slider(0.1, 2.0, 0.1, 1.0, func(v: float) -> void: _set_notification("Mouse Sensitivity: %.1f" % v)))
	_add_row("Invert Y", _make_checkbox(false, func(on: bool) -> void: _set_notification("Invert Y: %s" % ("On" if on else "Off"))))
	_add_row("Controller Vibration", _make_checkbox(true, func(on: bool) -> void: _set_notification("Controller Vibration: %s" % ("On" if on else "Off"))))

	_add_section_title("Accessibility")
	_add_row("Language", _make_options(["English", "Spanish", "French", "German", "Japanese", "Korean"], 0, func(_i: int) -> void: _set_notification("Language selection saved.")))
	_add_row("Colorblind Mode", _make_options(["Off", "Protanopia", "Deuteranopia", "Tritanopia"], 0, func(_i: int) -> void: _set_notification("Colorblind mode updated.")))
	_add_row("Subtitle Size", _make_options(["Small", "Medium", "Large"], 1, func(_i: int) -> void: _set_notification("Subtitle size updated.")))
	_add_row("Large Cursor", _make_checkbox(false, func(on: bool) -> void: _set_notification("Large Cursor: %s" % ("On" if on else "Off"))))

	_add_section_title("System")
	_add_row("Confirm on Quit", _make_checkbox(true, func(on: bool) -> void: _set_notification("Confirm on Quit: %s" % ("On" if on else "Off"))))
	_add_row("Background FPS", _make_options(["15", "30", "60"], 1, func(_i: int) -> void: _set_notification("Background FPS setting updated.")))
	var tier_text := "Premium (Ad-Free)" if _is_premium_user() else "Free"
	_add_row("App Tier", _make_info_label(tier_text))
	_add_row("Entitlement Source", _make_info_label(entitlement_source.capitalize()))
	if _is_premium_user():
		_add_row("Menu Banner Ads", _make_info_label("Forced Off"))
	else:
		_add_row("Menu Banner Ads", _make_info_label("Forced On"))

	_add_menu_button("Return to Main Menu", _show_main_menu, true)


func _on_display_mode_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	_set_notification("Display mode updated.")


func _on_vsync_toggled(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	_set_notification("VSync: %s" % ("On" if enabled else "Off"))


func _on_fps_cap_selected(index: int) -> void:
	var caps := [30, 60, 120, 144, 0]
	Engine.max_fps = caps[clampi(index, 0, caps.size() - 1)]
	if Engine.max_fps == 0:
		_set_notification("FPS Cap: Uncapped")
	else:
		_set_notification("FPS Cap: %d" % Engine.max_fps)


func _on_resolution_scale_changed(value: float) -> void:
	_set_notification("Resolution Scale: %d%%" % int(value))


func _set_bus_volume(bus_name: String, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	if value <= 0.0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value / 100.0))


func _start_endless_mode() -> void:
	_set_notification("Endless Mode scene is not configured yet.")


func _start_level(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	if not ResourceLoader.exists(scene_path):
		_set_notification("Missing scene: %s" % scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


func _go_back() -> void:
	match current_screen:
		Screen.TITLE:
			_quit_game()
		Screen.MAIN_MENU:
			_show_title_screen()
		Screen.PLAY_MENU:
			_show_main_menu()
		Screen.WORLD_SELECT:
			_show_play_menu()
		Screen.LEVEL_SELECT:
			_show_world_select()
		Screen.GUN_LOCKER:
			_show_main_menu()
		Screen.SETTINGS:
			_show_main_menu()


func _quit_game() -> void:
	if OS.has_feature("web"):
		_set_notification("Quit is not supported on web builds.")
		return
	get_tree().quit()


func _get_worlds() -> Array[Dictionary]:
	var worlds: Array[Dictionary] = []
	var dir := DirAccess.open(levels_root_path)
	if dir == null:
		return worlds

	dir.list_dir_begin()
	while true:
		var entry_name := dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name.begins_with("."):
			continue
		if dir.current_is_dir():
			worlds.append({"name": entry_name, "path": "%s/%s" % [levels_root_path, entry_name]})
	dir.list_dir_end()

	worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return worlds


func _get_levels_for_world(world_path: String) -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	var dir := DirAccess.open(world_path)
	if dir == null:
		return levels

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tscn"):
			continue

		var level_name := file_name.trim_suffix(".tscn")
		levels.append({"name": level_name, "path": "%s/%s" % [world_path, file_name]})
	dir.list_dir_end()

	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return levels


func _cache_cosmetic_options() -> void:
	gun_skin_options = _scan_files("res://assets/visual/magnum", ["png", "jpg", "jpeg"]) 
	bullet_skin_options = _scan_files("res://assets/visual/Bullet", ["png", "jpg", "jpeg"]) 

	if gun_skin_options.is_empty():
		gun_skin_options = ["Default Gun Skin"]
	if bullet_skin_options.is_empty():
		bullet_skin_options = ["Default Bullet Skin"]


func _scan_files(path: String, extensions: Array[String]) -> Array[String]:
	var results: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return results

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue

		var ext := file_name.get_extension().to_lower()
		if extensions.has(ext):
			results.append(file_name)
	dir.list_dir_end()

	results.sort()
	return results
