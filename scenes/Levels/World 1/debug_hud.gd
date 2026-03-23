extends CanvasLayer

@onready var label: Label = $Readout
const RESET_GUN_COST := 500

# Toggle to temporarily disable the reset control for testing
var reset_enabled: bool = true

var _latest_score: int = 0
var _latest_state: int = 0
var _prompt_title: String = ""
var _prompt_message: String = ""
var _prompt_options: Array = []
var _prompt_payload: Dictionary = {}

var _prompt_panel: PanelContainer
var _prompt_title_label: Label
var _prompt_message_label: Label
var _prompt_buttons: VBoxContainer
var _screen_fade: ColorRect
var _prompt_transition_running: bool = false
var _scene_transition_running: bool = false
var _state_label: Label
var _controls_label: Label
var _reset_button: Button
var _reset_feedback_label: Label


func _ready() -> void:
	# Keep HUD active during gameplay and while the scene tree is paused for prompt interaction.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_readout_ui()
	_setup_controls_legend()
	_setup_reset_button()
	_setup_prompt_ui()

	if gamemanager == null:
		_refresh_hud_text()
		return

	gamemanager.score_changed.connect(_on_score_changed)
	gamemanager.state_changed.connect(_on_state_changed)
	gamemanager.victory_prompt_requested.connect(_on_victory_prompt_requested)
	gamemanager.game_over_prompt_requested.connect(_on_game_over_prompt_requested)
	gamemanager.run_reset.connect(_on_run_reset)

	_on_score_changed(int(gamemanager.score))
	_on_state_changed(int(gamemanager.state))

func _on_score_changed(value: int) -> void:
	_latest_score = value
	_refresh_hud_text()


func _on_state_changed(value: int) -> void:
	_latest_state = value
	_refresh_hud_text()
	if value == 0:
		_hide_prompt()
		_set_gameplay_paused(false)


func _on_victory_prompt_requested(payload: Dictionary) -> void:
	_prompt_title = str(payload.get("title", "Victory"))
	_prompt_message = "Score: %d | Stars: %d" % [
		int(payload.get("score", _latest_score)),
		int(payload.get("stars", 0))
	]
	_prompt_options = payload.get("options", [])
	_prompt_payload = payload
	await _show_prompt_with_gameplay_fade()


func _on_game_over_prompt_requested(payload: Dictionary) -> void:
	_prompt_title = str(payload.get("title", "Game Over"))
	_prompt_message = str(payload.get("message", ""))
	_prompt_options = payload.get("options", [])
	_prompt_payload = payload
	_show_prompt()


func _on_run_reset() -> void:
	_prompt_title = ""
	_prompt_message = ""
	_prompt_options = []
	_prompt_payload = {}
	_hide_prompt()


func _setup_readout_ui() -> void:
	if label == null:
		return
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_size_override("font_size", 52)

	_state_label = Label.new()
	_state_label.name = "StateReadout"
	_state_label.offset_left = label.offset_left
	_state_label.offset_top = 118.0
	_state_label.offset_right = 520.0
	_state_label.offset_bottom = 160.0
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_state_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_state_label.add_theme_font_size_override("font_size", 22)
	add_child(_state_label)


func _setup_controls_legend() -> void:
	_controls_label = Label.new()
	_controls_label.name = "ControlsLegend"
	_controls_label.anchor_left = 0.0
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_right = 0.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.offset_left = 20.0
	_controls_label.offset_top = -132.0
	_controls_label.offset_right = 430.0
	_controls_label.offset_bottom = -20.0
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_controls_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_label.add_theme_font_size_override("font_size", 16)
	_controls_label.text = "Controls\nLMB/Space: Fire\nShift: Slow Time (Aim)\nR: Reset Gun (-500)\nEsc: Pause / Back"
	add_child(_controls_label)


func _setup_reset_button() -> void:
	_reset_button = Button.new()
	_reset_button.name = "ResetGunButton"
	_reset_button.anchor_left = 1.0
	_reset_button.anchor_top = 0.0
	_reset_button.anchor_right = 1.0
	_reset_button.anchor_bottom = 0.0
	_reset_button.offset_left = -220.0
	_reset_button.offset_top = 20.0
	_reset_button.offset_right = -20.0
	_reset_button.offset_bottom = 64.0
	_reset_button.text = "Reset Gun [R] (-500)"
	_reset_button.add_theme_font_size_override("font_size", 20)
	_reset_button.pressed.connect(_on_reset_button_pressed)
	_reset_button.disabled = not reset_enabled
	add_child(_reset_button)

	_reset_feedback_label = Label.new()
	_reset_feedback_label.name = "ResetGunFeedback"
	_reset_feedback_label.anchor_left = 1.0
	_reset_feedback_label.anchor_top = 0.0
	_reset_feedback_label.anchor_right = 1.0
	_reset_feedback_label.anchor_bottom = 0.0
	_reset_feedback_label.offset_left = -280.0
	_reset_feedback_label.offset_top = 66.0
	_reset_feedback_label.offset_right = -20.0
	_reset_feedback_label.offset_bottom = 96.0
	_reset_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reset_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reset_feedback_label.add_theme_font_size_override("font_size", 16)
	_reset_feedback_label.modulate = Color(1.0, 0.45, 0.45, 0.0)
	add_child(_reset_feedback_label)


