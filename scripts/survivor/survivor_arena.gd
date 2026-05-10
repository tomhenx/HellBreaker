class_name SurvivorArena
extends Node2D

const PLAYER_SCENE := "res://scenes/player/player.tscn"

# Massive arena — takes ~42 seconds to cross at full sprint
const FLOOR_R := 4200.0
const WALL_R  := 4188.0
const OUTER_R := 4260.0

const _PLAYER_SPAWN_POINTS := [
	Vector2(  0,  0),
	Vector2( 50,  0),
	Vector2(-50,  0),
	Vector2(  0, 50),
]

# Spawn enemy near a player, not at fixed arena points
const ENEMY_SPAWN_MIN_DIST := 200.0
const ENEMY_SPAWN_MAX_DIST := 500.0

# How many random objects to scatter
const PILLAR_COUNT     := 120
const LAVA_PIT_COUNT   := 28
const BONE_PILE_COUNT  := 90
const TORCH_WALL_COUNT := 50
const TORCH_INT_COUNT  := 40

const _AMBIENT_PATH        := "res://assets/audio/sfx/sfx_deep__20260508_131349.mp3"
const _SFX_COUNTDOWN_TICK  := "res://assets/audio/sfx/arena_countdown_tick.mp3"
const _SFX_ARENA_START     := "res://assets/audio/sfx/arena_start.mp3"
const _SFX_GAME_OVER       := "res://assets/audio/sfx/arena_game_over.mp3"
const _SFX_PLAYER_JOIN     := "res://assets/audio/sfx/player_join.mp3"

var _hud:            HUD
var _wave_manager:   WaveManager
var _spawned:        Dictionary = {}
var _light_tex:      GradientTexture2D
var _timer_label:    Label
var _lava_positions: Array = []
var _game_over:      bool  = false
var _sfx:            Dictionary = {}  # name -> AudioStreamPlayer

const REVIVE_RANGE   := 70.0
const REVIVE_TIME    := 10.0
const REVIVE_HP_PCT  := 0.30
const LOBBY_SCENE    := "res://scenes/lobby/hell_lobby.tscn"

var _revive_timers:   Dictionary = {}  # dead PlayerController -> float
var _run_elapsed:     float      = 0.0
var _player_results:  Array      = []  # collected per-player result dicts
var _countdown_label: Label      = null


func _ready() -> void:
	randomize()
	_light_tex = _make_light_texture()

	_hud = HUD.new()
	$UILayer.add_child(_hud)

	_build_atmosphere()
	_build_floor()
	_build_walls()
	_scatter_objects()
	_setup_lights()
	_setup_audio()
	_build_lava_kill_zones()
	_build_timer_label()

	if not multiplayer.has_multiplayer_peer():
		_do_spawn(1, "Player")
	else:
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
		_on_player_list_changed()

	_begin_countdown()


func _process(delta: float) -> void:
	if not _game_over:
		_run_elapsed += delta
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_process_revive(delta)


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and \
			NetworkManager.player_list_changed.is_connected(_on_player_list_changed):
		NetworkManager.player_list_changed.disconnect(_on_player_list_changed)


# ── Spawn management (time-based) ────────────────────────────────────────────

func _build_timer_label() -> void:
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 20)
	_timer_label.add_theme_color_override("font_color", Color("#FFDDAA"))
	_timer_label.add_theme_color_override("font_outline_color", Color("#000000"))
	_timer_label.add_theme_constant_override("outline_size", 3)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.anchor_left   = 0.5
	_timer_label.anchor_right  = 0.5
	_timer_label.anchor_top    = 0.0
	_timer_label.anchor_bottom = 0.0
	_timer_label.offset_left   = -200.0
	_timer_label.offset_right  =  200.0
	_timer_label.offset_top    =  10.0
	_timer_label.offset_bottom =  40.0
	_timer_label.text = ""
	$UILayer.add_child(_timer_label)


func _start_waves() -> void:
	if not is_instance_valid(self):
		return
	MusicManager.play_survivor_music()
	if is_instance_valid(_countdown_label):
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", Color("#FFEE00"))
		_countdown_label.scale    = Vector2(0.5, 0.5)
		_countdown_label.modulate = Color.WHITE
		var tw := create_tween()
		tw.tween_property(_countdown_label, "scale", Vector2(1.2, 1.2), 0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_countdown_label, "scale", Vector2(1.0, 1.0), 0.08)
		tw.tween_interval(0.35)
		tw.tween_property(_countdown_label, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if is_instance_valid(_countdown_label):
				_countdown_label.queue_free()
				_countdown_label = null)
	_wave_manager = WaveManager.new()
	_wave_manager.difficulty_tick.connect(_on_difficulty_tick)
	add_child(_wave_manager)
	_wave_manager.start()


