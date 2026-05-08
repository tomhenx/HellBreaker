class_name MerchantDialogue
extends CanvasLayer

signal closed

const DATA_PATH  := "res://data/dialogue/merchant_lines.json"
const TYPE_SPEED := 0.032   # seconds per character

var _text_label  : RichTextLabel
var _skip_btn    : Button
var _trade_btn   : Button
var _leave_btn   : Button
var _voice       : AudioStreamPlayer

var _lines       : Array  = []
var _full_text   : String = ""
var _char_idx    : int    = 0
var _type_timer  : float  = 0.0
var _is_typing   : bool   = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	_text_label = $Panel/VBox/Content/TextSide/TextScroll/DialogueText
	_skip_btn   = $Panel/VBox/TitleRow/SkipBtn
	_trade_btn  = $Panel/VBox/OptionsRow/TradeBtn
	_leave_btn  = $Panel/VBox/OptionsRow/LeaveBtn
	_voice      = $VoicePlayer

	_apply_styles()
	_load_data()
	_show_random_line()

	_skip_btn.pressed.connect(_on_skip)
	_trade_btn.pressed.connect(_on_trade)
	_leave_btn.pressed.connect(_on_leave)

	for btn: Button in [_skip_btn, _trade_btn, _leave_btn]:
		btn.mouse_entered.connect(func(): _hover_scale(btn))

	$Panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property($Panel, "modulate:a", 1.0, 0.18)


func _process(delta: float) -> void:
	if not _is_typing:
		return
	_type_timer += delta
	while _type_timer >= TYPE_SPEED and _char_idx < _full_text.length():
		_type_timer -= TYPE_SPEED
		_char_idx += 1
		_text_label.text = _full_text.left(_char_idx)
	if _char_idx >= _full_text.length():
		_is_typing = false
		_skip_btn.visible = false


func _load_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).has("lines"):
		_lines = (parsed as Dictionary)["lines"]


func _show_random_line() -> void:
	if _lines.is_empty():
		return
	var line: Dictionary = _lines[randi() % _lines.size()]
	_full_text  = line.get("text", "")
	_char_idx   = 0
	_type_timer = 0.0
	_is_typing  = true
	_skip_btn.visible = true
	_text_label.text  = ""

	var audio_path: String = line.get("audio", "")
	if not audio_path.is_empty():
		var stream := load(audio_path) as AudioStream
		if is_instance_valid(stream):
			_voice.stream = stream
			_voice.play()


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_skip() -> void:
	if _is_typing:
		_is_typing = false
		_text_label.text = _full_text
		_char_idx = _full_text.length()
		_skip_btn.visible = false
	if _voice.playing:
		_voice.stop()


func _on_trade() -> void:
	pass  # Shop system — Phase 2


func _on_leave() -> void:
	if _voice.playing:
		_voice.stop()
	var tw := create_tween()
	tw.tween_property($Panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): closed.emit(); queue_free())


func _hover_scale(btn: Button) -> void:
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.07)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.07)


# ── Styles ────────────────────────────────────────────────────────────────────

func _apply_styles() -> void:
	var panel: Control = $Panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top    = -270.0
	panel.offset_bottom = -6.0
	panel.offset_left   =  8.0
	panel.offset_right  = -8.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color     = Color("#120000F0")
	panel_style.border_color = Color("#CC2200")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel_style.shadow_color = Color(0.8, 0.1, 0.0, 0.4)
	panel_style.shadow_size  = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	# Speaker name
	var name_lbl: Label = $Panel/VBox/TitleRow/SpeakerName
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color("#FF4400"))
	name_lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	name_lbl.add_theme_constant_override("outline_size", 2)

	# Dialogue text
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	_text_label.add_theme_color_override("default_color", Color("#FFE8CC"))

	# Portrait bg style
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color     = Color("#120208")
	portrait_style.border_color = Color("#882200")
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(3)
	($Panel/VBox/Content/Portrait as PanelContainer).add_theme_stylebox_override("panel", portrait_style)

	# Buttons
	_style_btn(_skip_btn,  80, 28, true)
	_style_btn(_trade_btn, 140, 44, false)
	_style_btn(_leave_btn, 140, 44, false)

	var sep: HSeparator = $Panel/VBox/Separator
	sep.add_theme_color_override("color", Color("#441100"))


func _style_btn(btn: Button, min_w: float, min_h: float, is_small: bool) -> void:
	btn.custom_minimum_size = Vector2(min_w, min_h)
	btn.add_theme_font_size_override("font_size", 14 if is_small else 18)
	btn.add_theme_color_override("font_color", Color("#FFD0A0"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("#FF7700"))
	btn.add_theme_color_override("font_outline_color", Color("#18000A"))
	btn.add_theme_constant_override("outline_size", 1)
	var bg  := Color("#2A0000") if not is_small else Color("#1A0000")
	var brd := Color("#882200") if not is_small else Color("#551100")
	btn.add_theme_stylebox_override("normal",  _make_style(bg,          brd,          false))
	btn.add_theme_stylebox_override("hover",   _make_style(Color("#5A0000"), Color("#FF4400"), true))
	btn.add_theme_stylebox_override("pressed", _make_style(Color("#160000"), Color("#CC2200"), false))
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())


func _make_style(bg: Color, border: Color, glow: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left   = 10.0
	s.content_margin_right  = 10.0
	s.content_margin_top    = 4.0
	s.content_margin_bottom = 4.0
	if glow:
		s.shadow_color = Color(1.0, 0.25, 0.0, 0.5)
		s.shadow_size  = 6
	return s
