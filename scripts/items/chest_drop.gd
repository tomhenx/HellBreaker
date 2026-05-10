class_name ChestDrop
extends Node2D

const _CHEST_TEX     := "res://assets/sprites/items/chest.png"
const _PICKUP_RADIUS := 36.0

var chest_type: String = "common"   # "common" or "prismatic"

var _sprite:    Sprite2D
var _glow:      Polygon2D
var _area:      Area2D
var _bob_time:  float = 0.0
var _picked_up: bool  = false
var _base_y:    float = 0.0
var _hue_t:     float = 0.0


func _ready() -> void:
	add_to_group("chest_drops")
	_base_y = global_position.y

	_glow = Polygon2D.new()
	_glow.polygon = PackedVector2Array([
		Vector2(0, -22), Vector2(22, 0), Vector2(0, 22), Vector2(-22, 0)
	])
	_glow.color   = Color(1.0, 0.85, 0.0, 0.35) if chest_type == "common" \
		else Color(0.8, 0.2, 1.0, 0.50)
	_glow.z_index = -1
	add_child(_glow)

	_sprite = Sprite2D.new()
	var tex := load(_CHEST_TEX) as Texture2D
	if tex != null:
		_sprite.texture        = tex
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(2.5, 2.5)

	if chest_type == "prismatic":
		_sprite.scale = Vector2(2.9, 2.9)
		var ring2 := Polygon2D.new()
		ring2.polygon = PackedVector2Array([
			Vector2(0, -30), Vector2(30, 0), Vector2(0, 30), Vector2(-30, 0)
		])
		ring2.color   = Color(0.5, 0.0, 1.0, 0.25)
		ring2.z_index = -2
		add_child(ring2)

	add_child(_sprite)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask  = 2
	var shape := CircleShape2D.new()
	shape.radius = _PICKUP_RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	_area.add_child(col)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func _process(delta: float) -> void:
	_bob_time += delta
	position.y = _base_y + sin(_bob_time * 2.5) * 4.0
	if is_instance_valid(_glow):
		if chest_type == "prismatic":
			_hue_t += delta * 0.8
			_glow.color = Color.from_hsv(fmod(_hue_t, 1.0), 0.85, 1.0, 0.50 + sin(_bob_time * 3.8) * 0.15)
			modulate = Color.from_hsv(fmod(_hue_t + 0.3, 1.0), 0.5, 1.0, 1.0).lerp(Color.WHITE, 0.6)
		else:
			_glow.color.a = 0.22 + sin(_bob_time * 3.8) * 0.14


func _on_body_entered(body: Node) -> void:
	if _picked_up:
		return
	if not body is PlayerController:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_picked_up = true
	var server_player := _find_server_player()
	if is_instance_valid(server_player):
		server_player._trigger_chest_sequence(chest_type)
	if multiplayer.has_multiplayer_peer():
		_rpc_despawn.rpc()
	else:
		queue_free()


func _find_server_player() -> PlayerController:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			var pc := node as PlayerController
			if not multiplayer.has_multiplayer_peer() or pc.get_multiplayer_authority() == 1:
				return pc
	return null


@rpc("authority", "reliable", "call_local")
func _rpc_despawn() -> void:
	queue_free()
