extends Node2D

const PLAYER_SCENE  := "res://scenes/player/player.tscn"
const SPAWN_POINTS  := [
	Vector2(  0,   0),
	Vector2( 55,   0),
	Vector2(-55,   0),
	Vector2(  0,  55),
]

# peer_id → PlayerController node
var _spawned: Dictionary = {}
var _hud:     HUD


func _ready() -> void:
	_hud = HUD.new()
	$UILayer.add_child(_hud)

	if not multiplayer.has_multiplayer_peer():
		_do_spawn(1, "Player")
		return

	# Disable solo pause in co-op
	var pm := get_node_or_null("UILayer/PauseMenu") as PauseMenu
	if is_instance_valid(pm):
		pm.solo_mode = false

	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	# Trigger spawn for anyone already registered (host + any pre-join peers)
	_on_player_list_changed()


func _exit_tree() -> void:
	if NetworkManager.player_list_changed.is_connected(_on_player_list_changed):
		NetworkManager.player_list_changed.disconnect(_on_player_list_changed)


func _on_player_list_changed() -> void:
	for peer_id: int in NetworkManager.players:
		if not _spawned.has(peer_id):
			var pname: String = NetworkManager.players[peer_id].get("name", "Player")
			_do_spawn(peer_id, pname)


func _do_spawn(peer_id: int, player_name: String) -> void:
	var scene  := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as PlayerController
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	var keys: Array = NetworkManager.players.keys() if multiplayer.has_multiplayer_peer() else [1]
	var idx: int = keys.find(peer_id)
	if idx < 0:
		idx = 0
	player.position = SPAWN_POINTS[idx % SPAWN_POINTS.size()]

	$Players.add_child(player)
	_spawned[peer_id] = player
	player.init_player(player_name)

	var is_local := not multiplayer.has_multiplayer_peer() or player.is_multiplayer_authority()
	if is_local and is_instance_valid(_hud):
		_hud.connect_player(player)
