class_name HellLobby
extends Node2D

const PLAYER_SCENE := "res://scenes/player/player.tscn"

const _OBJ := {
	portal       = "res://assets/sprites/objects/portal.png",
	pentagram    = "res://assets/sprites/objects/pentagram.png",
	skull_pile   = "res://assets/sprites/objects/skull_pile.png",
	torch        = "res://assets/sprites/objects/torch.png",
	torture_rack = "res://assets/sprites/objects/torture_rack.png",
	shop_counter = "res://assets/sprites/objects/shop_counter.png",
	lava_pool    = "res://assets/sprites/objects/lava_pool.png",
	chains       = "res://assets/sprites/objects/chains.png",
}

const _AMBIENT_PATH := "res://assets/audio/sfx/sfx_deep__20260508_131349.mp3"
const _LAVA_PATH    := "res://assets/audio/sfx/sfx_bubbl_20260508_131352.mp3"
const _PORTAL_PATH  := "res://assets/audio/sfx/sfx_deep__20260508_131356.mp3"
const _TORCH_PATH   := "res://assets/audio/sfx/sfx_crack_20260508_131400.mp3"

# Circular room geometry
const FLOOR_R := 620.0   # visual floor radius
const WALL_R  := 608.0   # physics collision radius
const OUTER_R := 665.0   # outer wall visual radius

# Portal positions (N quadrant, left = Survivor, right = Dungeon)
const _SURVIVOR_PORTAL_POS  := Vector2(-240, -420)
const _DUNGEON_PORTAL_POS   := Vector2( 240, -420)

# Single lava pit — bottom-right, clear of portals and merchant
const _LAVA_POSITIONS := [
	Vector2(310, 310),
]

# 8 torches evenly around the inner wall face (scaled for bigger room)
const _TORCH_POSITIONS := [
	Vector2(-390, -390),  # NW
	Vector2(   0, -554),  # N
	Vector2( 390, -390),  # NE
	Vector2( 554,    0),  # E
	Vector2( 390,  390),  # SE
	Vector2(   0,  554),  # S
	Vector2(-390,  390),  # SW
	Vector2(-554,    0),  # W
]

const _SPAWN_POINTS := [
	Vector2(  0, 220),
	Vector2( 70, 220),
	Vector2(-70, 220),
	Vector2(  0, 295),
]

const _SFX_TICK_PATH := "res://assets/audio/sfx/arena_countdown_tick.mp3"

var _spawned:          Dictionary = {}
var _hud:              HUD
var _light_tex:        GradientTexture2D
var _portal_banner:    Label
var _survivor_portal:  Portal
var _dungeon_portal:   Portal
var _portal_tick_sfx:  AudioStreamPlayer
var _last_portal_cd_int: int = -1


func _ready() -> void:
	_light_tex = _make_light_texture()

	_hud = HUD.new()
	$UILayer.add_child(_hud)

	_build_atmosphere()
	_build_floor()
	_build_walls()
	_place_objects()
	_setup_lights()
	_setup_audio()
	_build_lava_kill_zones()
	_build_portal_banner()

	if not multiplayer.has_multiplayer_peer():
		_do_spawn(1, "Player")
		return

	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	_on_player_list_changed()


func _build_portal_banner() -> void:
	_portal_banner = Label.new()
	_portal_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_portal_banner.offset_top    = -60.0
	_portal_banner.offset_bottom =  60.0
	_portal_banner.offset_left   = -320.0
	_portal_banner.offset_right  =  320.0
	_portal_banner.add_theme_font_size_override("font_size", 52)
	_portal_banner.add_theme_color_override("font_color",         Color("#AAFFCC"))
	_portal_banner.add_theme_color_override("font_outline_color", Color("#002200"))
	_portal_banner.add_theme_constant_override("outline_size",    8)
	_portal_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portal_banner.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_portal_banner.visible = false
	$UILayer.add_child(_portal_banner)


func _exit_tree() -> void:
	if NetworkManager.player_list_changed.is_connected(_on_player_list_changed):
		NetworkManager.player_list_changed.disconnect(_on_player_list_changed)


# ── Atmosphere ─────────────────────────────────────────────────────────────

func _build_atmosphere() -> void:
	var mod := CanvasModulate.new()
	mod.color = Color(0.58, 0.20, 0.12)
	add_child(mod)


# ── Floor ──────────────────────────────────────────────────────────────────

