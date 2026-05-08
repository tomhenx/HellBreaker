extends Control

var _name_input   : LineEdit
var _host_btn     : Button
var _join_btn     : Button
var _back_btn     : Button
var _public_check : CheckBox
var _ff_check     : CheckBox
var _status       : Label
var _audio_hover: AudioStreamPlayer
var _audio_click: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_nodes()
	_apply_styles()
	_prewarm_audio()

	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_back_btn.pressed.connect(_on_back_pressed)

	for btn: Button in [_host_btn, _join_btn, _back_btn]:
		btn.mouse_entered.connect(_on_hover.bind(btn))

	_name_input.text = NetworkManager.local_name if not NetworkManager.local_name.is_empty() else "Player"
	_name_input.grab_focus()


func _cache_nodes() -> void:
	_name_input  = $Panel/VBox/NameInput
	_host_btn     = $Panel/VBox/HBox/HostBtn
	_join_btn     = $Panel/VBox/HBox/JoinBtn
	_public_check = $Panel/VBox/PublicCheck
	_ff_check     = $Panel/VBox/FriendlyFireCheck
	_back_btn     = $Panel/VBox/BackBtn
	_status      = $Panel/VBox/StatusLabel
	_audio_hover = $AudioHover
	_audio_click = $AudioClick


func _get_name() -> String:
	return _name_input.text.strip_edges()


func _on_host_pressed() -> void:
	_play_click()
	var pname := _get_name()
	if pname.is_empty():
		_status.text = "Please enter a name first."
		return
	_set_enabled(false)
	NetworkManager.friendly_fire = _ff_check.button_pressed

	if not NetworkManager.RELAY_URL.is_empty():
		_status.text = "Connecting to relay..."
		var err := NetworkManager.host_game_relay(pname, _public_check.button_pressed)
		if err != OK:
			_status.text = "Could not reach relay server."
			_set_enabled(true)
			return
		NetworkManager.relay_ready.connect(_on_relay_ready, CONNECT_ONE_SHOT)
	else:
		_status.text = "Starting server..."
		var err := NetworkManager.host_game(pname)
		if err != OK:
			_status.text = "Failed to start (port %d busy?)." % NetworkManager.GAME_PORT
			_set_enabled(true)
			return
		await _show_code("Room code: %s  |  IP: %s" % [NetworkManager.room_code, NetworkManager.local_ip])
		get_tree().change_scene_to_file("res://scenes/dungeon/test_room.tscn")


func _on_relay_ready() -> void:
	await _show_code("Room code: %s  (internet)" % NetworkManager.room_code)
	get_tree().change_scene_to_file("res://scenes/dungeon/test_room.tscn")


func _show_code(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color("#88FF88"))
	await get_tree().create_timer(1.8).timeout


func _on_join_pressed() -> void:
	_play_click()
	var pname := _get_name()
	if pname.is_empty():
		_status.text = "Please enter a name first."
		return
	NetworkManager.local_name = pname
	await get_tree().create_timer(0.12).timeout
	get_tree().change_scene_to_file("res://scenes/ui/coop_join.tscn")


func _on_back_pressed() -> void:
	_play_click()
	NetworkManager.disconnect_all()
	await get_tree().create_timer(0.12).timeout
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _set_enabled(val: bool) -> void:
	_host_btn.disabled = not val
	_join_btn.disabled = not val
	_back_btn.disabled = not val


func _on_hover(btn: Button) -> void:
	if is_instance_valid(_audio_hover):
		_audio_hover.stop()
		_audio_hover.play()
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.07)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.07)


func _play_click() -> void:
	if is_instance_valid(_audio_click):
		_audio_click.play()


func _prewarm_audio() -> void:
	for p: AudioStreamPlayer in [_audio_hover, _audio_click]:
		if is_instance_valid(p) and p.stream != null:
			var vol := p.volume_db
			p.volume_db = -80.0
			p.play()
			p.stop()
			p.volume_db = vol


func _apply_styles() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg: ColorRect = $BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.02, 0.02, 0.94)

	var panel: PanelContainer = $Panel
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -230.0
	panel.offset_right  =  230.0
	panel.offset_top    = -195.0
	panel.offset_bottom =  195.0

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#1A0000EE")
	ps.border_color = Color("#AA2200")
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", ps)

	var vbox: VBoxContainer = $Panel/VBox
	vbox.add_theme_constant_override("separation", 14)

	var title: Label = $Panel/VBox/TitleLabel
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#FF2200"))
	title.add_theme_color_override("font_outline_color", Color("#18000A"))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var name_lbl: Label = $Panel/VBox/NameLabel
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color("#CC8866"))

	var input: LineEdit = $Panel/VBox/NameInput
	input.add_theme_font_size_override("font_size", 20)

	var hbox: HBoxContainer = $Panel/VBox/HBox
	hbox.add_theme_constant_override("separation", 16)

	for btn: Button in [_host_btn, _join_btn]:
		_style_btn(btn, 180, 54)
	_style_btn(_back_btn, 460, 46)
	_back_btn.custom_minimum_size = Vector2(0, 46)

	_public_check.add_theme_font_size_override("font_size", 14)
	_public_check.add_theme_color_override("font_color", Color("#88CCFF"))

	_ff_check.add_theme_font_size_override("font_size", 14)
	_ff_check.add_theme_color_override("font_color", Color("#CC8866"))

	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("#FF6666"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _style_btn(btn: Button, min_w: float, min_h: float) -> void:
	btn.custom_minimum_size = Vector2(min_w, min_h)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#FFD0A0"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("#FF7700"))
	btn.add_theme_color_override("font_outline_color", Color("#18000A"))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_stylebox_override("normal",  _make_style(Color("#2A0000"), Color("#882200"), false))
	btn.add_theme_stylebox_override("hover",   _make_style(Color("#5A0000"), Color("#FF4400"), true))
	btn.add_theme_stylebox_override("pressed", _make_style(Color("#160000"), Color("#CC2200"), false))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())


func _make_style(bg: Color, border: Color, glow: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.content_margin_left   = 12.0
	s.content_margin_right  = 12.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	if glow:
		s.shadow_color = Color(1.0, 0.25, 0.0, 0.55)
		s.shadow_size  = 8
	return s
