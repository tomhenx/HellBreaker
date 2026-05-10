class_name DungeonBigMap
extends CanvasLayer

const CELL    := 42.0
const GAP     := 6.0
const STEP    := CELL + GAP
const GRID    := 11
const CORNER  := Vector2(30.0, 30.0)

const _ROOM_COLORS := {
	DungeonGenerator.RoomType.START:      Color("#22AA44"),
	DungeonGenerator.RoomType.COMBAT:     Color("#663322"),
	DungeonGenerator.RoomType.BOSS:       Color("#CC1100"),
	DungeonGenerator.RoomType.MINIBOSS:   Color("#882200"),
	DungeonGenerator.RoomType.SHOP:       Color("#AA8800"),
	DungeonGenerator.RoomType.TREASURE:   Color("#1144AA"),
	DungeonGenerator.RoomType.HEAL:       Color("#118866"),
	DungeonGenerator.RoomType.SACRIFICE:  Color("#770055"),
	DungeonGenerator.RoomType.GAMBLE:     Color("#886600"),
	DungeonGenerator.RoomType.RIDDLE_MAN: Color("#445588"),
	DungeonGenerator.RoomType.PVP:        Color("#883300"),
}
const _ROOM_ICONS := {
	DungeonGenerator.RoomType.START:      "S",
	DungeonGenerator.RoomType.COMBAT:     "",
	DungeonGenerator.RoomType.BOSS:       "B",
	DungeonGenerator.RoomType.MINIBOSS:   "M",
	DungeonGenerator.RoomType.SHOP:       "$",
	DungeonGenerator.RoomType.TREASURE:   "T",
	DungeonGenerator.RoomType.HEAL:       "+",
	DungeonGenerator.RoomType.SACRIFICE:  "X",
	DungeonGenerator.RoomType.GAMBLE:     "?",
	DungeonGenerator.RoomType.RIDDLE_MAN: "R",
	DungeonGenerator.RoomType.PVP:        "P",
}

var _overlay:     ColorRect
var _cells:       Dictionary = {}   # Vector2i → Control (panel)
var _dots:        Dictionary = {}   # peer_id  → ColorRect
var _connections: Array      = []   # Array of [Vector2i, Vector2i]


func _ready() -> void:
	layer        = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible      = false

	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.0, 0.0, 0.0, 0.88)
	add_child(_overlay)

	var title := Label.new()
	title.text = "DUNGEON MAP"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color",         Color("#FF4422"))
	title.add_theme_color_override("font_outline_color", Color("#000000"))
	title.add_theme_constant_override("outline_size", 3)
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(24.0, 8.0)
	add_child(title)

	var legend := _build_legend()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.position = Vector2(24.0, -140.0)
	add_child(legend)

	var hint := Label.new()
	hint.text = "Hold TAB to view"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.6))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-160.0, -22.0)
	add_child(hint)


func _process(_delta: float) -> void:
	visible = Input.is_action_pressed("dungeon_map")


# ── Public API ────────────────────────────────────────────────────────────────

func discover_room(grid_pos: Vector2i, rtype: DungeonGenerator.RoomType) -> void:
	if _cells.has(grid_pos):
		return
	var panel := _make_cell(grid_pos, rtype)
	add_child(panel)
	_cells[grid_pos] = panel
	_refresh_connections(grid_pos)


func connect_rooms(a: Vector2i, b: Vector2i) -> void:
	_connections.append([a, b])


func update_player(peer_id: int, grid_pos: Vector2i) -> void:
	if not _dots.has(peer_id):
		var dot := ColorRect.new()
		dot.size  = Vector2(10.0, 10.0)
		dot.color = _player_color(peer_id)
		add_child(dot)
		_dots[peer_id] = dot
	var dot: ColorRect = _dots[peer_id]
	var world  := _grid_to_screen(grid_pos)
	dot.position = world + Vector2(CELL * 0.5 - 5.0, CELL * 0.5 - 5.0)
	dot.visible  = _cells.has(grid_pos)


# ── Private ───────────────────────────────────────────────────────────────────

