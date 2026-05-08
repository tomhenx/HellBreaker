class_name PauseMenu
extends Control

signal resumed
signal quit_to_menu_requested

var solo_mode: bool = true

var _resume_btn: Button
var _quit_btn: Button
var _audio_hover: AudioStreamPlayer
var _audio_click: AudioStreamPlayer
var _is_paused: bool = false


func _ready() -> void:
	# ALWAYS so we catch the first Escape (game running) and second (game paused)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_resume_btn   = $Panel/VBox/ResumeBtn
	_quit_btn     = $Panel/VBox/QuitBtn
	_audio_hover  = $AudioHover
	_audio_click  = $AudioClick

	_prewarm_audio()
	_setup_styles()

	_resume_btn.pressed.connect(_on_resume_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)

	for btn: Button in [_resume_btn, _quit_btn]:
		btn.mouse_entered.connect(_on_btn_hover.bind(btn))


func _unhandled_input(event: InputEvent) -> void:
	if not solo_mode:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _is_paused:
			_do_resume()
		else:
			_do_pause()


# ── Pause / Resume ────────────────────────────────────────────────────────────

func _do_pause() -> void:
	_is_paused = true
	visible = true
	get_tree().paused = true
	_resume_btn.grab_focus()


func _do_resume() -> void:
	_is_paused = false
	visible = false
	get_tree().paused = false
	resumed.emit()


# ── Styles ────────────────────────────────────────────────────────────────────

func _setup_styles() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel: PanelContainer = $Panel
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -160.0
	panel.offset_right  =  160.0
	panel.offset_top    = -130.0
	panel.offset_bottom =  130.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#1A0000E6")
	panel_style.border_color = Color("#AA2200")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)

	var title_label: Label = $Panel/VBox/TitleLabel
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color("#FF2200"))
	title_label.add_theme_color_override("font_outline_color", Color("#18000A"))
	title_label.add_theme_constant_override("outline_size", 4)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	for btn: Button in [_resume_btn, _quit_btn]:
		_apply_btn_style(btn)


func _apply_btn_style(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(280, 50)
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
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	if glow:
		s.shadow_color = Color(1.0, 0.25, 0.0, 0.55)
		s.shadow_size = 8
	return s


# ── Audio ─────────────────────────────────────────────────────────────────────

func _prewarm_audio() -> void:
	for p: AudioStreamPlayer in [_audio_hover, _audio_click]:
		if is_instance_valid(p) and p.stream != null:
			var vol := p.volume_db
			p.volume_db = -80.0
			p.play()
			p.stop()
			p.volume_db = vol


func _on_btn_hover(btn: Button) -> void:
	if is_instance_valid(_audio_hover):
		_audio_hover.stop()
		_audio_hover.play()
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.07)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.07)


# ── Button Handlers ───────────────────────────────────────────────────────────

func _on_resume_pressed() -> void:
	if is_instance_valid(_audio_click):
		_audio_click.play()
	await get_tree().create_timer(0.1).timeout
	_do_resume()


func _on_quit_pressed() -> void:
	if is_instance_valid(_audio_click):
		_audio_click.play()
	get_tree().paused = false
	await get_tree().create_timer(0.12).timeout
	quit_to_menu_requested.emit()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
