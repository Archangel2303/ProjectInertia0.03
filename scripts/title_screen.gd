extends Control

enum Screen {
	TITLE,
	MAIN_MENU,
	PLAY_MENU,
	SHOP,
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

# Preloads force these levels into exported builds where directory scanning can be incomplete.
const WORLD_1_LEVEL_SCENES: Array[PackedScene] = [
	preload("res://scenes/Levels/World 1/W1L01.tscn"),
	preload("res://scenes/Levels/World 1/W1L02.tscn"),
	preload("res://scenes/Levels/World 1/W1L03.tscn"),
	preload("res://scenes/Levels/World 1/W1L04.tscn"),
	preload("res://scenes/Levels/World 1/W1L05.tscn"),
	preload("res://scenes/Levels/World 1/W1L06.tscn"),
	preload("res://scenes/Levels/World 1/W1L07.tscn"),
	preload("res://scenes/Levels/World 1/W1L08.tscn"),
	preload("res://scenes/Levels/World 1/W1L09.tscn"),
	preload("res://scenes/Levels/World 1/W1L10.tscn"),
	preload("res://scenes/Levels/World 1/W1L11.tscn"),
	preload("res://scenes/Levels/World 1/W1L12.tscn"),
	preload("res://scenes/Levels/World 1/W1L13.tscn"),
	preload("res://scenes/Levels/World 1/W1L14.tscn"),
	preload("res://scenes/Levels/World 1/W1L15.tscn")
]

const WORLD_LEVEL_CATALOG := {
	"World 1": WORLD_1_LEVEL_SCENES
}

@export var levels_root_path := "res://scenes/Levels"
@export_file("*.tscn") var fallback_level_scene := "res://scenes/Levels/World 1/W1L01.tscn"

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
var gun_skin_paths: Array[String] = []
var bullet_skin_paths: Array[String] = []
var bullet_trail_options: Array[String] = ["Default Trail", "Tracer", "Neon", "Smoke"]
var selected_gun_skin_path := ""
var selected_bullet_skin_path := ""
var selected_bullet_trail := "Default Trail"
var settings_display_mode_index := 0
var settings_vsync_enabled := true
var settings_fps_cap_index := 1
var settings_master_volume := 100.0
var settings_music_volume := 100.0


func _ready() -> void:
	_apply_synthwave_theme()
	_setup_banner_ad_placeholders()
	_load_menu_profile()
	_apply_entitlement_policy()
	_cache_cosmetic_options()
	_apply_selected_cosmetics_to_game_manager()
	_apply_saved_settings()
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


# ── Synthwave palette ────────────────────────────────────────────────
const NEON_MAGENTA := Color(1.0, 0.0, 0.55, 1.0)
const NEON_CYAN := Color(0.0, 0.92, 1.0, 1.0)
const NEON_WHITE := Color(0.92, 0.92, 0.96, 1.0)
const DARK_BG := Color(0.04, 0.02, 0.10, 0.92)
const PANEL_BG := Color(0.06, 0.03, 0.14, 0.88)
const BTN_NORMAL_BG := Color(0.08, 0.04, 0.18, 0.9)
const BTN_HOVER_BG := Color(0.14, 0.04, 0.28, 0.95)
const BTN_PRESSED_BG := Color(0.22, 0.02, 0.36, 1.0)
const BTN_DISABLED_BG := Color(0.06, 0.04, 0.10, 0.6)
const BORDER_COLOR := Color(1.0, 0.0, 0.55, 0.35)
const BORDER_HOVER := Color(0.0, 0.92, 1.0, 0.55)
const SEPARATOR_COLOR := Color(1.0, 0.0, 0.55, 0.25)


func _apply_synthwave_theme() -> void:
	var t := Theme.new()

