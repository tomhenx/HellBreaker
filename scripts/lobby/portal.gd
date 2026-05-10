class_name Portal
extends Area2D

enum PortalType { SURVIVOR, DUNGEON_CRAWLER }

signal countdown_tick(seconds_left: float)
signal portal_entered
signal portal_blocked  # fired when coming_soon portal countdown hits 0
signal players_status(inside: int, total: int)

@export var portal_type:   PortalType = PortalType.SURVIVOR
@export var target_scene:  String     = ""
@export var coming_soon:   bool       = false

const COUNTDOWN_SECONDS := 5.0
const PORTAL_HUM_PATH   := "res://assets/audio/sfx/portal_survivor_hum.mp3"
const PORTAL_ENTER_PATH := "res://assets/audio/sfx/portal_enter.mp3"

var _players_inside:    Array = []
var _countdown:         float = -1.0
var _is_transitioning:  bool  = false

var _hum_sfx:   AudioStreamPlayer
var _enter_sfx: AudioStreamPlayer


func _ready() -> void:
	var cs    := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 48.0
	cs.shape     = shape
	add_child(cs)

	collision_layer = 0
	collision_mask  = 2  # player layer

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_hum_sfx = AudioStreamPlayer.new()
	_hum_sfx.volume_db = -14.0
	var hum_stream := load(PORTAL_HUM_PATH) as AudioStream
	if hum_stream:
		_hum_sfx.stream = hum_stream
		_hum_sfx.finished.connect(_hum_sfx.play)
	add_child(_hum_sfx)
	_hum_sfx.play()

	_enter_sfx = AudioStreamPlayer.new()
	_enter_sfx.volume_db = -4.0
	var enter_stream := load(PORTAL_ENTER_PATH) as AudioStream
	if enter_stream:
		_enter_sfx.stream = enter_stream
	add_child(_enter_sfx)


func _process(delta: float) -> void:
	if _is_transitioning:
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		if _countdown >= 0.0:
			_countdown -= delta
			if multiplayer.has_multiplayer_peer():
				_rpc_tick.rpc(_countdown)
			countdown_tick.emit(_countdown)
			if _countdown <= 0.0:
				_trigger_transition()


func _on_body_entered(body: Node) -> void:
	if not body is PlayerController:
		return
	if not _players_inside.has(body):
		_players_inside.append(body)
	_check_all_players()


func _on_body_exited(body: Node) -> void:
	_players_inside.erase(body)
	if _countdown >= 0.0 and not _is_transitioning:
		_countdown = -1.0
		if multiplayer.has_multiplayer_peer():
			_rpc_cancel.rpc()
		else:
			countdown_tick.emit(-1.0)
	var total := get_tree().get_nodes_in_group("players").size()
	if multiplayer.has_multiplayer_peer():
		_rpc_status.rpc(_players_inside.size(), total)
	else:
		players_status.emit(_players_inside.size(), total)


func _check_all_players() -> void:
	if _is_transitioning:
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var total_players := get_tree().get_nodes_in_group("players").size()
		var inside := _players_inside.size()
		if multiplayer.has_multiplayer_peer():
			_rpc_status.rpc(inside, total_players)
		else:
			players_status.emit(inside, total_players)
		if total_players > 0 and inside >= total_players:
			if _countdown < 0.0:
				_countdown = COUNTDOWN_SECONDS


@rpc("authority", "unreliable_ordered")
func _rpc_tick(seconds: float) -> void:
	countdown_tick.emit(seconds)


@rpc("authority", "reliable", "call_local")
func _rpc_cancel() -> void:
	_countdown = -1.0
	countdown_tick.emit(-1.0)


@rpc("authority", "reliable", "call_local")
func _rpc_status(inside: int, total: int) -> void:
	players_status.emit(inside, total)


func _trigger_transition() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	if is_instance_valid(_enter_sfx) and _enter_sfx.stream != null:
		_enter_sfx.play()

	if coming_soon or target_scene.is_empty():
		# Reset so player can try again after the message clears
		if multiplayer.has_multiplayer_peer():
			_rpc_blocked.rpc()
		else:
			_do_blocked()
		return

	portal_entered.emit()
	if multiplayer.has_multiplayer_peer():
		_rpc_load_scene.rpc(target_scene)
	else:
		_do_load_scene(target_scene)


@rpc("authority", "reliable", "call_local")
func _rpc_blocked() -> void:
	_do_blocked()


func _do_blocked() -> void:
	portal_blocked.emit()
	# Allow re-entry after 3 seconds
	get_tree().create_timer(3.0).timeout.connect(func():
		_is_transitioning = false
		_countdown        = -1.0)


@rpc("authority", "reliable", "call_local")
func _rpc_load_scene(scene_path: String) -> void:
	_do_load_scene(scene_path)


func _do_load_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
