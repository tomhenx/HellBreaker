class_name LavaKingSlime
extends BaseEnemy

# ── Scenes / Assets ───────────────────────────────────────────────────────────
const _BLOB_SCENE   := "res://scenes/enemies/lava_blob.tscn"
const _POOL_SCENE   := "res://scenes/enemies/lava_pool.tscn"
const _CHEST_SCENE  := "res://scenes/items/chest_drop.tscn"
const _MUSIC_PATH   := "res://assets/audio/music/boss_lava_king.mp3"
const _SPRITE_DIR   := "res://assets/sprites/enemies/lava_king_slime/"

const _SFX_MAP := {
	"aggro":   "res://assets/audio/sfx/boss_aggro.mp3",
	"jump":    "res://assets/audio/sfx/boss_jump.mp3",
	"land":    "res://assets/audio/sfx/boss_land.mp3",
	"throw":   "res://assets/audio/sfx/boss_blob_throw.mp3",
	"geyser":  "res://assets/audio/sfx/boss_geyser.mp3",
	"hurt":    "res://assets/audio/sfx/boss_hurt.mp3",
	"death":   "res://assets/audio/sfx/boss_death.mp3",
	"warning": "res://assets/audio/sfx/boss_warning.mp3",
	"sizzle":  "res://assets/audio/sfx/boss_pool_sizzle.mp3",
}

# ── Config ────────────────────────────────────────────────────────────────────
const _BOSS_HP    := 2200.0
const _BOSS_SPEED := 100.0
const _BOSS_DMG   := 35.0
const _PHASE2_HP  := 0.60
const _PHASE3_HP  := 0.30
const _BODY_RADIUS := 45.0

# Attack weights [LAVA_JUMP, BLOB_THROW, GEYSER_BARRAGE, GROUND_SLAM, LAVA_FLOOD]
const _WEIGHTS := [
	[25, 25, 15, 25, 10],
	[20, 25, 25, 20, 10],
	[15, 30, 30, 15, 10],
]
# [telegraph_sec, cooldown_sec] per attack index
const _TIMING := [
	[1.20, 2.5],
	[0.50, 2.5],
	[1.30, 3.0],
	[0.45, 2.0],
	[1.50, 4.0],
]

enum BossState { INTRO, CHASE, TELEGRAPH, EXECUTE, COOLDOWN, DEAD }
enum Attack    { LAVA_JUMP = 0, BLOB_THROW = 1, GEYSER_BARRAGE = 2,
				 GROUND_SLAM = 3, LAVA_FLOOD = 4 }

# ── Runtime state ─────────────────────────────────────────────────────────────
var _boss_state:  int   = BossState.INTRO
var _phase:       int   = 1
var _state_timer: float = 2.0
var _cur_attack:  int   = Attack.GROUND_SLAM
var _wobble_t:    float = 0.0
var _phase_flags: Array = [false, false]   # phase2 / phase3 triggered

# Cached per-attack target data
var _jump_target:     Vector2        = Vector2.ZERO
var _geyser_spots:    Array[Vector2] = []
var _blob_targets:    Array[Vector2] = []

var _telegraph_nodes: Array = []
var _flood_pools:     Array = []

# ── Audio ──────────────────────────────────────────────────────────────────────
var _sfx:    Dictionary        = {}

# ── Visuals ────────────────────────────────────────────────────────────────────
var _body:       Polygon2D  = null
var _body_inner: Polygon2D  = null
var _glow:       Polygon2D  = null
var _eye_l:      Polygon2D  = null
var _eye_r:      Polygon2D  = null
var _pupil_l:    Polygon2D  = null
var _pupil_r:    Polygon2D  = null
var _crown:      Polygon2D  = null

# Sprite-based visual (preferred when sprites are downloaded)
var _sprite_node:  Sprite2D = null
var _sprite_texs:  Dictionary = {}   # "south"/"east"/"north"/"west" → Texture2D
var _facing:       String   = "south"
var _using_sprite: bool     = false

var _hp_canvas: CanvasLayer = null
var _hp_fill:   ColorRect   = null
var _hp_label:  Label       = null
const _HP_BAR_W := 320.0


