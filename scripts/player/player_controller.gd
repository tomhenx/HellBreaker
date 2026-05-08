class_name PlayerController
extends CharacterBody2D

signal died
signal hp_changed(current: float, maximum: float)
signal player_respawned
signal respawn_countdown(seconds_left: float)

const STATS_PATH      := "res://data/stats/player_base_stats.json"
const PROJECTILE_SCENE := "res://scenes/combat/projectile.tscn"

# Sprite sheet paths (populated once PixelLab assets are imported)
const ANIM_WALK  := "res://assets/sprites/characters/player/walk.png"
const ANIM_IDLE  := "res://assets/sprites/characters/player/idle.png"
const ANIM_DODGE := "res://assets/sprites/characters/player/dodge.png"

# Runtime stats
var stats: StatsResource
var current_hp: float = 100.0
var run_damage_bonus: float = 0.0
var run_speed_bonus: float = 0.0

# Internal state
const RESPAWN_TIME := 5.0

var spawn_position:   Vector2 = Vector2.ZERO
var _attack_cooldown: float   = 0.0
var _dodge_cooldown:  float   = 0.0
var _is_dodging:      bool    = false
var _dodge_timer:     float   = 0.0
var _dodge_dir:       Vector2 = Vector2.ZERO
var _iframes_timer:   float   = 0.0
var _is_dead:         bool    = false
var _respawn_timer:   float   = 0.0
var _aim_dir:         Vector2 = Vector2(1, 0)

# Node refs
var _visual:       CharacterVisual
var _body_poly:    Polygon2D        # placeholder, hidden when real sprites load
var _aim_poly:     Polygon2D
var _shoot_point:  Marker2D
var _name_label:   Label
var _projectile_scene: PackedScene

# Multiplayer position sync interval
var _sync_timer: float = 0.0

# Direction names matching CharacterVisual.DIR_ROW
const _DIR_NAMES := ["east","south-east","south","south-west","west","north-west","north","north-east"]


func _ready() -> void:
	stats      = StatsResource.from_json(STATS_PATH)
	current_hp = stats.max_hp

	_visual      = $CharacterVisual
	_body_poly   = $Body
	_aim_poly    = $AimIndicator
	_shoot_point = $ShootPoint
	_name_label  = $NameLabel
	_projectile_scene = load(PROJECTILE_SCENE)

	# Disable camera for remote players in co-op
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		$Camera2D.enabled = false

	_load_sprites()
	hp_changed.emit(current_hp, stats.max_hp)


func init_player(player_name: String) -> void:
	spawn_position = global_position
	if is_instance_valid(_name_label):
		_name_label.text = player_name
		_name_label.visible = multiplayer.has_multiplayer_peer()
		_name_label.add_theme_font_size_override("font_size", 5)
		_name_label.add_theme_color_override("font_color", Color("#FFFFFF"))
		_name_label.add_theme_color_override("font_outline_color", Color("#000000"))
		_name_label.add_theme_constant_override("outline_size", 1)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _load_sprites() -> void:
	var any := false
	for anim_name in ["idle", "walk", "dodge"]:
		var path := "res://assets/sprites/characters/player/%s.png" % anim_name
		var tex := load(path) as Texture2D
		if tex:
			# PixelLab walk = 8 frames, idle = varies, dodge = varies — set correct counts below
			var frames := 8
			var fps    := 8.0
			match anim_name:
				"idle":  frames = 4;  fps = 6.0
				"walk":  frames = 8;  fps = 10.0
				"dodge": frames = 6;  fps = 12.0
			_visual.register_animation(anim_name, tex, frames, fps)
			any = true
	if any:
		_body_poly.visible = false
		_aim_poly.visible  = false
		_visual.play("idle")
	else:
		_visual.visible = false   # keep polygon placeholders visible


func _physics_process(delta: float) -> void:
	if _is_dead:
		var is_auth := not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
		if is_auth:
			_respawn_timer -= delta
			respawn_countdown.emit(maxf(0.0, _respawn_timer))
			if _respawn_timer <= 0.0:
				_execute_respawn(spawn_position)
				if multiplayer.has_multiplayer_peer():
					_rpc_respawn.rpc(spawn_position)
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return  # remote player — position updated via _sync_state RPC
	_tick_timers(delta)
	if _is_dodging:
		_process_dodge(delta)
	else:
		_process_movement(delta)
		_process_aim()
		_process_attack(delta)
	move_and_slide()
	if multiplayer.has_multiplayer_peer():
		_sync_timer += delta
		if _sync_timer >= 0.033:   # ~30 Hz
			_sync_timer = 0.0
			_sync_state.rpc(global_position, _visual.get_current_anim(), _visual.get_current_dir())


@rpc("any_peer", "unreliable_ordered")
func _sync_state(pos: Vector2, anim: String, direction: String) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		global_position = pos
		if is_instance_valid(_visual) and not anim.is_empty():
			_visual.set_direction(direction)
			_visual.play(anim)


