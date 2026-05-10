class_name WorldItem
extends Area2D

const PICKUP_RANGE  := 72.0
const FLOAT_AMP     := 3.5
const FLOAT_SPEED   := 1.8

var item: ItemResource = null

var _float_t:   float = 0.0
var _is_hovered: bool = false

# Built nodes
var _sprite:     Sprite2D       = null
var _shadow:     Sprite2D       = null
var _tip_layer:  CanvasLayer    = null
var _tip_card:   PanelContainer = null
var _tip_style:  StyleBoxFlat   = null
var _tip_icon:   TextureRect    = null
var _tip_name:   Label          = null
var _tip_rarity: Label          = null
var _tip_sep1:   HSeparator     = null
var _tip_desc:   Label          = null
var _tip_sep2:   HSeparator     = null
var _tip_stats:  RichTextLabel  = null
var _relic_tween: Tween         = null
var _claimed:     bool          = false

const RARITY_COLORS := {
	"common":    Color("#B0B0B0"),
	"uncommon":  Color("#44CC55"),
	"rare":      Color("#4499FF"),
	"epic":      Color("#CC55FF"),
	"legendary": Color("#FF9900"),
	"set":       Color("#00DD88"),
	"relic":     Color("#FF4444"),
}


func setup(i: ItemResource) -> void:
	item    = i
	_float_t = randf() * TAU  # random start phase so items don't all bob in sync


func _ready() -> void:
	add_to_group("world_items")
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_build_visuals()
	_build_tooltip()

	if item != null:
		_apply_item_visuals()


func _build_visuals() -> void:
	_shadow = Sprite2D.new()
	_shadow.z_index      = -1
	_shadow.scale        = Vector2(1.0, 0.38)
	_shadow.position     = Vector2(0.0, 12.0)
	_shadow.modulate     = Color(0.0, 0.0, 0.0, 0.45)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.z_index       = 0
	_sprite.scale         = Vector2(0.88, 0.88)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _apply_item_visuals() -> void:
	if item == null:
		return
	if is_instance_valid(_sprite):
		_sprite.texture = item.icon
	if is_instance_valid(_shadow):
		_shadow.texture = item.icon


# ── Update loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_float_t += delta * FLOAT_SPEED
	var s := sin(_float_t)

	if is_instance_valid(_sprite):
		_sprite.position.y = s * FLOAT_AMP

	if is_instance_valid(_shadow):
		_shadow.modulate.a = remap(s, -1.0, 1.0, 0.25, 0.5)
		_shadow.scale.x    = remap(s, -1.0, 1.0, 0.85, 1.1)

	if _is_hovered and is_instance_valid(_tip_card) and _tip_card.visible:
		_position_tooltip()


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed
			and not (event as InputEventKey).echo
			and (event as InputEventKey).keycode == KEY_E):
		return
	var player := _local_player()
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > PICKUP_RANGE:
		return
	# Only the closest WorldItem responds so a single E press picks one item
	for node: Node in get_tree().get_nodes_in_group("world_items"):
		if node == self:
			continue
		var other_dist: float = (node as Node2D).global_position.distance_to(player.global_position)
		if other_dist < dist:
			return
	_do_pickup(player)
	get_viewport().set_input_as_handled()


