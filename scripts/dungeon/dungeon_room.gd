class_name DungeonRoom
extends Node2D

signal room_cleared(room: DungeonRoom)
signal stairs_used

const ROOM_W  := 1280.0
const ROOM_H  := 720.0
const WALL_T  := 40.0
const DOOR_W  := 80.0
const DOOR_HX := 600.0   # door gap left edge on N/S walls
const DOOR_HY := 320.0   # door gap top edge on E/W walls

const _ENEMIES_T1: Array[String] = [
	"res://scenes/enemies/skeleton.tscn",
	"res://scenes/enemies/rat.tscn",
	"res://scenes/enemies/slime.tscn",
]
const _ENEMIES_T2: Array[String] = [
	"res://scenes/enemies/skeleton.tscn",
	"res://scenes/enemies/bat.tscn",
	"res://scenes/enemies/blob.tscn",
	"res://scenes/enemies/imp.tscn",
]
const _ENEMIES_T3: Array[String] = [
	"res://scenes/enemies/orc.tscn",
	"res://scenes/enemies/imp.tscn",
	"res://scenes/enemies/hellhound.tscn",
	"res://scenes/enemies/lava_blob.tscn",
]
const _BOSS_SCENE     := "res://scenes/enemies/lava_king_slime.tscn"
const _MINIBOSS_POOL  := ["res://scenes/enemies/orc.tscn", "res://scenes/enemies/lava_blob.tscn"]
const _CHEST_SCENE    := "res://scenes/items/chest_drop.tscn"
const _SFX_DOOR_OPEN  := "res://assets/audio/sfx/dungeon_door_open.mp3"
const _SFX_DOOR_LOCK  := "res://assets/audio/sfx/dungeon_door_lock.mp3"
const _SFX_ROOM_CLEAR := "res://assets/audio/sfx/dungeon_room_clear.mp3"
const _SFX_STAIRS     := "res://assets/audio/sfx/dungeon_stairs.mp3"

var grid_pos:      Vector2i                        = Vector2i.ZERO
var room_type:     DungeonGenerator.RoomType        = DungeonGenerator.RoomType.COMBAT
var floor_theme:   DungeonGenerator.FloorTheme      = DungeonGenerator.FloorTheme.DUNGEON
var neighbor_dirs: Array[Vector2i]                  = []
var floor_level:   int                              = 1
var is_cleared:    bool                             = false
var is_discovered: bool                             = false

var _enemy_count:  int        = 0
var _is_locked:    bool       = false
var _has_spawned:  bool       = false
var _barriers:     Dictionary = {}   # Vector2i → Node2D
var _pulse_t:      float      = 0.0
var _enemies_node: Node2D
var _content_node: Node2D
var _sfx:          AudioStreamPlayer2D
var _rng:          RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_sfx = AudioStreamPlayer2D.new()
	_sfx.max_distance = 9999.0
	add_child(_sfx)
	_build_floor_visual()
	_enemies_node = Node2D.new()
	_enemies_node.name = "Enemies"
	add_child(_enemies_node)
	_content_node = Node2D.new()
	_content_node.name = "Content"
	add_child(_content_node)
	_build_walls()
	_build_decoration()
	if room_type == DungeonGenerator.RoomType.HEAL or room_type == DungeonGenerator.RoomType.SACRIFICE:
		_build_altar()
	elif room_type == DungeonGenerator.RoomType.SHOP:
		_build_shop_placeholder()
	elif room_type == DungeonGenerator.RoomType.TREASURE:
		_do_spawn_treasure()
	elif room_type in [DungeonGenerator.RoomType.GAMBLE, DungeonGenerator.RoomType.RIDDLE_MAN]:
		_build_npc_placeholder()
	elif room_type == DungeonGenerator.RoomType.START:
		_auto_clear()


func _process(delta: float) -> void:
	if not _is_locked:
		return
	_pulse_t += delta * 4.0
	for dir_key: Vector2i in _barriers.keys():
		var b: Node2D = _barriers[dir_key]
		if is_instance_valid(b):
			b.modulate.a = 0.7 + sin(_pulse_t) * 0.25