func _make_cell(gp: Vector2i, rtype: DungeonGenerator.RoomType) -> Control:
	var root   := Control.new()
	root.size   = Vector2(CELL, CELL)
	root.position = _grid_to_screen(gp)

	var bg := ColorRect.new()
	bg.size  = Vector2(CELL, CELL)
	bg.color = _ROOM_COLORS.get(rtype, Color(0.3, 0.3, 0.3))
	root.add_child(bg)

	var border := _make_border()
	root.add_child(border)

	var icon_str: String = _ROOM_ICONS.get(rtype, "")
	if icon_str != "":
		var lbl := Label.new()
		lbl.text = icon_str
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.9))
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		lbl.size = Vector2(CELL, CELL)
		lbl.position = Vector2(-CELL * 0.5, -CELL * 0.5)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		root.add_child(lbl)

	return root


func _make_border() -> ColorRect:
	var b := ColorRect.new()
	b.size     = Vector2(CELL, CELL)
	b.color    = Color(0.0, 0.0, 0.0, 0.0)
	var style  := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.0, 0.0, 0.0, 0.5)
	style.set_border_width_all(1)
	return b


func _refresh_connections(gp: Vector2i) -> void:
	const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d: Vector2i in DIRS:
		var nb := gp + d
		if _cells.has(nb):
			_draw_connector(gp, nb, d)


func _draw_connector(a: Vector2i, b: Vector2i, dir: Vector2i) -> void:
	var connector := ColorRect.new()
	connector.color = Color(0.35, 0.35, 0.35, 0.7)
	var pa := _grid_to_screen(a)
	var pb := _grid_to_screen(b)
	if dir.x != 0:
		connector.position = Vector2(pa.x + CELL, pa.y + CELL * 0.5 - 3.0)
		connector.size     = Vector2(GAP, 6.0)
	else:
		connector.position = Vector2(pa.x + CELL * 0.5 - 3.0, pa.y + CELL)
		connector.size     = Vector2(6.0, GAP)
	add_child(connector)
	move_child(connector, 1)


func _grid_to_screen(gp: Vector2i) -> Vector2:
	var map_w := STEP * GRID - GAP
	var map_h := STEP * GRID - GAP
	var vp    := get_viewport().get_visible_rect().size
	var ox    := (vp.x - map_w) * 0.5
	var oy    := (vp.y - map_h) * 0.5
	return Vector2(ox + gp.x * STEP, oy + gp.y * STEP)


func _player_color(peer_id: int) -> Color:
	match peer_id % 4:
		0: return Color("#FFFFFF")
		1: return Color("#FFFF00")
		2: return Color("#00FFFF")
		_: return Color("#FF88FF")


func _build_legend() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var heading := Label.new()
	heading.text = "LEGEND"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(heading)

	var entries := [
		["S  Start",      _ROOM_COLORS[DungeonGenerator.RoomType.START]],
		["   Combat",     _ROOM_COLORS[DungeonGenerator.RoomType.COMBAT]],
		["B  Boss",       _ROOM_COLORS[DungeonGenerator.RoomType.BOSS]],
		["M  Mini-boss",  _ROOM_COLORS[DungeonGenerator.RoomType.MINIBOSS]],
		["$  Shop",       _ROOM_COLORS[DungeonGenerator.RoomType.SHOP]],
		["T  Treasure",   _ROOM_COLORS[DungeonGenerator.RoomType.TREASURE]],
		["+  Heal",       _ROOM_COLORS[DungeonGenerator.RoomType.HEAL]],
		["X  Sacrifice",  _ROOM_COLORS[DungeonGenerator.RoomType.SACRIFICE]],
		["?  Gamble",     _ROOM_COLORS[DungeonGenerator.RoomType.GAMBLE]],
		["R  Riddle Man", _ROOM_COLORS[DungeonGenerator.RoomType.RIDDLE_MAN]],
	]
	for entry in entries:
		var row  := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14.0, 14.0)
		swatch.color = entry[1]
		row.add_child(swatch)
		var lbl := Label.new()
		lbl.text = "  " + entry[0]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row.add_child(lbl)
		vbox.add_child(row)

	return vbox
