class_name LevelUpScreen
extends CanvasLayer

const SLOT_SIZE  := 44
const EQUIP_SIZE := 46

const EQUIP_LAYOUT := [
	[0, 1, "head",     "HEAD"],
	[1, 0, "offhand",  "OFF"],
	[1, 1, "necklace", "NECK"],
	[1, 2, "weapon",   "WPN"],
	[2, 0, "ring1",    "RING"],
	[2, 1, "chest",    "CHEST"],
	[2, 2, "ring2",    "RING"],
	[3, 1, "legs",     "LEGS"],
	[4, 0, "hands",    "GLOVE"],
	[4, 2, "feet",     "BOOTS"],
]

const STAT_ROWS := [
	["MAX HP",  "max_hp",          "int"],
	["ARMOR",   "armor",           "int"],
	["SPEED",   "move_speed",      "int"],
	["DAMAGE",  "damage",          "int"],
	["ATK SPD", "attack_speed",    "float2"],
	["CRIT",    "crit_chance",     "pct"],
	["CRIT x",  "crit_multiplier", "float1x"],
	["DODGE",   "dodge_speed",     "int"],
]

const RARITY_COLORS := {
	"common":    Color("#B0B0B0"),
	"uncommon":  Color("#44CC55"),
	"rare":      Color("#4499FF"),
	"epic":      Color("#CC55FF"),
	"legendary": Color("#FF9900"),
	"relic":     Color("#FF4444"),
}

const _LEVEL_UP_SFX := "res://assets/audio/sfx/level_up.mp3"

var _rewards:       Array[Dictionary] = []
var _local_peer:    int               = 1
var _server_ctrl:   PlayerController  = null
var _local_player:  PlayerController  = null
var _local_claimed: bool              = false
var _inventory:     Inventory         = null
var _stats:         StatsResource     = null

var _waiting_label: Label             = null
var _ready_btn:     Button            = null
var _sfx:           AudioStreamPlayer = null

# Reward slots
var _reward_panels: Array = []   # Panel[]
var _reward_icons:  Array = []   # TextureRect[]
var _reward_items:  Array = []   # ItemResource or null

# Inventory slots
var _inv_panels:        Array      = []
var _inv_icons:         Array      = []
var _inv_wraps:         Array      = []
var _equip_panels:      Dictionary = {}
var _equip_icons:       Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _all_inv_slots:     Array      = []

# Tooltip — child of _ui_root so it renders above the panel
var _card:        PanelContainer = null
var _card_style:  StyleBoxFlat   = null
var _card_icon:   TextureRect    = null
var _card_name:   Label          = null
var _card_rarity: Label          = null
var _card_sep1:   HSeparator     = null
var _card_desc:   Label          = null
var _card_sep2:   HSeparator     = null
var _card_stats:  RichTextLabel  = null
var _relic_tween: Tween          = null

# Drag
var _drag_source:         Dictionary = {}
var _drag_ghost:          Control    = null
var _relic_anim_sprites:  Dictionary = {}

var _ui_root: Control = null


func init(level: int, rewards: Array[Dictionary], local_player: PlayerController,
		server_ctrl: PlayerController) -> void:
	_rewards      = rewards
	_local_player = local_player
	_server_ctrl  = server_ctrl
	_local_peer   = local_player.get_multiplayer_authority() \
					if multiplayer.has_multiplayer_peer() else 1
	_inventory    = local_player._inventory if is_instance_valid(local_player) else null
	_stats        = local_player.stats      if is_instance_valid(local_player) else null
	_build_ui(level)
	_play_level_up_sfx()
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh_inventory)
		_inventory.equipment_changed.connect(func(_s: String): _refresh_inventory())