# ─────────────────────────────────────────────────────────────────────────────
func _on_ready() -> void:
	hp              = _BOSS_HP
	max_hp          = _BOSS_HP
	move_speed      = _BOSS_SPEED
	attack_damage   = _BOSS_DMG
	xp_reward       = 500
	coin_reward_min = 40
	coin_reward_max = 80
	attack_cooldown_time = 9999.0   # boss manages its own attack cycle

	add_to_group("bosses")
	_build_visual()
	_build_hp_bar()
	_load_audio()


# ── Physics override ──────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_wobble_t += delta
	_wobble_visual()

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_pick_target()
	_boss_tick(delta)
	move_and_slide()

	if multiplayer.has_multiplayer_peer():
		_sync_timer += delta
		if _sync_timer >= 0.05:
			_sync_timer = 0.0
			_rpc_sync.rpc(global_position, velocity.normalized())


# ── Boss state machine ────────────────────────────────────────────────────────
func _boss_tick(delta: float) -> void:
	_state_timer -= delta

	match _boss_state:
		BossState.INTRO:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_play_sfx("aggro")
				_boss_state  = BossState.CHASE
				_state_timer = _base_attack_delay()

		BossState.CHASE:
			_chase_move()
			if _state_timer <= 0.0:
				_enter_telegraph()

		BossState.TELEGRAPH:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_clear_telegraphs()
				_execute_attack(_cur_attack)
				_boss_state = BossState.EXECUTE

		BossState.EXECUTE:
			velocity = Vector2.ZERO  # handled per-attack

		BossState.COOLDOWN:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_boss_state  = BossState.CHASE
				_state_timer = _base_attack_delay()

	_check_phase_transition()


func _chase_move() -> void:
	if not is_instance_valid(_target):
		velocity = Vector2.ZERO
		return
	var dir := (_target.global_position - global_position).normalized()
	velocity = dir * move_speed * (1.0 + 0.15 * (_phase - 1))


func _base_attack_delay() -> float:
	return maxf(1.2, 2.5 - (_phase - 1) * 0.4)


# ── Telegraph ─────────────────────────────────────────────────────────────────
func _enter_telegraph() -> void:
	_cur_attack  = _choose_attack()
	_boss_state  = BossState.TELEGRAPH
	_state_timer = _TIMING[_cur_attack][0]
	_play_sfx("warning")
	_build_telegraph(_cur_attack)


func _choose_attack() -> int:
	var weights: Array = _WEIGHTS[_phase - 1]
	var total := 0
	for w: int in weights: total += w
	var roll := randi() % total
	var cum  := 0
	for i in weights.size():
		cum += weights[i]
		if roll < cum:
			return i
	return Attack.GROUND_SLAM


func _build_telegraph(attack: int) -> void:
	match attack:
		Attack.LAVA_JUMP:
			_jump_target = _nearest_player_pos()
			_add_warn_circle(_jump_target, 70.0, Color(1.0, 0.9, 0.0, 0.5))

		Attack.BLOB_THROW:
			_blob_targets.clear()
			var players := _all_players()
			for pc in players:
				_blob_targets.append((pc as PlayerController).global_position)
			# extra blobs with spread
			for i in mini(2, _phase):
				var angle := randf() * TAU
				_blob_targets.append(global_position + Vector2(cos(angle), sin(angle)) * 130.0)
			for pos: Vector2 in _blob_targets:
				_add_warn_circle(pos, 38.0, Color(1.0, 0.4, 0.0, 0.45))

		Attack.GEYSER_BARRAGE:
			_geyser_spots.clear()
			var count := 4 + _phase
			for i in count:
				var ang := float(i) / float(count) * TAU + randf() * 0.4
				var dist := randf_range(80.0, 180.0)
				_geyser_spots.append(global_position + Vector2(cos(ang), sin(ang)) * dist)
			for pos: Vector2 in _geyser_spots:
				_add_warn_circle(pos, 38.0, Color(1.0, 0.55, 0.0, 0.55))

		Attack.GROUND_SLAM:
			for r in [65.0, 115.0, 165.0]:
				_add_warn_ring(global_position, r, Color(1.0, 0.8, 0.0, 0.35))

		Attack.LAVA_FLOOD:
			# Show a large warning zone on a random side of the boss
			var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
			_flood_pools.clear()
			var dir: Vector2 = dirs[randi() % dirs.size()]
			for i in 3:
				var offset := dir * (100.0 + i * 90.0) + \
					dir.rotated(PI * 0.5) * randf_range(-60.0, 60.0)
				_add_warn_circle(global_position + offset, 75.0, Color(1.0, 0.2, 0.0, 0.40))


