extends Control

var _games_list : VBoxContainer
var _ip_input   : LineEdit
var _connect_btn: Button
var _refresh_btn: Button
var _back_btn   : Button
var _status     : Label
var _audio_hover: AudioStreamPlayer
var _audio_click: AudioStreamPlayer

var _discovered:    Dictionary = {}  # address → info dict
var _relay_shown:   Dictionary = {}  # code → true, relay rooms already in list
var _connecting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_nodes()
	_apply_styles()
	_prewarm_audio()

	_connect_btn.pressed.connect(_on_connect_pressed)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	_back_btn.pressed.connect(_on_back_pressed)

	for btn: Button in [_connect_btn, _refresh_btn, _back_btn]:
		btn.mouse_entered.connect(_on_hover.bind(btn))

	NetworkManager.game_found.connect(_on_game_found)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.rooms_listed.connect(_on_rooms_listed)

	NetworkManager.start_discovery()
	NetworkManager.list_relay_rooms()
	_status.text = "Scanning for games..."


func _exit_tree() -> void:
	NetworkManager.stop_discovery()
	if NetworkManager.game_found.is_connected(_on_game_found):
		NetworkManager.game_found.disconnect(_on_game_found)
	if NetworkManager.connection_succeeded.is_connected(_on_connected):
		NetworkManager.connection_succeeded.disconnect(_on_connected)
	if NetworkManager.connection_failed.is_connected(_on_connect_failed):
		NetworkManager.connection_failed.disconnect(_on_connect_failed)
	if NetworkManager.rooms_listed.is_connected(_on_rooms_listed):
		NetworkManager.rooms_listed.disconnect(_on_rooms_listed)


func _cache_nodes() -> void:
	_games_list  = $Panel/VBox/Scroll/GamesList
	_ip_input    = $Panel/VBox/ManualRow/IPInput
	_connect_btn = $Panel/VBox/ManualRow/ConnectBtn
	_refresh_btn = $Panel/VBox/RefreshBtn
	_back_btn    = $Panel/VBox/BackBtn
	_status      = $StatusLabel
	_audio_hover = $AudioHover
	_audio_click = $AudioClick


func _on_game_found(info: Dictionary) -> void:
	var addr: String = info.get("address", "")
	if _discovered.has(addr):
		var entry: HBoxContainer = _games_list.get_node_or_null(addr)
		if is_instance_valid(entry):
			(entry.get_child(0) as Label).text = _entry_label(info)
		return

	_discovered[addr] = info
	if _status.text.begins_with("Scanning"):
		_status.text = ""

	var row := HBoxContainer.new()
	row.name = addr
	row.add_theme_constant_override("separation", 10)

	var lbl := Label.new()
	lbl.text = _entry_label(info)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color("#FFD0A0"))
	lbl.add_theme_color_override("font_outline_color", Color("#18000A"))
	lbl.add_theme_constant_override("outline_size", 1)

	var btn := Button.new()
	btn.text = "JOIN"
	_style_btn(btn, 80, 36)
	btn.pressed.connect(_join_addr.bind(addr))
	btn.mouse_entered.connect(_on_hover.bind(btn))

	row.add_child(lbl)
	row.add_child(btn)
	_games_list.add_child(row)


func _on_rooms_listed(rooms: Array) -> void:
	for room: Dictionary in rooms:
		var code: String = room.get("code", "")
		if code.is_empty() or _relay_shown.has(code):
			continue
		_relay_shown[code] = true
		if _status.text == "Scanning for games...":
			_status.text = ""

		var row := HBoxContainer.new()
		row.name = "relay_" + code
		row.add_theme_constant_override("separation", 10)

		var lbl := Label.new()
		lbl.text = _entry_label(room) + "  [online]"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color("#A0D4FF"))
		lbl.add_theme_color_override("font_outline_color", Color("#18000A"))
		lbl.add_theme_constant_override("outline_size", 1)

		var btn := Button.new()
		btn.text = "JOIN"
		_style_btn(btn, 80, 36)
		btn.pressed.connect(_join_relay.bind(code))
		btn.mouse_entered.connect(_on_hover.bind(btn))

		row.add_child(lbl)
		row.add_child(btn)
		_games_list.add_child(row)