func _play_level_up_sfx() -> void:
	_sfx = AudioStreamPlayer.new()
	var stream := load(_LEVEL_UP_SFX) as AudioStream
	if stream:
		_sfx.stream    = stream
		_sfx.volume_db = 0.0
		add_child(_sfx)
		_sfx.play()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_ghost != null:
			_drag_ghost.global_position = get_viewport().get_mouse_position() \
				- Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		if is_instance_valid(_card) and _card.visible:
			_position_card()
	elif event is InputEventMouseButton \
			and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_ghost != null:
			_finish_drag()
			get_viewport().set_input_as_handled()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui(level: int) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 10

	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_ui_root)

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_ui_root.add_child(center)

	var panel := PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.08, 0.06, 0.10)
	ps.border_color = Color("#FFD700")
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.shadow_color = Color(0, 0, 0, 0.75)
	ps.shadow_size  = 18
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text                 = "⚡   LEVEL UP!  —  Level %d   ⚡" % level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#FFD700"))
	vbox.add_child(title)
	vbox.add_child(_hsep(Color("#FFD70055")))

	vbox.add_child(_build_rewards_row())
	vbox.add_child(_hsep(Color("#4A0800")))

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	vbox.add_child(content)

	_build_equip_section(content)
	content.add_child(_vsep())
	_build_backpack_section(content)
	content.add_child(_vsep())
	_build_stats_section(content)

	vbox.add_child(_hsep(Color("#4A0800")))
	vbox.add_child(_build_bottom_bar())

	_build_tooltip_card()
	_refresh_inventory()
	_refresh_stats_panel()


func _build_rewards_row() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 5)

	var hdr_row := HBoxContainer.new()
	hdr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hdr_row.add_theme_constant_override("separation", 8)
	wrap.add_child(hdr_row)

	var hdr := Label.new()
	hdr.text = "CHOOSE A REWARD"
	hdr.add_theme_color_override("font_color", Color("#FFD700"))
	hdr.add_theme_font_size_override("font_size", 13)
	hdr_row.add_child(hdr)

	var sub := Label.new()
	sub.text = "— click to take, hover to preview"
	sub.add_theme_color_override("font_color", Color("#555555"))
	sub.add_theme_font_size_override("font_size", 10)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hdr_row.add_child(sub)

	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 8)
	wrap.add_child(slots_row)

	for i in _rewards.size():
		var rd: Dictionary  = _rewards[i]
		var item            := ItemResource.from_id(rd.get("item_id", ""))
		_reward_items.append(item)

		var sd     := _create_slot(SLOT_SIZE, "")
		var inner: Panel       = sd["inner"]
		var icon:  TextureRect = sd["icon"]
		slots_row.add_child(sd["wrap"])

		var rarity_col: Color = RARITY_COLORS.get(item.rarity if item else "common", Color.WHITE) as Color
		var sty := StyleBoxFlat.new()
		sty.bg_color     = Color(0.12, 0.09, 0.16)
		sty.border_color = rarity_col
		sty.set_border_width_all(2)
		sty.set_corner_radius_all(3)
		sty.shadow_color = Color(0, 0, 0, 0.5)
		sty.shadow_size  = 4
		inner.add_theme_stylebox_override("panel", sty)

		if item and item.icon:
			icon.texture = item.icon

		if int(rd.get("claimed_by", -1)) != -1:
			inner.modulate = Color(0.45, 0.45, 0.45)

		inner.gui_input.connect(_on_reward_pressed.bind(i))
		inner.mouse_entered.connect(_show_reward_tip.bind(i))
		inner.mouse_exited.connect(_hide_tip)

		_reward_panels.append(inner)
		_reward_icons.append(icon)

	return wrap


