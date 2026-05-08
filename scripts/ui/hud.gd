class_name HUD
extends Control

var _hp_bar      : ProgressBar
var _hp_label    : Label
var _respawn_lbl : Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.position = Vector2(12, 12)
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	var lbl := Label.new()
	lbl.text = "HP"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#FF4444"))
	lbl.custom_minimum_size = Vector2(20, 0)
	row.add_child(lbl)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(160, 16)
	_hp_bar.max_value  = 100
	_hp_bar.value      = 100
	_hp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#CC2200")
	fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#2A0000")
	bg.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", bg)
	row.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_label.add_theme_color_override("font_color", Color("#FF8888"))
	_hp_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(_hp_label)

	_respawn_lbl = Label.new()
	_respawn_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_respawn_lbl.offset_top    = -20.0
	_respawn_lbl.offset_bottom =  20.0
	_respawn_lbl.offset_left   = -200.0
	_respawn_lbl.offset_right  =  200.0
	_respawn_lbl.add_theme_font_size_override("font_size", 28)
	_respawn_lbl.add_theme_color_override("font_color", Color("#FF2200"))
	_respawn_lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	_respawn_lbl.add_theme_constant_override("outline_size", 4)
	_respawn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_lbl.visible = false
	add_child(_respawn_lbl)


func connect_player(player: PlayerController) -> void:
	player.hp_changed.connect(_on_hp_changed)
	player.died.connect(_on_died)
	player.respawn_countdown.connect(_on_respawn_countdown)
	player.player_respawned.connect(_on_respawned)
	_on_hp_changed(player.current_hp, player.stats.max_hp)


func _on_hp_changed(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value     = current
	_hp_label.text    = "%d / %d" % [int(current), int(maximum)]


func _on_died() -> void:
	_respawn_lbl.text    = "You died..."
	_respawn_lbl.visible = true


func _on_respawn_countdown(seconds_left: float) -> void:
	_respawn_lbl.text    = "Respawning in %d..." % [ceili(seconds_left)]
	_respawn_lbl.visible = true


func _on_respawned() -> void:
	_respawn_lbl.visible = false