func _refresh_hud_text() -> void:
	if label != null:
		label.text = "%06d" % _latest_score
	if _state_label != null:
		_state_label.text = "STATE: %s" % _state_to_text(_latest_state)
	if _reset_button != null:
		var can_reset := _latest_score >= RESET_GUN_COST and _latest_state == 0
		_reset_button.disabled = not can_reset


func _setup_prompt_ui() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "PromptPanel"
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_top = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.anchor_bottom = 0.5
	_prompt_panel.offset_left = -260.0
	_prompt_panel.offset_top = -170.0
	_prompt_panel.offset_right = 260.0
	_prompt_panel.offset_bottom = 170.0
	_prompt_panel.visible = false
	add_child(_prompt_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_prompt_panel.add_child(box)

	_prompt_title_label = Label.new()
	_prompt_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_title_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_prompt_title_label)

	_prompt_message_label = Label.new()
	_prompt_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_prompt_message_label)

	_prompt_buttons = VBoxContainer.new()
	_prompt_buttons.add_theme_constant_override("separation", 6)
	box.add_child(_prompt_buttons)

	_screen_fade = ColorRect.new()
	_screen_fade.name = "PromptFade"
	_screen_fade.anchor_left = 0.0
	_screen_fade.anchor_top = 0.0
	_screen_fade.anchor_right = 1.0
	_screen_fade.anchor_bottom = 1.0
	_screen_fade.offset_left = 0.0
	_screen_fade.offset_top = 0.0
	_screen_fade.offset_right = 0.0
	_screen_fade.offset_bottom = 0.0
	_screen_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_screen_fade.visible = false
	add_child(_screen_fade)


func _show_prompt() -> void:
	if _prompt_panel == null:
		return
	_show_prompt_content()
	_set_gameplay_paused(true)


func _show_prompt_content() -> void:
	if _prompt_panel == null:
		return

	_prompt_title_label.text = _prompt_title
	_prompt_message_label.text = _prompt_message
	_rebuild_prompt_buttons()
	_prompt_panel.visible = true


func _show_prompt_with_gameplay_fade() -> void:
	if _prompt_transition_running:
		return
	_prompt_transition_running = true
	await _fade_prompt_screen_to(1.0, 0.22)
	_show_prompt_content()
	await _fade_prompt_screen_to(0.0, 0.22)
	_set_gameplay_paused(true)
	_prompt_transition_running = false


func _hide_prompt() -> void:
	if _prompt_panel == null:
		return
	_prompt_panel.visible = false
	_set_gameplay_paused(false)


