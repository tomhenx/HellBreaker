class_name MainMenu
extends Control

const BG_PATH    := "res://assets/sprites/ui/menu_background.png"
const LOGO_PATH  := "res://assets/sprites/ui/title_logo.png"

var _bg: TextureRect
var _overlay: ColorRect
var _title: TextureRect
var _tagline: Label
var _buttons_box: VBoxContainer
var _solo_btn: Button
var _coop_btn: Button
var _settings_btn: Button
var _exit_btn: Button
var _version_label: Label
var _audio_hover: AudioStreamPlayer
var _audio_click: AudioStreamPlayer
var _left_flame: CPUParticles2D
var _right_flame: CPUParticles2D
var _center_flame: CPUParticles2D


func _ready() -> void:
	_cache_nodes()
	_load_textures()
	_setup_layout()
	_style_tagline()
	_style_buttons()
	_style_version()
	_setup_particles()
	_connect_buttons()
	_prewarm_audio()
	await get_tree().process_frame
	_play_entrance()
	MusicManager.play_menu_music()


func _cache_nodes() -> void:
	_bg            = $BG
	_overlay       = $DarkOverlay
	_title         = $TitleLogo
	_tagline       = $TaglineLabel
	_buttons_box   = $ButtonsVBox
	_solo_btn      = $ButtonsVBox/SoloBtn
	_coop_btn      = $ButtonsVBox/CoopBtn
	_settings_btn  = $ButtonsVBox/SettingsBtn
	_exit_btn      = $ButtonsVBox/ExitBtn
	_version_label = $VersionLabel
	_audio_hover   = $AudioHover
	_audio_click   = $AudioClick
	_left_flame    = $LeftFlame
	_right_flame   = $RightFlame
	_center_flame  = $CenterFlame


func _load_textures() -> void:
	var bg_tex := load(BG_PATH) as Texture2D
	if bg_tex and is_instance_valid(_bg):
		_bg.texture = bg_tex
	var logo_tex := load(LOGO_PATH) as Texture2D
	if logo_tex and is_instance_valid(_title):
		_title.texture = logo_tex


# ── Layout ───────────────────────────────────────────────────────────────────

func _setup_layout() -> void:
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Title logo — centered, preserves aspect ratio
	_title.set_position(Vector2(115, 8))
	_title.set_size(Vector2(1050, 328))
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.pivot_offset = Vector2(525, 164)

	_tagline.set_position(Vector2(440, 342))
	_tagline.set_size(Vector2(400, 36))

	_buttons_box.set_position(Vector2(480, 388))
	_buttons_box.set_size(Vector2(320, 290))

	_version_label.set_position(Vector2(1140, 696))


# ── Styles ───────────────────────────────────────────────────────────────────

func _style_tagline() -> void:
	_tagline.add_theme_font_size_override("font_size", 17)
	_tagline.add_theme_color_override("font_color", Color("#CC5500"))
	_tagline.add_theme_color_override("font_outline_color", Color("#000000"))
	_tagline.add_theme_constant_override("outline_size", 3)
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _style_buttons() -> void:
	_buttons_box.add_theme_constant_override("separation", 12)
	for btn: Button in [_solo_btn, _coop_btn, _settings_btn, _exit_btn]:
		_apply_button_style(btn)
		btn.mouse_entered.connect(_on_btn_hover.bind(btn))


func _apply_button_style(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(320, 56)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color("#FFD0A0"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("#FF7700"))
	btn.add_theme_color_override("font_outline_color", Color("#18000A"))
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_stylebox_override("normal",  _make_btn_style(Color("#2A0000"), Color("#882200"), false))
	btn.add_theme_stylebox_override("hover",   _make_btn_style(Color("#5A0000"), Color("#FF4400"), true))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(Color("#160000"), Color("#CC2200"), false))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())


func _make_btn_style(bg: Color, border: Color, glow: bool) -> StyleBoxFlat:
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
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 2)
	return s


