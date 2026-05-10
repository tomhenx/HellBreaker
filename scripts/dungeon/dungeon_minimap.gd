class_name DungeonMinimap
extends CanvasLayer

const CELL      := 9.0
const GAP       := 2.0
const STEP      := CELL + GAP
const MARGIN    := 12.0
const GRID_DIM  := 11

var _cells:       Dictionary = {}   # Vector2i → ColorRect
var _player_dots: Dictionary = {}   # peer_id → ColorRect
var _bg:          ColorRect


func _ready() -> void:
	layer = 18

	# Background panel
	var panel_w := GRID_DIM * STEP + MARGIN * 2.0
	var panel_h := GRID_DIM * STEP + MARGIN * 2.0
	_bg = ColorRect.new()
	_bg.size    = Vector2(panel_w, panel_h)
	_bg.color   = Color(0.0, 0.0, 0.0, 0.55)
	_bg.position = Vector2(1280.0 - panel_w - 8.0, 8.0)
	add_child(_bg)


func discover_room(grid_pos: Vector2i, rtype: DungeonGenerator.RoomType) -> void:
	if _cells.has(grid_pos):
		return
	var cell := ColorRect.new()
	cell.size     = Vector2(CELL, CELL)
	cell.position = _grid_to_screen(grid_pos)
	cell.color    = _room_color(rtype)
	add_child(cell)
	_cells[grid_pos] = cell


func update_player(peer_id: int, grid_pos: Vector2i) -> void:
	if not _player_dots.has(peer_id):
		var dot := ColorRect.new()
		dot.size  = Vector2(5.0, 5.0)
		dot.color = Color(1.0, 1.0, 1.0, 0.95) if peer_id == 1 else Color(0.4, 0.8, 1.0, 0.95)
		add_child(dot)
		_player_dots[peer_id] = dot
	var dot: ColorRect = _player_dots[peer_id]
	if is_instance_valid(dot):
		var cell_sc := _grid_to_screen(grid_pos)
		dot.position = cell_sc + Vector2((CELL - 5.0) * 0.5, (CELL - 5.0) * 0.5)


func remove_player(peer_id: int) -> void:
	if _player_dots.has(peer_id):
		var dot: ColorRect = _player_dots[peer_id]
		if is_instance_valid(dot):
			dot.queue_free()
		_player_dots.erase(peer_id)


func _grid_to_screen(gp: Vector2i) -> Vector2:
	var ox := 1280.0 - (GRID_DIM * STEP + MARGIN * 2.0) - 8.0 + MARGIN
	var oy := 8.0 + MARGIN
	return Vector2(ox + gp.x * STEP, oy + gp.y * STEP)


func _room_color(rtype: DungeonGenerator.RoomType) -> Color:
	match rtype:
		DungeonGenerator.RoomType.START:      return Color("#22AA44")
		DungeonGenerator.RoomType.COMBAT:     return Color("#882222")
		DungeonGenerator.RoomType.BOSS:       return Color("#FF1111")
		DungeonGenerator.RoomType.MINIBOSS:   return Color("#FF6600")
		DungeonGenerator.RoomType.SHOP:       return Color("#FFAA00")
		DungeonGenerator.RoomType.TREASURE:   return Color("#00AAFF")
		DungeonGenerator.RoomType.HEAL:       return Color("#00FF88")
		DungeonGenerator.RoomType.SACRIFICE:  return Color("#AA00FF")
		DungeonGenerator.RoomType.GAMBLE:     return Color("#FF00AA")
		DungeonGenerator.RoomType.RIDDLE_MAN: return Color("#AAAAFF")
		DungeonGenerator.RoomType.PVP:        return Color("#FF4400")
	return Color("#555555")
