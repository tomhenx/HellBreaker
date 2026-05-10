class_name LavaPool
extends Area2D

var damage_per_second: float = 10.0
var lifetime:          float = 5.0
var radius:            float = 50.0
var owner_peer_id:     int   = 1

var _elapsed:     float = 0.0
var _dmg_tick:    float = 0.0
var _bodies:      Array = []
var _active:      bool  = true
var _body_outer:  Polygon2D = null
var _body_inner:  Polygon2D = null


func _ready() -> void:
	z_index = 1
	collision_layer = 0
	collision_mask  = 2

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape  = sh
	add_child(cs)

	_body_outer = Polygon2D.new()
	_body_outer.polygon = _blob_pts(radius, 7297)
	_body_outer.color   = Color(1.0, 0.22, 0.0, 0.85)
	_body_outer.z_index = 1
	add_child(_body_outer)

	_body_inner = Polygon2D.new()
	_body_inner.polygon = _blob_pts(radius * 0.55, 5531)
	_body_inner.color   = Color(1.0, 0.70, 0.1, 0.90)
	_body_inner.z_index = 2
	add_child(_body_inner)

	body_entered.connect(func(b): if b not in _bodies: _bodies.append(b))
	body_exited.connect(func(b): _bodies.erase(b))

	scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _blob_pts(r: float, seed_val: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed  = seed_val
	var seg := 16
	for i in seg:
		var a := float(i) / float(seg) * TAU
		var w := rng.randf_range(0.82, 1.18)
		pts.append(Vector2(cos(a), sin(a)) * r * w)
	return pts


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_elapsed  += delta
	_dmg_tick -= delta

	var frac := clampf(1.0 - _elapsed / lifetime, 0.0, 1.0)
	if is_instance_valid(_body_outer):
		_body_outer.color.a = 0.85 * frac
	if is_instance_valid(_body_inner):
		_body_inner.color.a = (0.80 + sin(_elapsed * 5.0) * 0.15) * frac

	if _elapsed >= lifetime:
		_active = false
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ZERO, 0.25)
		tw.tween_callback(queue_free)
		set_physics_process(false)
		return

	if _dmg_tick <= 0.0:
		_dmg_tick = 0.35
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return
		for body in _bodies:
			if is_instance_valid(body) and body.has_method("take_damage"):
				body.take_damage(damage_per_second * 0.35, false)
