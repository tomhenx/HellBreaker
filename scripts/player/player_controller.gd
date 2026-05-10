class_name PlayerController
extends CharacterBody2D

signal died
signal hp_changed(current: float, maximum: float)
signal player_respawned
signal respawn_countdown(seconds_left: float)
signal weapon_changed(weapon: WeaponResource)
signal coins_changed(amount: int)
signal xp_changed(current_xp: int, xp_needed: int, level: int)
signal level_up_gained(new_level: int)

const STATS_PATH        := "res://data/stats/player_base_stats.json"
const DEFAULT_WEAPON_ID := "throwing_axe"
const MELEE_SCENE       := preload("res://scenes/combat/melee_slash.tscn")
const WORLD_ITEM_SCENE  := preload("res://scenes/items/world_item.tscn")

# Sprite sheet paths (populated once PixelLab assets are imported)
const ANIM_WALK  := "res://assets/sprites/characters/player/walk.png"
const ANIM_IDLE  := "res://assets/sprites/characters/player/idle.png"
const ANIM_DODGE := "res://assets/sprites/characters/player/dodge.png"

# Runtime stats
var stats: StatsResource
var current_hp: float = 100.0
var run_damage_bonus:     float = 0.0
var run_speed_bonus:      float = 0.0
var run_crit_bonus:       float = 0.0
var run_atk_speed_bonus:  float = 0.0
var coins: int = 1000

# XP & level
var current_xp: int = 0
var level:      int = 1

# Weapons
var current_weapon:  WeaponResource
var current_offhand: WeaponResource = null

# Inventory
var _inventory: Inventory
var _inventory_ui:     Control     = null
var _inventory_canvas: CanvasLayer = null

# Floating skull effects (one per skull item in inventory)
var _skull_effects: Array[FloatingSkullEffect] = []

# Dog companions (one per Good Boy's Collar in inventory)
var _dog_companions: Array[GoodBoyCompanion] = []

# Level-up screen (server manages rewards/ready state; all peers hold UI ref)
var _level_up_screen:      LevelUpScreen     = null
var _level_up_rewards:     Array[Dictionary] = []
var _level_up_ready_peers: Array[int]        = []
var _level_up_pending:     bool              = false

const _LEVEL_UP_SCREEN_PATH := "res://scenes/ui/level_up_screen.tscn"

# Admin menu
var _admin_menu: AdminMenu = null
const _ADMIN_MENU_PATH := "res://scenes/ui/admin_menu.tscn"

# Chest screen
var _chest_screen:      ChestScreen = null
var _chest_rewards:     Dictionary  = {}
var _chest_ready_peers: Array[int]  = []

const _CHEST_SCREEN_PATH := "res://scenes/ui/chest_screen.tscn"

# Passive effects
var _passive_timers:   Dictionary = {}  # item_id -> accumulated seconds
var _fire_trail_timer: float      = 0.0
var _fire_trail_active: bool      = false

# Run stats (reset each arena run)
var stat_damage_dealt: float = 0.0
var stat_damage_taken: float = 0.0
var stat_kills:        int   = 0

# Arena flags
var can_respawn:       bool  = true

# Internal state
const RESPAWN_TIME := 5.0

var spawn_position:   Vector2 = Vector2.ZERO
var _attack_cooldown:  float = 0.0
var _offhand_cooldown: float = 0.0
var _dodge_cooldown:  float   = 0.0
var _is_dodging:      bool    = false
var _dodge_timer:     float   = 0.0
var _dodge_dir:       Vector2 = Vector2.ZERO
var _iframes_timer:   float   = 0.0
var _is_dead:         bool    = false
var _respawn_timer:   float   = 0.0
var _aim_dir:         Vector2 = Vector2(1, 0)

# Screen shake
var _shake_timer:    float = 0.0
var _shake_duration: float = 0.3
var _shake_strength: float = 0.0

# Node refs
var _visual:      CharacterVisual
var _body_poly:   Polygon2D
var _aim_poly:    Polygon2D
var _shoot_point: Marker2D
var _name_label:  Label
var _throw_sfx:   AudioStreamPlayer
var _melee_sfx:   AudioStreamPlayer
var _death_sfx:   AudioStreamPlayer
var _hit_sfx:     AudioStreamPlayer

# Multiplayer position sync interval
var _sync_timer: float = 0.0

# Direction names matching CharacterVisual.DIR_ROW
const _DIR_NAMES := ["east","south-east","south","south-west","west","north-west","north","north-east"]