func _on_difficulty_tick(elapsed: float, _intensity: float) -> void:
	if not is_instance_valid(_timer_label):
		return
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	if mins > 0:
		_timer_label.text = "%d minutes %d seconds" % [mins, secs]
	else:
		_timer_label.text = "%d seconds" % secs
	# Tint red as difficulty climbs
	var t := clampf(_intensity, 0.0, 1.0)
	_timer_label.add_theme_color_override("font_color",
		Color(1.0, lerpf(0.87, 0.27, t), lerpf(0.67, 0.07, t)))


# ── Atmosphere ──────────────────────────────────────────────────────────────

func _build_atmosphere() -> void:
	var mod := CanvasModulate.new()
	mod.color = Color(0.48, 0.16, 0.08)
	add_child(mod)


# ── Floor ───────────────────────────────────────────────────────────────────

func _build_floor() -> void:
	var fn: Node2D = $Floor
	_poly_ring(fn, FLOOR_R, OUTER_R, 80, Color("#0d0402"))
	_circle_poly(fn, Vector2.ZERO, FLOOR_R,        80, Color("#140704"))
	_circle_poly(fn, Vector2.ZERO, FLOOR_R * 0.70, 72, Color("#170905"))
	_circle_poly(fn, Vector2.ZERO, FLOOR_R * 0.35, 56, Color("#1a0c07"))
	_poly_ring(fn, FLOOR_R - 25.0, FLOOR_R, 80, Color("#100402"))

	# Blood splatters
	for i in 60:
		var a := randf() * TAU
		var r := randf_range(60.0, FLOOR_R * 0.85)
		_circle_poly(fn, Vector2(cos(a), sin(a)) * r,
			randf_range(10.0, 35.0), 12, Color(0.20, 0.03, 0.01, randf_range(0.5, 0.85)))

	# Cracks / dark lines (stylized as thin polygons)
	for i in 30:
		var a := randf() * TAU
		var r0 := randf_range(30.0, FLOOR_R * 0.80)
		var r1 := r0 + randf_range(40.0, 180.0)
		var da := randf_range(0.02, 0.06)
		var pts := PackedVector2Array([
			Vector2(cos(a),      sin(a))      * r0,
			Vector2(cos(a + da), sin(a + da)) * r0,
			Vector2(cos(a + da), sin(a + da)) * r1,
			Vector2(cos(a),      sin(a))      * r1,
		])
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color   = Color(0.06, 0.01, 0.0, 0.7)
		fn.add_child(poly)


# ── Walls ───────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "WallBody"
	add_child(body)
	const SEGS := 160
	for i in SEGS:
		var a0 := TAU * i       / float(SEGS)
		var a1 := TAU * (i + 1) / float(SEGS)
		var cs  := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = Vector2(cos(a0), sin(a0)) * WALL_R
		seg.b = Vector2(cos(a1), sin(a1)) * WALL_R
		cs.shape = seg
		body.add_child(cs)


# ── Scattered objects ────────────────────────────────────────────────────────

