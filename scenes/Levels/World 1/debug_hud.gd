extends CanvasLayer

@onready var label: Label = $Readout

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


func _ready() -> void:
	_setup_prompt_ui()

	if gamemanager == null:
		return

	gamemanager.score_changed.connect(_on_score_changed)
	gamemanager.state_changed.connect(_on_state_changed)
	gamemanager.victory_prompt_requested.connect(_on_victory_prompt_requested)
	gamemanager.game_over_prompt_requested.connect(_on_game_over_prompt_requested)
	gamemanager.run_reset.connect(_on_run_reset)

	_on_score_changed(int(gamemanager.score))
	_on_state_changed(int(gamemanager.state))

func _process(_dt: float) -> void:
	var b: RigidBody3D = null

	if gamemanager != null and gamemanager.player_gun != null:
		b = gamemanager.player_gun

	# Fallback: search the current scene (safer than searching the Window root)
	if b == null:
		var root_scene := get_tree().get_current_scene()
		if root_scene == null and get_tree().get_root().get_child_count() > 0:
			root_scene = get_tree().get_root().get_child(0)
		if root_scene != null:
			var candidate: Node = _find_node_recursive(root_scene, "PlayerGun")
			if candidate != null:
				b = candidate as RigidBody3D

	if b == null:
		label.text = _build_hud_text("No gun found")
		return

	var telemetry := "ang_vel: %s\nlin_vel: %s\nrot(deg): %s" % [
		str(b.angular_velocity),
		str(b.linear_velocity),
		str(b.rotation_degrees)
	]
	label.text = _build_hud_text(telemetry)


func _on_score_changed(value: int) -> void:
	_latest_score = value


func _on_state_changed(value: int) -> void:
	_latest_state = value
	if value == 0:
		_hide_prompt()


func _on_victory_prompt_requested(payload: Dictionary) -> void:
	_prompt_title = str(payload.get("title", "Victory"))
	_prompt_message = "Score: %d | Stars: %d" % [
		int(payload.get("score", _latest_score)),
		int(payload.get("stars", 0))
	]
	_prompt_options = payload.get("options", [])
	_prompt_payload = payload
	_show_prompt()


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


func _build_hud_text(telemetry: String) -> String:
	var state_label := _state_to_text(_latest_state)
	return "Score: %d\nState: %s\n\n%s" % [_latest_score, state_label, telemetry]


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


func _show_prompt() -> void:
	if _prompt_panel == null:
		return

	_prompt_title_label.text = _prompt_title
	_prompt_message_label.text = _prompt_message
	_rebuild_prompt_buttons()
	_prompt_panel.visible = true


func _hide_prompt() -> void:
	if _prompt_panel == null:
		return
	_prompt_panel.visible = false


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

	match option_key:
		"watch_ad_continue":
			if gamemanager.watch_ad_continue_from_game_over():
				_hide_prompt()
		"retry_level":
			gamemanager.restart_level()
		"world_select":
			gamemanager.return_to_world_select()
		"main_menu":
			gamemanager.return_to_main_menu()
		"watch_ad_double_rewards":
			if gamemanager.watch_ad_double_victory_rewards():
				_prompt_options = _prompt_options.filter(func(value: Variant) -> bool:
					return String(value) != "watch_ad_double_rewards"
				)
				_prompt_message = "%s\nRewards doubled." % _prompt_message
				_show_prompt()
		"continue_next_level":
			if not gamemanager.continue_to_next_level():
				_prompt_message = "%s\nNo next level available in this world." % _prompt_message
				_show_prompt()


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

func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found: Node = _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null
