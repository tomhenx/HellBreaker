class_name CoinDrop
extends Node2D

var coin_value: int = 1

const PICKUP_RADIUS := 24.0
const FLOAT_AMP     := 2.5
const FLOAT_SPEED   := 2.2
const COIN_SFX      := "res://assets/audio/sfx/coin_pickup.mp3"

var _time:    float = 0.0
var _claimed: bool  = false
var _area:    Area2D
var _visual:  Node2D
var _sfx:     AudioStreamPlayer


func _ready() -> void:
	_area   = $PickupArea
	_visual = $Visual
	_sfx    = $SFX

	# Build visual: gold coin circle
	_build_visual()

	# Collision for pickup detection
	var cs    := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PICKUP_RADIUS
	cs.shape     = shape
	_area.add_child(cs)

	var stream := load(COIN_SFX) as AudioStream
	if stream:
		_sfx.stream = stream

	_area.body_entered.connect(_on_body_entered)
	_animate_spawn()


func _build_visual() -> void:
	const SEGS := 12
	var coin_pts := PackedVector2Array()
	for i in SEGS:
		var a := TAU * i / float(SEGS)
		coin_pts.append(Vector2(cos(a), sin(a)) * 5.0)
	var coin := $Visual/Coin as Polygon2D
	coin.polygon = coin_pts
	coin.color   = Color(1.0, 0.85, 0.15)


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
	var pc := body as PlayerController
	if multiplayer.has_multiplayer_peer():
		_rpc_pickup.rpc(pc.get_multiplayer_authority())
	else:
		_do_pickup(pc)


@rpc("authority", "reliable", "call_local")
func _rpc_pickup(peer_id: int) -> void:
	var pc := _find_player(peer_id)
	if is_instance_valid(pc):
		_do_pickup(pc)


func _do_pickup(pc: PlayerController) -> void:
	if pc.is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		pc.add_coins(coin_value)
	if is_instance_valid(_sfx) and _sfx.stream != null:
		_sfx.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_visual, "scale",      Vector2(1.8, 1.8), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "modulate:a", 0.0,               0.22).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _animate_spawn() -> void:
	_visual.scale = Vector2(0.05, 0.05)
	_visual.position = Vector2(0, -8)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_visual, "scale",    Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_visual, "position", Vector2.ZERO, 0.25).set_ease(Tween.EASE_OUT)


func _find_player(peer_id: int) -> PlayerController:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController and node.get_multiplayer_authority() == peer_id:
			return node as PlayerController
	return null