func _set_gameplay_paused(active: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = active


func _fade_prompt_screen_to(target_alpha: float, duration: float) -> void:
	if _screen_fade == null:
		return
	_screen_fade.visible = true
	if duration <= 0.0:
		_screen_fade.color = Color(0.0, 0.0, 0.0, clampf(target_alpha, 0.0, 1.0))
		if target_alpha <= 0.001:
			_screen_fade.visible = false
		return

	var tween := create_tween()
	tween.tween_property(_screen_fade, "color:a", clampf(target_alpha, 0.0, 1.0), duration)
	await tween.finished
	if target_alpha <= 0.001:
		_screen_fade.visible = false


func _rebuild_prompt_buttons() -> void:
	for child in _prompt_buttons.get_children():
		child.queue_free()

	var first_button: Button = null
	for option in _prompt_options:
		var option_key := String(option)
		var button := Button.new()
		button.text = _option_to_button_text(option_key)
		button.custom_minimum_size = Vector2(320, 40)
		button.pressed.connect(_on_prompt_option_pressed.bind(option_key))

		if option_key == "continue_next_level":
			var next_level_path := String(_prompt_payload.get("next_level_path", ""))
			if next_level_path.is_empty():
				button.disabled = true

		_prompt_buttons.add_child(button)
		if first_button == null and not button.disabled:
			first_button = button

	if first_button != null:
		first_button.grab_focus()


func _option_to_button_text(option_key: String) -> String:
	match option_key:
		"watch_ad_continue":
			return "Watch Ad: Continue"
		"retry_level":
			return "Retry Level"
		"world_select":
			return "World Select"
		"main_menu":
			return "Main Menu"
		"watch_ad_double_rewards":
			return "Watch Ad: Double Rewards"
		"continue_next_level":
			return "Continue to Next Level"
		_:
			return option_key.capitalize()


func _on_prompt_option_pressed(option_key: String) -> void:
	if gamemanager == null:
		return
	if gamemanager.has_method("play_ui_interaction"):
		gamemanager.play_ui_interaction()

	match option_key:
		"watch_ad_continue":
			if gamemanager.watch_ad_continue_from_game_over():
				_hide_prompt()
		"retry_level":
			await _run_scene_transition_option(option_key)
		"world_select":
			await _run_scene_transition_option(option_key)
		"main_menu":
			await _run_scene_transition_option(option_key)
		"watch_ad_double_rewards":
			if gamemanager.watch_ad_double_victory_rewards():
				_prompt_options = _prompt_options.filter(func(value: Variant) -> bool:
					return String(value) != "watch_ad_double_rewards"
				)
				_prompt_message = "%s\nRewards doubled." % _prompt_message
				_show_prompt()
		"continue_next_level":
			await _run_scene_transition_option(option_key)


func _run_scene_transition_option(option_key: String) -> void:
	if _scene_transition_running:
		return
	_scene_transition_running = true

	var action := Callable()
	var fade_out_music := true
	var keep_level_music_until_loop_end := false

	match option_key:
		"retry_level":
			action = Callable(gamemanager, "restart_level")
		"world_select":
			action = Callable(gamemanager, "return_to_world_select")
		"main_menu":
			action = Callable(gamemanager, "return_to_main_menu")
			fade_out_music = false
			keep_level_music_until_loop_end = true
		"continue_next_level":
			var next_level_path := String(_prompt_payload.get("next_level_path", ""))
			if next_level_path.is_empty():
				_prompt_message = "%s\nNo next level available in this world." % _prompt_message
				_show_prompt()
				_scene_transition_running = false
				return
			action = Callable(gamemanager, "continue_to_next_level")
		_:
			_scene_transition_running = false
			return

	_set_gameplay_paused(false)
	if gamemanager.has_method("run_screen_transition"):
		await gamemanager.run_screen_transition(action, 0.32, 0.24, fade_out_music, keep_level_music_until_loop_end)
	elif action.is_valid():
		action.call()

	_scene_transition_running = false


func _state_to_text(value: int) -> String:
	match value:
		0:
			return "PLAYING"
		1:
			return "PAUSED"
		2:
			return "LEVEL_COMPLETE"
		3:
			return "GAME_OVER"
		_:
			return "UNKNOWN"


func _unhandled_input(event: InputEvent) -> void:
	if not reset_enabled:
		return

	if event.is_action_pressed("reset_gun"):
		_try_reset_player_gun()
		get_viewport().set_input_as_handled()


func _on_reset_button_pressed() -> void:
	_try_reset_player_gun()


func _try_reset_player_gun() -> void:
	if gamemanager == null:
		return
	if _latest_state != 0:
		return
	if _latest_score < RESET_GUN_COST:
		_show_reset_not_enough_score_feedback()
		return
	if gamemanager.has_method("play_ui_interaction"):
		gamemanager.play_ui_interaction()
	if gamemanager.has_method("try_reset_player_gun"):
		gamemanager.try_reset_player_gun()


func _show_reset_not_enough_score_feedback() -> void:
	if _reset_feedback_label != null:
		var deficit := maxi(0, RESET_GUN_COST - _latest_score)
		_reset_feedback_label.text = "Need +%d more score" % deficit
		_reset_feedback_label.modulate = Color(1.0, 0.45, 0.45, 0.0)
		var feedback_tween := create_tween()
		feedback_tween.tween_property(_reset_feedback_label, "modulate:a", 1.0, 0.08)
		feedback_tween.tween_interval(0.55)
		feedback_tween.tween_property(_reset_feedback_label, "modulate:a", 0.0, 0.2)

	if _reset_button != null:
		_reset_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		var button_tween := create_tween()
		button_tween.tween_property(_reset_button, "modulate", Color(1.0, 0.68, 0.68, 1.0), 0.06)
		button_tween.tween_property(_reset_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.16)