func _ready() -> void:
	add_to_group("players")
	stats      = StatsResource.from_json(STATS_PATH)
	current_hp = stats.max_hp

	_visual      = $CharacterVisual
	_body_poly   = $Body
	_aim_poly    = $AimIndicator
	_shoot_point = $ShootPoint
	_name_label  = $NameLabel
	_inventory   = $Inventory

	# Disable camera for remote players in co-op
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		$Camera2D.enabled = false

	_load_sprites()

	# Throw SFX player
	_throw_sfx = AudioStreamPlayer.new()
	add_child(_throw_sfx)
	var throw_stream := load("res://assets/audio/sfx/axe_throw.mp3") as AudioStream
	if throw_stream:
		_throw_sfx.stream    = throw_stream
		_throw_sfx.volume_db = -6.0

	# Melee SFX player
	_melee_sfx = AudioStreamPlayer.new()
	add_child(_melee_sfx)
	var melee_stream := load("res://assets/audio/sfx/sword_swing.mp3") as AudioStream
	if melee_stream:
		_melee_sfx.stream    = melee_stream
		_melee_sfx.volume_db = -4.0

	# Death SFX player
	_death_sfx = AudioStreamPlayer.new()
	add_child(_death_sfx)
	var death_stream := load("res://assets/audio/sfx/player_death.mp3") as AudioStream
	if death_stream:
		_death_sfx.stream    = death_stream
		_death_sfx.volume_db = -3.0

	# Hit SFX player
	_hit_sfx = AudioStreamPlayer.new()
	add_child(_hit_sfx)
	var hit_stream := load("res://assets/audio/sfx/player_hit.mp3") as AudioStream
	if hit_stream:
		_hit_sfx.stream    = hit_stream
		_hit_sfx.volume_db = -4.0

	# Equip default weapon directly — guarantees current_weapon is never null
	_equip_weapon(DEFAULT_WEAPON_ID)

	# Inventory — react to equipment/item changes
	_inventory.equipment_changed.connect(_on_equipment_changed)
	_inventory.inventory_changed.connect(_recalculate_stats)
	_inventory.equipment_changed.connect(func(_s: String): _recalculate_stats())
	_inventory.inventory_changed.connect(_check_skull_effect)
	_inventory.inventory_changed.connect(_check_dog_companions)
	_inventory.equipment_changed.connect(func(_s: String): _check_dog_companions())

	var sword_item := ItemResource.from_id("wooden_sword")
	if sword_item != null:
		_inventory.add_item(sword_item)
		_inventory.equip_from_inv(0, "weapon")

	hp_changed.emit(current_hp, stats.max_hp)
	coins_changed.emit(coins)
	xp_changed.emit(current_xp, _xp_for_level(level), level)


func init_player(player_name: String) -> void:
	spawn_position = global_position
	if is_instance_valid(_name_label):
		_name_label.text = player_name
		_name_label.visible = multiplayer.has_multiplayer_peer()
		_name_label.add_theme_font_size_override("font_size", 16)
		_name_label.add_theme_color_override("font_color",         Color("#FFFFFF"))
		_name_label.add_theme_color_override("font_outline_color", Color("#000000"))
		_name_label.add_theme_constant_override("outline_size", 3)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		_name_label.clip_contents        = false
		_name_label.autowrap_mode        = TextServer.AUTOWRAP_OFF


func _load_sprites() -> void:
	var any := false
	for anim_name in ["idle", "walk", "dodge"]:
		var path := "res://assets/sprites/characters/player/%s.png" % anim_name
		var tex := load(path) as Texture2D
		if tex:
			var frames := 8
			var fps    := 8.0
			match anim_name:
				"idle":  frames = 4;  fps = 6.0
				"walk":  frames = 8;  fps = 10.0
				"dodge": frames = 6;  fps = 20.0
			_visual.register_animation(anim_name, tex, frames, fps)
			any = true
	# Die animation — one-shot, 8 fps, 8 frames detected from sheet width
	var die_tex := load("res://assets/sprites/characters/player/die.png") as Texture2D
	if die_tex:
		var die_frames := int(die_tex.get_width() * 8 / die_tex.get_height())
		_visual.register_animation("die", die_tex, die_frames, 8.0, false)
	_visual.animation_finished.connect(_on_visual_animation_finished)
	if any:
		_body_poly.visible = false
		_aim_poly.visible  = false
		_visual.play("idle")
	else:
		_visual.visible = false   # keep polygon placeholders visible


func _on_visual_animation_finished(_anim: String) -> void:
	pass  # die animation freezes on last frame automatically


func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_O:
		_toggle_admin_menu()
		get_viewport().set_input_as_handled()


func _toggle_admin_menu() -> void:
	if is_instance_valid(_admin_menu):
		_admin_menu.queue_free()
		_admin_menu = null
		return
	var scene := load(_ADMIN_MENU_PATH) as PackedScene
	if scene == null:
		return
	_admin_menu = scene.instantiate() as AdminMenu
	_admin_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_admin_menu)
	_admin_menu.init(self)


func _physics_process(delta: float) -> void:
	if _is_dead:
		if can_respawn:
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
	_update_shake(delta)
	_process_passive_effects(delta)
	var inv_open := is_instance_valid(_inventory_canvas) and _inventory_canvas.visible
	if Input.is_action_just_pressed("inventory") or \
			(Input.is_action_just_pressed("ui_cancel") and inv_open):
		_toggle_inventory()
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

	_visual.set_weapon_rotation(aim.angle())
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
	if is_instance_valid(_inventory_ui):
		return
	if not get_tree().get_nodes_in_group("blocks_player_input").is_empty():
		return

	if current_weapon != null and _attack_cooldown <= 0.0 \
			and Input.is_action_pressed("attack"):
		_execute_attack(current_weapon, false)
		_attack_cooldown = 1.0 / ((stats.attack_speed + run_atk_speed_bonus) * current_weapon.attack_speed_multiplier)

	if current_offhand != null and _offhand_cooldown <= 0.0 \
			and Input.is_action_pressed("attack_offhand"):
		_execute_attack(current_offhand, true)
		# Offhand attack speed is halved → cooldown is doubled
		_offhand_cooldown = 2.0 / ((stats.attack_speed + run_atk_speed_bonus) * current_offhand.attack_speed_multiplier)