func _style_version() -> void:
	_version_label.add_theme_font_size_override("font_size", 11)
	_version_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.25))


# ── Particles ────────────────────────────────────────────────────────────────

func _setup_particles() -> void:
	_configure_flame(_left_flame,   Vector2(160,  730))
	_configure_flame(_right_flame,  Vector2(1120, 730))
	_configure_flame(_center_flame, Vector2(640,  730), 30)


func _configure_flame(p: CPUParticles2D, pos: Vector2, amount: int = 55) -> void:
	p.global_position = pos
	p.emitting        = true
	p.amount          = amount
	p.lifetime        = 2.0
	p.one_shot        = false
	p.explosiveness   = 0.0
	p.randomness      = 0.6
	p.direction       = Vector2(0.0, -1.0)
	p.spread          = 22.0
	p.gravity         = Vector2(0.0, 0.0)
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 130.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 9.0
	p.color = Color(1.0, 0.45, 0.0, 0.85)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7,  0.1, 1.0))
	grad.add_point(0.45, Color(1.0, 0.2, 0.0, 0.7))
	grad.add_point(0.8,  Color(0.4, 0.0, 0.0, 0.3))
	grad.set_color(1, Color(0.05, 0.0, 0.0, 0.0))
	p.color_ramp = grad


# ── Entrance Animation ────────────────────────────────────────────────────────

func _play_entrance() -> void:
	var title_y := _title.position.y
	var box_x   := _buttons_box.position.x

	_title.position.y        -= 90
	_title.modulate.a         = 0.0
	_tagline.modulate.a       = 0.0
	_buttons_box.position.x  -= 130
	_buttons_box.modulate.a   = 0.0

	var tw := create_tween()

	tw.tween_property(_title, "position:y", title_y, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(_title, "modulate:a", 1.0, 0.5)

	tw.tween_interval(0.12)
	tw.tween_property(_tagline, "modulate:a", 1.0, 0.35)

	tw.tween_interval(0.22)
	tw.tween_property(_buttons_box, "position:x", box_x, 0.42)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(_buttons_box, "modulate:a", 1.0, 0.32)

	tw.tween_callback(_start_title_pulse)


func _start_title_pulse() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_title, "scale", Vector2(1.025, 1.025), 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "scale", Vector2(1.0, 1.0), 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


# ── Audio Pre-warm ────────────────────────────────────────────────────────────

func _prewarm_audio() -> void:
	for player: AudioStreamPlayer in [_audio_hover, _audio_click]:
		if is_instance_valid(player) and player.stream != null:
			var vol := player.volume_db
			player.volume_db = -80.0
			player.play()
			player.stop()
			player.volume_db = vol


# ── Hover & Click ─────────────────────────────────────────────────────────────

func _on_btn_hover(btn: Button) -> void:
	if is_instance_valid(_audio_hover):
		_audio_hover.stop()
		_audio_hover.play()
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.07)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.07)


func _play_click() -> void:
	if is_instance_valid(_audio_click):
		_audio_click.play()


# ── Button Handlers ───────────────────────────────────────────────────────────

func _connect_buttons() -> void:
	_solo_btn.pressed.connect(_on_solo_pressed)
	_coop_btn.pressed.connect(_on_coop_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_exit_btn.pressed.connect(_on_exit_pressed)


func _on_solo_pressed() -> void:
	_play_click()
	MusicManager.stop_all(0.4)
	NetworkManager.disconnect_all()
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/lobby/hell_lobby.tscn")


func _on_coop_pressed() -> void:
	_play_click()
	MusicManager.stop_all(0.4)
	if multiplayer.has_multiplayer_peer():
		NetworkManager.disconnect_all()
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/ui/coop_name.tscn")


func _on_settings_pressed() -> void:
	_play_click()
	var screen := load("res://scripts/ui/settings_screen.gd") as GDScript
	if screen == null:
		return
	var node: SettingsScreen = screen.new()
	add_child(node)


func _on_exit_pressed() -> void:
	_play_click()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