func _input_event(_vp: Viewport, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var player := _local_player()
		if player == null:
			return
		if global_position.distance_to(player.global_position) > PICKUP_RANGE:
			_flash_out_of_range()
			return
		_do_pickup(player)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_show_tooltip()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_hide_tooltip()


# ── Pickup ────────────────────────────────────────────────────────────────────

func _do_pickup(player: PlayerController) -> void:
	if item == null or not is_instance_valid(player):
		return
	if not multiplayer.has_multiplayer_peer():
		if player._inventory.add_item(item):
			queue_free()
		else:
			_flash_out_of_range()
		return
	if multiplayer.is_server():
		if _claimed:
			return
		_claimed = true
		if player._inventory.add_item(item):
			_despawn.rpc()
		else:
			_claimed = false
			_flash_out_of_range()
	else:
		_request_remove.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_remove() -> void:
	if not multiplayer.is_server() or _claimed:
		return
	_claimed = true
	var sender := multiplayer.get_remote_sender_id()
	_confirm_pickup.rpc_id(sender, item.id)
	_despawn.rpc()


@rpc("authority", "reliable")
func _confirm_pickup(item_id: String) -> void:
	var player := _local_player()
	if player == null:
		return
	var itm := ItemResource.from_id(item_id)
	if itm != null:
		player._inventory.add_item(itm)


@rpc("authority", "reliable", "call_local")
func _despawn() -> void:
	queue_free()


func _flash_out_of_range() -> void:
	if not is_instance_valid(_sprite):
		return
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color(1.6, 0.3, 0.3), 0.07)
	tw.tween_property(_sprite, "modulate", Color.WHITE,           0.18)


func _local_player() -> PlayerController:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var pc := node as PlayerController
		if pc == null:
			continue
		if not multiplayer.has_multiplayer_peer() or pc.is_multiplayer_authority():
			return pc
	return null


# ── Tooltip ───────────────────────────────────────────────────────────────────

func _build_tooltip() -> void:
	_tip_layer       = CanvasLayer.new()
	_tip_layer.layer = 50
	add_child(_tip_layer)

	_tip_card = PanelContainer.new()
	_tip_card.visible             = false
	_tip_card.custom_minimum_size = Vector2(210, 0)
	_tip_card.z_index             = 100
	_tip_card.mouse_filter        = Control.MOUSE_FILTER_IGNORE

	_tip_style = StyleBoxFlat.new()
	_tip_style.bg_color     = Color("#0C0008F4")
	_tip_style.border_color = Color("#B0B0B0")
	_tip_style.set_border_width_all(2)
	_tip_style.set_corner_radius_all(5)
	_tip_style.shadow_color = Color(0, 0, 0, 0.8)
	_tip_style.shadow_size  = 10
	_tip_card.add_theme_stylebox_override("panel", _tip_style)
	_tip_layer.add_child(_tip_card)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		var v := 8 if side in ["left", "right"] else 6
		margin.add_theme_constant_override("margin_" + side, v)
	_tip_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# ── header row ──
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_tip_icon = TextureRect.new()
	_tip_icon.custom_minimum_size = Vector2(38, 38)
	_tip_icon.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_tip_icon.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tip_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tip_icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_tip_icon)

	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 2)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_col)

	_tip_name = Label.new()
	_tip_name.add_theme_font_size_override("font_size", 13)
	_tip_name.add_theme_color_override("font_color",         Color("#B0B0B0"))
	_tip_name.add_theme_color_override("font_outline_color", Color("#000000"))
	_tip_name.add_theme_constant_override("outline_size", 2)
	_tip_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_name.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_tip_name)

	_tip_rarity = Label.new()
	_tip_rarity.add_theme_font_size_override("font_size", 10)
	_tip_rarity.add_theme_color_override("font_color", Color("#B0B0B0"))
	_tip_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_tip_rarity)

	# ── body ──
	_tip_sep1 = HSeparator.new()
	_tip_sep1.add_theme_color_override("color", Color("#444444"))
	vbox.add_child(_tip_sep1)

	_tip_desc = Label.new()
	_tip_desc.add_theme_font_size_override("font_size", 11)
	_tip_desc.add_theme_color_override("font_color", Color("#888888"))
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tip_desc)

	_tip_sep2 = HSeparator.new()
	_tip_sep2.add_theme_color_override("color", Color("#2A2A2A"))
	vbox.add_child(_tip_sep2)

	_tip_stats = RichTextLabel.new()
	_tip_stats.bbcode_enabled      = true
	_tip_stats.fit_content         = true
	_tip_stats.scroll_active       = false
	_tip_stats.add_theme_font_size_override("normal_font_size", 11)
	_tip_stats.add_theme_color_override("default_color", Color("#CCCCCC"))
	_tip_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tip_stats)