func _add_warn_circle(pos: Vector2, r: float, col: Color) -> void:
	var n := Polygon2D.new()
	n.polygon = _circle_pts(r, 24)
	n.color   = col
	n.z_index = 3
	get_tree().current_scene.add_child(n)
	n.global_position = pos
	_telegraph_nodes.append(n)
	# Pulse the alpha
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "modulate:a", 0.3, 0.3)
	tw.tween_property(n, "modulate:a", 1.0, 0.3)


func _add_warn_ring(pos: Vector2, r: float, col: Color) -> void:
	var outer := Polygon2D.new()
	outer.polygon = _ring_pts(r, r + 14.0, 32)
	outer.color   = col
	outer.z_index = 3
	get_tree().current_scene.add_child(outer)
	outer.global_position = pos
	_telegraph_nodes.append(outer)


func _clear_telegraphs() -> void:
	for n in _telegraph_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_telegraph_nodes.clear()


# ── Execute attacks ───────────────────────────────────────────────────────────
func _execute_attack(attack: int) -> void:
	match attack:
		Attack.LAVA_JUMP:      _exec_lava_jump()
		Attack.BLOB_THROW:     _exec_blob_throw()
		Attack.GEYSER_BARRAGE: _exec_geyser_barrage()
		Attack.GROUND_SLAM:    _exec_ground_slam()
		Attack.LAVA_FLOOD:     _exec_lava_flood()


func _end_attack() -> void:
	_boss_state  = BossState.COOLDOWN
	_state_timer = _TIMING[_cur_attack][1] * (1.0 - (_phase - 1) * 0.12)


# ─── LAVA JUMP ────────────────────────────────────────────────────────────────
func _exec_lava_jump() -> void:
	_play_sfx("jump")
	var target := _jump_target

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.3, 0.55), 0.18).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(self, "scale", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_CIRC)

	get_tree().create_timer(0.40).timeout.connect(func():
		if not is_instance_valid(self): return
		global_position = target
		visible = true
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(self, "scale", Vector2(1.5, 0.5), 0.08)
		tw2.chain().tween_property(self, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK)
		_play_sfx("land")
		_spawn_land_impact(target)
		_damage_players_in_radius(target, 85.0, _BOSS_DMG * 1.5)
		get_tree().create_timer(0.30).timeout.connect(_end_attack)
	)


func _spawn_land_impact(pos: Vector2) -> void:
	var root := get_tree().current_scene
	for i in 12:
		var r   := randf_range(3.0, 7.0)
		var ang := randf() * TAU
		var p   := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)
		])
		p.color = Color(1.0, randf_range(0.2, 0.7), 0.0, 1.0)
		p.z_index = 10
		root.add_child(p)
		p.global_position = pos
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(50.0, 140.0)
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "global_position", pos + vel, 0.5)
		tw.tween_property(p, "rotation_degrees", randf_range(-180.0, 180.0), 0.5)
		tw.tween_property(p, "modulate:a", 0.0, 0.42).set_delay(0.08)
		tw.tween_callback(p.queue_free).set_delay(0.55)

	# Shockwave ring
	var ring := Polygon2D.new()
	ring.polygon = _ring_pts(0.0, 20.0, 28)
	ring.color   = Color(1.0, 0.6, 0.0, 0.7)
	ring.z_index = 5
	root.add_child(ring)
	ring.global_position = pos
	var rtw := ring.create_tween().set_parallel(true)
	rtw.tween_property(ring, "scale", Vector2.ONE * 5.5, 0.45).set_trans(Tween.TRANS_CIRC)
	rtw.tween_property(ring, "modulate:a", 0.0, 0.45)
	rtw.tween_callback(ring.queue_free).set_delay(0.48)


