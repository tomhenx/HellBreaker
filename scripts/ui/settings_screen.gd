class_name SettingsScreen
extends Control

signal closed

var _music_slider: HSlider
var _music_label:  Label
var _close_btn:    Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color        = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# Panel
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -220.0
	panel.offset_right  =  220.0
	panel.offset_top    = -160.0
	panel.offset_bottom =  160.0
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color("#160000F0")
	sty.border_color = Color("#AA2200")
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 18)
	var mg := 24
	vbox.offset_left   =  mg
	vbox.offset_right  = -mg
	vbox.offset_top    =  mg
	vbox.offset_bottom = -mg
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#FF4400"))
	title.add_theme_color_override("font_outline_color", Color("#000000"))
	title.add_theme_constant_override("outline_size", 3)
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color("#441100"))
	vbox.add_child(sep)

	# Music volume row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	var lbl := Label.new()
	lbl.text = "Music Volume"
	lbl.custom_minimum_size = Vector2(120.0, 0.0)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color("#FFD0A0"))
	row.add_child(lbl)

	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step      = 0.01
	_music_slider.value     = MusicManager.get_volume()
	_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_slider.custom_minimum_size   = Vector2(0.0, 24.0)
	_style_slider(_music_slider)
	row.add_child(_music_slider)

	_music_label = Label.new()
	_music_label.text = "%d%%" % int(MusicManager.get_volume() * 100.0)
	_music_label.custom_minimum_size = Vector2(44.0, 0.0)
	_music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_music_label.add_theme_font_size_override("font_size", 14)
	_music_label.add_theme_color_override("font_color", Color("#FFAA44"))
	row.add_child(_music_label)

	_music_slider.value_changed.connect(_on_music_volume_changed)

	vbox.add_child(Control.new())  # spacer

	# Close button
	_close_btn = Button.new()
	_close_btn.text = "CLOSE"
	_close_btn.custom_minimum_size = Vector2(180.0, 46.0)
	_apply_btn_style(_close_btn)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(_close_btn)
	vbox.add_child(btn_row)

	_close_btn.pressed.connect(_on_close_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_close_pressed()


func _on_music_volume_changed(val: float) -> void:
	MusicManager.set_volume(val)
	if is_instance_valid(_music_label):
		_music_label.text = "%d%%" % int(val * 100.0)


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()


func _style_slider(s: HSlider) -> void:
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color("#FF4400")
	grabber.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area",          grabber)
	s.add_theme_stylebox_override("grabber_area_highlight", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#330000")
	track.set_corner_radius_all(2)
	s.add_theme_stylebox_override("slider", track)


func _apply_btn_style(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color",         Color("#FFD0A0"))
	btn.add_theme_color_override("font_hover_color",   Color("#FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("#FF7700"))
	btn.add_theme_color_override("font_outline_color", Color("#18000A"))
	btn.add_theme_constant_override("outline_size", 2)
	var sty := StyleBoxFlat.new()
	sty.bg_color    = Color("#2A0000")
	sty.border_color = Color("#882200")
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(3)
	sty.content_margin_left   = 16.0
	sty.content_margin_right  = 16.0
	sty.content_margin_top    = 6.0
	sty.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("normal",  sty)
	var sty_h := sty.duplicate() as StyleBoxFlat
	sty_h.bg_color    = Color("#5A0000")
	sty_h.border_color = Color("#FF4400")
	sty_h.shadow_color = Color(1.0, 0.25, 0.0, 0.4)
	sty_h.shadow_size  = 6
	btn.add_theme_stylebox_override("hover",   sty_h)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