func _show_tooltip() -> void:
	if item == null or not is_instance_valid(_tip_card):
		return
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null

	var rc: Color = RARITY_COLORS.get(item.rarity, RARITY_COLORS["common"])
	_tip_style.border_color = rc
	_tip_sep1.add_theme_color_override("color", rc.darkened(0.3))
	_tip_icon.texture = item.icon
	_tip_name.text    = item.item_name
	_tip_name.add_theme_color_override("font_color", rc)
	_tip_rarity.text  = "  %s" % item.rarity.to_upper()
	_tip_rarity.add_theme_color_override("font_color", rc.darkened(0.15))

	var has_desc := not item.description.is_empty()
	_tip_desc.text    = item.description
	_tip_desc.visible = has_desc

	var extras := ""
	for key: String in item.stat_bonuses:
		var val: float = float(item.stat_bonuses[key])
		extras += "[color=#44FF99]%s%s %s[/color]\n" % [
			"+" if val >= 0.0 else "",
			_fmt_bonus(key, val),
			key.capitalize()
		]
	var has_passives := false
	for fx: Dictionary in item.passive_effects:
		has_passives = true
		if fx.get("type", "") == "hp_regen":
			var a: float = float(fx.get("amount", 1))
			var v: float = float(fx.get("interval", 5))
			var as_ := "%d" % int(a) if a == floorf(a) else "%.1f" % a
			var vs_ := "%d" % int(v) if v == floorf(v) else "%.1f" % v
			extras += "[color=#FF6655]♥[/color] [color=#44FF99]+%s HP / %ss[/color]\n" % [as_, vs_]
		elif fx.get("type", "") == "dog_companion":
			extras += "[color=#88CCFF]Companion dog hunts nearby enemies[/color]\n"
	if has_passives:
		extras += "[color=#443333]— Active while in inventory —[/color]\n"

	var has_extras := not extras.is_empty()
	_tip_sep1.visible  = has_desc or has_extras
	_tip_sep2.visible  = has_desc and has_extras
	_tip_stats.visible = has_extras
	_tip_stats.clear()
	if has_extras:
		_tip_stats.append_text(extras.strip_edges())

	_tip_card.visible = true
	_tip_card.reset_size()
	_position_tooltip()

	if item.rarity == "relic":
		_relic_tween = _tip_card.create_tween().set_loops()
		_relic_tween.tween_method(_apply_relic_hue, 0.0, 1.0, 1.8)


func _hide_tooltip() -> void:
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null
	if is_instance_valid(_tip_card):
		_tip_card.visible = false


func _position_tooltip() -> void:
	var mpos    := _tip_card.get_viewport().get_mouse_position()
	var vp_size := _tip_card.get_viewport_rect().size
	var cs      := _tip_card.size
	var x := mpos.x + 18.0
	var y := mpos.y - 10.0
	if x + cs.x > vp_size.x - 4.0:
		x = mpos.x - cs.x - 10.0
	if y + cs.y > vp_size.y - 4.0:
		y = vp_size.y - cs.y - 4.0
	if y < 4.0:
		y = 4.0
	_tip_card.global_position = Vector2(x, y)


func _apply_relic_hue(t: float) -> void:
	var c := Color.from_hsv(t, 0.90, 1.0)
	if is_instance_valid(_tip_name):
		_tip_name.add_theme_color_override("font_color", c)
	if is_instance_valid(_tip_rarity):
		_tip_rarity.add_theme_color_override("font_color", c.darkened(0.12))
	if _tip_style != null:
		_tip_style.border_color = c


func _fmt_bonus(key: String, val: float) -> String:
	match key:
		"crit_chance":     return "%d%%" % int(val * 100)
		"crit_multiplier": return "%.1fx" % val
		_:                 return "%d" % int(val) if val == floorf(val) else "%.2f" % val
