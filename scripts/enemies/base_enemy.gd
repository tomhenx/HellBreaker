class_name BaseEnemy
extends CharacterBody2D

signal died(enemy: BaseEnemy)

## Overridden by subclasses in _on_ready()
var hp:                   float = 30.0
var max_hp:               float = 30.0
var move_speed:           float = 80.0
var attack_range:         float = 28.0
var attack_damage:        float = 8.0
var attack_cooldown_time: float = 1.2
var xp_reward:            int   = 10
var coin_reward_min:      int   = 0
var coin_reward_max:      int   = 2

const XP_ORB_SCENE    := "res://scenes/items/xp_orb.tscn"
const COIN_DROP_SCENE := "res://scenes/items/coin_drop.tscn"
const CHEST_DROP_SCENE := "res://scenes/items/chest_drop.tscn"
const CHEST_DROP_CHANCE := 0.005

var _is_dead:              bool             = false
var _attack_cooldown:      float            = 0.0
var _target:               PlayerController = null
var _sync_timer:           float            = 0.0
var _last_attacker_id:     int              = -1


func _ready() -> void:
	add_to_group("enemies")
	_on_ready()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_attack_cooldown -= delta
	_pick_target()

	if is_instance_valid(_target):
		_ai_tick()
	else:
		velocity = Vector2.ZERO
		_on_idle()

	move_and_slide()

	if multiplayer.has_multiplayer_peer():
		_sync_timer += delta
		if _sync_timer >= 0.05:  # 20 Hz
			_sync_timer = 0.0
			_rpc_sync.rpc(global_position, velocity.normalized())


@rpc("authority", "unreliable_ordered")
func _rpc_sync(pos: Vector2, dir: Vector2) -> void:
	global_position = pos
	if dir.length() > 0.1:
		_on_moving(dir)
	else:
		_on_idle()


func _pick_target() -> void:
	var best_dist := INF
	var best: PlayerController = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is PlayerController:
			continue
		var pc := node as PlayerController
		if pc._is_dead:
			continue
		var d := global_position.distance_to(pc.global_position)
		if d < best_dist:
			best_dist = d
			best = pc
	_target = best


func _ai_tick() -> void:
	var dist := global_position.distance_to(_target.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		_on_idle()
		if _attack_cooldown <= 0.0:
			_attack_cooldown = attack_cooldown_time
			_perform_attack()
	else:
		var dir := (_target.global_position - global_position).normalized()
		velocity = dir * move_speed
		_on_moving(dir)


func _perform_attack() -> void:
	_on_attack_start()
	if is_instance_valid(_target):
		_target.take_damage(attack_damage)
	if multiplayer.has_multiplayer_peer():
		_rpc_attack_visual.rpc()


@rpc("authority", "reliable", "call_remote")
func _rpc_attack_visual() -> void:
	_on_attack_start()


func take_damage(amount: float, is_crit: bool = false, attacker_peer_id: int = -1) -> void:
	if _is_dead:
		return
	if attacker_peer_id >= 0:
		_last_attacker_id = attacker_peer_id
	hp = maxf(0.0, hp - amount)
	# Credit damage dealt to attacker
	if attacker_peer_id >= 0:
		var credited := minf(amount, hp + amount)  # actual damage landed
		_credit_attacker_damage(attacker_peer_id, credited)
	if multiplayer.has_multiplayer_peer():
		_rpc_on_hit.rpc(hp, is_crit)
	else:
		_on_hit(is_crit)
		if hp <= 0.0:
			_execute_death()


func _credit_attacker_kill() -> void:
	if _last_attacker_id < 0:
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			var pc := node as PlayerController
			if not multiplayer.has_multiplayer_peer() or pc.get_multiplayer_authority() == _last_attacker_id:
				pc.credit_kill()
				return


func _credit_attacker_damage(peer_id: int, amount: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			var pc := node as PlayerController
			if not multiplayer.has_multiplayer_peer() or pc.get_multiplayer_authority() == peer_id:
				pc.credit_damage(amount)
				return


@rpc("authority", "reliable", "call_local")
func _rpc_on_hit(new_hp: float, is_crit: bool) -> void:
	hp = new_hp
	_on_hit(is_crit)
	if hp <= 0.0 and not _is_dead:
		_execute_death()


func _execute_death() -> void:
	_is_dead = true
	_on_death()
	var is_authority := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_authority:
		_drop_rewards()
		_credit_attacker_kill()
		died.emit(self)
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(self):
			queue_free())


func _drop_rewards() -> void:
	var xp_scene := load(XP_ORB_SCENE) as PackedScene
	if xp_scene:
		var orb: Node2D = xp_scene.instantiate()
		orb.set("xp_value", xp_reward)
		get_tree().current_scene.add_child(orb)
		orb.global_position = global_position

	if coin_reward_max > 0:
		var coin_count := randi_range(coin_reward_min, coin_reward_max)
		if coin_count > 0:
			var coin_scene := load(COIN_DROP_SCENE) as PackedScene
			if coin_scene:
				var coin: Node2D = coin_scene.instantiate()
				coin.set("coin_value", coin_count)
				get_tree().current_scene.add_child(coin)
				coin.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))

	if randf() < CHEST_DROP_CHANCE:
		var chest_scene := load(CHEST_DROP_SCENE) as PackedScene
		if chest_scene:
			var chest: Node2D = chest_scene.instantiate()
			get_tree().current_scene.add_child(chest)
			chest.global_position = global_position