func _entry_label(info: Dictionary) -> String:
	var code: String = info.get("code", "")
	var code_str := "  [%s]" % code if not code.is_empty() else ""
	return "%s's game%s   (%d/%d players)" % [
		info.get("host", "Unknown"),
		code_str,
		info.get("players", 0),
		info.get("max", NetworkManager.MAX_PLAYERS)
	]


func _join_addr(address: String) -> void:
	if _connecting:
		return
	_play_click()
	_connecting = true
	_status.text = "Connecting to %s..." % address
	_set_enabled(false)
	var err := NetworkManager.join_game(NetworkManager.local_name, address)
	if err != OK:
		_status.text = "Failed to connect."
		_connecting = false
		_set_enabled(true)


func _on_connect_pressed() -> void:
	_play_click()
	var raw := _ip_input.text.strip_edges()
	if raw.is_empty():
		_status.text = "Enter a room code or IP address."
		return
	# 6 uppercase-only chars → relay room code; anything else → direct IP/base-62
	if raw.length() == 6 and not raw.contains(".") and raw == raw.to_upper():
		_join_relay(raw)
	else:
		_join_addr(raw)


func _join_relay(code: String) -> void:
	if NetworkManager.RELAY_URL.is_empty():
		_status.text = "Relay not configured — use an IP address instead."
		return
	if _connecting:
		return
	_connecting = true
	_status.text = "Connecting via relay..."
	_set_enabled(false)
	var err := NetworkManager.join_game_relay(NetworkManager.local_name, code)
	if err != OK:
		_status.text = "Failed to connect."
		_connecting = false
		_set_enabled(true)


func _on_refresh_pressed() -> void:
	_play_click()
	_discovered.clear()
	_relay_shown.clear()
	for child in _games_list.get_children():
		child.queue_free()
	NetworkManager.stop_discovery()
	NetworkManager.start_discovery()
	NetworkManager.list_relay_rooms()
	_status.text = "Scanning for games..."


func _on_back_pressed() -> void:
	_play_click()
	NetworkManager.disconnect_all()
	await get_tree().create_timer(0.12).timeout
	get_tree().change_scene_to_file("res://scenes/ui/coop_name.tscn")


func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/dungeon/test_room.tscn")


func _on_connect_failed(reason: String) -> void:
	_status.text = reason
	_connecting = false
	_set_enabled(true)


func _set_enabled(val: bool) -> void:
	_connect_btn.disabled = not val
	_refresh_btn.disabled = not val
	_back_btn.disabled    = not val
	for row: Node in _games_list.get_children():
		if row.get_child_count() > 1:
			var btn := row.get_child(1)
			if btn is Button:
				(btn as Button).disabled = not val


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
	panel.offset_left   = -340.0
	panel.offset_right  =  340.0
	panel.offset_top    = -270.0
	panel.offset_bottom =  270.0

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#1A0000EE")
	ps.border_color = Color("#AA2200")
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", ps)

	($Panel/VBox as VBoxContainer).add_theme_constant_override("separation", 12)

	var title: Label = $Panel/VBox/TitleLabel
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#FF2200"))
	title.add_theme_color_override("font_outline_color", Color("#18000A"))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var scroll: ScrollContainer = $Panel/VBox/Scroll
	scroll.custom_minimum_size = Vector2(0, 220)

	var ip_lbl: Label = $Panel/VBox/ManualRow/IPLabel
	ip_lbl.add_theme_font_size_override("font_size", 14)
	ip_lbl.add_theme_color_override("font_color", Color("#CC8866"))

	_ip_input.add_theme_font_size_override("font_size", 16)
	_ip_input.placeholder_text = "Room code or IP..."

	for btn: Button in [_connect_btn, _refresh_btn, _back_btn]:
		_style_btn(btn, 120, 44)

	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color("#FF9966"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _style_btn(btn: Button, min_w: float, min_h: float) -> void:
	btn.custom_minimum_size = Vector2(min_w, min_h)
	btn.add_theme_font_size_override("font_size", 17)
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
	s.content_margin_left   = 10.0
	s.content_margin_right  = 10.0
	s.content_margin_top    = 4.0
	s.content_margin_bottom = 4.0
	if glow:
		s.shadow_color = Color(1.0, 0.25, 0.0, 0.55)
		s.shadow_size  = 8
	return s
