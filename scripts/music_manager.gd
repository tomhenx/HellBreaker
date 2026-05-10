extends Node

const _MENU_TRACKS: Array[String] = [
	"res://assets/audio/music/menu_theme_1.mp3",
	"res://assets/audio/music/menu_theme_2.mp3",
	"res://assets/audio/music/menu_theme_3.mp3",
	"res://assets/audio/music/menu_theme_4.mp3",
]

const _SURVIVOR_TRACKS: Array[String] = [
	"res://assets/audio/music/survivor_1.mp3",
	"res://assets/audio/music/survivor_2.mp3",
	"res://assets/audio/music/survivor_3.mp3",
	"res://assets/audio/music/survivor_4.mp3",
	"res://assets/audio/music/survivor_5.mp3",
	"res://assets/audio/music/survivor_6.mp3",
	"res://assets/audio/music/survivor_7.mp3",
	"res://assets/audio/music/survivor_8.mp3",
	"res://assets/audio/music/survivor_9.mp3",
	"res://assets/audio/music/survivor_10.mp3",
]

var _player:         AudioStreamPlayer
var _volume_linear:  float         = 0.75
var _mode:           String        = "idle"
var _queue:          Array[String] = []


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.finished.connect(_on_finished)


# ── Public API ────────────────────────────────────────────────────────────────

func play_menu_music() -> void:
	if _mode == "boss" or _mode == "gameover":
		return
	if _mode == "menu" and _player.playing:
		return
	_mode = "menu"
	_rebuild_queue(_MENU_TRACKS)
	_advance()


func play_survivor_music() -> void:
	_mode = "survivor"
	_rebuild_queue(_SURVIVOR_TRACKS)
	_crossfade_to(_queue.pop_front())


func play_boss_music(path: String) -> void:
	_mode = "boss"
	_crossfade_to(path)


func stop_boss_music(fade_secs: float = 3.5) -> void:
	var tw := create_tween()
	tw.tween_property(_player, "volume_db", -80.0, fade_secs)
	tw.tween_callback(func():
		_player.stop()
		_mode = "idle"
	)


func play_game_over() -> void:
	const _PATH := "res://assets/audio/music/game_over.mp3"
	_mode = "gameover"
	var s := load(_PATH) as AudioStream
	if s == null:
		return
	_player.stop()
	_player.stream    = s
	_player.volume_db = _vol_db()
	_player.play()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_player, "volume_db", -80.0, 4.0)
	tw.tween_callback(_player.stop)


func stop_all(_fade_secs: float = 0.5) -> void:
	_mode = "idle"
	_player.stop()


func set_volume(linear: float) -> void:
	_volume_linear = clampf(linear, 0.0, 1.0)
	if _player.playing:
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", _vol_db(), 0.1)


func get_volume() -> float:
	return _volume_linear


# ── Internal ──────────────────────────────────────────────────────────────────

func _vol_db() -> float:
	if _volume_linear <= 0.001:
		return -80.0
	return linear_to_db(_volume_linear)


func _on_finished() -> void:
	match _mode:
		"menu":     _advance()
		"survivor": _advance()


func _advance() -> void:
	if _queue.is_empty():
		var src := _MENU_TRACKS if _mode == "menu" else _SURVIVOR_TRACKS
		_rebuild_queue(src)
	if _queue.is_empty():
		return
	_crossfade_to(_queue.pop_front())


func _rebuild_queue(tracks: Array[String]) -> void:
	_queue.clear()
	for t: String in tracks:
		if ResourceLoader.exists(t):
			_queue.append(t)
	_queue.shuffle()


func _crossfade_to(path: String) -> void:
	var s := load(path) as AudioStream
	if s == null:
		return
	var target_db := _vol_db()
	if _player.playing:
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", -80.0, 0.5)
		tw.tween_callback(func():
			_player.stream    = s
			_player.volume_db = -80.0
			_player.play()
			var tw2 := create_tween()
			tw2.tween_property(_player, "volume_db", target_db, 1.5)
		)
	else:
		_player.stream    = s
		_player.volume_db = -80.0
		_player.play()
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", target_db, 1.5)