func _scatter_objects() -> void:
	var objs: Node2D = $Objects

	# ── Pillars ──────────────────────────────────────────────────────────
	for i in PILLAR_COUNT:
		var pos := _rand_pos(220.0, FLOOR_R * 0.90)
		_place_pillar(objs, pos)

	# ── Lava pits ─────────────────────────────────────────────────────────
	for i in LAVA_PIT_COUNT:
		var pos := _rand_pos(300.0, FLOOR_R * 0.88)
		_lava_positions.append(pos)
		_place_lava_pit(objs, pos)

	# ── Bone / skull piles ────────────────────────────────────────────────
	var bone_tex := load("res://assets/sprites/objects/skull_pile.png") as Texture2D
	for i in BONE_PILE_COUNT:
		var pos := _rand_pos(120.0, FLOOR_R * 0.92)
		_place_sprite_object(objs, bone_tex, pos, randf_range(1.4, 2.2))

	# ── Wall torches ──────────────────────────────────────────────────────
	var torch_tex := load("res://assets/sprites/objects/torch.png") as Texture2D
	for i in TORCH_WALL_COUNT:
		var a   := randf() * TAU
		var pos := Vector2(cos(a), sin(a)) * randf_range(FLOOR_R * 0.88, FLOOR_R * 0.95)
		_place_sprite_object(objs, torch_tex, pos, 1.8)

	# ── Interior torches ──────────────────────────────────────────────────
	for i in TORCH_INT_COUNT:
		var pos := _rand_pos(200.0, FLOOR_R * 0.70)
		_place_sprite_object(objs, torch_tex, pos, 1.6)

	# ── Chains near wall ──────────────────────────────────────────────────
	var chain_tex := load("res://assets/sprites/objects/chains.png") as Texture2D
	for i in 16:
		var a   := randf() * TAU
		var pos := Vector2(cos(a), sin(a)) * randf_range(FLOOR_R * 0.80, FLOOR_R * 0.93)
		_place_sprite_object(objs, chain_tex, pos, 1.8)

	# ── Pentagrams (occasional ritual circles) ────────────────────────────
	var pent_tex := load("res://assets/sprites/objects/pentagram.png") as Texture2D
	for i in 6:
		var pos := _rand_pos(350.0, FLOOR_R * 0.80)
		_place_sprite_object(objs, pent_tex, pos, randf_range(1.6, 2.8))

	# ── Lava pools decoration (static, no kill zone) ──────────────────────
	var lava_tex := load("res://assets/sprites/objects/lava_pool.png") as Texture2D
	for i in 8:
		var pos := _rand_pos(250.0, FLOOR_R * 0.85)
		_place_sprite_object(objs, lava_tex, pos, randf_range(1.6, 2.4))


func _rand_pos(min_r: float, max_r: float) -> Vector2:
	var a := randf() * TAU
	var r := sqrt(randf_range(min_r * min_r, max_r * max_r))
	return Vector2(cos(a), sin(a)) * r


func _place_pillar(parent: Node2D, pos: Vector2) -> void:
	# Blocky stone pillar: visual circle + collision
	var body := StaticBody2D.new()
	body.position = pos
	parent.add_child(body)

	# Collision
	var cs    := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	var r     := randf_range(14.0, 24.0)
	shape.radius = r
	cs.shape = shape
	body.add_child(cs)

	# Visual: stacked circles for depth
	_circle_poly(body, Vector2.ZERO, r + 3.0, 10, Color(0.16, 0.10, 0.07))
	_circle_poly(body, Vector2.ZERO, r,        10, Color(0.28, 0.18, 0.12))
	_circle_poly(body, Vector2(-2, -3), r * 0.55, 8, Color(0.38, 0.26, 0.18))
	_circle_poly(body, Vector2(-3, -5), r * 0.20, 6, Color(0.50, 0.36, 0.24))


func _place_lava_pit(parent: Node2D, pos: Vector2) -> void:
	var pit := Node2D.new()
	pit.position = pos
	parent.add_child(pit)
	_circle_poly(pit, Vector2.ZERO, 48.0, 20, Color("#5a1200"))
	_circle_poly(pit, Vector2.ZERO, 34.0, 20, Color("#aa2c00"))
	_circle_poly(pit, Vector2.ZERO, 18.0, 16, Color("#ff6600"))
	_circle_poly(pit, Vector2.ZERO, 8.0,  12, Color("#ffcc00"))


func _place_sprite_object(parent: Node2D, tex: Texture2D, pos: Vector2, sc: float) -> void:
	if tex == null:
		return
	var root := Node2D.new()
	root.position = pos
	parent.add_child(root)
	var s := Sprite2D.new()
	s.texture        = tex
	s.scale          = Vector2(sc, sc)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(s)


# ── Lava kill zones ──────────────────────────────────────────────────────────

func _build_lava_kill_zones() -> void:
	for pos: Vector2 in _lava_positions:
		var area := Area2D.new()
		area.position       = pos
		area.collision_layer = 0
		area.collision_mask = 2  # player layer
		var cs    := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 28.0
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(func(b: Node2D) -> void: _on_lava_body_entered(pos, b))
		add_child(area)


func _on_lava_body_entered(lava_pos: Vector2, body: Node2D) -> void:
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var peer_id := body.get_multiplayer_authority()
	if multiplayer.has_multiplayer_peer():
		_rpc_lava_kill.rpc(peer_id)
	else:
		_do_lava_kill(peer_id)