# ─── BLOB THROW ───────────────────────────────────────────────────────────────
func _exec_blob_throw() -> void:
	var blob_packed := load(_BLOB_SCENE) as PackedScene
	if blob_packed == null:
		_end_attack()
		return

	var count   := _blob_targets.size()
	var interval := 0.22

	for i in count:
		var target_pos: Vector2 = _blob_targets[i]
		get_tree().create_timer(i * interval).timeout.connect(func():
			if not is_instance_valid(self): return
			_play_sfx("throw")
			var blob: LavaBlob = blob_packed.instantiate() as LavaBlob
			blob.pool_radius       = 52.0 + _phase * 5.0
			blob.pool_lifetime     = 3.5 + _phase * 0.5
			blob.pool_dps          = 10.0 + _phase * 2.0
			blob.owner_peer_id     = 1
			get_tree().current_scene.add_child(blob)
			blob.launch(global_position, target_pos, randf_range(0.65, 0.85))
		)

	get_tree().create_timer(count * interval + 0.9).timeout.connect(_end_attack)


# ─── GEYSER BARRAGE ───────────────────────────────────────────────────────────
func _exec_geyser_barrage() -> void:
	var interval := 0.25
	for i in _geyser_spots.size():
		var pos: Vector2 = _geyser_spots[i]
		get_tree().create_timer(i * interval).timeout.connect(func():
			if not is_instance_valid(self): return
			_spawn_geyser(pos)
		)
	var total_time := _geyser_spots.size() * interval + 0.6
	get_tree().create_timer(total_time).timeout.connect(_end_attack)


func _spawn_geyser(pos: Vector2) -> void:
	_play_sfx("geyser")
	_damage_players_in_radius(pos, 40.0, _BOSS_DMG * 0.9)

	var root := get_tree().current_scene

	# Eruption column
	var col := Polygon2D.new()
	col.polygon = PackedVector2Array([
		Vector2(-18, 0), Vector2(18, 0), Vector2(12, -90), Vector2(-12, -90)
	])
	col.color   = Color(1.0, 0.45, 0.0, 0.92)
	col.z_index = 6
	root.add_child(col)
	col.global_position = pos

	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(-28, 0), Vector2(28, 0), Vector2(18, -100), Vector2(-18, -100)
	])
	glow.color   = Color(1.0, 0.8, 0.1, 0.5)
	glow.z_index = 5
	root.add_child(glow)
	glow.global_position = pos

	var tw := col.create_tween().set_parallel(true)
	tw.tween_property(col, "scale",       Vector2(1.3, 1.2), 0.08).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(col, "modulate:a", 0.0, 0.35)
	tw.tween_callback(col.queue_free).set_delay(0.45)

	var gtw := glow.create_tween().set_parallel(true)
	gtw.tween_property(glow, "modulate:a", 0.0, 0.40)
	gtw.tween_callback(glow.queue_free).set_delay(0.45)

	# Small pool at geyser base
	var pool_packed := load(_POOL_SCENE) as PackedScene
	if pool_packed != null:
		var pool: LavaPool = pool_packed.instantiate() as LavaPool
		pool.radius            = 30.0
		pool.lifetime          = 2.0
		pool.damage_per_second = 8.0
		pool.owner_peer_id     = 1
		root.add_child(pool)
		pool.global_position = pos


# ─── GROUND SLAM ─────────────────────────────────────────────────────────────
func _exec_ground_slam() -> void:
	_play_sfx("land")

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.5, 0.55), 0.12).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(self, "scale", Vector2.ONE, 0.22)

	var radii   := [65.0, 115.0, 165.0]
	var delays  := [0.0,   0.20,   0.40]
	var hit_ids := [[], [], []]   # prevent double-hit per ring

	for i in radii.size():
		var r: float = radii[i]
		var d: float = delays[i]
		get_tree().create_timer(d).timeout.connect(func():
			if not is_instance_valid(self): return
			_spawn_shockwave_ring(r)
			_damage_players_ring(global_position, r - 22.0, r + 22.0, _BOSS_DMG * 0.85)
		)

	get_tree().create_timer(0.80).timeout.connect(_end_attack)