	# ── Panel ─────────────────────────────────────────────────────────
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = PANEL_BG
	panel_sb.border_color = BORDER_COLOR
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(6)
	panel_sb.shadow_color = Color(1.0, 0.0, 0.55, 0.08)
	panel_sb.shadow_size = 12
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	# ── Buttons ───────────────────────────────────────────────────────
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		match state_name:
			"normal":
				sb.bg_color = BTN_NORMAL_BG
				sb.border_color = BORDER_COLOR
			"hover":
				sb.bg_color = BTN_HOVER_BG
				sb.border_color = BORDER_HOVER
			"pressed":
				sb.bg_color = BTN_PRESSED_BG
				sb.border_color = NEON_CYAN
			"disabled":
				sb.bg_color = BTN_DISABLED_BG
				sb.border_color = Color(0.3, 0.2, 0.4, 0.2)
			"focus":
				sb.bg_color = BTN_HOVER_BG
				sb.border_color = NEON_CYAN
				sb.set_border_width_all(2)
		t.set_stylebox(state_name, "Button", sb)

	t.set_color("font_color", "Button", NEON_CYAN)
	t.set_color("font_hover_color", "Button", NEON_WHITE)
	t.set_color("font_pressed_color", "Button", NEON_MAGENTA)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.3, 0.5, 0.5))
	t.set_color("font_focus_color", "Button", NEON_WHITE)
	t.set_font_size("font_size", "Button", 16)

	# ── Labels ────────────────────────────────────────────────────────
	t.set_color("font_color", "Label", NEON_WHITE)
	t.set_font_size("font_size", "Label", 15)

	# ── CheckBox ──────────────────────────────────────────────────────
	t.set_color("font_color", "CheckBox", NEON_CYAN)
	t.set_color("font_hover_color", "CheckBox", NEON_WHITE)

	# ── OptionButton ──────────────────────────────────────────────────
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		match state_name:
			"normal":
				sb.bg_color = BTN_NORMAL_BG
				sb.border_color = BORDER_COLOR
			"hover":
				sb.bg_color = BTN_HOVER_BG
				sb.border_color = BORDER_HOVER
			"pressed":
				sb.bg_color = BTN_PRESSED_BG
				sb.border_color = NEON_CYAN
			"disabled":
				sb.bg_color = BTN_DISABLED_BG
				sb.border_color = Color(0.3, 0.2, 0.4, 0.2)
			"focus":
				sb.bg_color = BTN_HOVER_BG
				sb.border_color = NEON_CYAN
		t.set_stylebox(state_name, "OptionButton", sb)
	t.set_color("font_color", "OptionButton", NEON_CYAN)
	t.set_color("font_hover_color", "OptionButton", NEON_WHITE)
	t.set_color("font_focus_color", "OptionButton", NEON_WHITE)

	# ── HSlider ───────────────────────────────────────────────────────
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.08, 0.04, 0.18, 0.8)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = NEON_MAGENTA * Color(1, 1, 1, 0.6)
	slider_fill.set_corner_radius_all(3)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# ── HSeparator ────────────────────────────────────────────────────
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = SEPARATOR_COLOR
	sep_sb.content_margin_top = 1
	sep_sb.content_margin_bottom = 1
	t.set_stylebox("separator", "HSeparator", sep_sb)
	t.set_constant("separation", "HSeparator", 8)

	# ── ScrollContainer ──────────────────────────────────────────────
	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_bg)

	theme = t


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _set_header(title: String, subtitle: String, hint: String = "") -> void:
	menu_title.text = title.to_upper()
	menu_subtitle.text = subtitle.to_upper()
	hint_label.text = hint.to_upper()
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
		Screen.SHOP:
			return [
				"[ Banner Ad Placeholder | Featured Crate Bundle ]",
				"[ Banner Ad Placeholder | Limited Time Currency Pack ]",
				"[ Banner Ad Placeholder | Trail Color Mega Pack ]"
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
		_load_runtime_defaults_for_settings()
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

	selected_gun_skin_path = String(cfg.get_value("cosmetics", "gun_skin_path", ""))
	selected_bullet_skin_path = String(cfg.get_value("cosmetics", "bullet_skin_path", ""))
	selected_bullet_trail = String(cfg.get_value("cosmetics", "bullet_trail", bullet_trail_options[0]))

	_load_runtime_defaults_for_settings()
	settings_display_mode_index = clampi(int(cfg.get_value("settings", "display_mode_index", settings_display_mode_index)), 0, 2)
	settings_vsync_enabled = bool(cfg.get_value("settings", "vsync_enabled", settings_vsync_enabled))
	settings_fps_cap_index = clampi(int(cfg.get_value("settings", "fps_cap_index", settings_fps_cap_index)), 0, 4)
	settings_master_volume = clampf(float(cfg.get_value("settings", "master_volume", settings_master_volume)), 0.0, 100.0)
	settings_music_volume = clampf(float(cfg.get_value("settings", "music_volume", settings_music_volume)), 0.0, 100.0)


func _save_menu_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("entitlement", "premium_unlocked", _is_premium_user())
	cfg.set_value("entitlement", "source", entitlement_source)
	cfg.set_value("ads", "menu_banner_ads_enabled", menu_banner_ads_enabled)
	cfg.set_value("ads", "dismissed_screens", _dismissed_banner_screens)
	cfg.set_value("cosmetics", "gun_skin_path", selected_gun_skin_path)
	cfg.set_value("cosmetics", "bullet_skin_path", selected_bullet_skin_path)
	cfg.set_value("cosmetics", "bullet_trail", selected_bullet_trail)
	cfg.set_value("settings", "display_mode_index", settings_display_mode_index)
	cfg.set_value("settings", "vsync_enabled", settings_vsync_enabled)
	cfg.set_value("settings", "fps_cap_index", settings_fps_cap_index)
	cfg.set_value("settings", "master_volume", settings_master_volume)
	cfg.set_value("settings", "music_volume", settings_music_volume)
	cfg.save(MENU_PROFILE_PATH)


func _load_runtime_defaults_for_settings() -> void:
	settings_display_mode_index = _get_current_display_mode_index()
	settings_vsync_enabled = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	settings_fps_cap_index = _fps_cap_to_index(Engine.max_fps)
	settings_master_volume = _get_bus_volume_percent("Master", 100.0)
	settings_music_volume = _get_music_volume_percent_default()


func _apply_saved_settings() -> void:
	_on_display_mode_selected(settings_display_mode_index, false)
	_on_vsync_toggled(settings_vsync_enabled, false)
	_on_fps_cap_selected(settings_fps_cap_index, false)
	_apply_master_volume(settings_master_volume, false)
	_apply_music_volume(settings_music_volume, false)


func _get_current_display_mode_index() -> int:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return 2
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return 1
	return 0


func _fps_cap_to_index(cap: int) -> int:
	var caps: Array[int] = [30, 60, 120, 144, 0]
	var idx := caps.find(cap)
	if idx != -1:
		return idx
	if cap <= 0:
		return caps.size() - 1
	return 1


func _get_bus_volume_percent(bus_name: String, fallback: float = 100.0) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return fallback
	return _db_to_percent(AudioServer.get_bus_volume_db(bus_index))


func _get_music_volume_percent_default() -> float:
	if gamemanager != null and gamemanager.has_method("get_music_volume_percent"):
		return clampf(float(gamemanager.get_music_volume_percent()), 0.0, 100.0)
	return _get_bus_volume_percent("Music", 100.0)


func _db_to_percent(db: float) -> float:
	if db <= -79.9:
		return 0.0
	return clampf(db_to_linear(db) * 100.0, 0.0, 100.0)


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


func _play_ui_interaction_sound() -> void:
	if gamemanager != null and gamemanager.has_method("play_ui_interaction"):
		gamemanager.play_ui_interaction()


func _add_menu_button(text: String, callback: Callable, should_grab_focus := false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(340, 48)
	button.text = text.to_upper()
	button.pressed.connect(func() -> void:
		_play_ui_interaction_sound()
		if callback.is_valid():
			callback.call())
	content.add_child(button)
	if should_grab_focus:
		button.grab_focus()
	return button


func _add_section_title(text: String) -> void:
	var label := Label.new()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	content.add_child(spacer)
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", NEON_MAGENTA)
	content.add_child(label)
	var sep := HSeparator.new()
	content.add_child(sep)


func _add_row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = label_text.to_upper()
	label.custom_minimum_size = Vector2(260, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", NEON_CYAN * Color(1, 1, 1, 0.8))

	row.add_child(label)
	row.add_child(control)
	content.add_child(row)


func _make_info_label(text: String) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(240, 0)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", NEON_WHITE * Color(1, 1, 1, 0.7))
	return label


func _make_checkbox(pressed: bool, callback: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.button_pressed = pressed
	box.toggled.connect(func(on: bool) -> void:
		_play_ui_interaction_sound()
		if callback.is_valid():
			callback.call(on))
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
	option.item_selected.connect(func(index: int) -> void:
		_play_ui_interaction_sound()
		if callback.is_valid():
			callback.call(index))
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
	_add_menu_button("Shop", _show_shop)
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


func _show_shop() -> void:
	current_screen = Screen.SHOP
	_clear_content()
	_set_header("Shop", "Spend credits on gameplay and cosmetics", "Esc: Back to Main Menu")
	_set_notification("")

	var balance_label := Label.new()
	balance_label.text = "Credits: %d" % _get_shop_balance()
	balance_label.add_theme_font_size_override("font_size", 24)
	content.add_child(balance_label)

	_add_section_title("Featured")
	_add_shop_item_button("Neon Trail Unlock", "trail_neon_unlock", 300, balance_label, true)
	_add_shop_item_button("Smoke Trail Unlock", "trail_smoke_unlock", 300, balance_label)
	_add_shop_item_button("Gun Test Skin Bundle", "gun_skin_bundle_test", 450, balance_label)
	_add_shop_item_button("Bullet Test Skin Bundle", "bullet_skin_bundle_test", 450, balance_label)
	_add_shop_item_button("Starter Credits Pack (+600)", "credits_pack_small", 250, balance_label)

	_add_section_title("Daily")
	var daily_button := _add_menu_button("Claim Free Daily Credits (+200)", func() -> void:
		var result := _claim_daily_credits_from_shop(200)
		if bool(result.get("ok", false)):
			balance_label.text = "Credits: %d" % int(result.get("balance", _get_shop_balance()))
			_set_notification("Claimed +%d credits." % int(result.get("amount", 0)))
			_show_shop()
		else:
			_set_notification("Daily credits already claimed today.")
	)
	if _daily_claim_already_used_today():
		daily_button.disabled = true
		daily_button.text = "Daily Credits Claimed"

	_add_menu_button("Return to Main Menu", _show_main_menu)


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

	var gun_skin_picker := _make_options(gun_skin_options, _get_skin_option_index(gun_skin_paths, selected_gun_skin_path), func(index: int) -> void:
		var requested_path := _get_skin_path_from_option_index(gun_skin_paths, index)
		if _is_gun_skin_available_for_player(requested_path):
			selected_gun_skin_path = requested_path
		else:
			_set_notification("That gun skin is locked. Unlock it in Shop.")
			_show_gun_locker()
			return
		_apply_selected_cosmetics_to_game_manager()
		_save_menu_profile()
		_set_notification("Gun Skin: %s" % _display_name_for_skin_path(selected_gun_skin_path, "Default Gun Skin"))
	)
	_add_row("Gun Skin", gun_skin_picker)

	var bullet_skin_picker := _make_options(bullet_skin_options, _get_skin_option_index(bullet_skin_paths, selected_bullet_skin_path), func(index: int) -> void:
		var requested_path := _get_skin_path_from_option_index(bullet_skin_paths, index)
		if _is_bullet_skin_available_for_player(requested_path):
			selected_bullet_skin_path = requested_path
		else:
			_set_notification("That bullet skin is locked. Unlock it in Shop.")
			_show_gun_locker()
			return
		_apply_selected_cosmetics_to_game_manager()
		_save_menu_profile()
		_set_notification("Bullet Skin: %s" % _display_name_for_skin_path(selected_bullet_skin_path, "Default Bullet Skin"))
	)
	_add_row("Bullet Skin", bullet_skin_picker)

	var trail_picker := _make_options(bullet_trail_options, bullet_trail_options.find(selected_bullet_trail), func(index: int) -> void:
		var requested_trail := bullet_trail_options[clampi(index, 0, bullet_trail_options.size() - 1)]
		if _is_bullet_trail_available_for_player(requested_trail):
			selected_bullet_trail = requested_trail
		else:
			selected_bullet_trail = bullet_trail_options[0]
			_set_notification("%s is locked. Unlock it in Shop." % requested_trail)
			_show_gun_locker()
			return
		_apply_selected_cosmetics_to_game_manager()
		_save_menu_profile()
		_set_notification("Bullet Trail Skin: %s" % selected_bullet_trail)
	)
	_add_row("Bullet Trail Skin", trail_picker)

	_add_section_title("Preview")
	var preview := Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.text = "Selected Gun: %s\nSelected Bullet: %s\nTrail: %s\n\nSkins now apply in-level on the gun mesh and spawned bullets." % [
		_display_name_for_skin_path(selected_gun_skin_path, "Default Gun Skin"),
		_display_name_for_skin_path(selected_bullet_skin_path, "Default Bullet Skin"),
		selected_bullet_trail
	]
	content.add_child(preview)

	_add_menu_button("Return to Main Menu", _show_main_menu, true)


func _show_settings() -> void:
	current_screen = Screen.SETTINGS
	_clear_content()
	_set_header("Settings", "Active options used by this build", "Esc: Back to Main Menu")
	_set_notification("")

	_add_section_title("Display")
	_add_row("Display Mode", _make_options(["Windowed", "Borderless", "Fullscreen"], settings_display_mode_index, _on_display_mode_selected))
	_add_row("VSync", _make_checkbox(settings_vsync_enabled, _on_vsync_toggled))
	_add_row("FPS Cap", _make_options(["30", "60", "120", "144", "Uncapped"], settings_fps_cap_index, _on_fps_cap_selected))

	_add_section_title("Audio")
	_add_row("Master Volume", _make_slider(0, 100, 1, settings_master_volume, _on_master_volume_changed))
	_add_row("Music Volume", _make_slider(0, 100, 1, settings_music_volume, _on_music_volume_changed))

	_add_menu_button("Return to Main Menu", _show_main_menu, true)


func _on_display_mode_selected(index: int, show_notification: bool = true) -> void:
	settings_display_mode_index = clampi(index, 0, 2)
	match settings_display_mode_index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	_save_menu_profile()
	if show_notification:
		_set_notification("Display mode updated.")


func _on_vsync_toggled(enabled: bool, show_notification: bool = true) -> void:
	settings_vsync_enabled = enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	_save_menu_profile()
	if show_notification:
		_set_notification("VSync: %s" % ("On" if enabled else "Off"))


func _on_fps_cap_selected(index: int, show_notification: bool = true) -> void:
	var caps := [30, 60, 120, 144, 0]
	settings_fps_cap_index = clampi(index, 0, caps.size() - 1)
	Engine.max_fps = caps[settings_fps_cap_index]
	_save_menu_profile()
	if show_notification:
		if Engine.max_fps == 0:
			_set_notification("FPS Cap: Uncapped")
		else:
			_set_notification("FPS Cap: %d" % Engine.max_fps)


func _on_master_volume_changed(value: float) -> void:
	_apply_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	_apply_music_volume(value)


func _apply_master_volume(value: float, show_notification: bool = true) -> void:
	settings_master_volume = clampf(value, 0.0, 100.0)
	_set_bus_volume("Master", settings_master_volume)
	_save_menu_profile()
	if show_notification:
		_set_notification("Master Volume: %d%%" % int(settings_master_volume))


func _apply_music_volume(value: float, show_notification: bool = true) -> void:
	settings_music_volume = clampf(value, 0.0, 100.0)
	if gamemanager != null and gamemanager.has_method("set_music_volume_percent"):
		gamemanager.set_music_volume_percent(settings_music_volume)
	else:
		_set_bus_volume("Music", settings_music_volume)
	_save_menu_profile()
	if show_notification:
		_set_notification("Music Volume: %d%%" % int(settings_music_volume))


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
		Screen.SHOP:
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
	var seen: Dictionary = {}
	var dir := DirAccess.open(levels_root_path)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var entry_name := dir.get_next()
			if entry_name.is_empty():
				break
			if entry_name.begins_with("."):
				continue
			if dir.current_is_dir():
				seen[entry_name] = true
				worlds.append({"name": entry_name, "path": "%s/%s" % [levels_root_path, entry_name]})
		dir.list_dir_end()

	for world_name in WORLD_LEVEL_CATALOG.keys():
		if seen.has(world_name):
			continue
		var paths := _get_catalog_level_paths_for_world_name(world_name)
		if paths.is_empty():
			continue
		worlds.append({"name": world_name, "path": "%s/%s" % [levels_root_path, world_name]})

	worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return worlds


func _get_levels_for_world(world_path: String) -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	var dir := DirAccess.open(world_path)
	if dir != null:
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

	if levels.is_empty():
		for level_path in _get_catalog_level_paths_for_world_name(world_path.get_file()):
			var level_name := level_path.get_file().trim_suffix(".tscn")
			levels.append({"name": level_name, "path": level_path})

	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	return levels


func _get_catalog_level_paths_for_world_name(world_name: String) -> Array[String]:
	var result: Array[String] = []
	if not WORLD_LEVEL_CATALOG.has(world_name):
		return result

	for scene: PackedScene in WORLD_LEVEL_CATALOG[world_name]:
		if scene == null:
			continue
		var path := scene.resource_path
		if path.is_empty():
			continue
		if not ResourceLoader.exists(path):
			continue
		result.append(path)

	result.sort()
	return result


func _cache_cosmetic_options() -> void:
	var gun_files := _scan_files("res://assets/visual/magnum", ["png", "jpg", "jpeg"])
	var bullet_files := _scan_files("res://assets/visual/Bullet", ["png", "jpg", "jpeg"])

	gun_skin_paths.clear()
	for file_name in gun_files:
		gun_skin_paths.append("res://assets/visual/magnum/%s" % file_name)

	bullet_skin_paths.clear()
	for file_name in bullet_files:
		bullet_skin_paths.append("res://assets/visual/Bullet/%s" % file_name)

	gun_skin_options = ["Default Gun Skin"]
	for path in gun_skin_paths:
		gun_skin_options.append(_display_name_for_skin_path(path, "Default Gun Skin"))

	bullet_skin_options = ["Default Bullet Skin"]
	for path in bullet_skin_paths:
		bullet_skin_options.append(_display_name_for_skin_path(path, "Default Bullet Skin"))

	_sanitize_selected_cosmetics()


func _sanitize_selected_cosmetics() -> void:
	if not selected_gun_skin_path.is_empty() and not gun_skin_paths.has(selected_gun_skin_path):
		selected_gun_skin_path = ""
	if not _is_gun_skin_available_for_player(selected_gun_skin_path):
		selected_gun_skin_path = ""
	if not selected_bullet_skin_path.is_empty() and not bullet_skin_paths.has(selected_bullet_skin_path):
		selected_bullet_skin_path = ""
	if not _is_bullet_skin_available_for_player(selected_bullet_skin_path):
		selected_bullet_skin_path = ""
	if not bullet_trail_options.has(selected_bullet_trail):
		selected_bullet_trail = bullet_trail_options[0]
	if not _is_bullet_trail_available_for_player(selected_bullet_trail):
		selected_bullet_trail = bullet_trail_options[0]


func _display_name_for_skin_path(path: String, default_label: String) -> String:
	if path.is_empty():
		return default_label
	return path.get_file().get_basename().replace("_", " ")


func _get_skin_option_index(paths: Array[String], selected_path: String) -> int:
	if selected_path.is_empty():
		return 0
	var idx := paths.find(selected_path)
	if idx == -1:
		return 0
	return idx + 1


func _get_skin_path_from_option_index(paths: Array[String], option_index: int) -> String:
	if option_index <= 0:
		return ""
	var idx := option_index - 1
	if idx < 0 or idx >= paths.size():
		return ""
	return paths[idx]


func _apply_selected_cosmetics_to_game_manager() -> void:
	if gamemanager == null:
		return
	if gamemanager.has_method("set_selected_cosmetics"):
		gamemanager.set_selected_cosmetics(selected_gun_skin_path, selected_bullet_skin_path, selected_bullet_trail)


func _add_shop_item_button(item_name: String, item_id: String, cost: int, balance_label: Label, focus := false) -> void:
	var owned := _shop_item_owned(item_id)
	var button := _add_menu_button(_format_shop_item_button_text(item_name, cost, owned), func() -> void:
		if _shop_item_owned(item_id):
			_set_notification("%s is already owned." % item_name)
			return

		var result := _purchase_shop_item(item_id, cost)
		if not bool(result.get("ok", false)):
			_set_notification("Not enough credits for %s." % item_name)
			return

		if item_id == "credits_pack_small":
			if gamemanager != null and gamemanager.has_method("add_shop_currency"):
				gamemanager.add_shop_currency(600)
			result["balance"] = _get_shop_balance()

		balance_label.text = "Credits: %d" % int(result.get("balance", _get_shop_balance()))
		if item_id == "trail_neon_unlock":
			_set_notification("Purchased Neon Trail. It is now selectable in Gun Locker.")
		elif item_id == "trail_smoke_unlock":
			_set_notification("Purchased Smoke Trail. It is now selectable in Gun Locker.")
		elif item_id == "credits_pack_small":
			_set_notification("Purchased Starter Credits Pack. +600 credits granted.")
		elif item_id == "gun_skin_bundle_test":
			_set_notification("Purchased Gun Test Skin Bundle. Test gun skins unlocked.")
		elif item_id == "bullet_skin_bundle_test":
			_set_notification("Purchased Bullet Test Skin Bundle. Test bullet skins unlocked.")
		else:
			_set_notification("Purchased %s." % item_name)
		_show_shop()
	, focus)
	button.disabled = owned


func _format_shop_item_button_text(item_name: String, cost: int, owned: bool) -> String:
	if owned:
		return "%s  |  OWNED" % item_name
	return "%s  |  %d Credits" % [item_name, cost]


func _get_shop_balance() -> int:
	if gamemanager != null and gamemanager.has_method("get_shop_currency"):
		return int(gamemanager.get_shop_currency())
	return 0


func _purchase_shop_item(item_id: String, cost: int) -> Dictionary:
	if gamemanager == null or not gamemanager.has_method("purchase_shop_item"):
		return {"ok": false, "reason": "shop_unavailable", "balance": 0}
	var result: Variant = gamemanager.purchase_shop_item(item_id, cost)
	if result is Dictionary:
		return result
	return {"ok": false, "reason": "shop_unavailable", "balance": _get_shop_balance()}


func _shop_item_owned(item_id: String) -> bool:
	if gamemanager == null or not gamemanager.has_method("has_shop_item"):
		return false
	return bool(gamemanager.has_shop_item(item_id))


func _claim_daily_credits_from_shop(amount: int) -> Dictionary:
	if gamemanager == null or not gamemanager.has_method("claim_daily_shop_credits"):
		return {"ok": false, "reason": "shop_unavailable", "amount": 0, "balance": 0}
	var result: Variant = gamemanager.claim_daily_shop_credits(amount)
	if result is Dictionary:
		return result
	return {"ok": false, "reason": "shop_unavailable", "amount": 0, "balance": _get_shop_balance()}


func _daily_claim_already_used_today() -> bool:
	if gamemanager == null or not gamemanager.has_method("get_last_daily_claim_date"):
		return false
	return String(gamemanager.get_last_daily_claim_date()) == Time.get_date_string_from_system()


func _is_bullet_trail_available_for_player(style: String) -> bool:
	if style == "Default Trail":
		return true
	if gamemanager == null or not gamemanager.has_method("is_bullet_trail_unlocked"):
		return style == "Tracer"
	return bool(gamemanager.is_bullet_trail_unlocked(style))


func _is_gun_skin_available_for_player(path: String) -> bool:
	if path.is_empty():
		return true
	if gamemanager == null or not gamemanager.has_method("is_gun_skin_unlocked"):
		return true
	return bool(gamemanager.is_gun_skin_unlocked(path))


func _is_bullet_skin_available_for_player(path: String) -> bool:
	if path.is_empty():
		return true
	if gamemanager == null or not gamemanager.has_method("is_bullet_skin_unlocked"):
		return true
	return bool(gamemanager.is_bullet_skin_unlocked(path))


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
