class_name LavaBlob
extends Node2D

const _POOL_SCENE := "res://scenes/enemies/lava_pool.tscn"
const _LAND_SFX   := "res://assets/audio/sfx/boss_blob_land.mp3"

var pool_radius:       float = 55.0
var pool_lifetime:     float = 4.5
var pool_dps:          float = 10.0
var owner_peer_id:     int   = 1

var _glow:   Polygon2D = null
var _body:   Polygon2D = null
var _core:   Polygon2D = null
var _wobble: float     = 0.0


func _ready() -> void:
	z_index = 5

	_glow = Polygon2D.new()
	_glow.polygon = _circle_pts(26.0, 14)
	_glow.color   = Color(1.0, 0.45, 0.0, 0.45)
	add_child(_glow)

	_body = Polygon2D.new()
	_body.polygon = _circle_pts(15.0, 12)
	_body.color   = Color(1.0, 0.18, 0.0, 1.0)
	add_child(_body)

	_core = Polygon2D.new()
	_core.polygon = _circle_pts(7.0, 10)
	_core.color   = Color(1.0, 0.85, 0.2, 0.95)
	add_child(_core)


func _process(delta: float) -> void:
	_wobble += delta * 8.0
	var w := sin(_wobble) * 0.08 + 1.0
	if is_instance_valid(_body):
		_body.scale = Vector2(1.0 / w, w)


func launch(from: Vector2, to: Vector2, flight_time: float = 0.75) -> void:
	global_position = from
	var peak := from.lerp(to, 0.5) + Vector2(0.0, -120.0)
	var tw := create_tween()
	tw.tween_method(_arc_move.bind(from, peak, to), 0.0, 1.0, flight_time) \
		.set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_on_land)


func _arc_move(t: float, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var a := p0.lerp(p1, t)
	var b := p1.lerp(p2, t)
	global_position = a.lerp(b, t)
	var s := 1.0 + sin(t * PI) * 0.45
	scale = Vector2.ONE * s


func _circle_pts(r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := float(i) / float(seg) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _on_land() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		queue_free()
		return

	var pool_packed := load(_POOL_SCENE) as PackedScene
	if pool_packed != null:
		var pool: LavaPool = pool_packed.instantiate() as LavaPool
		pool.radius            = pool_radius
		pool.lifetime          = pool_lifetime
		pool.damage_per_second = pool_dps
		pool.owner_peer_id     = owner_peer_id
		get_tree().current_scene.add_child(pool)
		pool.global_position = global_position

	_spawn_splat()

	var sfx := AudioStreamPlayer.new()
	var s := load(_LAND_SFX) as AudioStream
	if s != null:
		sfx.stream    = s
		sfx.volume_db = -3.0
		get_tree().current_scene.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)

	queue_free()


func _spawn_splat() -> void:
	var root := get_tree().current_scene
	for i in 8:
		var r := randf_range(1.5, 4.0)
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)
		])
		p.color   = Color(1.0, randf_range(0.15, 0.55), 0.0, 1.0)
		p.z_index = 8
		root.add_child(p)
		p.global_position = global_position
		var vel := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() \
			* randf_range(30.0, 90.0)
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "position", p.position + vel, 0.4)
		tw.tween_property(p, "modulate:a", 0.0, 0.35).set_delay(0.06)
		tw.tween_callback(p.queue_free).set_delay(0.45)