# ── Public (called by DungeonFloor) ─────────────────────────────────────────

func on_player_entered(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if is_cleared or _has_spawned:
		return
	_has_spawned = true
	_server_spawn_enemies()


# ── Server-side enemy spawning ───────────────────────────────────────────────

func _server_spawn_enemies() -> void:
	match room_type:
		DungeonGenerator.RoomType.BOSS:
			_enemy_count = 1
			if multiplayer.has_multiplayer_peer():
				_rpc_spawn_enemy.rpc(_BOSS_SCENE, Vector2(ROOM_W * 0.5, ROOM_H * 0.35), "boss_0")
			else:
				_do_spawn_enemy(_BOSS_SCENE, Vector2(ROOM_W * 0.5, ROOM_H * 0.35), "boss_0")
			_set_locked(true)

		DungeonGenerator.RoomType.MINIBOSS:
			_enemy_count = 2
			var mb0 := _MINIBOSS_POOL[(floor_level) % _MINIBOSS_POOL.size()]
			var mb1 := _MINIBOSS_POOL[(floor_level + 1) % _MINIBOSS_POOL.size()]
			if multiplayer.has_multiplayer_peer():
				_rpc_spawn_enemy.rpc(mb0, Vector2(ROOM_W * 0.5, ROOM_H * 0.35), "mb_0")
				_rpc_spawn_enemy.rpc(mb1, Vector2(ROOM_W * 0.38, ROOM_H * 0.55), "mb_1")
			else:
				_do_spawn_enemy(mb0, Vector2(ROOM_W * 0.5, ROOM_H * 0.35), "mb_0")
				_do_spawn_enemy(mb1, Vector2(ROOM_W * 0.38, ROOM_H * 0.55), "mb_1")
			_set_locked(true)

		DungeonGenerator.RoomType.COMBAT:
			var count := clampi(_rng.randi_range(2 + floor_level, 4 + floor_level), 2, 8)
			_enemy_count = count
			var pool := _enemy_pool()
			for i in range(count):
				var sp  := _random_spawn_pos()
				var sc  := pool[_rng.randi() % pool.size()]
				var nm  := "enemy_%d" % i
				if multiplayer.has_multiplayer_peer():
					_rpc_spawn_enemy.rpc(sc, sp, nm)
				else:
					_do_spawn_enemy(sc, sp, nm)
			if count > 0:
				_set_locked(true)
			else:
				_auto_clear()

		_:
			_auto_clear()


func _auto_clear() -> void:
	_enemy_count = 0
	_mark_cleared()


@rpc("authority", "reliable", "call_local")
func _rpc_spawn_enemy(scene_path: String, local_pos: Vector2, ename: String) -> void:
	_do_spawn_enemy(scene_path, local_pos, ename)


func _do_spawn_enemy(scene_path: String, local_pos: Vector2, ename: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var enemy := packed.instantiate() as BaseEnemy
	if enemy == null:
		return
	enemy.name     = ename
	enemy.position = local_pos
	_enemies_node.add_child(enemy)
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		enemy.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	_enemy_count -= 1
	if _enemy_count <= 0:
		_mark_cleared()


func _mark_cleared() -> void:
	if is_cleared:
		return
	is_cleared = true
	_set_locked(false)
	_play_sfx(_SFX_ROOM_CLEAR)
	room_cleared.emit(self)
	if room_type == DungeonGenerator.RoomType.BOSS:
		_rpc_spawn_stairs.rpc()


func _set_locked(locked: bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_locked.rpc(locked)
	else:
		_apply_lock(locked)


@rpc("authority", "reliable", "call_local")
func _rpc_set_locked(locked: bool) -> void:
	_apply_lock(locked)


@rpc("authority", "reliable", "call_local")
func _rpc_spawn_stairs() -> void:
	_build_stairs()


func _play_sfx(path: String) -> void:
	var s := load(path) as AudioStream
	if s == null:
		return
	_sfx.stream    = s
	_sfx.volume_db = -8.0
	_sfx.play()


func _apply_lock(locked: bool) -> void:
	_is_locked = locked
	_play_sfx(_SFX_DOOR_LOCK if locked else _SFX_DOOR_OPEN)
	for dir_key: Vector2i in _barriers.keys():
		var b: Node2D = _barriers[dir_key]
		if not is_instance_valid(b):
			continue
		b.visible = locked
		var body: StaticBody2D = b.get_node_or_null("PhysicsBody")
		if is_instance_valid(body):
			body.process_mode = Node.PROCESS_MODE_INHERIT if locked else Node.PROCESS_MODE_DISABLED


# ── Visual builders ──────────────────────────────────────────────────────────

func _build_floor_visual() -> void:
	var floor_col := _theme_floor_color()
	var bg := ColorRect.new()
	bg.size    = Vector2(ROOM_W, ROOM_H)
	bg.color   = floor_col
	bg.z_index = -10
	add_child(bg)

	if room_type == DungeonGenerator.RoomType.BOSS:
		var overlay := ColorRect.new()
		overlay.size    = Vector2(ROOM_W, ROOM_H)
		overlay.color   = Color(0.25, 0.0, 0.0, 0.20)
		overlay.z_index = -9
		add_child(overlay)
	elif floor_theme == DungeonGenerator.FloorTheme.HEAVEN:
		_build_heaven_bloodstains()


func _theme_floor_color() -> Color:
	match room_type:
		DungeonGenerator.RoomType.BOSS:      return Color("#1A0000")
		DungeonGenerator.RoomType.SHOP:      return Color("#1A1400")
		DungeonGenerator.RoomType.TREASURE:  return Color("#001A0A")
		DungeonGenerator.RoomType.HEAL:      return Color("#001015")
		DungeonGenerator.RoomType.SACRIFICE: return Color("#150008")
		_: pass

	match floor_theme:
		DungeonGenerator.FloorTheme.DUNGEON: return Color("#131318")
		DungeonGenerator.FloorTheme.GARDEN:  return Color("#0D180D")
		DungeonGenerator.FloorTheme.HEAVEN:  return Color("#1E1C12")
		DungeonGenerator.FloorTheme.HELL:    return Color("#1A0A00")
	return Color("#131318")


func _theme_wall_color() -> Color:
	match floor_theme:
		DungeonGenerator.FloorTheme.DUNGEON: return Color("#0C0C16")
		DungeonGenerator.FloorTheme.GARDEN:  return Color("#0A1409")
		DungeonGenerator.FloorTheme.HEAVEN:  return Color("#18160C")
		DungeonGenerator.FloorTheme.HELL:    return Color("#120700")
	return Color("#0C0C16")


func _theme_trim_color() -> Color:
	match floor_theme:
		DungeonGenerator.FloorTheme.DUNGEON: return Color("#333344")
		DungeonGenerator.FloorTheme.GARDEN:  return Color("#1A4A1A")
		DungeonGenerator.FloorTheme.HEAVEN:  return Color("#5A5030")
		DungeonGenerator.FloorTheme.HELL:    return Color("#441500")
	return Color("#333344")


func _build_heaven_bloodstains() -> void:
	for _i in range(14):
		var splash := Polygon2D.new()
		var pts: Array[Vector2] = []
		var cx  := _rng.randf_range(100.0, ROOM_W - 100.0)
		var cy  := _rng.randf_range(80.0, ROOM_H - 80.0)
		var r   := _rng.randf_range(14.0, 38.0)
		var seg := _rng.randi_range(7, 12)
		for k in range(seg):
			var a  := k * TAU / seg
			var dr := _rng.randf_range(0.6, 1.15)
			pts.append(Vector2(cx + cos(a) * r * dr, cy + sin(a) * r * dr))
		splash.polygon = PackedVector2Array(pts)
		splash.color   = Color(_rng.randf_range(0.35, 0.55), 0.0, 0.0, _rng.randf_range(0.5, 0.85))
		splash.z_index = -9
		add_child(splash)


func _build_walls() -> void:
	var wc := _theme_wall_color()
	var tc := _theme_trim_color()
	var has_n := Vector2i(0, -1) in neighbor_dirs
	var has_s := Vector2i(0,  1) in neighbor_dirs
	var has_w := Vector2i(-1, 0) in neighbor_dirs
	var has_e := Vector2i(1,  0) in neighbor_dirs

	# ── Top ──
	if has_n:
		_wall(Rect2(0, 0, DOOR_HX, WALL_T), wc, tc)
		_wall(Rect2(DOOR_HX + DOOR_W, 0, ROOM_W - DOOR_HX - DOOR_W, WALL_T), wc, tc)
		_make_barrier(Vector2i(0, -1), Rect2(DOOR_HX, 0, DOOR_W, WALL_T))
	else:
		_wall(Rect2(0, 0, ROOM_W, WALL_T), wc, tc)

	# ── Bottom ──
	if has_s:
		_wall(Rect2(0, ROOM_H - WALL_T, DOOR_HX, WALL_T), wc, tc)
		_wall(Rect2(DOOR_HX + DOOR_W, ROOM_H - WALL_T, ROOM_W - DOOR_HX - DOOR_W, WALL_T), wc, tc)
		_make_barrier(Vector2i(0, 1), Rect2(DOOR_HX, ROOM_H - WALL_T, DOOR_W, WALL_T))
	else:
		_wall(Rect2(0, ROOM_H - WALL_T, ROOM_W, WALL_T), wc, tc)

	# ── Left ──
	if has_w:
		_wall(Rect2(0, WALL_T, WALL_T, DOOR_HY - WALL_T), wc, tc)
		_wall(Rect2(0, DOOR_HY + DOOR_W, WALL_T, ROOM_H - DOOR_HY - DOOR_W - WALL_T), wc, tc)
		_make_barrier(Vector2i(-1, 0), Rect2(0, DOOR_HY, WALL_T, DOOR_W))
	else:
		_wall(Rect2(0, WALL_T, WALL_T, ROOM_H - WALL_T * 2.0), wc, tc)

	# ── Right ──
	if has_e:
		_wall(Rect2(ROOM_W - WALL_T, WALL_T, WALL_T, DOOR_HY - WALL_T), wc, tc)
		_wall(Rect2(ROOM_W - WALL_T, DOOR_HY + DOOR_W, WALL_T, ROOM_H - DOOR_HY - DOOR_W - WALL_T), wc, tc)
		_make_barrier(Vector2i(1, 0), Rect2(ROOM_W - WALL_T, DOOR_HY, WALL_T, DOOR_W))
	else:
		_wall(Rect2(ROOM_W - WALL_T, WALL_T, WALL_T, ROOM_H - WALL_T * 2.0), wc, tc)

	# Boss door glows
	if room_type == DungeonGenerator.RoomType.BOSS:
		for dkey: Vector2i in _barriers.keys():
			_add_boss_door_glow(dkey)


func _wall(rect: Rect2, wall_col: Color, trim_col: Color) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs    := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size  = rect.size
	cs.position = rect.position + rect.size * 0.5
	cs.shape    = shape
	body.add_child(cs)
	add_child(body)

	var vr := ColorRect.new()
	vr.position = rect.position
	vr.size     = rect.size
	vr.color    = wall_col
	vr.z_index  = -8
	add_child(vr)

	# Inner trim line
	const TW := 3.0
	var tr := ColorRect.new()
	tr.color   = trim_col
	tr.z_index = -7
	if rect.size.x >= rect.size.y:   # horizontal wall
		if rect.position.y < ROOM_H * 0.5:
			tr.position = Vector2(rect.position.x, rect.position.y + rect.size.y - TW)
		else:
			tr.position = rect.position
		tr.size = Vector2(rect.size.x, TW)
	else:                             # vertical wall
		if rect.position.x < ROOM_W * 0.5:
			tr.position = Vector2(rect.position.x + rect.size.x - TW, rect.position.y)
		else:
			tr.position = rect.position
		tr.size = Vector2(TW, rect.size.y)
	add_child(tr)


func _make_barrier(dir: Vector2i, rect: Rect2) -> void:
	var root := Node2D.new()
	root.visible = false
	add_child(root)
	_barriers[dir] = root

	var fill := ColorRect.new()
	fill.position = rect.position
	fill.size     = rect.size
	fill.color    = Color(0.5, 0.0, 0.0, 0.80)
	root.add_child(fill)

	# Center bar
	var bar := ColorRect.new()
	bar.color = Color(0.85, 0.15, 0.05, 0.95)
	if rect.size.x >= rect.size.y:
		bar.position = Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 - 3.0)
		bar.size     = Vector2(rect.size.x, 6.0)
	else:
		bar.position = Vector2(rect.position.x + rect.size.x * 0.5 - 3.0, rect.position.y)
		bar.size     = Vector2(6.0, rect.size.y)
	root.add_child(bar)

	var body := StaticBody2D.new()
	body.name            = "PhysicsBody"
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs    := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size   = rect.size
	cs.position  = rect.position + rect.size * 0.5
	cs.shape     = shape
	body.add_child(cs)
	root.add_child(body)


func _add_boss_door_glow(dir: Vector2i) -> void:
	var overlay := ColorRect.new()
	overlay.color   = Color(0.7, 0.08, 0.0, 0.45)
	overlay.z_index = -6
	if dir.y != 0:
		var y := 0.0 if dir.y == -1 else ROOM_H - WALL_T
		overlay.position = Vector2(DOOR_HX - 8.0, y)
		overlay.size     = Vector2(DOOR_W + 16.0, WALL_T)
	else:
		var x := 0.0 if dir.x == -1 else ROOM_W - WALL_T
		overlay.position = Vector2(x, DOOR_HY - 8.0)
		overlay.size     = Vector2(WALL_T, DOOR_W + 16.0)
	add_child(overlay)


func _build_decoration() -> void:
	# Subtle floor cracks / detail
	for _i in range(5 + _rng.randi() % 4):
		var crack := Polygon2D.new()
		var cx  := _rng.randf_range(WALL_T + 40.0, ROOM_W - WALL_T - 40.0)
		var cy  := _rng.randf_range(WALL_T + 40.0, ROOM_H - WALL_T - 40.0)
		var len := _rng.randf_range(30.0, 100.0)
		var ang := _rng.randf_range(0.0, TAU)
		var w   := 2.0
		var pts := PackedVector2Array([
			Vector2(cx + cos(ang) * len * 0.5 - sin(ang) * w, cy + sin(ang) * len * 0.5 + cos(ang) * w),
			Vector2(cx - cos(ang) * len * 0.5 - sin(ang) * w, cy - sin(ang) * len * 0.5 + cos(ang) * w),
			Vector2(cx - cos(ang) * len * 0.5 + sin(ang) * w, cy - sin(ang) * len * 0.5 - cos(ang) * w),
			Vector2(cx + cos(ang) * len * 0.5 + sin(ang) * w, cy + sin(ang) * len * 0.5 - cos(ang) * w),
		])
		crack.polygon = pts
		crack.color   = Color(0.0, 0.0, 0.0, 0.25)
		crack.z_index = -9
		add_child(crack)


func _build_altar() -> void:
	var altar := Polygon2D.new()
	altar.position = Vector2(ROOM_W * 0.5, ROOM_H * 0.5)
	var pts: Array[Vector2] = []
	const R := 30.0
	for i in range(8):
		var a := i * TAU / 8.0
		pts.append(Vector2(cos(a) * R, sin(a) * R))
	altar.polygon = PackedVector2Array(pts)
	altar.color = Color(0.55, 0.05, 0.5, 0.9) if room_type == DungeonGenerator.RoomType.SACRIFICE \
		else Color(0.05, 0.55, 0.55, 0.9)
	_content_node.add_child(altar)

	var lbl := Label.new()
	lbl.text = "Sacrificial Altar" if room_type == DungeonGenerator.RoomType.SACRIFICE else "Healing Fountain"
	lbl.position = Vector2(ROOM_W * 0.5 - 90.0, ROOM_H * 0.5 + 38.0)
	lbl.size = Vector2(180, 20)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("#CCAAFF") if room_type == DungeonGenerator.RoomType.SACRIFICE else Color("#AAFFDD"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_node.add_child(lbl)


func _build_shop_placeholder() -> void:
	var lbl := Label.new()
	lbl.text = "SHOP — Coming Soon"
	lbl.position = Vector2(ROOM_W * 0.5 - 100.0, ROOM_H * 0.5 - 14.0)
	lbl.size = Vector2(200, 28)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("#FFCC44"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_node.add_child(lbl)


func _build_npc_placeholder() -> void:
	var name_str := "Gamble Room" if room_type == DungeonGenerator.RoomType.GAMBLE else "Riddle Man"
	var lbl := Label.new()
	lbl.text = name_str
	lbl.position = Vector2(ROOM_W * 0.5 - 80.0, ROOM_H * 0.5 - 14.0)
	lbl.size = Vector2(160, 28)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color("#DDBBFF"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_node.add_child(lbl)


func _do_spawn_treasure() -> void:
	var packed := load(_CHEST_SCENE) as PackedScene
	if packed == null:
		return
	var count := _rng.randi_range(1, 2)
	for i in range(count):
		var chest := packed.instantiate()
		var cx    := ROOM_W * 0.5 + (i - (count - 1) * 0.5) * 100.0
		chest.position = Vector2(cx, ROOM_H * 0.5)
		_content_node.add_child(chest)
	_auto_clear()


func _build_stairs() -> void:
	var cx := ROOM_W * 0.5
	var cy := ROOM_H * 0.5

	var glow := Polygon2D.new()
	glow.position = Vector2(cx, cy)
	glow.polygon  = _rect_poly(52.0, 20.0)
	glow.color    = Color(0.3, 0.9, 1.0, 0.45)
	_content_node.add_child(glow)

	var inner := Polygon2D.new()
	inner.position = Vector2(cx, cy)
	inner.polygon  = _rect_poly(36.0, 13.0)
	inner.color    = Color(0.6, 1.0, 1.0, 0.9)
	_content_node.add_child(inner)

	var lbl := Label.new()
	lbl.text = "NEXT FLOOR [E]"
	lbl.position = Vector2(cx - 60.0, cy - 30.0)
	lbl.size = Vector2(120, 16)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#AAEEFF"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_node.add_child(lbl)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 2
	var cs    := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(72.0, 40.0)
	cs.shape   = shape
	area.position = Vector2(cx, cy)
	area.add_child(cs)
	_content_node.add_child(area)

	_content_node.set_meta("stairs_area", area)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _rect_poly(hw: float, hh: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])


func _enemy_pool() -> Array[String]:
	if floor_level <= 1:   return _ENEMIES_T1
	elif floor_level <= 2: return _ENEMIES_T2
	else:                  return _ENEMIES_T3


func _random_spawn_pos() -> Vector2:
	var cx   := ROOM_W * 0.5
	var cy   := ROOM_H * 0.5
	var pad  := WALL_T + 80.0
	var mind := 200.0
	for _a in range(30):
		var x := _rng.randf_range(pad, ROOM_W - pad)
		var y := _rng.randf_range(pad, ROOM_H - pad)
		if Vector2(x, y).distance_to(Vector2(cx, cy)) >= mind:
			return Vector2(x, y)
	return Vector2(cx + _rng.randf_range(-200.0, 200.0), cy + _rng.randf_range(-200.0, 200.0))
