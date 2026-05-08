class_name Projectile
extends Area2D

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var is_crit: bool = false
var lifetime: float = 2.0
var _elapsed: float = 0.0
var owner_peer_id: int = 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		queue_free()
		return
	if body is PlayerController:
		if body.get_multiplayer_authority() == owner_peer_id:
			return
		if not NetworkManager.friendly_fire:
			return
	if body.has_method("take_damage"):
		body.take_damage(damage, is_crit)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		queue_free()
		return
	if area.has_method("take_damage"):
		area.take_damage(damage, is_crit)
	queue_free()