func _spawn_shockwave_ring(r: float) -> void:
	var root := get_tree().current_scene
	var ring := Polygon2D.new()
	ring.polygon = _ring_pts(r, r + 18.0, 32)
	ring.color   = Color(1.0, 0.65, 0.0, 0.80)
	ring.z_index = 6
	root.add_child(ring)
	ring.global_position = global_position
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale",      Vector2.ONE * 1.35, 0.40).set_trans(Tween.TRANS_CIRC)
	tw.tween_property(ring, "modulate:a", 0.0,               0.42)
	tw.tween_callback(ring.queue_free).set_delay(0.46)


# ─── LAVA FLOOD ──────────────────────────────────────────────────────────────
func _exec_lava_flood() -> void:
	_play_sfx("sizzle")

	var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var dir:  Vector2 = dirs[randi() % dirs.size()]
	var perp: Vector2 = dir.rotated(PI * 0.5)
	var pool_packed := load(_POOL_SCENE) as PackedScene
	if pool_packed == null:
		_end_attack()
		return

	for row in 3:
		for col in 3:
			var offset := dir * (100.0 + row * 90.0) + perp * (col - 1) * 90.0
			var pool: LavaPool = pool_packed.instantiate() as LavaPool
			pool.radius            = 72.0
			pool.lifetime          = 4.0
			pool.damage_per_second = 12.0
			pool.owner_peer_id     = 1
			get_tree().current_scene.add_child(pool)
			pool.global_position = global_position + offset
			_flood_pools.append(pool)

	get_tree().create_timer(4.5).timeout.connect(_end_attack)


# ── Damage helpers ────────────────────────────────────────────────────────────
func _damage_players_in_radius(origin: Vector2, r: float, dmg: float) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if not node is PlayerController: continue
		var pc := node as PlayerController
		if pc.global_position.distance_to(origin) <= r:
			pc.take_damage(dmg, false)


func _damage_players_ring(origin: Vector2, r_min: float, r_max: float, dmg: float) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if not node is PlayerController: continue
		var pc := node as PlayerController
		var d  := pc.global_position.distance_to(origin)
		if d >= r_min and d <= r_max:
			pc.take_damage(dmg, false)


func _nearest_player_pos() -> Vector2:
	if is_instance_valid(_target):
		return _target.global_position
	return global_position + Vector2(60.0, 0.0)


func _all_players() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			result.append(node)
	return result


# ── Phase transitions ─────────────────────────────────────────────────────────
func _check_phase_transition() -> void:
	var ratio := hp / max_hp
	if not _phase_flags[0] and ratio <= _PHASE2_HP:
		_phase_flags[0] = true
		_phase = 2
		_on_phase_change(2)
	elif not _phase_flags[1] and ratio <= _PHASE3_HP:
		_phase_flags[1] = true
		_phase = 3
		_on_phase_change(3)