@rpc("authority", "reliable", "call_local")
func _rpc_lava_kill(peer_id: int) -> void:
	_do_lava_kill(peer_id)


func _do_lava_kill(peer_id: int) -> void:
	var player: PlayerController = _find_player_by_authority(peer_id)
	if not is_instance_valid(player):
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(player, "scale",    Vector2(0.05, 0.05),        0.28).set_ease(Tween.EASE_IN)
	tw.tween_property(player, "modulate", Color(2.0, 0.55, 0.0, 0.0), 0.28).set_ease(Tween.EASE_IN)
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		tw.chain().tween_callback(func():
			if is_instance_valid(player):
				player.take_damage(99999.0))


# ── Lighting ─────────────────────────────────────────────────────────────────

func _setup_lights() -> void:
	var lights: Node2D = $Lights

	# Dim ambient light for the full arena
	var ambient := _make_light(Vector2.ZERO, Color(0.80, 0.12, 0.02), 22.0, 0.18)
	lights.add_child(ambient)
	_anim_pulse(ambient, 0.13, 0.22, 6.0)

	# Lava pit lights
	for pos: Vector2 in _lava_positions:
		var l := _make_light(pos, Color(1.0, 0.30, 0.02), 1.4, 0.40)
		lights.add_child(l)
		_anim_pulse(l, 0.28, 0.55, 2.2 + randf() * 1.5)

	# Sample some torch positions for lights (can't light every torch — too many)
	var torch_count := 0
	for child in $Objects.get_children():
		if torch_count >= 40:
			break
		if not child is Node2D:
			continue
		var l := _make_light(child.position, Color(1.0, 0.42, 0.08), 1.0, 0.45)
		lights.add_child(l)
		_anim_flicker(l, 0.45)
		torch_count += 1


func _make_light_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill     = GradientTexture2D.FILL_RADIAL
	gtex.width    = 256
	gtex.height   = 256
	return gtex


func _make_light(pos: Vector2, col: Color, tex_scale: float, energy: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.position      = pos
	light.color         = col
	light.energy        = energy
	light.texture       = _light_tex
	light.texture_scale = tex_scale
	return light


func _anim_flicker(light: PointLight2D, base: float) -> void:
	var ap  := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var a   := Animation.new()
	a.loop_mode = Animation.LOOP_LINEAR
	var dur := 0.30 + randf() * 0.35
	a.length = dur
	var tr := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr, ".:energy")
	a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
	a.track_insert_key(tr, 0.0,        base)
	a.track_insert_key(tr, dur * 0.22, base * 0.58)
	a.track_insert_key(tr, dur * 0.55, base * 0.86)
	a.track_insert_key(tr, dur * 0.80, base * 0.70)
	a.track_insert_key(tr, dur,        base)
	lib.add_animation("flicker", a)
	ap.add_animation_library("", lib)
	light.add_child(ap)
	ap.play("flicker")


func _anim_pulse(light: PointLight2D, e_min: float, e_max: float, period: float) -> void:
	var ap  := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var a   := Animation.new()
	a.loop_mode = Animation.LOOP_LINEAR
	a.length = period
	var tr := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr, ".:energy")
	a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
	a.track_insert_key(tr, 0.0,          e_min)
	a.track_insert_key(tr, period * 0.5, e_max)
	a.track_insert_key(tr, period,       e_min)
	lib.add_animation("pulse", a)
	ap.add_animation_library("", lib)
	light.add_child(ap)
	ap.play("pulse")


# ── Audio ────────────────────────────────────────────────────────────────────

func _setup_audio() -> void:
	var ambient := load(_AMBIENT_PATH) as AudioStream
	if ambient != null:
		var p := AudioStreamPlayer.new()
		p.stream    = ambient
		p.volume_db = -8.0
		p.finished.connect(p.play)
		add_child(p)
		p.play()

	for entry: Array in [
		["tick",       _SFX_COUNTDOWN_TICK, -4.0],
		["game_over",  _SFX_GAME_OVER,      -3.0],
		["player_join",_SFX_PLAYER_JOIN,    -5.0],
	]:
		var s := load(entry[1]) as AudioStream
		if s == null:
			continue
		var p2 := AudioStreamPlayer.new()
		p2.stream    = s
		p2.volume_db = float(entry[2])
		add_child(p2)
		_sfx[entry[0]] = p2