func _build_floor() -> void:
	var fn: Node2D = $Floor

	# Outer wall ring (visual stone border beyond the playfield)
	_poly_ring(fn, FLOOR_R, OUTER_R, 48, Color("#0d0402"))

	# Main circular floor — 3 concentric zones for depth
	_circle_poly(fn, Vector2.ZERO, FLOOR_R,        56, Color("#1e0b06"))
	_circle_poly(fn, Vector2.ZERO, FLOOR_R * 0.80, 48, Color("#200d07"))
	_circle_poly(fn, Vector2.ZERO, FLOOR_R * 0.45, 36, Color("#221009"))

	# Inner border ring — darker ring just inside wall
	_poly_ring(fn, FLOOR_R - 22.0, FLOOR_R, 48, Color("#120503"))

	# Lava pit floors
	for pos: Vector2 in _LAVA_POSITIONS:
		_circle_poly(fn, pos, 48.0, 20, Color("#5a1200"))
		_circle_poly(fn, pos, 34.0, 20, Color("#aa2c00"))
		_circle_poly(fn, pos, 18.0, 16, Color("#ff6600"))


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


# ── Walls ──────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "WallBody"
	add_child(body)

	const SEGS := 40
	for i in SEGS:
		var a0 := TAU * i       / float(SEGS)
		var a1 := TAU * (i + 1) / float(SEGS)
		var cs := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = Vector2(cos(a0), sin(a0)) * WALL_R
		seg.b = Vector2(cos(a1), sin(a1)) * WALL_R
		cs.shape = seg
		body.add_child(cs)


# ── Objects ────────────────────────────────────────────────────────────────

func _place_objects() -> void:
	var objs: Node2D = $Objects

	# Pentagram — center
	_obj(objs, "pentagram",    Vector2(  0,   0), 2.4)

	# Portals — north quadrant (two separate portals)
	_place_portals(objs)

	# Shop counter — merchant alcove SW
	_obj(objs, "shop_counter", Vector2(-270, 150), 2.4, false, Vector2(160, 72))

	# Torture racks — blocking pillars NW and NE
	_obj(objs, "torture_rack", Vector2(-420, -120), 2.0, false, Vector2(72, 110))
	_obj(objs, "torture_rack", Vector2( 420, -120), 2.0, true,  Vector2(72, 110))

	# Lava pools
	for pos: Vector2 in _LAVA_POSITIONS:
		_obj(objs, "lava_pool", pos, 2.2)

	# Skull piles — mid-room accents
	_obj(objs, "skull_pile", Vector2(-330,  30), 2.0)
	_obj(objs, "skull_pile", Vector2( 330,  30), 2.0)
	_obj(objs, "skull_pile", Vector2(   0, 430), 2.0)
	_obj(objs, "skull_pile", Vector2(   0,   0), 1.6)

	# Chains — near wall, 4 positions
	for pos: Vector2 in [Vector2(-490, -226), Vector2(-490, 105), Vector2(490, -226), Vector2(490, 105)]:
		_obj(objs, "chains", pos, 2.0)

	# Torches (sprite at wall positions)
	for tp: Vector2 in _TORCH_POSITIONS:
		_obj(objs, "torch", tp, 2.0)


func _place_portals(parent: Node2D) -> void:
	# ── Survivor portal (green) ────────────────────────────────────────────
	_survivor_portal = _make_portal_instance(
		_SURVIVOR_PORTAL_POS,
		Portal.PortalType.SURVIVOR,
		"res://scenes/survivor/survivor_arena.tscn",
		false,
		Color("#00FF66"),
		"The Proving\nGrounds",
		Color("#88FFBB")
	)
	parent.add_child(_survivor_portal)

	# ── Dungeon Crawler portal (hell red — coming soon) ────────────────────
	DungeonFloor.current_floor = 1
	_dungeon_portal = _make_portal_instance(
		_DUNGEON_PORTAL_POS,
		Portal.PortalType.DUNGEON_CRAWLER,
		"res://scenes/dungeon/dungeon_floor.tscn",
		false,
		Color("#FF4400"),
		"The Descent",
		Color("#FF8844")
	)
	parent.add_child(_dungeon_portal)

	# Wire up signals to the big centered banner (both portals share it)
	_survivor_portal.countdown_tick.connect(_on_portal_countdown)
	_survivor_portal.players_status.connect(_on_portal_status)
	_dungeon_portal.countdown_tick.connect(func(sec: float) -> void:
		_on_portal_countdown_dungeon(sec))
	_dungeon_portal.players_status.connect(_on_portal_status)
	_dungeon_portal.portal_blocked.connect(_on_dungeon_portal_blocked)