func _on_phase_change(new_phase: int) -> void:
	_play_sfx("aggro")
	var flash_col := Color(1.5, 0.3, 0.0, 1.0) if new_phase == 2 else Color(2.5, 0.1, 0.1, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", flash_col, 0.1)
	tw.chain().tween_property(self, "modulate", Color.WHITE, 0.4)
	# Speed bump
	move_speed = _BOSS_SPEED * (1.0 + (new_phase - 1) * 0.18)
	_update_body_color()


# ── Visual ────────────────────────────────────────────────────────────────────
func _build_visual() -> void:
	# Try sprite-based visual first
	for dir: String in ["south", "east", "north", "west"]:
		var path := _SPRITE_DIR + dir + ".png"
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_sprite_texs[dir] = tex

	if not _sprite_texs.is_empty():
		_using_sprite = true
		_sprite_node = Sprite2D.new()
		_sprite_node.texture        = _sprite_texs.get("south") as Texture2D
		_sprite_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite_node.scale          = Vector2(2.2, 2.2)
		_sprite_node.z_index        = 1
		add_child(_sprite_node)

		# Keep a subtle glow behind the sprite
		_glow = Polygon2D.new()
		_glow.polygon = _circle_pts(_BODY_RADIUS * 1.5, 18)
		_glow.color   = Color(1.0, 0.4, 0.0, 0.22)
		_glow.z_index = 0
		add_child(_glow)
		return

	var r := _BODY_RADIUS

	_glow = Polygon2D.new()
	_glow.polygon = _circle_pts(r * 1.45, 20)
	_glow.color   = Color(1.0, 0.4, 0.0, 0.28)
	_glow.z_index = -1
	add_child(_glow)

	_body = Polygon2D.new()
	_body.polygon = _blob_pts(r, 3771)
	_body.color   = Color(0.96, 0.27, 0.02, 1.0)
	_body.z_index = 0
	add_child(_body)

	_body_inner = Polygon2D.new()
	_body_inner.polygon = _blob_pts(r * 0.55, 8821)
	_body_inner.color   = Color(1.0, 0.68, 0.08, 0.85)
	_body_inner.z_index = 1
	add_child(_body_inner)

	# Eyes
	var eye_r_size := r * 0.22
	_eye_l  = _make_circle_poly(eye_r_size, Color(1.0, 0.95, 0.15, 1.0), 2)
	_eye_r  = _make_circle_poly(eye_r_size, Color(1.0, 0.95, 0.15, 1.0), 2)
	_pupil_l = _make_circle_poly(eye_r_size * 0.45, Color(0.05, 0.0, 0.0, 1.0), 3)
	_pupil_r = _make_circle_poly(eye_r_size * 0.45, Color(0.05, 0.0, 0.0, 1.0), 3)
	_eye_l.position  = Vector2(-r * 0.32, -r * 0.22)
	_eye_r.position  = Vector2( r * 0.32, -r * 0.22)
	_pupil_l.position = _eye_l.position + Vector2(0.0, eye_r_size * 0.18)
	_pupil_r.position = _eye_r.position + Vector2(0.0, eye_r_size * 0.18)
	add_child(_eye_l);  add_child(_eye_r)
	add_child(_pupil_l); add_child(_pupil_r)

	# Crown
	_crown = Polygon2D.new()
	var cr := r * 0.55
	_crown.polygon = PackedVector2Array([
		Vector2(-cr,       -r * 0.70),
		Vector2(-cr * 0.6, -r * 1.10),
		Vector2(-cr * 0.1, -r * 0.82),
		Vector2( cr * 0.3, -r * 1.20),
		Vector2( cr * 0.7, -r * 0.82),
		Vector2( cr * 1.0, -r * 1.08),
		Vector2( cr,       -r * 0.70),
	])
	_crown.color   = Color(1.0, 0.82, 0.04, 1.0)
	_crown.z_index = 2
	add_child(_crown)


func _make_circle_poly(r: float, col: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = _circle_pts(r, 14)
	p.color   = col
	p.z_index = z
	return p


func _wobble_visual() -> void:
	# Update sprite direction
	if _using_sprite and is_instance_valid(_sprite_node):
		_update_sprite_facing()
		var w := sin(_wobble_t * 3.2) * 0.035 + 1.0
		_sprite_node.scale = Vector2(2.2 * w, 2.2 * (2.0 - w))
		if is_instance_valid(_glow):
			_glow.color.a = 0.22 + sin(_wobble_t * 2.2) * 0.10
		return

	if not is_instance_valid(_body):
		return
	var w := sin(_wobble_t * 3.5) * 0.045 + 1.0
	_body.scale       = Vector2(w, 2.0 - w)
	_body_inner.scale = _body.scale
	if is_instance_valid(_glow):
		_glow.color.a = 0.28 + sin(_wobble_t * 2.2) * 0.10

	if is_instance_valid(_eye_l) and is_instance_valid(_target):
		var look := (_target.global_position - global_position).normalized() * 3.0
		_pupil_l.position = _eye_l.position  + look
		_pupil_r.position = _eye_r.position  + look


func _update_sprite_facing() -> void:
	var dir := "south"
	var spd := velocity.length()
	if spd > 10.0:
		var ang := velocity.angle()
		# Map angle to cardinal direction
		if ang > -PI * 0.25 and ang <= PI * 0.25:
			dir = "east"
		elif ang > PI * 0.25 and ang <= PI * 0.75:
			dir = "south"
		elif ang > PI * 0.75 or ang <= -PI * 0.75:
			dir = "west"
		else:
			dir = "north"
	elif is_instance_valid(_target):
		var to := _target.global_position - global_position
		var ang := to.angle()
		if ang > -PI * 0.25 and ang <= PI * 0.25:
			dir = "east"
		elif ang > PI * 0.25 and ang <= PI * 0.75:
			dir = "south"
		elif ang > PI * 0.75 or ang <= -PI * 0.75:
			dir = "west"
		else:
			dir = "north"
	if dir != _facing and _sprite_texs.has(dir):
		_facing = dir
		_sprite_node.texture = _sprite_texs[dir] as Texture2D


func _update_body_color() -> void:
	if _using_sprite and is_instance_valid(_sprite_node):
		match _phase:
			2: _sprite_node.modulate = Color(1.2, 0.6, 0.5, 1.0)
			3: _sprite_node.modulate = Color(1.4, 0.3, 0.3, 1.0)
		return
	if not is_instance_valid(_body):
		return
	match _phase:
		2:
			_body.color       = Color(0.85, 0.15, 0.01, 1.0)
			_body_inner.color = Color(1.0, 0.40, 0.05, 0.85)
			if is_instance_valid(_glow): _glow.color = Color(1.0, 0.25, 0.0, 0.35)
		3:
			_body.color       = Color(0.60, 0.06, 0.01, 1.0)
			_body_inner.color = Color(1.0, 0.20, 0.02, 0.85)
			if is_instance_valid(_glow): _glow.color = Color(1.0, 0.10, 0.0, 0.45)


# ── Boss HP bar ───────────────────────────────────────────────────────────────
func _build_hp_bar() -> void:
	_hp_canvas = CanvasLayer.new()
	_hp_canvas.layer        = 20
	_hp_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hp_canvas)

	# Absolute pixel positions — no anchors, no layout containers.
	# Screen is 1280×720. Frame: 336×44, centred horizontally, 20px off bottom.
	const FRAME_W := _HP_BAR_W + 16.0
	const FRAME_H := 44.0
	const FRAME_X := (1280.0 - FRAME_W) * 0.5
	const FRAME_Y := 720.0 - FRAME_H - 20.0

	var frame := Panel.new()
	frame.position     = Vector2(FRAME_X, FRAME_Y)
	frame.size         = Vector2(FRAME_W, FRAME_H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color(0.06, 0.02, 0.0, 0.92)
	sty.border_color = Color("#FF4400")
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sty)
	_hp_canvas.add_child(frame)

	var lbl := Label.new()
	lbl.text                    = "LAVA KING SLIME"
	lbl.position                = Vector2(8.0, 4.0)
	lbl.size                    = Vector2(_HP_BAR_W, 18.0)
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#FF6622"))
	frame.add_child(lbl)
	_hp_label = lbl

	var bar_bg := ColorRect.new()
	bar_bg.color        = Color(0.15, 0.0, 0.0, 1.0)
	bar_bg.position     = Vector2(8.0, 26.0)
	bar_bg.size         = Vector2(_HP_BAR_W, 12.0)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bar_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color        = Color("#FF2200")
	_hp_fill.position     = Vector2(8.0, 26.0)
	_hp_fill.size         = Vector2(_HP_BAR_W, 12.0)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_hp_fill)