# ── Movement ──────────────────────────────────────────────────────────────────

func _process_movement(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * (stats.move_speed + run_speed_bonus)

	if dir != Vector2.ZERO:
		_visual.set_direction(_vec_to_dir(dir))
		_visual.play("walk")
	else:
		_visual.play("idle")

	if Input.is_action_just_pressed("dodge") and _dodge_cooldown <= 0.0 and dir != Vector2.ZERO:
		_start_dodge(dir)


func _start_dodge(dir: Vector2) -> void:
	_is_dodging    = true
	_dodge_dir     = dir.normalized()
	_dodge_timer   = stats.dodge_duration
	_dodge_cooldown = stats.dodge_cooldown
	_iframes_timer = stats.dodge_duration
	_visual.set_direction(_vec_to_dir(dir))
	_visual.play("dodge", true)


func _process_dodge(_delta: float) -> void:
	velocity = _dodge_dir * stats.dodge_speed
	_dodge_timer -= _delta
	if _dodge_timer <= 0.0:
		_is_dodging = false


# ── Aim ───────────────────────────────────────────────────────────────────────

func _process_aim() -> void:
	var aim := _get_aim_direction()
	if aim == Vector2.ZERO:
		aim = _aim_dir
	else:
		_aim_dir = aim

	if is_instance_valid(_shoot_point):
		_shoot_point.rotation = aim.angle()
	if is_instance_valid(_aim_poly):
		_aim_poly.rotation = aim.angle()

	_visual.set_direction(_vec_to_dir(aim))


func _get_aim_direction() -> Vector2:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.25:
		return stick.normalized()
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		return to_mouse.normalized()
	return Vector2.ZERO


# ── Attack ────────────────────────────────────────────────────────────────────

func _process_attack(_delta: float) -> void:
	if _attack_cooldown > 0.0 or not Input.is_action_pressed("attack"):
		return
	_fire_projectile()
	_attack_cooldown = 1.0 / stats.attack_speed


func _fire_projectile() -> void:
	if _projectile_scene == null or not is_instance_valid(_shoot_point):
		return
	var is_crit := randf() < stats.crit_chance
	var dmg     := (stats.damage + run_damage_bonus) * (stats.crit_multiplier if is_crit else 1.0)
	var vel     : Vector2 = _shoot_point.transform.x * stats.projectile_speed
	var lt      := stats.attack_range / stats.projectile_speed
	var uid     := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_do_spawn_projectile(_shoot_point.global_position, vel, dmg, is_crit, lt, uid)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_projectile.rpc(_shoot_point.global_position, vel, dmg, is_crit, lt, uid)


@rpc("authority", "unreliable")
func _rpc_spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, crit: bool, lt: float, uid: int) -> void:
	_do_spawn_projectile(pos, vel, dmg, crit, lt, uid)


func _do_spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, crit: bool, lt: float, uid: int) -> void:
	var p: Projectile = _projectile_scene.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.velocity        = vel
	p.damage          = dmg
	p.is_crit         = crit
	p.lifetime        = lt
	p.owner_peer_id   = uid


# ── Damage & Death ────────────────────────────────────────────────────────────

func take_damage(amount: float, _is_crit: bool = false) -> void:
	if _is_dead or _iframes_timer > 0.0:
		return
	current_hp     = maxf(0.0, current_hp - amount)
	_iframes_timer = stats.iframes_duration
	hp_changed.emit(current_hp, stats.max_hp)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_hp.rpc(current_hp)
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead       = true
	velocity       = Vector2.ZERO
	_respawn_timer = RESPAWN_TIME
	died.emit()


func _execute_respawn(pos: Vector2) -> void:
	_is_dead       = false
	current_hp     = stats.max_hp
	_iframes_timer = 1.0
	global_position = pos
	hp_changed.emit(current_hp, stats.max_hp)
	player_respawned.emit()


@rpc("authority", "reliable")
func _rpc_respawn(pos: Vector2) -> void:
	_execute_respawn(pos)


@rpc("any_peer", "reliable")
func _rpc_sync_hp(hp: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() != 1:
		return
	current_hp = hp
	hp_changed.emit(current_hp, stats.max_hp)
	if current_hp <= 0.0 and not _is_dead:
		_die()


func equip_weapon(texture: Texture2D) -> void:
	_visual.equip_weapon(texture)


func unequip_weapon() -> void:
	_visual.unequip_weapon()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _tick_timers(delta: float) -> void:
	if _attack_cooldown > 0.0: _attack_cooldown -= delta
	if _dodge_cooldown  > 0.0: _dodge_cooldown  -= delta
	if _iframes_timer   > 0.0: _iframes_timer   -= delta


func _vec_to_dir(v: Vector2) -> String:
	# Snap a direction vector to the nearest of 8 compass names
	var angle := fposmod(v.angle() + TAU, TAU)
	var idx    := int(round(angle / (TAU / 8.0))) % 8
	return _DIR_NAMES[idx]