func _play_sfx(sfx_name: String) -> void:
	var p: AudioStreamPlayer = _sfx.get(sfx_name, null)
	if is_instance_valid(p):
		p.play()


# ── Countdown before waves start ──────────────────────────────────────────────

func _begin_countdown() -> void:
	# Dedicated full-screen label — created here, destroyed after GO! fades
	_countdown_label = Label.new()
	_countdown_label.add_theme_font_size_override("font_size", 120)
	_countdown_label.add_theme_color_override("font_color", Color("#FF4422"))
	_countdown_label.add_theme_color_override("font_outline_color", Color("#000000"))
	_countdown_label.add_theme_constant_override("outline_size", 8)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.anchor_left   = 0.0
	_countdown_label.anchor_right  = 1.0
	_countdown_label.anchor_top    = 0.0
	_countdown_label.anchor_bottom = 1.0
	_countdown_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	$UILayer.add_child(_countdown_label)

	_show_countdown_number(3)
	get_tree().create_timer(1.0).timeout.connect(func(): _show_countdown_number(2))
	get_tree().create_timer(2.0).timeout.connect(func(): _show_countdown_number(1))
	get_tree().create_timer(3.0).timeout.connect(_start_waves)


func _show_countdown_number(n: int) -> void:
	_play_sfx("tick")
	if not is_instance_valid(_countdown_label):
		return
	_countdown_label.text     = str(n)
	_countdown_label.scale    = Vector2(0.5, 0.5)
	_countdown_label.modulate = Color.WHITE
	_countdown_label.add_theme_color_override("font_color", Color("#FF4422"))
	var tw := create_tween()
	tw.tween_property(_countdown_label, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.25)
	tw.tween_property(_countdown_label, "modulate:a", 0.0, 0.50).set_ease(Tween.EASE_IN)


# ── Player spawning ───────────────────────────────────────────────────────────

func _do_spawn(peer_id: int, player_name: String) -> void:
	var scene  := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as PlayerController
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	var keys: Array = NetworkManager.players.keys() if multiplayer.has_multiplayer_peer() else [1]
	var idx := maxi(0, keys.find(peer_id))
	player.position = _PLAYER_SPAWN_POINTS[idx % _PLAYER_SPAWN_POINTS.size()]
	$Players.add_child(player)
	_spawned[peer_id] = player
	player.init_player(player_name)
	player.can_respawn = false
	player.died.connect(_on_player_died)
	var is_local := not multiplayer.has_multiplayer_peer() or player.is_multiplayer_authority()
	if is_local and is_instance_valid(_hud):
		_hud.connect_player(player)
	# Play join sound for every player (including local in multiplayer, skip in solo)
	if multiplayer.has_multiplayer_peer():
		_play_sfx("player_join")


func _on_player_list_changed() -> void:
	for peer_id: int in NetworkManager.players:
		if not _spawned.has(peer_id):
			var pname: String = NetworkManager.players[peer_id].get("name", "Player")
			_do_spawn(peer_id, pname)


# ── Revive system ─────────────────────────────────────────────────────────────

func _process_revive(delta: float) -> void:
	if _game_over:
		return
	var all_players := get_tree().get_nodes_in_group("players")
	var dead_list: Array[PlayerController]  = []
	var alive_list: Array[PlayerController] = []
	for node: Node in all_players:
		if not node is PlayerController:
			continue
		var pc := node as PlayerController
		if pc._is_dead:
			dead_list.append(pc)
		else:
			alive_list.append(pc)

	for dead: PlayerController in dead_list:
		var reviver: PlayerController = null
		for alive: PlayerController in alive_list:
			if alive.global_position.distance_to(dead.global_position) <= REVIVE_RANGE:
				reviver = alive
				break

		if is_instance_valid(reviver):
			var prev: float = _revive_timers.get(dead, 0.0)
			var next: float = prev + delta
			_revive_timers[dead] = next
			var progress: float = clampf(next / REVIVE_TIME, 0.0, 1.0)
			_rpc_revive_progress.rpc(dead.name, progress)
			if next >= REVIVE_TIME:
				_revive_timers.erase(dead)
				dead.revive(REVIVE_HP_PCT)
				_rpc_revive_progress.rpc(dead.name, -1.0)  # -1 = done, hide bar
		else:
			if _revive_timers.has(dead):
				_revive_timers.erase(dead)
				_rpc_revive_progress.rpc(dead.name, 0.0)


