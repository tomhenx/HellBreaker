class_name DungeonFloor
extends Node2D

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LOBBY_SCENE  := "res://scenes/lobby/hell_lobby.tscn"
const ROOM_W       := 1280.0
const ROOM_H       := 720.0

const _SPAWN_OFFSETS := [
	Vector2(0,   0),
	Vector2(50,  0),
	Vector2(-50, 0),
	Vector2(0,  50),
]

# Persist across scene reloads
static var current_floor: int = 1
static var _floor_seed:   int = 0

var _rooms:          Dictionary = {}   # Vector2i → DungeonRoom
var _spawned:        Dictionary = {}   # peer_id  → PlayerController
var _player_rooms:   Dictionary = {}   # peer_id  → Vector2i (current grid pos)
var _start_grid:     Vector2i   = Vector2i(5, 5)
var _hud:            HUD
var _minimap:        DungeonMinimap
var _local_player:   PlayerController = null
var _stairs_room:    DungeonRoom      = null
var _near_stairs:    bool             = false


func _ready() -> void:
	_hud = HUD.new()
	$UILayer.add_child(_hud)

	_minimap = DungeonMinimap.new()
	$UILayer.add_child(_minimap)

	# Theme music is started after _init_floor determines the theme

	if not multiplayer.has_multiplayer_peer():
		_floor_seed = randi()
		_init_floor(_floor_seed)
	elif multiplayer.is_server():
		_floor_seed = randi()
		_rpc_init_floor.rpc(_floor_seed)
	# clients wait for _rpc_init_floor RPC


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and \
			NetworkManager.player_list_changed.is_connected(_on_player_list_changed):
		NetworkManager.player_list_changed.disconnect(_on_player_list_changed)


@rpc("authority", "reliable", "call_local")
func _rpc_init_floor(seed_val: int) -> void:
	_init_floor(seed_val)


func _init_floor(seed_val: int) -> void:
	_floor_seed = seed_val
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Point the pause menu quit button at the lobby
	var pm: PauseMenu = $UILayer/PauseMenu
	if is_instance_valid(pm):
		pm.quit_target_scene = LOBBY_SCENE

	var theme := DungeonGenerator.theme_for_floor(current_floor)
	MusicManager.play_dungeon_music(theme as int)
	_build_atmosphere(theme)

	var room_data := DungeonGenerator.generate(current_floor, rng)
	_build_rooms(room_data, theme)

	# Spawn players after rooms exist
	if not multiplayer.has_multiplayer_peer():
		_do_spawn(1, "Player")
	else:
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
		_on_player_list_changed()

	# Discover the start room on the minimap
	var start_room := _rooms.get(_start_grid) as DungeonRoom
	if is_instance_valid(start_room):
		_rpc_discover_room.rpc(_start_grid.x, _start_grid.y, start_room.room_type as int)


