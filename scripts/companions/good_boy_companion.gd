class_name GoodBoyCompanion
extends CharacterBody2D

const MOVE_SPEED     := 120.0
const RETURN_SPEED   := 90.0
const ATTACK_RANGE   := 22.0
const ATTACK_DAMAGE  := 1.0
const ATTACK_CD_TIME := 1.2
const CHASE_RANGE    := 350.0
const IDLE_ORBIT_RAD := 30.0

const _IDLE_PATH   := "res://assets/sprites/companions/good_boy/idle.png"
const _WALK_PATH   := "res://assets/sprites/companions/good_boy/walk.png"
const _ATTACK_PATH := "res://assets/sprites/companions/good_boy/attack.png"
const _BARK_SFX    := "res://assets/audio/sfx/dog_bark.mp3"
const _ATTACK_SFX  := "res://assets/audio/sfx/dog_attack.mp3"

const _DIR_NAMES := ["east","south-east","south","south-west","west","north-west","north","north-east"]

const _IDLE_FRAMES   := 8
const _WALK_FRAMES   := 6
const _ATTACK_FRAMES := 6

var _owner_player: PlayerController = null
var _target:       BaseEnemy        = null
var _attack_cd:    float            = 0.0
var _is_attacking: bool             = false
var _orbit_offset: Vector2          = Vector2(30.0, 0.0)

var _visual:     CharacterVisual
var _bark_sfx:   AudioStreamPlayer2D
var _attack_sfx: AudioStreamPlayer2D


func init(player: PlayerController, slot: int = 0, total: int = 1) -> void:
	_owner_player = player
	var angle := float(slot) / float(max(total, 1)) * TAU + PI * 0.3
	_orbit_offset = Vector2(cos(angle), sin(angle)) * IDLE_ORBIT_RAD
	if is_instance_valid(player):
		global_position = player.global_position + _orbit_offset


func _ready() -> void:
	add_to_group("companions")
	_visual     = $CharacterVisual
	_bark_sfx   = _make_sfx(_BARK_SFX,   -4.0, 200.0)
	_attack_sfx = _make_sfx(_ATTACK_SFX, -3.0, 220.0)
	_load_animations()
	_visual.play("idle")
	_schedule_bark()


func _make_sfx(path: String, vol: float, max_dist: float) -> AudioStreamPlayer2D:
	var sfx := AudioStreamPlayer2D.new()
	sfx.volume_db    = vol
	sfx.max_distance = max_dist
	var stream := load(path) as AudioStream
	if stream:
		sfx.stream = stream
	add_child(sfx)
	return sfx


func _load_animations() -> void:
	_try_register("idle",   _IDLE_PATH,   _IDLE_FRAMES,   8.0,  true)
	_try_register("walk",   _WALK_PATH,   _WALK_FRAMES,  14.0,  true)
	_try_register("attack", _ATTACK_PATH, _ATTACK_FRAMES, 18.0, false)
	_visual.animation_finished.connect(_on_anim_finished)


func _try_register(anim: String, path: String, frames: int, fps: float, loop: bool) -> void:
	var tex := load(path) as Texture2D
	if tex:
		_visual.register_animation(anim, tex, frames, fps, loop)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_owner_player) or _owner_player._is_dead:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_attack_cd -= delta
	_pick_target()

	if is_instance_valid(_target) and not _target._is_dead:
		_chase_and_attack()
	else:
		_follow_player()

	move_and_slide()

	if multiplayer.has_multiplayer_peer():
		_rpc_sync.rpc(global_position)


func _pick_target() -> void:
	var best_dist := CHASE_RANGE
	var best: BaseEnemy = null
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is BaseEnemy:
			continue
		var e := node as BaseEnemy
		if e._is_dead:
			continue
		var d := _owner_player.global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	_target = best


func _chase_and_attack() -> void:
	var dist := global_position.distance_to(_target.global_position)
	if dist <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if _attack_cd <= 0.0 and not _is_attacking:
			_attack_cd    = ATTACK_CD_TIME
			_is_attacking = true
			_visual.play("attack", true)
			_target.take_damage(ATTACK_DAMAGE)
			if is_instance_valid(_attack_sfx) and _attack_sfx.stream != null:
				_attack_sfx.play()
			if multiplayer.has_multiplayer_peer():
				_rpc_attack_visual.rpc()
	else:
		var dir := (_target.global_position - global_position).normalized()
		velocity = dir * MOVE_SPEED
		_visual.set_direction(_vec_to_dir(dir))
		if not _is_attacking:
			_visual.play("walk")


func _follow_player() -> void:
	var target_pos := _owner_player.global_position + _orbit_offset
	var dist := global_position.distance_to(target_pos)
	if dist > 8.0:
		var dir := (target_pos - global_position).normalized()
		velocity = dir * RETURN_SPEED
		_visual.set_direction(_vec_to_dir(dir))
		if not _is_attacking:
			_visual.play("walk")
	else:
		velocity = Vector2.ZERO
		if not _is_attacking:
			_visual.play("idle")


func _on_anim_finished(anim_name: String) -> void:
	if anim_name == "attack":
		_is_attacking = false
		_visual.play("idle")


func _schedule_bark() -> void:
	if not is_instance_valid(self):
		return
	var wait := randf_range(18.0, 40.0)
	get_tree().create_timer(wait).timeout.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(_bark_sfx) and _bark_sfx.stream != null:
			_bark_sfx.play()
		_schedule_bark())


@rpc("authority", "unreliable_ordered")
func _rpc_sync(pos: Vector2) -> void:
	global_position = pos


@rpc("authority", "reliable", "call_remote")
func _rpc_attack_visual() -> void:
	_visual.play("attack", true)


func _vec_to_dir(v: Vector2) -> String:
	var angle := fposmod(v.angle() + TAU, TAU)
	var idx   := int(round(angle / (TAU / 8.0))) % 8
	return _DIR_NAMES[idx]