@rpc("authority", "reliable", "call_local")
func _rpc_revive_progress(player_name: String, progress: float) -> void:
	# find the dead player's down-overlay and update its bar
	var target: PlayerController = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == player_name and node is PlayerController:
			target = node as PlayerController
			break
	if not is_instance_valid(target):
		return
	var bar: ProgressBar = target.get_meta("revive_bar", null)
	if progress < 0.0:
		# Revived — hide overlay
		var overlay: Control = target.get_meta("down_overlay", null)
		if is_instance_valid(overlay):
			overlay.queue_free()
		return
	if not is_instance_valid(bar):
		return
	bar.value = progress * 100.0
	bar.visible = progress > 0.0


# ── Death / game-over ─────────────────────────────────────────────────────────

func _on_player_died() -> void:
	if _game_over:
		return

	# In multiplayer only: show "down" overlay so the player can wait for revive
	if multiplayer.has_multiplayer_peer():
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node is PlayerController:
				var pc := node as PlayerController
				if pc._is_dead and not pc.has_meta("down_overlay") and pc.is_multiplayer_authority():
					_build_down_overlay(pc)

	# Server checks if all are dead
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var any_alive := false
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node is PlayerController and not (node as PlayerController)._is_dead:
				any_alive = true
				break
		if not any_alive:
			_trigger_game_over()


func _trigger_game_over() -> void:
	if _game_over:
		return
	_game_over = true
	if is_instance_valid(_wave_manager):
		_wave_manager.set_process(false)

	# Collect results from all players
	var results: Array = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			var pc := node as PlayerController
			results.append({
				"name":           pc.name,
				"kills":          pc.stat_kills,
				"damage_dealt":   int(pc.stat_damage_dealt),
				"damage_taken":   int(pc.stat_damage_taken),
				"coins":          pc.coins,
				"level":          pc.level,
			})

	var mins: int = int(_run_elapsed) / 60
	var secs: int = int(_run_elapsed) % 60
	var time_str := "%d:%02d" % [mins, secs]

	if multiplayer.has_multiplayer_peer():
		_rpc_show_results.rpc(time_str, results)
	else:
		_play_sfx("game_over")
		_show_results_screen(time_str, results)


@rpc("authority", "reliable", "call_local")
func _rpc_show_results(time_str: String, results: Array) -> void:
	_play_sfx("game_over")
	_show_results_screen(time_str, results)


# ── Results screen ─────────────────────────────────────────────────────────────

func _build_down_overlay(pc: PlayerController) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	pc.add_child(layer)
	pc.set_meta("down_overlay", layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)

	var lbl := Label.new()
	lbl.text = "YOU ARE DOWN\nWaiting for revive..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color("#FF4422"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.anchor_left   = 0.5
	lbl.anchor_right  = 0.5
	lbl.anchor_top    = 0.4
	lbl.anchor_bottom = 0.6
	lbl.offset_left   = -250.0
	lbl.offset_right  =  250.0
	layer.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value     = 0
	bar.visible   = false
	bar.anchor_left   = 0.5
	bar.anchor_right  = 0.5
	bar.anchor_top    = 0.62
	bar.anchor_bottom = 0.62
	bar.offset_left   = -150.0
	bar.offset_right  =  150.0
	bar.offset_top    = 0.0
	bar.offset_bottom = 24.0
	layer.add_child(bar)
	pc.set_meta("revive_bar", bar)