# ── Death animation (call from _on_death with the enemy's visual node) ───────

func play_death_animation(visual: Node2D) -> void:
	velocity = Vector2.ZERO
	set_physics_process(false)

	# Particles first so they appear behind the shrinking body
	_spawn_death_particles()

	if not is_instance_valid(visual):
		return

	var tw := create_tween().set_parallel(true)

	# 1. Bright white flash, then burn orange
	tw.tween_property(visual, "modulate", Color(3.5, 3.5, 3.5, 1.0), 0.05)
	tw.chain().tween_property(visual, "modulate", Color(2.2, 0.35, 0.05, 1.0), 0.10)

	# 2. Fall over — rotate ~100 degrees
	var fall_dir: float = 1.0 if randf() > 0.5 else -1.0
	tw.tween_property(self, "rotation_degrees", fall_dir * 100.0, 0.38) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

	# 3. Impact squish: briefly stretch wide & flat, then collapse to zero
	tw.tween_property(self, "scale", Vector2(1.5, 0.45), 0.12) \
		.set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "scale", Vector2(0.0, 0.0), 0.30) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CIRC)

	# 4. Fade alpha (starts a beat after the flash)
	tw.tween_property(visual, "modulate:a", 0.0, 0.40).set_delay(0.18)


func _spawn_death_particles() -> void:
	var root := get_tree().current_scene
	for i in 7:
		var r := randf_range(2.5, 6.5)
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)
		])
		p.color = Color(randf_range(0.7, 1.0), randf_range(0.0, 0.18), 0.0, 1.0)
		p.z_index = 5
		root.add_child(p)
		p.global_position = global_position + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		var vel := Vector2(randf_range(-90, 90), randf_range(-130, -25))
		var ptw := p.create_tween().set_parallel(true)
		ptw.tween_property(p, "position", p.position + vel * 0.45, 0.5)
		ptw.tween_property(p, "rotation_degrees", randf_range(-180.0, 180.0), 0.5)
		ptw.tween_property(p, "modulate:a", 0.0, 0.42).set_delay(0.10)
		ptw.tween_callback(p.queue_free).set_delay(0.55)


# ── Overrideable hooks ──────────────────────────────────────────────────────
func _on_ready() -> void: pass
func _on_idle() -> void: pass
func _on_moving(_dir: Vector2) -> void: pass
func _on_attack_start() -> void: pass
func _on_hit(_is_crit: bool) -> void: pass
func _on_death() -> void: pass