func _build_equip_section(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	vbox.add_child(_section_label("EQUIPPED"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	var lmap: Dictionary = {}
	for e: Array in EQUIP_LAYOUT:
		lmap[Vector2i(e[0], e[1])] = e

	for row in range(5):
		for col in range(3):
			var k := Vector2i(row, col)
			if lmap.has(k):
				var e:       Array  = lmap[k]
				var slot_id: String = e[2]
				var lbl_str: String = e[3]
				var sd := _create_slot(EQUIP_SIZE, lbl_str)
				grid.add_child(sd["wrap"])
				_equip_panels[slot_id] = sd["inner"]
				_equip_icons[slot_id]  = sd["icon"]
				_all_inv_slots.append({panel = sd["inner"], type = "equip", ref = slot_id})
				sd["inner"].gui_input.connect(_on_inv_slot_pressed.bind("equip", slot_id))
				sd["inner"].mouse_entered.connect(_show_equip_tip.bind(slot_id))
				sd["inner"].mouse_exited.connect(_hide_tip)
			else:
				var sp := Control.new()
				sp.custom_minimum_size = Vector2(EQUIP_SIZE, EQUIP_SIZE + 15)
				grid.add_child(sp)


func _build_backpack_section(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	parent.add_child(vbox)
	vbox.add_child(_section_label("BACKPACK"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	var total := Inventory.SLOT_COUNT + Inventory.MAX_BONUS_SLOTS
	for i in total:
		var sd := _create_slot(SLOT_SIZE, "")
		grid.add_child(sd["wrap"])
		_inv_panels.append(sd["inner"])
		_inv_icons.append(sd["icon"])
		_inv_wraps.append(sd["wrap"])
		_all_inv_slots.append({panel = sd["inner"], type = "inv", ref = i})
		sd["inner"].gui_input.connect(_on_inv_slot_pressed.bind("inv", i))
		sd["inner"].mouse_entered.connect(_show_inv_tip.bind(i))
		sd["inner"].mouse_exited.connect(_hide_tip)
		if i >= Inventory.SLOT_COUNT:
			sd["wrap"].visible = false


func _build_stats_section(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	parent.add_child(vbox)
	vbox.add_child(_section_label("STATS"))

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(pad)

	for rd: Array in STAT_ROWS:
		vbox.add_child(_build_stat_row(rd[0]))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(filler)


func _build_stat_row(stat_name: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   4)
	m.add_theme_constant_override("margin_right",  4)
	m.add_theme_constant_override("margin_top",    3)
	m.add_theme_constant_override("margin_bottom", 3)
	pc.add_child(m)

	var hbox := HBoxContainer.new()
	m.add_child(hbox)

	var lbl := Label.new()
	lbl.text = stat_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#664433"))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = "—"
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color",         Color("#FFCC44"))
	val.add_theme_color_override("font_outline_color", Color("#000000"))
	val.add_theme_constant_override("outline_size", 1)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(val)

	_stat_value_labels[stat_name] = val
	return pc


func _build_bottom_bar() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	_waiting_label = Label.new()
	_waiting_label.text                  = "Press READY when you're done"
	_waiting_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_color_override("font_color", Color("#AAAAAA"))
	hbox.add_child(_waiting_label)

	_ready_btn = Button.new()
	_ready_btn.text                = "READY"
	_ready_btn.custom_minimum_size = Vector2(120, 36)
	_ready_btn.add_theme_font_size_override("font_size", 15)
	_ready_btn.pressed.connect(_on_ready_pressed)
	hbox.add_child(_ready_btn)

	return hbox


# ── Slot factory ──────────────────────────────────────────────────────────────

func _create_slot(size: int, slot_label: String) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)

	var inner := Panel.new()
	inner.custom_minimum_size = Vector2(size, size)
	inner.mouse_filter = Control.MOUSE_FILTER_STOP
	inner.add_theme_stylebox_override("panel", _slot_style(false, false))

	var icon := TextureRect.new()
	icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left   =  5;  icon.offset_top    =  5
	icon.offset_right  = -5;  icon.offset_bottom = -5
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inner.add_child(icon)

	wrap.add_child(inner)

	if not slot_label.is_empty():
		var lbl := Label.new()
		lbl.text = slot_label
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color("#664433"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size  = Vector2(size, 13)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(lbl)

	return {wrap = wrap, inner = inner, icon = icon}


func _slot_style(has_item: bool, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color     = Color("#4A1500")
		s.border_color = Color("#FFBB00")
		s.set_border_width_all(2)
	elif has_item:
		s.bg_color     = Color("#2B0D00")
		s.border_color = Color("#6B2800")
		s.set_border_width_all(1)
	else:
		s.bg_color     = Color("#160400")
		s.border_color = Color("#380900")
		s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size  = 4
	return s


# ── Reward interaction ─────────────────────────────────────────────────────────

func _on_reward_pressed(event: InputEvent, slot_idx: int) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if _local_claimed:
		return
	var rd: Dictionary = _rewards[slot_idx]
	if int(rd.get("claimed_by", -1)) != -1:
		return
	if not multiplayer.has_multiplayer_peer():
		if is_instance_valid(_server_ctrl):
			_server_ctrl._process_claim(_local_peer, slot_idx)
	else:
		_server_ctrl.rpc_claim_level_reward.rpc_id(1, slot_idx)


func _show_reward_tip(idx: int) -> void:
	_set_tip(_reward_items[idx] as ItemResource if idx < _reward_items.size() else null)


# ── Inventory drag & drop ─────────────────────────────────────────────────────

func _on_inv_slot_pressed(event: InputEvent, slot_type: String, slot_ref: Variant) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if _inventory == null:
		return
	get_viewport().set_input_as_handled()

	var item: ItemResource
	if slot_type == "inv":
		item = _inventory.items[slot_ref as int] as ItemResource
	else:
		item = _inventory.equipped.get(slot_ref, null) as ItemResource
	if item == null:
		return

	_hide_tip()
	_drag_source = {type = slot_type, ref = slot_ref, item = item}
	_drag_ghost  = _make_drag_ghost(item)
	_drag_ghost.global_position = get_viewport().get_mouse_position() \
		- Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
	_ui_root.add_child(_drag_ghost)
	_refresh_inventory()


func _make_drag_ghost(item: ItemResource) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 200

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = Color(1, 1, 1, 0.82)
	bg.add_theme_stylebox_override("panel", _slot_style(true, true))
	c.add_child(bg)

	var icon := TextureRect.new()
	icon.texture      = item.icon
	icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left   =  5;  icon.offset_top    =  5
	icon.offset_right  = -5;  icon.offset_bottom = -5
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.add_child(icon)
	return c


func _finish_drag() -> void:
	var ghost := _drag_ghost
	_drag_ghost = null
	ghost.queue_free()

	var target := _find_slot_at(get_viewport().get_mouse_position())
	if target.is_empty():
		_eject_from_source(_drag_source)
	else:
		_apply_drop(_drag_source, target)
	_drag_source = {}
	_refresh_inventory()


func _eject_from_source(src: Dictionary) -> void:
	if _inventory == null:
		return
	match src.get("type", ""):
		"inv":
			_inventory.remove_item(src["ref"] as int)
		"equip":
			var s: String = src["ref"] as String
			_inventory.equipped[s] = null
			_inventory.equipment_changed.emit(s)
			_inventory.inventory_changed.emit()


func _find_slot_at(gpos: Vector2) -> Dictionary:
	for sd: Dictionary in _all_inv_slots:
		var p: Panel = sd["panel"]
		if is_instance_valid(p) and p.get_global_rect().has_point(gpos):
			return sd
	return {}


func _apply_drop(from: Dictionary, to: Dictionary) -> void:
	if from.is_empty() or to.is_empty() or _inventory == null:
		return
	var ft: String = from["type"]
	var tt: String = to["type"]
	var fr: Variant = from["ref"]
	var tr: Variant = to["ref"]

	if ft == "inv" and tt == "inv":
		if fr != tr:
			_inventory.swap_inv(fr as int, tr as int)
	elif ft == "inv" and tt == "equip":
		if _inventory.can_equip(from["item"] as ItemResource, tr as String):
			_inventory.equip_from_inv(fr as int, tr as String)
	elif ft == "equip" and tt == "inv":
		_inventory.move_equip_to_inv(fr as String, tr as int)
	elif ft == "equip" and tt == "equip":
		if fr != tr:
			_inventory.swap_equip(fr as String, tr as String)


# ── Tooltip ────────────────────────────────────────────────────────────────────

func _build_tooltip_card() -> void:
	_card = PanelContainer.new()
	_card.visible    = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(200, 0)
	_card.z_index    = 150

	_card_style = _make_box(Color("#0C0008F4"), Color("#B0B0B0"), 2, 5)
	_card_style.shadow_color = Color(0, 0, 0, 0.80)
	_card_style.shadow_size  = 10
	_card.add_theme_stylebox_override("panel", _card_style)
	_ui_root.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_card_icon = TextureRect.new()
	_card_icon.custom_minimum_size = Vector2(38, 38)
	_card_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card_icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_card_icon)

	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 2)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	hbox.add_child(name_col)

	_card_name = Label.new()
	_card_name.add_theme_font_size_override("font_size", 13)
	_card_name.add_theme_color_override("font_color",         Color("#B0B0B0"))
	_card_name.add_theme_color_override("font_outline_color", Color("#000000"))
	_card_name.add_theme_constant_override("outline_size", 2)
	_card_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_card_name.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_card_name)

	_card_rarity = Label.new()
	_card_rarity.add_theme_font_size_override("font_size", 10)
	_card_rarity.add_theme_color_override("font_color", Color("#B0B0B0"))
	_card_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_card_rarity)

	_card_sep1 = HSeparator.new()
	_card_sep1.add_theme_color_override("color", Color("#444444"))
	vbox.add_child(_card_sep1)

	_card_desc = Label.new()
	_card_desc.add_theme_font_size_override("font_size", 11)
	_card_desc.add_theme_color_override("font_color", Color("#888888"))
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_card_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_desc)

	_card_sep2 = HSeparator.new()
	_card_sep2.add_theme_color_override("color", Color("#2A2A2A"))
	_card_sep2.visible = false
	vbox.add_child(_card_sep2)

	_card_stats = RichTextLabel.new()
	_card_stats.bbcode_enabled      = true
	_card_stats.fit_content         = true
	_card_stats.scroll_active       = false
	_card_stats.visible             = false
	_card_stats.add_theme_font_size_override("normal_font_size", 11)
	_card_stats.add_theme_color_override("default_color", Color("#CCCCCC"))
	_card_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_stats)


func _show_inv_tip(idx: int) -> void:
	_set_tip(_inventory.items[idx] as ItemResource if _inventory else null)

func _show_equip_tip(slot_id: String) -> void:
	_set_tip(_inventory.equipped.get(slot_id, null) as ItemResource if _inventory else null)

func _set_tip(item: ItemResource) -> void:
	if not is_instance_valid(_card):
		return
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null
	if item == null:
		_card.visible = false
		return

	var rc: Color = RARITY_COLORS.get(item.rarity, RARITY_COLORS["common"])

	_card_style.border_color = rc
	_card_sep1.add_theme_color_override("color", rc.darkened(0.3))
	_card_icon.texture = item.icon
	_card_name.text    = item.item_name
	_card_name.add_theme_color_override("font_color", rc)
	_card_rarity.text  = "  %s" % item.rarity.to_upper()
	_card_rarity.add_theme_color_override("font_color", rc.darkened(0.15))

	var has_desc := not item.description.is_empty()
	_card_desc.text    = item.description
	_card_desc.visible = has_desc

	var extras := ""

	if item.item_type == "weapon" and not item.weapon_id.is_empty():
		var w := WeaponResource.from_id(item.weapon_id)
		if w != null:
			var bd := _stats.damage       if _stats != null else 25.0
			var ba := _stats.attack_speed if _stats != null else 1.0
			var bc := _stats.crit_chance  if _stats != null else 0.05
			extras += "[color=#555555]DMG[/color] [color=#FFCC44]%d[/color]   [color=#555555]SPD[/color] [color=#FFCC44]%.2f[/color]\n" \
				% [floori(bd * w.damage_multiplier), snappedf(ba * w.attack_speed_multiplier, 0.01)]
			extras += "[color=#555555]RNG[/color] [color=#FFCC44]%d[/color]   [color=#555555]CRIT[/color] [color=#FFCC44]%d%%[/color]\n" \
				% [int(w.range), int(bc * 100)]

	for key: String in item.stat_bonuses:
		var v: float = float(item.stat_bonuses[key])
		extras += "[color=#44FF99]%s%s %s[/color]\n" \
			% ["+" if v >= 0.0 else "", _fmt_bonus(key, v), key.capitalize()]

	var has_pass := false
	for fx: Dictionary in item.passive_effects:
		has_pass = true
		if fx.get("type", "") == "hp_regen":
			var amt := float(fx.get("amount", 1))
			var ivl := float(fx.get("interval", 5))
			extras += "[color=#FF6655]♥[/color] [color=#44FF99]+%s HP / %ss[/color]\n" \
				% [("%d" % int(amt)) if amt == floorf(amt) else ("%.1f" % amt),
				   ("%d" % int(ivl)) if ivl == floorf(ivl) else ("%.1f" % ivl)]
		elif fx.get("type", "") == "dog_companion":
			extras += "[color=#88CCFF]Companion dog hunts nearby enemies[/color]\n"
	if has_pass:
		extras += "[color=#443333]— Active while in inventory —[/color]\n"

	var has_extras := not extras.is_empty()
	_card_sep1.visible  = has_desc or has_extras
	_card_sep2.visible  = has_desc and has_extras
	_card_stats.visible = has_extras
	_card_stats.clear()
	if has_extras:
		_card_stats.append_text(extras.strip_edges())

	_card.visible = true
	_card.reset_size()
	_position_card()

	if item.rarity == "relic":
		_relic_tween = create_tween().set_loops()
		_relic_tween.tween_method(_apply_relic_hue, 0.0, 1.0, 1.8)


func _apply_relic_hue(t: float) -> void:
	var c := Color.from_hsv(t, 0.90, 1.0)
	if is_instance_valid(_card_name):   _card_name.add_theme_color_override("font_color", c)
	if is_instance_valid(_card_rarity): _card_rarity.add_theme_color_override("font_color", c.darkened(0.12))
	if _card_style != null:             _card_style.border_color = c


func _hide_tip() -> void:
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null
	if is_instance_valid(_card):
		_card.visible = false


func _position_card() -> void:
	var mp  := get_viewport().get_mouse_position()
	var vp  := get_viewport().get_visible_rect().size
	var cs  := _card.size
	var x   := mp.x + 18.0
	var y   := mp.y - 10.0
	if x + cs.x > vp.x - 4.0: x = mp.x - cs.x - 10.0
	if y + cs.y > vp.y - 4.0: y = vp.y - cs.y - 4.0
	if y < 4.0: y = 4.0
	_card.global_position = Vector2(x, y)


# ── Refresh ────────────────────────────────────────────────────────────────────

func _refresh_inventory() -> void:
	if _inventory == null:
		return
	var dt: String = _drag_source.get("type", "")
	var dr: Variant = _drag_source.get("ref", null)
	var active     := _inventory.slot_count()

	for i in _inv_panels.size():
		_inv_wraps[i].visible = i < active
		if i < active:
			var item := _inventory.items[i] as ItemResource
			_update_slot(_inv_panels[i], _inv_icons[i], null if (dt == "inv" and dr == i) else item, false)

	for sid: String in _equip_panels:
		var item := _inventory.equipped.get(sid, null) as ItemResource
		_update_slot(_equip_panels[sid], _equip_icons[sid],
			null if (dt == "equip" and dr == sid) else item, false)

	_refresh_stats_panel()


func _update_slot(inner: Panel, icon: TextureRect, item: ItemResource, selected: bool) -> void:
	inner.add_theme_stylebox_override("panel", _slot_style(item != null, selected))
	icon.texture = item.icon if item != null else null
	icon.visible = item != null
	_sync_relic_effect(inner, item)


func _sync_relic_effect(inner: Panel, item: ItemResource) -> void:
	var existing: AnimatedSprite2D = _relic_anim_sprites.get(inner, null)
	var want := item != null and item.rarity == "relic" \
		and ResourceLoader.exists("res://assets/sprites/items/%s/frame_0.png" % item.id)
	if want and not is_instance_valid(existing):
		var anim := _create_relic_anim(inner, item.id)
		if anim != null:
			_relic_anim_sprites[inner] = anim
	elif not want and is_instance_valid(existing):
		existing.queue_free()
		_relic_anim_sprites.erase(inner)


func _create_relic_anim(parent: Panel, item_id: String) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	sf.add_animation("fire")
	sf.set_animation_speed("fire", 10.0)
	sf.set_animation_loop("fire", true)
	var n := 0
	while true:
		var path := "res://assets/sprites/items/%s/frame_%d.png" % [item_id, n]
		if not ResourceLoader.exists(path): break
		var tex := load(path) as Texture2D
		if tex == null: break
		sf.add_frame("fire", tex)
		n += 1
	if n == 0:
		return null
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames  = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.z_index        = 2
	var sz := parent.custom_minimum_size
	anim.position = Vector2(sz.x * 0.5, sz.y * 0.5)
	anim.scale    = Vector2.ONE * ((sz.x - 10.0) / 48.0)
	anim.play("fire")
	parent.add_child(anim)
	return anim


func _refresh_stats_panel() -> void:
	var s: StatsResource = _local_player.stats if is_instance_valid(_local_player) else _stats
	if s == null or _stat_value_labels.is_empty():
		return
	var mw: WeaponResource = _local_player.current_weapon  if is_instance_valid(_local_player) else null
	var ow: WeaponResource = _local_player.current_offhand if is_instance_valid(_local_player) else null

	for rd: Array in STAT_ROWS:
		var sn: String = rd[0]
		var pn: String = rd[1]
		var fmt: String = rd[2]
		var lbl: Label = _stat_value_labels.get(sn, null)
		if not is_instance_valid(lbl):
			continue
		match sn:
			"DAMAGE":
				var bd: float = s.damage
				var md := floori(bd * (mw.damage_multiplier if mw else 1.0))
				lbl.text = "%d (%d)" % [md, floori(bd * ow.damage_multiplier * 0.5)] \
					if ow != null else "%d" % md
			"ATK SPD":
				var ba: float = s.attack_speed
				var ma := snappedf(ba * (mw.attack_speed_multiplier if mw else 1.0), 0.01)
				lbl.text = "%.2f (%.2f)" % [ma, snappedf(ba * ow.attack_speed_multiplier * 0.5, 0.01)] \
					if ow != null else "%.2f" % ma
			_:
				var raw: Variant = s.get(pn)
				if raw == null: lbl.text = "—"; continue
				match fmt:
					"int":     lbl.text = "%d"   % int(float(raw))
					"float2":  lbl.text = "%.2f" % float(raw)
					"float1x": lbl.text = "%.1fx" % float(raw)
					"pct":     lbl.text = "%d%%"  % int(float(raw) * 100.0)
					_:         lbl.text = str(raw)


# ── Network callbacks ──────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	_ready_btn.disabled = true
	_ready_btn.text     = "WAITING..."
	if not multiplayer.has_multiplayer_peer():
		if is_instance_valid(_server_ctrl):
			_server_ctrl._process_ready(_local_peer)
	else:
		_server_ctrl.rpc_level_up_ready.rpc_id(1)


func update_reward(slot_idx: int, claimer_peer: int) -> void:
	_rewards[slot_idx]["claimed_by"] = claimer_peer
	if claimer_peer == _local_peer:
		_local_claimed = true
	if slot_idx < _reward_panels.size() and is_instance_valid(_reward_panels[slot_idx]):
		(_reward_panels[slot_idx] as Panel).modulate = Color(0.45, 0.45, 0.45)


func set_ready_state(ready_peers: Array, total: int) -> void:
	var count := ready_peers.size()
	_waiting_label.text = "All players ready!" \
		if count >= total else "Waiting: %d / %d ready" % [count, total]
	if _local_peer in ready_peers and is_instance_valid(_ready_btn):
		_ready_btn.text     = "READY ✓"
		_ready_btn.disabled = true


# ── Style helpers ─────────────────────────────────────────────────────────────

func _hsep(col: Color) -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_color_override("color", col)
	return s

func _vsep() -> VSeparator:
	var s := VSeparator.new()
	s.add_theme_color_override("color", Color("#4A0800"))
	return s

func _make_box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color",         Color("#BB5533"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 1)
	return lbl

func _fmt_bonus(key: String, val: float) -> String:
	match key:
		"crit_chance":     return "%d%%" % int(val * 100)
		"crit_multiplier": return "%.1fx" % val
		_: return "%d" % int(val) if val == floorf(val) else "%.2f" % val
