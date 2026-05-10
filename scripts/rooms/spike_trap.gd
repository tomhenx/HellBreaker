class_name SpikeTrap
extends Area2D

const DAMAGE        := 10.0
const WARN_TIME     := 0.10
const EXTEND_TIME   := 0.16
const RETRACT_TIME  := 0.28
const RETRACT_DELAY := 0.30

enum State { IDLE, WARNING, EXTENDING, ACTIVE, RETRACTING }

var _state: State = State.IDLE
var _tween: Tween = null

@onready var _idle_sprite:   Sprite2D            = $IdleSprite
@onready var _active_sprite: Sprite2D            = $ActiveSprite
@onready var _extend_sfx:    AudioStreamPlayer2D = $ExtendSFX
@onready var _retract_sfx:   AudioStreamPlayer2D = $RetractSFX


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_active_sprite.modulate.a = 0.0
	_active_sprite.scale      = Vector2.ONE


func _on_body_entered(body: Node2D) -> void:
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	match _state:
		State.IDLE:
			_trigger_warn()
		State.RETRACTING:
			_trigger_extend()
		State.ACTIVE:
			_deal_damage(body as PlayerController)


func _on_body_exited(body: Node2D) -> void:
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _state != State.ACTIVE:
		return
	if _players_on_trap().is_empty():
		_schedule_retract()


func _players_on_trap() -> Array:
	var out: Array = []
	for b in get_overlapping_bodies():
		if b is PlayerController:
			out.append(b)
	return out


# ── Network dispatch ──────────────────────────────────────────────────────────
# Server calls _trigger_*; these broadcast via call_local RPC in MP or run
# directly in singleplayer. Clients only ever execute the _play_* visuals.

func _trigger_warn() -> void:
	if multiplayer.has_multiplayer_peer(): _rpc_warn.rpc()
	else: _play_warn()

func _trigger_extend() -> void:
	if multiplayer.has_multiplayer_peer(): _rpc_extend.rpc()
	else: _play_extend()

func _trigger_retract() -> void:
	if multiplayer.has_multiplayer_peer(): _rpc_retract.rpc()
	else: _play_retract()


@rpc("authority", "reliable", "call_local")
func _rpc_warn() -> void:
	_play_warn()

@rpc("authority", "reliable", "call_local")
func _rpc_extend() -> void:
	_play_extend()

@rpc("authority", "reliable", "call_local")
func _rpc_retract() -> void:
	_play_retract()


# ── Visual playback (runs on ALL peers) ───────────────────────────────────────

func _play_warn() -> void:
	_state = State.WARNING
	_cancel_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_idle_sprite, "modulate", Color(1.5, 0.25, 0.25, 1.0), WARN_TIME) \
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_idle_sprite, "scale", Vector2(1.06, 1.06), WARN_TIME * 0.6)
	# Only server/singleplayer drives the next state transition
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_tween.chain().tween_callback(_trigger_extend)


func _play_extend() -> void:
	_state = State.EXTENDING
	_cancel_tween()
	_idle_sprite.modulate    = Color.WHITE
	_idle_sprite.scale       = Vector2.ONE
	_active_sprite.scale     = Vector2(0.4, 0.4)
	_active_sprite.modulate.a = 0.0

	if is_instance_valid(_extend_sfx):
		_extend_sfx.play()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_idle_sprite,   "modulate:a", 0.0,            EXTEND_TIME * 0.55) \
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(_active_sprite, "modulate:a", 1.0,            EXTEND_TIME * 0.45)
	_tween.tween_property(_active_sprite, "scale",      Vector2(1.18, 1.18), EXTEND_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_tween.chain().tween_property(_active_sprite, "scale", Vector2(1.0, 1.0), EXTEND_TIME * 0.25) \
			.set_ease(Tween.EASE_IN)
		_tween.chain().tween_callback(_on_extended)
	else:
		# Clients: finish the settle animation without a state callback
		_tween.chain().tween_property(_active_sprite, "scale", Vector2(1.0, 1.0), EXTEND_TIME * 0.25) \
			.set_ease(Tween.EASE_IN)


func _play_retract() -> void:
	_state = State.RETRACTING
	_cancel_tween()

	if is_instance_valid(_retract_sfx):
		_retract_sfx.play()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_active_sprite, "modulate:a", 0.0,         RETRACT_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_active_sprite, "scale",      Vector2(0.6, 0.6), RETRACT_TIME) \
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(_idle_sprite,   "modulate:a", 1.0,         RETRACT_TIME * 0.55) \
		.set_delay(RETRACT_TIME * 0.45).set_ease(Tween.EASE_OUT)

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_tween.chain().tween_callback(_on_retracted)


# ── Server-only callbacks ─────────────────────────────────────────────────────

func _on_extended() -> void:
	_state = State.ACTIVE
	_active_sprite.scale = Vector2.ONE
	for b: Node in _players_on_trap():
		_deal_damage(b as PlayerController)
	if _players_on_trap().is_empty():
		_schedule_retract()


func _schedule_retract() -> void:
	var timer := get_tree().create_timer(RETRACT_DELAY)
	timer.timeout.connect(func():
		if _state == State.ACTIVE and _players_on_trap().is_empty():
			_trigger_retract())


func _on_retracted() -> void:
	_state = State.IDLE
	_idle_sprite.modulate    = Color.WHITE
	_idle_sprite.scale       = Vector2.ONE
	_active_sprite.scale     = Vector2.ONE
	_active_sprite.modulate.a = 0.0


# ── Helpers ───────────────────────────────────────────────────────────────────

func _deal_damage(player: PlayerController) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if is_instance_valid(player):
		player.take_damage(DAMAGE)


func _cancel_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
		_tween = null
