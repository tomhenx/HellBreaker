class_name XpOrb
extends Node2D

var xp_value: int = 10

const PICKUP_RADIUS := 28.0
const FLOAT_AMP     := 3.0
const FLOAT_SPEED   := 2.0

const PICKUP_SFX := "res://assets/audio/sfx/xp_pickup.mp3"

var _time:       float = 0.0
var _claimed:    bool  = false
var _base_y:     float = 0.0
var _area:       Area2D
var _visual:     Node2D
var _sfx:        AudioStreamPlayer


func _ready() -> void:
	_base_y = position.y
	_area   = $PickupArea
	_visual = $Visual
	_sfx    = $SFX

	# Build visual: outer glow + bright core
	_build_visual()

	# Collision for pickup detection
	var cs    := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PICKUP_RADIUS
	cs.shape     = shape
	_area.add_child(cs)

	var stream := load(PICKUP_SFX) as AudioStream
	if stream:
		_sfx.stream = stream

	_area.body_entered.connect(_on_body_entered)
	_animate_spawn()


func _build_visual() -> void:
	const SEGS := 14
	# Outer glow ring
	var pts_outer := PackedVector2Array()
	var pts_inner := PackedVector2Array()
	for i in SEGS:
		var a := TAU * i / float(SEGS)
		pts_outer.append(Vector2(cos(a), sin(a)) * 7.0)
		pts_inner.append(Vector2(cos(a), sin(a)) * 3.5)
	var outer := $Visual/Outer as Polygon2D
	outer.polygon  = pts_outer
	outer.color    = Color(0.1, 1.0, 0.4, 0.45)
	var inner := $Visual/Inner as Polygon2D
	inner.polygon  = pts_inner
	inner.color    = Color(0.6, 1.0, 0.7, 0.95)


func _process(delta: float) -> void:
	if _claimed:
		return
	_time += delta
	_visual.position.y = sin(_time * FLOAT_SPEED) * FLOAT_AMP


func _on_body_entered(body: Node) -> void:
	if _claimed:
		return
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_claimed = true
	if multiplayer.has_multiplayer_peer():
		_rpc_pickup.rpc()
	else:
		_do_pickup()


@rpc("authority", "reliable", "call_local")
func _rpc_pickup() -> void:
	_do_pickup()


func _do_pickup() -> void:
	# Give XP to every player — each peer handles the player(s) it owns.
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			var pc := node as PlayerController
			if not multiplayer.has_multiplayer_peer() or pc.is_multiplayer_authority():
				pc.add_xp(xp_value)
	_play_pickup_sfx()
	_animate_pickup()


func _play_pickup_sfx() -> void:
	if is_instance_valid(_sfx) and _sfx.stream != null:
		_sfx.play()


func _animate_spawn() -> void:
	_visual.scale = Vector2(0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _animate_pickup() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_visual, "scale",      Vector2(2.0, 2.0), 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "modulate:a", 0.0,               0.25).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