func _make_portal_instance(pos: Vector2, ptype: Portal.PortalType,
		target: String, coming_soon: bool,
		tint: Color, label_text: String, label_col: Color) -> Portal:
	var p := Portal.new()
	p.position    = pos
	p.portal_type = ptype
	p.target_scene = target
	p.coming_soon  = coming_soon

	# Sprite visual (tinted)
	var tex := load(_OBJ["portal"]) as Texture2D
	if tex:
		var s := Sprite2D.new()
		s.texture        = tex
		s.scale          = Vector2(2.2, 2.2)
		s.modulate       = tint
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		p.add_child(s)
	else:
		# Fallback: drawn circles
		_portal_fallback_circles(p, tint)

	# Name label
	var lbl := Label.new()
	lbl.text     = label_text
	lbl.position = Vector2(-48, -72)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color",         label_col)
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 1)
	p.add_child(lbl)

	if coming_soon:
		var cs_lbl := Label.new()
		cs_lbl.text     = "Coming Soon"
		cs_lbl.position = Vector2(-38, -55)
		cs_lbl.add_theme_font_size_override("font_size", 9)
		cs_lbl.add_theme_color_override("font_color",         Color("#FFAA00"))
		cs_lbl.add_theme_color_override("font_outline_color", Color("#000000"))
		cs_lbl.add_theme_constant_override("outline_size", 1)
		p.add_child(cs_lbl)

	return p


func _portal_fallback_circles(parent: Node2D, col: Color) -> void:
	for r: float in [42.0, 28.0, 14.0]:
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color   = col.darkened(1.0 - r / 42.0)
		parent.add_child(poly)


func _obj(parent: Node2D, key: String, pos: Vector2, sc: float = 2.0,
		flip_h: bool = false, col_size: Vector2 = Vector2.ZERO) -> void:
	var tex := load(_OBJ[key]) as Texture2D
	if tex == null:
		return

	var root: Node2D
	if col_size != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.position = pos
		parent.add_child(body)
		root = body
		var cs    := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = col_size
		cs.shape   = shape
		body.add_child(cs)
	else:
		root = Node2D.new()
		root.position = pos
		parent.add_child(root)

	var s := Sprite2D.new()
	s.texture        = tex
	s.scale          = Vector2(sc * (-1.0 if flip_h else 1.0), sc)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(s)


# ── Lighting ───────────────────────────────────────────────────────────────

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


func _make_light(pos: Vector2, col: Color, scale: float, energy: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.position      = pos
	light.color         = col
	light.energy        = energy
	light.texture       = _light_tex
	light.texture_scale = scale
	return light


func _setup_lights() -> void:
	var lights: Node2D = $Lights

	for tp: Vector2 in _TORCH_POSITIONS:
		var l := _make_light(tp, Color(1.0, 0.42, 0.08), 1.3, 0.55)
		lights.add_child(l)
		_anim_flicker(l, 0.55)

	for pos: Vector2 in _LAVA_POSITIONS:
		var l := _make_light(pos, Color(1.0, 0.28, 0.02), 1.7, 0.45)
		lights.add_child(l)
		_anim_pulse(l, 0.35, 0.62, 2.5 + randf() * 1.5)

	# Survivor portal — green glow
	var survivor_l := _make_light(_SURVIVOR_PORTAL_POS, Color(0.0, 1.0, 0.35), 2.6, 0.60)
	lights.add_child(survivor_l)
	_anim_pulse(survivor_l, 0.42, 0.78, 2.2)

	# Dungeon portal — hell red glow
	var dungeon_l := _make_light(_DUNGEON_PORTAL_POS, Color(0.90, 0.05, 0.0), 2.6, 0.60)
	lights.add_child(dungeon_l)
	_anim_pulse(dungeon_l, 0.42, 0.78, 2.6)

	var pent_l := _make_light(Vector2(0, 0), Color(0.90, 0.0, 0.05), 1.1, 0.28)
	lights.add_child(pent_l)
	_anim_pulse(pent_l, 0.18, 0.38, 5.0)

	var merc_l := _make_light(Vector2(-290, 172), Color(0.95, 0.55, 0.15), 1.8, 0.38)
	lights.add_child(merc_l)
	_anim_flicker(merc_l, 0.38)


func _anim_flicker(light: PointLight2D, base: float) -> void:
	var ap  := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var a   := Animation.new()
	a.loop_mode = Animation.LOOP_LINEAR
	var dur := 0.35 + randf() * 0.30
	a.length = dur
	var tr := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr, ".:energy")
	a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
	a.track_insert_key(tr, 0.0,        base)
	a.track_insert_key(tr, dur * 0.20, base * 0.62)
	a.track_insert_key(tr, dur * 0.55, base * 0.88)
	a.track_insert_key(tr, dur * 0.78, base * 0.74)
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