func _execute_attack(weapon: WeaponResource, is_offhand: bool) -> void:
	var dmg_mult := 0.5 if is_offhand else 1.0
	if weapon.weapon_type == "melee":
		_do_melee_attack(weapon, dmg_mult)
	else:
		_fire_projectile(weapon, dmg_mult)


func _do_melee_attack(weapon: WeaponResource, dmg_mult: float = 1.0) -> void:
	if is_instance_valid(_melee_sfx) and _melee_sfx.stream != null:
		_melee_sfx.play()
	var is_crit := randf() < (stats.crit_chance + run_crit_bonus)
	var dmg := maxf(
		(stats.damage + run_damage_bonus) * weapon.damage_multiplier * dmg_mult
			* (stats.crit_multiplier if is_crit else 1.0),
		1.0
	)
	var uid := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var r   := weapon.range * 0.5
	var pos := global_position + _aim_dir * r
	var tex_path: String = weapon.hand_texture.resource_path \
		if weapon.hand_texture != null else ""
	_do_spawn_melee(pos, dmg, is_crit, uid, r, tex_path)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_melee.rpc(pos, dmg, is_crit, uid, r, tex_path)


@rpc("authority", "unreliable")
func _rpc_spawn_melee(pos: Vector2, dmg: float, crit: bool, uid: int, r: float,
		tex_path: String) -> void:
	_do_spawn_melee(pos, dmg, crit, uid, r, tex_path)


func _do_spawn_melee(pos: Vector2, dmg: float, crit: bool, uid: int, r: float,
		tex_path: String = "") -> void:
	var slash: MeleeSlash = MELEE_SCENE.instantiate()
	slash.radius          = r
	slash.damage          = dmg
	slash.is_crit         = crit
	slash.owner_peer_id   = uid
	slash.weapon_tex_path = tex_path
	slash.rotation        = _aim_dir.angle()
	get_tree().current_scene.add_child(slash)
	slash.global_position = pos


func _fire_projectile(weapon: WeaponResource, dmg_mult: float = 1.0) -> void:
	if weapon.projectile_scene == null or not is_instance_valid(_shoot_point):
		return
	if is_instance_valid(_throw_sfx) and _throw_sfx.stream != null:
		_throw_sfx.play()
	var is_crit := randf() < (stats.crit_chance + run_crit_bonus)
	var spd     := stats.projectile_speed * weapon.projectile_speed_multiplier
	var dmg     := maxf(
		(stats.damage + run_damage_bonus) * weapon.damage_multiplier * dmg_mult
			* (stats.crit_multiplier if is_crit else 1.0),
		1.0
	)
	var vel  : Vector2 = _shoot_point.transform.x * spd
	var lt   := weapon.range / spd
	var spin := weapon.spin_speed
	var uid  := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var scene_path := weapon.projectile_scene.resource_path
	_do_spawn_projectile(weapon.projectile_scene, _shoot_point.global_position, vel, dmg, is_crit, lt, uid, spin)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_projectile.rpc(scene_path, _shoot_point.global_position, vel, dmg, is_crit, lt, uid, spin)


@rpc("authority", "unreliable")
func _rpc_spawn_projectile(scene_path: String, pos: Vector2, vel: Vector2, dmg: float, crit: bool, lt: float, uid: int, spin: float) -> void:
	var scene := load(scene_path) as PackedScene
	if scene != null:
		_do_spawn_projectile(scene, pos, vel, dmg, crit, lt, uid, spin)


func _do_spawn_projectile(scene: PackedScene, pos: Vector2, vel: Vector2, dmg: float, crit: bool, lt: float, uid: int, spin: float) -> void:
	var p: Projectile = scene.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.velocity        = vel
	p.damage          = dmg
	p.is_crit         = crit
	p.lifetime        = lt
	p.owner_peer_id   = uid
	if "spin_speed" in p:
		p.spin_speed = spin


# ── Damage & Death ────────────────────────────────────────────────────────────

func take_damage(amount: float, _is_crit: bool = false) -> void:
	if _is_dead or _iframes_timer > 0.0:
		return
	var effective := maxf(amount - stats.armor, 0.0)
	if effective <= 0.0:
		return
	stat_damage_taken += effective
	current_hp     = maxf(0.0, current_hp - effective)
	_iframes_timer = stats.iframes_duration
	hp_changed.emit(current_hp, stats.max_hp)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_hp.rpc(current_hp)
	_shake_camera(clampf(effective / 5.0, 3.0, 8.0))
	if is_instance_valid(_hit_sfx) and _hit_sfx.stream != null:
		_hit_sfx.play()
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead       = true
	velocity       = Vector2.ZERO
	_respawn_timer = RESPAWN_TIME
	if is_instance_valid(_visual):
		_visual.play("die", true)
		_visual.unequip_weapon()
	if is_instance_valid(_death_sfx) and _death_sfx.stream != null:
		_death_sfx.play()
	died.emit()


func _execute_respawn(pos: Vector2) -> void:
	_is_dead        = false
	current_hp      = stats.max_hp
	_iframes_timer  = 1.0
	global_position = pos
	scale           = Vector2.ONE
	modulate        = Color.WHITE
	if is_instance_valid(_visual):
		_visual.play("idle", true)
		if current_weapon != null and current_weapon.hand_texture != null:
			_visual.equip_weapon(current_weapon.hand_texture)
		if current_offhand != null and current_offhand.hand_texture != null:
			_visual.equip_offhand(current_offhand.hand_texture)
		else:
			_visual.unequip_offhand()
	hp_changed.emit(current_hp, stats.max_hp)
	player_respawned.emit()