func _show_results_screen(time_str: String, results: Array) -> void:
	MusicManager.play_game_over()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	# Dark overlay
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.0, 0.06, 0.93)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)

	# Title
	var title := Label.new()
	title.text = "RESULTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color("#FF3300"))
	title.add_theme_color_override("font_outline_color", Color("#000000"))
	title.add_theme_constant_override("outline_size", 5)
	title.anchor_left  = 0.5
	title.anchor_right = 0.5
	title.offset_left  = -200.0
	title.offset_right = 200.0
	title.offset_top   = 28.0
	layer.add_child(title)

	# Time survived
	var time_lbl := Label.new()
	time_lbl.text = "Time Survived:  %s" % time_str
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_lbl.add_theme_font_size_override("font_size", 22)
	time_lbl.add_theme_color_override("font_color", Color("#FFDDAA"))
	time_lbl.anchor_left  = 0.5
	time_lbl.anchor_right = 0.5
	time_lbl.offset_left  = -240.0
	time_lbl.offset_right = 240.0
	time_lbl.offset_top   = 96.0
	layer.add_child(time_lbl)

	# Player cards — laid out as a horizontal row centred on screen
	var card_w    := 210.0
	var card_h    := 240.0
	var card_gap  := 20.0
	var total_w   := results.size() * card_w + (results.size() - 1) * card_gap
	var start_x   := -total_w / 2.0

	for i: int in results.size():
		var data: Dictionary = results[i]
		var cx: float = start_x + i * (card_w + card_gap)
		_build_player_card(layer, data, cx, 140.0, card_w, card_h)

	# Back to Lobby button (only shown to the local authority player)
	var is_auth := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_auth:
		var btn := Button.new()
		btn.text = "Back to Lobby"
		btn.anchor_left   = 0.5
		btn.anchor_right  = 0.5
		btn.anchor_top    = 1.0
		btn.anchor_bottom = 1.0
		btn.offset_left   = -120.0
		btn.offset_right  =  120.0
		btn.offset_top    = -70.0
		btn.offset_bottom = -30.0
		btn.add_theme_font_size_override("font_size", 18)
		layer.add_child(btn)
		btn.pressed.connect(func():
			if multiplayer.has_multiplayer_peer():
				_rpc_load_lobby.rpc(LOBBY_SCENE)
			else:
				get_tree().change_scene_to_file(LOBBY_SCENE))


func _build_player_card(parent: CanvasLayer, data: Dictionary,
		cx: float, cy: float, w: float, h: float) -> void:
	var card := ColorRect.new()
	card.color = Color(0.10, 0.04, 0.14, 0.90)
	card.anchor_left   = 0.5
	card.anchor_right  = 0.5
	card.anchor_top    = 0.0
	card.anchor_bottom = 0.0
	card.offset_left   = cx
	card.offset_right  = cx + w
	card.offset_top    = cy
	card.offset_bottom = cy + h
	parent.add_child(card)

	# Border
	var border := ColorRect.new()
	border.color = Color(0.55, 0.15, 0.65, 1.0)
	border.anchor_right  = 1.0
	border.anchor_bottom = 0.0
	border.offset_bottom = 3.0
	card.add_child(border)

	var rows: Array[Array] = [
		["Player",        str(data.get("name", "?"))],
		["Level",         "Lv %d" % data.get("level", 1)],
		["Kills",         str(data.get("kills", 0))],
		["Damage Dealt",  str(data.get("damage_dealt", 0))],
		["Damage Taken",  str(data.get("damage_taken", 0))],
		["Coins",         str(data.get("coins", 0))],
	]
	for r: int in rows.size():
		var label_txt: String = rows[r][0]
		var value_txt: String = rows[r][1]
		var y_off: float = 12.0 + r * 36.0

		var lbl := Label.new()
		lbl.text = label_txt
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color("#AAAACC"))
		lbl.position = Vector2(10.0, y_off)
		lbl.size     = Vector2(w - 20.0, 28.0)
		card.add_child(lbl)

		var val := Label.new()
		val.text = value_txt
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color", Color("#FFFFFF"))
		val.position = Vector2(10.0, y_off)
		val.size     = Vector2(w - 20.0, 28.0)
		card.add_child(val)


@rpc("authority", "reliable", "call_local")
func _rpc_load_lobby(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _find_player_by_authority(peer_id: int) -> PlayerController:
	for p: Node in get_tree().get_nodes_in_group("players"):
		if p is PlayerController and p.get_multiplayer_authority() == peer_id:
			return p as PlayerController
	return null


# ── Polygon helpers ──────────────────────────────────────────────────────────

func _circle_poly(parent: Node, center: Vector2, r: float, segments: int, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_add_poly(parent, pts, col)


func _poly_ring(parent: Node, r_inner: float, r_outer: float, segments: int, col: Color) -> void:
	for i in segments:
		var a0 := TAU * i       / float(segments)
		var a1 := TAU * (i + 1) / float(segments)
		var quad := PackedVector2Array([
			Vector2(cos(a0), sin(a0)) * r_inner,
			Vector2(cos(a1), sin(a1)) * r_inner,
			Vector2(cos(a1), sin(a1)) * r_outer,
			Vector2(cos(a0), sin(a0)) * r_outer,
		])
		_add_poly(parent, quad, col)


func _add_poly(parent: Node, pts: PackedVector2Array, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color   = col
	parent.add_child(p)