# ── Audio ──────────────────────────────────────────────────────────────────

func _setup_audio() -> void:
	_global_audio(_AMBIENT_PATH, -13.0)

	for pos: Vector2 in _LAVA_POSITIONS:
		_spatial_audio(_LAVA_PATH, pos, -19.0, 155.0)

	_spatial_audio(_PORTAL_PATH, _SURVIVOR_PORTAL_POS, -14.0, 240.0)
	_spatial_audio(_PORTAL_PATH, _DUNGEON_PORTAL_POS,  -16.0, 200.0)

	for tp: Vector2 in [_TORCH_POSITIONS[0], _TORCH_POSITIONS[2], _TORCH_POSITIONS[4], _TORCH_POSITIONS[6]]:
		_spatial_audio(_TORCH_PATH, tp, -25.0, 100.0)

	var tick_stream := load(_SFX_TICK_PATH) as AudioStream
	if tick_stream:
		_portal_tick_sfx = AudioStreamPlayer.new()
		_portal_tick_sfx.stream    = tick_stream
		_portal_tick_sfx.volume_db = -3.0
		add_child(_portal_tick_sfx)


func _global_audio(path: String, vol_db: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream    = stream
	p.volume_db = vol_db
	p.finished.connect(p.play)
	add_child(p)
	p.play()


func _spatial_audio(path: String, pos: Vector2, vol_db: float, max_dist: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.position    = pos
	p.stream      = stream
	p.volume_db   = vol_db
	p.max_distance = max_dist
	p.attenuation = 1.5
	p.finished.connect(p.play)
	add_child(p)
	p.play()


# ── Lava kill zones ────────────────────────────────────────────────────────

func _build_lava_kill_zones() -> void:
	for pos: Vector2 in _LAVA_POSITIONS:
		var area := Area2D.new()
		area.position        = pos
		area.collision_layer = 0
		area.collision_mask  = 2  # player layer
		var cs    := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 30.0
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(func(b: Node2D) -> void: _on_lava_body_entered(pos, b))
		add_child(area)


func _on_lava_body_entered(lava_pos: Vector2, body: Node2D) -> void:
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var peer_id: int = body.get_multiplayer_authority()
	if multiplayer.has_multiplayer_peer():
		_rpc_lava_kill.rpc(peer_id, lava_pos)
	else:
		_do_lava_kill(peer_id, lava_pos)


@rpc("authority", "reliable", "call_local")
func _rpc_lava_kill(peer_id: int, lava_pos: Vector2) -> void:
	_do_lava_kill(peer_id, lava_pos)


func _do_lava_kill(peer_id: int, lava_pos: Vector2) -> void:
	var player: PlayerController = _find_player_by_authority(peer_id)
	if not is_instance_valid(player):
		return

	# Visual sink — runs on all peers
	var tween := create_tween().set_parallel(true)
	tween.tween_property(player, "scale",    Vector2(0.05, 0.05),        0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(player, "modulate", Color(2.0, 0.55, 0.0, 0.0), 0.28) \
		.set_ease(Tween.EASE_IN)
	_play_lava_splash(lava_pos)

	# Damage — server / singleplayer only, after the sink animation
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(player):
				player.take_damage(99999.0))


func _play_lava_splash(pos: Vector2) -> void:
	# Expanding concentric rings
	var splash := Node2D.new()
	splash.position = pos
	add_child(splash)
	_poly_ring(splash, 22.0, 36.0, 20, Color(2.0, 0.65, 0.05, 0.95))
	_poly_ring(splash, 10.0, 20.0, 16, Color(2.5, 0.85, 0.15, 1.0))
	_circle_poly(splash, Vector2.ZERO, 10.0, 12, Color(3.0, 1.2, 0.4, 1.0))

	# Light burst at the pit
	var burst := PointLight2D.new()
	burst.position      = pos
	burst.color         = Color(1.0, 0.42, 0.02)
	burst.energy        = 4.5
	burst.texture       = _light_tex
	burst.texture_scale = 3.8
	add_child(burst)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(splash, "scale",      Vector2(4.5, 4.5), 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(splash, "modulate:a", 0.0,               0.5) \
		.set_ease(Tween.EASE_IN)
	tween.tween_property(burst,  "energy",     0.0,               0.55) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		splash.queue_free()
		burst.queue_free())

	# Spatial SFX
	var sfx := AudioStreamPlayer2D.new()
	sfx.position     = pos
	sfx.max_distance = 600.0
	sfx.volume_db    = 4.0
	var stream := load("res://assets/audio/sfx/lava_death.mp3") as AudioStream
	if stream:
		sfx.stream = stream
		add_child(sfx)
		sfx.finished.connect(sfx.queue_free)
		sfx.play()
	else:
		sfx.queue_free()


func _find_player_by_authority(peer_id: int) -> PlayerController:
	for p: Node in get_tree().get_nodes_in_group("players"):
		if p is PlayerController and p.get_multiplayer_authority() == peer_id:
			return p as PlayerController
	return null


# ── Portal banner ──────────────────────────────────────────────────────────

func _on_portal_countdown(sec: float) -> void:
	if not is_instance_valid(_portal_banner):
		return
	if sec < 0.0:
		_portal_banner.visible = false
		_last_portal_cd_int = -1
		return
	var count := ceili(sec)
	if count != _last_portal_cd_int:
		_last_portal_cd_int = count
		if is_instance_valid(_portal_tick_sfx):
			_portal_tick_sfx.play()
	_portal_banner.add_theme_font_size_override("font_size", 52)
	_portal_banner.add_theme_color_override("font_color", Color("#AAFFCC"))
	_portal_banner.text    = str(count) if count > 0 else "GO!"
	_portal_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_portal_banner, "scale", Vector2(1.25, 1.25), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(_portal_banner, "scale", Vector2(1.0,  1.0),  0.18).set_ease(Tween.EASE_IN)


func _on_portal_countdown_dungeon(sec: float) -> void:
	if not is_instance_valid(_portal_banner):
		return
	if sec < 0.0:
		_portal_banner.visible = false
		_last_portal_cd_int = -1
		return
	var count := ceili(sec)
	if count != _last_portal_cd_int:
		_last_portal_cd_int = count
		if is_instance_valid(_portal_tick_sfx):
			_portal_tick_sfx.play()
	_portal_banner.add_theme_font_size_override("font_size", 52)
	_portal_banner.add_theme_color_override("font_color", Color("#FF8844"))
	_portal_banner.text    = str(count) if count > 0 else "Soon..."
	_portal_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_portal_banner, "scale", Vector2(1.25, 1.25), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(_portal_banner, "scale", Vector2(1.0,  1.0),  0.18).set_ease(Tween.EASE_IN)


func _on_dungeon_portal_blocked() -> void:
	if not is_instance_valid(_portal_banner):
		return
	_portal_banner.add_theme_font_size_override("font_size", 38)
	_portal_banner.add_theme_color_override("font_color", Color("#FF5500"))
	_portal_banner.text    = "Coming Soon!\nThis dungeon is\nnot yet open."
	_portal_banner.visible = true
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_portal_banner, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		_portal_banner.visible  = true
		_portal_banner.modulate = Color.WHITE
		_portal_banner.visible  = false)


func _on_portal_status(inside: int, total: int) -> void:
	if not is_instance_valid(_portal_banner):
		return
	if inside == 0:
		_portal_banner.visible = false
		return
	if inside < total and total > 1:
		_portal_banner.add_theme_font_size_override("font_size", 36)
		_portal_banner.add_theme_color_override("font_color", Color("#FFDD88"))
		_portal_banner.text    = "Waiting for players...\n(%d / %d)" % [inside, total]
		_portal_banner.visible = true


# ── Player spawning ────────────────────────────────────────────────────────

func _do_spawn(peer_id: int, player_name: String) -> void:
	var scene  := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as PlayerController
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	var keys: Array = NetworkManager.players.keys() if multiplayer.has_multiplayer_peer() else [1]
	var idx := maxi(0, keys.find(peer_id))
	player.position = _SPAWN_POINTS[idx % _SPAWN_POINTS.size()]

	$Players.add_child(player)
	_spawned[peer_id] = player
	player.init_player(player_name)

	var is_local := not multiplayer.has_multiplayer_peer() or player.is_multiplayer_authority()
	if is_local and is_instance_valid(_hud):
		_hud.connect_player(player)


func _on_player_list_changed() -> void:
	for peer_id: int in NetworkManager.players:
		if not _spawned.has(peer_id):
			var pname: String = NetworkManager.players[peer_id].get("name", "Player")
			_do_spawn(peer_id, pname)