func _update_hp_bar() -> void:
	if not is_instance_valid(_hp_fill):
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_fill.size  = Vector2(_HP_BAR_W * frac, 12.0)
	_hp_fill.color = Color("#FF2200").lerp(Color("#FFAA00"), frac)


# ── Audio ─────────────────────────────────────────────────────────────────────
func _load_audio() -> void:
	for key: String in _SFX_MAP:
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		var s := load(_SFX_MAP[key]) as AudioStream
		if s != null:
			player.stream = s
		match key:
			"hurt":   player.volume_db = -5.0
			"death":  player.volume_db = -2.0
			_:        player.volume_db = -4.0
		add_child(player)
		_sfx[key] = player

	MusicManager.play_boss_music(_MUSIC_PATH)


func _play_sfx(key: String) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_sfx.rpc(key)
	else:
		_do_play_sfx(key)


@rpc("authority", "reliable", "call_local")
func _rpc_play_sfx(key: String) -> void:
	_do_play_sfx(key)


func _do_play_sfx(key: String) -> void:
	var player: AudioStreamPlayer = _sfx.get(key) as AudioStreamPlayer
	if is_instance_valid(player) and player.stream != null:
		player.stop()
		player.play()


# ── BaseEnemy hooks ───────────────────────────────────────────────────────────
func _on_hit(is_crit: bool) -> void:
	_play_sfx("hurt")
	_update_hp_bar()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate", Color(2.5, 0.8, 0.3, 1.0), 0.05)
	tw.chain().tween_property(self, "modulate", Color.WHITE, 0.18)