func revive(hp_percent: float = 0.30) -> void:
	_execute_respawn(global_position)
	current_hp = maxf(1.0, stats.max_hp * hp_percent)
	hp_changed.emit(current_hp, stats.max_hp)
	if multiplayer.has_multiplayer_peer():
		_rpc_respawn.rpc(global_position)


func credit_kill() -> void:
	stat_kills += 1
	# on_kill_heal passive (e.g. Tatra Tea Hell Edition)
	for item: ItemResource in _all_inventory_items():
		for fx: Dictionary in item.passive_effects:
			if fx.get("type", "") == "on_kill_heal":
				var amount: float = float(fx.get("amount", 2.0))
				current_hp = minf(current_hp + amount, stats.max_hp)
				hp_changed.emit(current_hp, stats.max_hp)


func credit_damage(amount: float) -> void:
	stat_damage_dealt += amount


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


func pickup_weapon(weapon_id: String) -> void:
	var item := ItemResource.from_id(weapon_id)
	if item == null:
		return
	if _inventory.add_item(item):
		if _inventory.equipped.get("weapon", null) == null:
			var idx := _inventory.find_item(weapon_id)
			if idx >= 0:
				_inventory.equip_from_inv(idx, "weapon")


func _on_equipment_changed(slot_id: String) -> void:
	match slot_id:
		"weapon":
			var item := _inventory.equipped.get("weapon", null) as ItemResource
			if item != null and not item.weapon_id.is_empty():
				_equip_weapon(item.weapon_id)  # emits weapon_changed internally
				# 2H weapon: force-unequip whatever is in the offhand
				if current_weapon != null and current_weapon.is_two_handed:
					_inventory.unequip_slot("offhand")
					current_offhand = null
					if is_instance_valid(_visual):
						_visual.unequip_offhand()
			else:
				current_weapon = null
				if is_instance_valid(_visual):
					_visual.unequip_weapon()
				weapon_changed.emit(current_weapon)
		"offhand":
			var item := _inventory.equipped.get("offhand", null) as ItemResource
			if item != null and not item.weapon_id.is_empty():
				current_offhand = WeaponResource.from_id(item.weapon_id)
				if is_instance_valid(_visual):
					if current_offhand != null and current_offhand.hand_texture != null:
						_visual.equip_offhand(current_offhand.hand_texture)
					else:
						_visual.unequip_offhand()
			else:
				current_offhand = null
				if is_instance_valid(_visual):
					_visual.unequip_offhand()


func _equip_weapon(weapon_id: String) -> void:
	var w := WeaponResource.from_id(weapon_id)
	if w == null:
		return
	current_weapon = w
	if is_instance_valid(_visual):
		if w.hand_texture != null:
			_visual.equip_weapon(w.hand_texture)
		else:
			_visual.unequip_weapon()
	weapon_changed.emit(current_weapon)


func _toggle_inventory() -> void:
	if is_instance_valid(_inventory_canvas):
		_inventory_canvas.queue_free()
		_inventory_canvas = null
		_inventory_ui     = null
		return
	var ui := InventoryUI.new()
	ui.init(_inventory, stats, self)
	ui.drop_requested.connect(_on_item_dropped_to_world)
	_inventory_ui = ui

	_inventory_canvas = CanvasLayer.new()
	_inventory_canvas.layer = 15
	get_tree().current_scene.add_child(_inventory_canvas)
	_inventory_canvas.add_child(ui)

	# If the UI closes itself (backdrop click / ✕ button), clean up the canvas wrapper too
	ui.tree_exited.connect(func():
		_inventory_ui = null
		if is_instance_valid(_inventory_canvas):
			_inventory_canvas.queue_free()
			_inventory_canvas = null
	)


func _on_item_dropped_to_world(dropped_item: ItemResource) -> void:
	var scatter    := Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))
	var target_pos := global_position + scatter
	if not multiplayer.has_multiplayer_peer():
		_spawn_world_item(dropped_item.id, target_pos, "")
		return
	if multiplayer.is_server():
		var wname := "wi_%d" % Time.get_ticks_msec()
		_spawn_world_item(dropped_item.id, target_pos, wname)
		_rpc_spawn_wi.rpc(dropped_item.id, target_pos, wname)
	else:
		_rpc_request_drop.rpc_id(1, dropped_item.id, target_pos)