func _build_atmosphere(theme: DungeonGenerator.FloorTheme) -> void:
	var mod := CanvasModulate.new()
	match theme:
		DungeonGenerator.FloorTheme.DUNGEON: mod.color = Color(0.60, 0.60, 0.75)
		DungeonGenerator.FloorTheme.GARDEN:  mod.color = Color(0.45, 0.65, 0.38)
		DungeonGenerator.FloorTheme.HEAVEN:  mod.color = Color(0.85, 0.82, 0.70)
		DungeonGenerator.FloorTheme.HELL:    mod.color = Color(0.70, 0.28, 0.10)
	add_child(mod)

	# Floor level label (bottom-left HUD area)
	var lbl := Label.new()
	lbl.text = "Floor %d" % current_floor
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color("#DDCCAA"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.position = Vector2(12.0, 686.0)
	lbl.z_index  = 99
	$UILayer.add_child(lbl)

	# Theme label
	var theme_names := ["DUNGEON", "GARDEN", "HEAVEN", "HELL"]
	var tlbl := Label.new()
	tlbl.text = theme_names[theme]
	tlbl.add_theme_font_size_override("font_size", 11)
	tlbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
	tlbl.position = Vector2(12.0, 704.0)
	tlbl.z_index  = 99
	$UILayer.add_child(tlbl)


func _build_rooms(room_data: Array[Dictionary], theme: DungeonGenerator.FloorTheme) -> void:
	for rd: Dictionary in room_data:
		var gp: Vector2i                 = rd["pos"]
		var rt: DungeonGenerator.RoomType = rd["type"] as DungeonGenerator.RoomType
		var nb: Array[Vector2i]          = rd["neighbors"]

		# Compute door directions (which adjacent grid cells have rooms)
		var dirs: Array[Vector2i] = []
		for nbp: Vector2i in nb:
			dirs.append(nbp - gp)

		var room := DungeonRoom.new()
		room.name          = "R_%d_%d" % [gp.x, gp.y]
		room.grid_pos      = gp
		room.room_type     = rt
		room.floor_theme   = theme
		room.neighbor_dirs = dirs
		room.floor_level   = current_floor
		room.position      = Vector2(gp.x * ROOM_W, gp.y * ROOM_H)
		room.room_cleared.connect(_on_room_cleared.bind(room))
		room.stairs_used.connect(_on_stairs_used)
		$Rooms.add_child(room)
		_rooms[gp] = room

		if rt == DungeonGenerator.RoomType.START:
			_start_grid = gp
		elif rt == DungeonGenerator.RoomType.BOSS:
			_stairs_room = room


func _on_room_cleared(room: DungeonRoom) -> void:
	pass   # sounds / XP grants could go here


func _on_stairs_used() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	current_floor += 1
	if multiplayer.has_multiplayer_peer():
		_rpc_next_floor.rpc()
	else:
		_do_floor_transition()


func _do_floor_transition() -> void:
	MusicManager.stop_all(0.6)
	await get_tree().create_timer(0.7).timeout
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon_floor.tscn")


# Called by lobby when entering dungeon (resets run)
static func reset_run() -> void:
	current_floor = 1


@rpc("authority", "reliable", "call_local")
func _rpc_next_floor() -> void:
	_do_floor_transition()


# ── Player management (mirrors test_room.gd) ─────────────────────────────────

func _on_player_list_changed() -> void:
	for peer_id: int in NetworkManager.players:
		if not _spawned.has(peer_id):
			_do_spawn(peer_id, NetworkManager.players[peer_id].get("name", "Player"))


func _do_spawn(peer_id: int, player_name: String) -> void:
	var scene  := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as PlayerController
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Spawn at start room center
	var start_world := Vector2(_start_grid.x * ROOM_W + ROOM_W * 0.5,
							   _start_grid.y * ROOM_H + ROOM_H * 0.5)
	var keys: Array = NetworkManager.players.keys() if multiplayer.has_multiplayer_peer() else [1]
	var idx   := keys.find(peer_id)
	if idx < 0:
		idx = 0
	player.position = start_world + _SPAWN_OFFSETS[idx % _SPAWN_OFFSETS.size()]

	$Players.add_child(player)
	_spawned[peer_id] = player
	player.init_player(player_name)

	var is_local := not multiplayer.has_multiplayer_peer() or player.is_multiplayer_authority()
	if is_local:
		_local_player = player
		if is_instance_valid(_hud):
			_hud.connect_player(player)


# ── Per-frame room tracking ───────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_handle_local_stairs_input()
		return
	_check_player_rooms()
	_handle_local_stairs_input()


func _check_player_rooms() -> void:
	for peer_id: int in _spawned.keys():
		var player: PlayerController = _spawned[peer_id]
		if not is_instance_valid(player):
			continue
		var gx := floori(player.global_position.x / ROOM_W)
		var gy := floori(player.global_position.y / ROOM_H)
		var cur := Vector2i(gx, gy)
		var prev: Vector2i = _player_rooms.get(peer_id, Vector2i(-999, -999))
		if cur == prev:
			continue
		_player_rooms[peer_id] = cur

		# Notify old room
		if prev != Vector2i(-999, -999):
			var old: DungeonRoom = _rooms.get(prev)
			if is_instance_valid(old):
				old.on_player_exited_room(peer_id) if old.has_method("on_player_exited_room") else null

		# Notify new room
		var room: DungeonRoom = _rooms.get(cur)
		if is_instance_valid(room):
			room.on_player_entered(peer_id)
			if not room.is_discovered:
				room.is_discovered = true
				_rpc_discover_room.rpc(cur.x, cur.y, room.room_type as int)

		# Update minimap player dot
		_minimap.update_player(peer_id, cur)


func _handle_local_stairs_input() -> void:
	if not is_instance_valid(_local_player):
		return
	if not Input.is_action_just_pressed("interact"):
		return
	# Check if local player is near stairs
	if not is_instance_valid(_stairs_room) or not _stairs_room.is_cleared:
		return
	var stairs_area: Area2D = _stairs_room._content_node.get_meta("stairs_area", null) as Area2D
	if not is_instance_valid(stairs_area):
		return
	var bodies := stairs_area.get_overlapping_bodies()
	for b: Node in bodies:
		if b == _local_player:
			_on_stairs_used()
			return


@rpc("authority", "reliable", "call_local")
func _rpc_discover_room(gx: int, gy: int, room_type: int) -> void:
	_minimap.discover_room(Vector2i(gx, gy), room_type as DungeonGenerator.RoomType)