func _on_death() -> void:
	_boss_state = BossState.DEAD
	_clear_telegraphs()
	_play_sfx("death")
	set_physics_process(false)

	if is_instance_valid(_hp_canvas):
		var tw := _hp_canvas.create_tween()
		tw.tween_property(_hp_canvas, "modulate:a", 0.0, 1.2)
		tw.tween_callback(_hp_canvas.queue_free)

	MusicManager.stop_boss_music(3.5)

	_spawn_death_explosion()


func _spawn_death_explosion() -> void:
	var root := get_tree().current_scene
	for _i in 24:
		var r   := randf_range(4.0, 12.0)
		var ang := randf() * TAU
		var p   := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)
		])
		p.color   = Color(1.0, randf_range(0.15, 0.75), 0.0, 1.0)
		p.z_index = 12
		root.add_child(p)
		p.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(60.0, 200.0)
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "global_position", p.global_position + vel, 0.8)
		tw.tween_property(p, "rotation_degrees", randf_range(-360.0, 360.0), 0.8)
		tw.tween_property(p, "modulate:a", 0.0, 0.65).set_delay(0.12)
		tw.tween_callback(p.queue_free).set_delay(0.88)

	# Big flash
	var flash := Polygon2D.new()
	flash.polygon = _circle_pts(120.0, 20)
	flash.color   = Color(1.0, 0.6, 0.0, 0.85)
	flash.z_index = 11
	root.add_child(flash)
	flash.global_position = global_position
	var ftw := flash.create_tween().set_parallel(true)
	ftw.tween_property(flash, "scale",      Vector2.ONE * 2.2, 0.45).set_trans(Tween.TRANS_CIRC)
	ftw.tween_property(flash, "modulate:a", 0.0,               0.50)
	ftw.tween_callback(flash.queue_free).set_delay(0.55)


func _drop_rewards() -> void:
	var xp_scene := load(XP_ORB_SCENE) as PackedScene
	if xp_scene:
		var orb: Node2D = xp_scene.instantiate()
		orb.set("xp_value", xp_reward)
		get_tree().current_scene.add_child(orb)
		orb.global_position = global_position

	var coin_scene := load(COIN_DROP_SCENE) as PackedScene
	if coin_scene:
		for i in randi_range(coin_reward_min, coin_reward_max):
			var c: Node2D = coin_scene.instantiate()
			c.set("coin_value", 1)
			get_tree().current_scene.add_child(c)
			c.global_position = global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40))

	var chest_packed := load(_CHEST_SCENE) as PackedScene
	if chest_packed == null:
		return

	# 2 common chests
	for i in 2:
		var ang := float(i) / 2.0 * TAU
		var chest: ChestDrop = chest_packed.instantiate() as ChestDrop
		chest.chest_type = "common"
		get_tree().current_scene.add_child(chest)
		chest.global_position = global_position + Vector2(cos(ang), sin(ang)) * 70.0

	# 1 prismatic chest
	var pchest: ChestDrop = chest_packed.instantiate() as ChestDrop
	pchest.chest_type = "prismatic"
	get_tree().current_scene.add_child(pchest)
	pchest.global_position = global_position


# ── Geometry helpers ──────────────────────────────────────────────────────────
func _circle_pts(r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := float(i) / float(seg) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _blob_pts(r: float, seed_val: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var pts := PackedVector2Array()
	var seg := 20
	for i in seg:
		var a := float(i) / float(seg) * TAU
		var w := rng.randf_range(0.84, 1.16)
		pts.append(Vector2(cos(a), sin(a)) * r * w)
	return pts


func _ring_pts(r_inner: float, r_outer: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := float(i) / float(seg) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r_outer)
	for i in range(seg - 1, -1, -1):
		var a := float(i) / float(seg) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r_inner)
	return pts