@rpc("any_peer", "reliable")
func _rpc_request_drop(item_id: String, spawn_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var wname := "wi_%d_%d" % [multiplayer.get_remote_sender_id(), Time.get_ticks_msec()]
	_spawn_world_item(item_id, spawn_pos, wname)
	_rpc_spawn_wi.rpc(item_id, spawn_pos, wname)


@rpc("any_peer", "reliable")
func _rpc_spawn_wi(item_id: String, spawn_pos: Vector2, node_name: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # only trust spawns originating from server
	_spawn_world_item(item_id, spawn_pos, node_name)


func _spawn_world_item(item_id: String, spawn_pos: Vector2, node_name: String) -> void:
	var itm := ItemResource.from_id(item_id)
	if itm == null:
		return
	var wi := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if not node_name.is_empty():
		wi.name = node_name
	wi.setup(itm)
	get_tree().current_scene.add_child(wi)
	wi.global_position = spawn_pos


# ── Passive & Stat Bonus System ───────────────────────────────────────────────

func _recalculate_stats() -> void:
	var prev_max := stats.max_hp
	stats = StatsResource.from_json(STATS_PATH)

	# inventory_slots bonus counts only when the item is equipped
	var slot_bonus: int = 0
	for v: Variant in _inventory.equipped.values():
		if v is ItemResource:
			slot_bonus += int((v as ItemResource).stat_bonuses.get("inventory_slots", 0))
	_inventory.set_bonus_slots(slot_bonus)

	var all_items: Array[ItemResource] = _all_inventory_items()
	for item: ItemResource in all_items:
		for key: String in item.stat_bonuses:
			if key == "inventory_slots":
				continue
			var bonus: float = float(item.stat_bonuses[key])
			var cur: Variant = stats.get(key)
			if cur != null:
				stats.set(key, float(cur) + bonus)

	if stats.max_hp != prev_max:
		current_hp = minf(current_hp, stats.max_hp)
		hp_changed.emit(current_hp, stats.max_hp)


func _process_passive_effects(delta: float) -> void:
	if _is_dead:
		return
	_fire_trail_active = false
	for item: ItemResource in _all_inventory_items():
		if item.passive_effects.is_empty():
			continue
		var acc: float = _passive_timers.get(item.id, 0.0) + delta
		for fx: Dictionary in item.passive_effects:
			if fx.get("type", "") == "fire_trail":
				_fire_trail_active = true
				continue
			var interval: float = float(fx.get("interval", 5.0))
			if acc >= interval:
				_execute_passive(fx)
		_passive_timers[item.id] = fmod(acc, float(item.passive_effects[0].get("interval", 5.0)))

	# Fire trail tick (independent of interval system)
	if _fire_trail_active and is_multiplayer_authority():
		_fire_trail_timer += delta
		if _fire_trail_timer >= 0.18:
			_fire_trail_timer = 0.0
			_spawn_fire_ember()


func _spawn_fire_ember() -> void:
	var ember     := Polygon2D.new()
	var r         := randf_range(5.0, 11.0)
	var pts: Array[Vector2] = []
	for i in range(6):
		var a := i * TAU / 6.0 + randf_range(-0.4, 0.4)
		pts.append(Vector2(cos(a) * r * randf_range(0.6, 1.2),
		                   sin(a) * r * randf_range(0.6, 1.2)))
	ember.polygon  = PackedVector2Array(pts)
	ember.color    = Color(randf_range(0.9, 1.0), randf_range(0.3, 0.6), 0.0, 0.85)
	ember.position = global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	ember.z_index  = -1
	get_parent().add_child(ember)
	var tw := ember.create_tween()
	tw.tween_property(ember, "color:a", 0.0, randf_range(0.9, 1.8))
	tw.tween_callback(ember.queue_free)


func _execute_passive(fx: Dictionary) -> void:
	match fx.get("type", ""):
		"hp_regen":
			var amount: float = float(fx.get("amount", 1.0))
			current_hp = minf(current_hp + amount, stats.max_hp)
			hp_changed.emit(current_hp, stats.max_hp)


func _all_inventory_items() -> Array[ItemResource]:
	var result: Array[ItemResource] = []
	for v: Variant in _inventory.equipped.values():
		if v is ItemResource:
			result.append(v as ItemResource)
	for v: Variant in _inventory.items:
		if v is ItemResource:
			var item := v as ItemResource
			if item.equip_slot.is_empty():  # non-equippable items (relics) stay active from backpack
				result.append(item)
	return result


# ── Coins ─────────────────────────────────────────────────────────────────────

func add_coins(n: int) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	coins += n
	coins_changed.emit(coins)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_coins.rpc(coins)


func spend_coins(n: int) -> bool:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return false
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_coins.rpc(coins)
	return true


@rpc("any_peer", "reliable")
func _rpc_sync_coins(amount: int) -> void:
	if multiplayer.has_multiplayer_peer() and \
			multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	coins = amount
	coins_changed.emit(coins)


# ── XP & Level ───────────────────────────────────────────────────────────────

func add_xp(amount: int) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	current_xp += amount
	var needed := _xp_for_level(level)
	var leveled_up := false
	while current_xp >= needed:
		current_xp -= needed
		level      += 1
		leveled_up  = true
		_apply_level_up()
		if multiplayer.has_multiplayer_peer():
			_rpc_level_up.rpc(level)
		level_up_gained.emit(level)
		needed = _xp_for_level(level)
	xp_changed.emit(current_xp, needed, level)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_xp.rpc(current_xp, level)
	# Server's own player triggers the level-up reward screen for all players
	if leveled_up and not _level_up_active() and not _level_up_pending:
		var is_trigger := not multiplayer.has_multiplayer_peer() or \
			(multiplayer.is_server() and is_multiplayer_authority())
		if is_trigger:
			_level_up_pending = true
			call_deferred("_trigger_level_up_sequence", level)


func _xp_for_level(lvl: int) -> int:
	return int(50.0 * pow(1.22, lvl - 1))


func _apply_level_up() -> void:
	run_damage_bonus    += 2.0
	run_speed_bonus     += 4.0
	run_crit_bonus      += 0.005
	run_atk_speed_bonus += 0.05
	current_hp           = minf(current_hp + 10.0, stats.max_hp + float(level - 1) * 5.0)
	hp_changed.emit(current_hp, stats.max_hp)


@rpc("any_peer", "reliable")
func _rpc_sync_xp(xp: int, lvl: int) -> void:
	if multiplayer.has_multiplayer_peer() and \
			multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	current_xp = xp
	level      = lvl
	xp_changed.emit(current_xp, _xp_for_level(level), level)


@rpc("authority", "reliable", "call_remote")
func _rpc_level_up(new_level: int) -> void:
	level = new_level
	level_up_gained.emit(new_level)


# ── Floating Skull ────────────────────────────────────────────────────────────

func _check_skull_effect() -> void:
	var skull_count := 0
	for v: Variant in _inventory.items:
		if v is ItemResource and (v as ItemResource).id == "skull_of_uncle_fernando":
			skull_count += 1

	if skull_count == _skull_effects.size():
		return

	_sync_skulls(skull_count)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_skulls.rpc(skull_count)


func _sync_skulls(count: int) -> void:
	while _skull_effects.size() > count:
		var s: FloatingSkullEffect = _skull_effects.pop_back()
		if is_instance_valid(s):
			s.queue_free()
	while _skull_effects.size() < count:
		var slot := _skull_effects.size()
		var s := FloatingSkullEffect.new()
		s.init(self, slot, count)
		get_tree().current_scene.add_child(s)
		_skull_effects.append(s)


@rpc("authority", "reliable")
func _rpc_sync_skulls(count: int) -> void:
	_sync_skulls(count)


@rpc("authority", "unreliable")
func _rpc_fernando_scream(skull_idx: int, scream_idx: int) -> void:
	if skull_idx >= 0 and skull_idx < _skull_effects.size():
		var s: FloatingSkullEffect = _skull_effects[skull_idx]
		if is_instance_valid(s):
			s.do_scream(scream_idx)


# ── Level-Up Reward Screen ────────────────────────────────────────────────────

func _level_up_active() -> bool:
	return is_instance_valid(_level_up_screen)


func _trigger_level_up_sequence(new_level: int) -> void:
	_level_up_pending = false
	if _level_up_active():
		return
	var peers := _get_player_peers()
	_level_up_rewards     = _generate_rewards(new_level, peers)
	_level_up_ready_peers = []
	var json := JSON.stringify(_level_up_rewards)
	if multiplayer.has_multiplayer_peer():
		_rpc_show_level_up.rpc(new_level, json)
	else:
		_show_level_up_local(new_level, _level_up_rewards)
		get_tree().paused = true


@rpc("authority", "reliable", "call_local")
func _rpc_show_level_up(new_level: int, rewards_json: String) -> void:
	var rewards: Array[Dictionary] = _parse_rewards_json(rewards_json)
	_show_level_up_local(new_level, rewards)
	get_tree().paused = true


func _show_level_up_local(new_level: int, rewards: Array[Dictionary]) -> void:
	var local_player := _find_local_player()
	if local_player == null:
		return
	var server_ctrl := _find_server_player()

	var screen_scene := load(_LEVEL_UP_SCREEN_PATH) as PackedScene
	if screen_scene == null:
		push_error("LevelUpScreen scene not found")
		return
	_level_up_screen             = screen_scene.instantiate() as LevelUpScreen
	_level_up_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_level_up_screen)
	_level_up_screen.init(new_level, rewards, local_player, server_ctrl)


# ── Server: item claiming ──────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func rpc_claim_level_reward(slot_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_process_claim(multiplayer.get_remote_sender_id(), slot_idx)


func _process_claim(caller_peer: int, slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _level_up_rewards.size():
		return
	var rd: Dictionary = _level_up_rewards[slot_idx]
	if int(rd.get("claimed_by", -1)) != -1:
		return
	# One item per player per level-up
	for existing: Dictionary in _level_up_rewards:
		if int(existing.get("claimed_by", -1)) == caller_peer:
			return
	_level_up_rewards[slot_idx]["claimed_by"] = caller_peer
	_give_item_to_peer(caller_peer, rd.get("item_id", ""))
	if multiplayer.has_multiplayer_peer():
		_rpc_update_reward.rpc(slot_idx, caller_peer)
	elif is_instance_valid(_level_up_screen):
		_level_up_screen.update_reward(slot_idx, caller_peer)


@rpc("authority", "reliable", "call_local")
func _rpc_update_reward(slot_idx: int, claimer_peer: int) -> void:
	if is_instance_valid(_level_up_screen):
		_level_up_screen.update_reward(slot_idx, claimer_peer)


func _give_item_to_peer(peer_id: int, item_id: String) -> void:
	var item := ItemResource.from_id(item_id)
	if item == null:
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is PlayerController:
			continue
		var pc := node as PlayerController
		var owns := not multiplayer.has_multiplayer_peer() or \
			pc.get_multiplayer_authority() == peer_id
		if not owns:
			continue
		if not multiplayer.has_multiplayer_peer() or peer_id == multiplayer.get_unique_id():
			pc._inventory.add_item(item)
		else:
			pc._rpc_grant_item.rpc_id(peer_id, item_id)
		return


@rpc("any_peer", "reliable")
func _rpc_grant_item(item_id: String) -> void:
	# Only server may grant items
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() != 1:
		return
	var item := ItemResource.from_id(item_id)
	if item:
		_inventory.add_item(item)


# ── Server: ready state ────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func rpc_level_up_ready() -> void:
	if not multiplayer.is_server():
		return
	_process_ready(multiplayer.get_remote_sender_id())


func _process_ready(peer_id: int) -> void:
	if peer_id in _level_up_ready_peers:
		return
	_level_up_ready_peers.append(peer_id)
	var total := maxi(1, get_tree().get_nodes_in_group("players").size())
	if multiplayer.has_multiplayer_peer():
		_rpc_update_ready_state.rpc(_level_up_ready_peers.duplicate(), total)
	elif is_instance_valid(_level_up_screen):
		_level_up_screen.set_ready_state(_level_up_ready_peers, total)
	if _level_up_ready_peers.size() >= total:
		_close_level_up()


@rpc("authority", "reliable", "call_local")
func _rpc_update_ready_state(ready_peers: Array, total: int) -> void:
	if is_instance_valid(_level_up_screen):
		_level_up_screen.set_ready_state(ready_peers, total)


# ── Close screen ──────────────────────────────────────────────────────────────

func _close_level_up() -> void:
	_level_up_rewards.clear()
	_level_up_ready_peers.clear()
	if multiplayer.has_multiplayer_peer():
		_rpc_close_level_up.rpc()
	else:
		_close_level_up_local()


@rpc("authority", "reliable", "call_local")
func _rpc_close_level_up() -> void:
	_close_level_up_local()


func _close_level_up_local() -> void:
	if is_instance_valid(_level_up_screen):
		_level_up_screen.queue_free()
		_level_up_screen = null
	get_tree().paused = false


# ── Chest Screen ──────────────────────────────────────────────────────────────

func _chest_active() -> bool:
	return is_instance_valid(_chest_screen)


func _trigger_chest_sequence(chest_type: String = "common") -> void:
	if _chest_active() or _level_up_active():
		return
	_chest_rewards     = {}
	_chest_ready_peers = []
	var peers   := _get_player_peers()
	var pool: Array[ItemResource]
	var weights: Dictionary
	if chest_type == "prismatic":
		pool    = _build_relic_pool()
		weights = {"relic": 100, "secret": 1}  # secret items are ultra-rare (~0.25% per roll)
		if pool.is_empty():
			pool    = _build_reward_pool()
			weights = {"legendary": 80, "epic": 20}
	else:
		pool    = _build_reward_pool()
		weights = {"common": 40, "uncommon": 30, "rare": 20, "epic": 8, "legendary": 2}
	var used: Array[String] = []
	for peer_id: int in peers:
		var item := _pick_reward_item(pool, weights, used)
		if item:
			used.append(item.id)
			_chest_rewards[str(peer_id)] = item.id
	var json := JSON.stringify(_chest_rewards)
	if multiplayer.has_multiplayer_peer():
		_rpc_open_chest.rpc(json)
	else:
		_open_chest_local(_chest_rewards)
		get_tree().paused = true


@rpc("authority", "reliable", "call_local")
func _rpc_open_chest(rewards_json: String) -> void:
	var parsed: Variant = JSON.parse_string(rewards_json)
	var rewards: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	_open_chest_local(rewards)
	get_tree().paused = true


func _open_chest_local(rewards: Dictionary) -> void:
	var local_player := _find_local_player()
	if local_player == null:
		return
	var server_ctrl := _find_server_player()
	var screen_scene := load(_CHEST_SCREEN_PATH) as PackedScene
	if screen_scene == null:
		push_error("ChestScreen scene not found")
		return
	_chest_screen = screen_scene.instantiate() as ChestScreen
	_chest_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_chest_screen)
	_chest_screen.init(rewards, local_player, server_ctrl)


@rpc("any_peer", "reliable")
func rpc_chest_ready() -> void:
	if not multiplayer.is_server():
		return
	_process_chest_ready(multiplayer.get_remote_sender_id())


func _process_chest_ready(peer_id: int) -> void:
	if peer_id in _chest_ready_peers:
		return
	_chest_ready_peers.append(peer_id)
	var total := maxi(1, get_tree().get_nodes_in_group("players").size())
	if multiplayer.has_multiplayer_peer():
		_rpc_update_chest_ready.rpc(_chest_ready_peers.duplicate(), total)
	elif is_instance_valid(_chest_screen):
		_chest_screen.set_ready_state(_chest_ready_peers, total)
	if _chest_ready_peers.size() >= total:
		_close_chest()


@rpc("authority", "reliable", "call_local")
func _rpc_update_chest_ready(ready_peers: Array, total: int) -> void:
	if is_instance_valid(_chest_screen):
		_chest_screen.set_ready_state(ready_peers, total)


func _close_chest() -> void:
	_chest_rewards.clear()
	_chest_ready_peers.clear()
	if multiplayer.has_multiplayer_peer():
		_rpc_close_chest.rpc()
	else:
		_close_chest_local()


@rpc("authority", "reliable", "call_local")
func _rpc_close_chest() -> void:
	_close_chest_local()


func _close_chest_local() -> void:
	if is_instance_valid(_chest_screen):
		_chest_screen.queue_free()
		_chest_screen = null
	get_tree().paused = false


# ── Reward generation (server only) ───────────────────────────────────────────

func _generate_rewards(lvl: int, player_peers: Array[int]) -> Array[Dictionary]:
	var pool    := _build_reward_pool()
	var weights := _rarity_weights(lvl)
	var used:   Array[String]     = []
	var result: Array[Dictionary] = []
	var count := player_peers.size() * 2
	for _i in count:
		var item := _pick_reward_item(pool, weights, used)
		if item:
			used.append(item.id)
			result.append({"item_id": item.id, "claimed_by": -1})
	return result


static func _build_reward_pool() -> Array[ItemResource]:
	var f := FileAccess.open("res://data/items/items.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return []
	var items_data: Dictionary = (parsed as Dictionary).get("items", {})
	var pool: Array[ItemResource] = []
	for id: String in items_data.keys():
		var d: Dictionary = items_data[id] as Dictionary
		if d.get("rarity", "") == "relic":
			continue
		if int(d.get("max_stack", 1)) > 1:
			continue
		var item := ItemResource.from_id(id)
		if item:
			pool.append(item)
	return pool


static func _build_relic_pool() -> Array[ItemResource]:
	var f := FileAccess.open("res://data/items/items.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return []
	var items_data: Dictionary = (parsed as Dictionary).get("items", {})
	var pool: Array[ItemResource] = []
	for id: String in items_data.keys():
		var d: Dictionary = items_data[id] as Dictionary
		var rarity: String = d.get("rarity", "")
		# "secret" items (e.g. Tatra Tea) enter the pool at a tiny weight via drop_weight field
		if rarity != "relic" and rarity != "secret":
			continue
		var item := ItemResource.from_id(id)
		if item:
			pool.append(item)
	return pool


static func _rarity_weights(lvl: int) -> Dictionary:
	return {
		"common":    max(0, 65 - lvl * 5),
		"uncommon":  clampi(10 + lvl * 3, 0, 35),
		"rare":      clampi((lvl - 2) * 4, 0, 30),
		"epic":      clampi((lvl - 5) * 3, 0, 25),
		"legendary": clampi((lvl - 9) * 2, 0, 20),
	}


func _pick_reward_item(pool: Array[ItemResource], weights: Dictionary,
		used: Array[String]) -> ItemResource:
	var total_w := 0
	var entries: Array[Dictionary] = []
	for item in pool:
		if item.id in used:
			continue
		var w: int = weights.get(item.rarity, 0)
		if w <= 0:
			continue
		total_w += w
		entries.append({"item": item, "cum": total_w})
	if entries.is_empty():
		for item in pool:
			if item.id not in used:
				return item
		return null
	var roll := randi() % total_w
	for entry: Dictionary in entries:
		if roll < int(entry.get("cum", 0)):
			return entry.get("item") as ItemResource
	return null


func _get_player_peers() -> Array[int]:
	if not multiplayer.has_multiplayer_peer():
		return [1]
	var peers: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			peers.append((node as PlayerController).get_multiplayer_authority())
	return peers


func _find_local_player() -> PlayerController:
	if not multiplayer.has_multiplayer_peer():
		return self
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController and (node as PlayerController).is_multiplayer_authority():
			return node as PlayerController
	return null


func _find_server_player() -> PlayerController:
	if not multiplayer.has_multiplayer_peer():
		return self
	# When called inside _rpc_show_level_up (which runs on the server's node),
	# self IS the server's player on every peer.
	return self


static func _parse_rewards_json(json_str: String) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(json_str)
	var result: Array[Dictionary] = []
	if parsed is Array:
		for entry: Variant in (parsed as Array):
			if entry is Dictionary:
				result.append(entry as Dictionary)
	return result


# ── Dog Companion ─────────────────────────────────────────────────────────────

const _DOG_SCENE := "res://scenes/companions/good_boy_companion.tscn"

func _check_dog_companions() -> void:
	var collar_count := 0
	for v: Variant in _inventory.items:
		if v is ItemResource and (v as ItemResource).id == "good_boys_collar":
			collar_count += 1
	var equipped_collar := _inventory.equipped.get("necklace", null) as ItemResource
	if equipped_collar != null and equipped_collar.id == "good_boys_collar":
		collar_count += 1

	if collar_count == _dog_companions.size():
		return

	_sync_dogs(collar_count)
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_dogs.rpc(collar_count)


func _sync_dogs(count: int) -> void:
	while _dog_companions.size() > count:
		var d: GoodBoyCompanion = _dog_companions.pop_back()
		if is_instance_valid(d):
			d.queue_free()
	while _dog_companions.size() < count:
		var slot   := _dog_companions.size()
		var packed := load(_DOG_SCENE) as PackedScene
		if packed == null:
			break
		var d: GoodBoyCompanion = packed.instantiate()
		d.init(self, slot, count)
		get_tree().current_scene.add_child(d)
		_dog_companions.append(d)


@rpc("authority", "reliable")
func _rpc_sync_dogs(count: int) -> void:
	_sync_dogs(count)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _tick_timers(delta: float) -> void:
	if _attack_cooldown  > 0.0: _attack_cooldown  -= delta
	if _offhand_cooldown > 0.0: _offhand_cooldown -= delta
	if _dodge_cooldown   > 0.0: _dodge_cooldown   -= delta
	if _iframes_timer    > 0.0: _iframes_timer    -= delta


func _shake_camera(strength: float, duration: float = 0.3) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	_shake_strength = strength
	_shake_duration = duration
	_shake_timer    = duration


func _update_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		return
	_shake_timer -= delta
	var t   := _shake_timer / _shake_duration
	var cam := $Camera2D
	cam.offset = Vector2(
		randf_range(-_shake_strength, _shake_strength),
		randf_range(-_shake_strength, _shake_strength)
	) * t
	if _shake_timer <= 0.0:
		cam.offset = Vector2.ZERO


func _vec_to_dir(v: Vector2) -> String:
	# Snap a direction vector to the nearest of 8 compass names
	var angle := fposmod(v.angle() + TAU, TAU)
	var idx    := int(round(angle / (TAU / 8.0))) % 8
	return _DIR_NAMES[idx]
