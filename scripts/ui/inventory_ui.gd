class_name InventoryUI
extends Control

const SLOT_SIZE  := 52
const EQUIP_SIZE := 54

const EQUIP_LAYOUT := [
	[0, 1, "head",     "HEAD"],
	[1, 0, "offhand",  "OFF"],
	[1, 1, "necklace", "NECK"],
	[1, 2, "weapon",   "WEAPON"],
	[2, 0, "ring1",    "RING"],
	[2, 1, "chest",    "CHEST"],
	[2, 2, "ring2",    "RING"],
	[3, 1, "legs",     "LEGS"],
	[4, 0, "hands",    "GLOVES"],
	[4, 2, "feet",     "BOOTS"],
]

const RARITY_COLORS := {
	"common":    Color("#B0B0B0"),
	"uncommon":  Color("#44CC55"),
	"rare":      Color("#4499FF"),
	"epic":      Color("#CC55FF"),
	"legendary": Color("#FF9900"),
	"set":       Color("#00DD88"),
	"relic":     Color("#FF4444"),  # base; animated in _animate_relic_color
}

const STAT_ROWS := [
	["MAX HP",   "max_hp",         "int"],
	["ARMOR",    "armor",          "int"],
	["SPEED",    "move_speed",     "int"],
	["DAMAGE",   "damage",         "int"],
	["ATK SPD",  "attack_speed",   "float2"],
	["CRIT",     "crit_chance",    "pct"],
	["CRIT x",   "crit_multiplier","float1x"],
	["DODGE",    "dodge_speed",    "int"],
]

signal drop_requested(item: ItemResource)

var _inventory: Inventory
var _stats: StatsResource = null

var _inv_panels:   Array      = []
var _inv_icons:    Array      = []
var _inv_wraps:    Array      = []
var _equip_panels: Dictionary = {}
var _equip_icons:  Dictionary = {}

# Floating tooltip card
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

# Stats panel value labels keyed by stat name
var _stat_value_labels: Dictionary = {}

# Player reference for live stat reads (avoids stale StatsResource after _recalculate_stats)
var _player: PlayerController = null

# Relic animated icon overlays: Panel → AnimatedSprite2D
var _relic_anim_sprites: Dictionary = {}

# Drag state
var _all_slots:   Array      = []
var _drag_source: Dictionary = {}
var _drag_ghost:  Control    = null


func init(inv: Inventory, player_stats: StatsResource = null, player: PlayerController = null) -> void:
	_inventory = inv
	_stats = player_stats
	_player = player
	_inventory.inventory_changed.connect(_refresh)
	_inventory.equipment_changed.connect(func(_s: String): _refresh())


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if _inventory != null:
		_refresh()
	_refresh_stats_panel()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_ghost != null:
			_drag_ghost.global_position = get_global_mouse_position() - Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		if is_instance_valid(_card) and _card.visible:
			_position_card()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_ghost != null:
			_finish_drag()
			accept_event()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if _drag_ghost == null:
				queue_free())
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -380
	panel.offset_right  =  380
	panel.offset_top    = -245
	panel.offset_bottom =  245
	var ps := _make_box(Color("#13000EF8"), Color("#881400"), 2, 6)
	ps.shadow_color = Color(0, 0, 0, 0.75)
	ps.shadow_size  = 22
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_titlebar(root)
	_add_hsep(root)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	root.add_child(content)

	_build_equip_panel(content)
	_add_vsep(content)
	_build_inv_panel(content)
	_add_vsep(content)
	_build_stats_panel(content)

	_build_tooltip_card()


func _build_titlebar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color",         Color("#FF3300"))
	title.add_theme_color_override("font_outline_color", Color("#1A0000"))
	title.add_theme_constant_override("outline_size", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_color_override("font_color",         Color("#FF6644"))
	close.add_theme_color_override("font_hover_color",   Color("#FFFFFF"))
	close.add_theme_color_override("font_pressed_color", Color("#FF2200"))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close.pressed.connect(queue_free)
	bar.add_child(close)


func _add_hsep(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color("#4A0800"))
	parent.add_child(sep)


func _add_vsep(parent: HBoxContainer) -> void:
	var sep := VSeparator.new()
	sep.add_theme_color_override("color", Color("#4A0800"))
	parent.add_child(sep)


func _build_equip_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)
	vbox.add_child(_section_label("EQUIPMENT"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(grid)

	var layout_map: Dictionary = {}
	for entry: Array in EQUIP_LAYOUT:
		layout_map[Vector2i(entry[0], entry[1])] = entry

	for row in range(5):
		for col in range(3):
			var key := Vector2i(row, col)
			if layout_map.has(key):
				var entry: Array     = layout_map[key]
				var slot_id: String  = entry[2]
				var slot_lbl: String = entry[3]
				var sd := _create_slot(EQUIP_SIZE, slot_lbl)
				grid.add_child(sd["wrap"])
				_equip_panels[slot_id] = sd["inner"]
				_equip_icons[slot_id]  = sd["icon"]
				_all_slots.append({panel = sd["inner"], type = "equip", ref = slot_id})
				sd["inner"].gui_input.connect(_on_slot_pressed.bind("equip", slot_id))
				sd["inner"].mouse_entered.connect(_show_equip_tip.bind(slot_id))
				sd["inner"].mouse_exited.connect(_hide_tip)
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(EQUIP_SIZE, EQUIP_SIZE + 16)
				grid.add_child(spacer)


func _build_inv_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)
	vbox.add_child(_section_label("BACKPACK"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(grid)

	var total := Inventory.SLOT_COUNT + Inventory.MAX_BONUS_SLOTS
	for i in total:
		var sd := _create_slot(SLOT_SIZE, "")
		grid.add_child(sd["wrap"])
		_inv_panels.append(sd["inner"])
		_inv_icons.append(sd["icon"])
		_inv_wraps.append(sd["wrap"])
		_all_slots.append({panel = sd["inner"], type = "inv", ref = i})
		sd["inner"].gui_input.connect(_on_slot_pressed.bind("inv", i))
		sd["inner"].mouse_entered.connect(_show_inv_tip.bind(i))
		sd["inner"].mouse_exited.connect(_hide_tip)
		# Bonus slots start hidden; shown when earned via equipment
		if i >= Inventory.SLOT_COUNT:
			sd["wrap"].visible = false


func _build_stats_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vbox)
	vbox.add_child(_section_label("STATS"))

	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer_top)

	for row_def: Array in STAT_ROWS:
		var stat_name: String = row_def[0]
		var row := _build_stat_row(stat_name)
		vbox.add_child(row)

	var spacer_mid := Control.new()
	spacer_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer_mid)


func _build_stat_row(stat_name: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0)
	bg.set_border_width_all(0)
	pc.add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   4)
	margin.add_theme_constant_override("margin_right",  4)
	margin.add_theme_constant_override("margin_top",    3)
	margin.add_theme_constant_override("margin_bottom", 3)
	pc.add_child(margin)

	var hbox := HBoxContainer.new()
	margin.add_child(hbox)

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


func _refresh_stats_panel() -> void:
	# Always read from _player.stats when available — _stats can be stale
	# after _recalculate_stats() replaces the stats object on the player.
	var cur_stats: StatsResource = _player.stats if is_instance_valid(_player) else _stats
	if cur_stats == null or _stat_value_labels.is_empty():
		return

	var main_w: WeaponResource = _player.current_weapon  if is_instance_valid(_player) else null
	var off_w:  WeaponResource = _player.current_offhand if is_instance_valid(_player) else null

	for row_def: Array in STAT_ROWS:
		var stat_name: String = row_def[0]
		var prop_name: String = row_def[1]
		var fmt: String       = row_def[2]
		var lbl: Label        = _stat_value_labels.get(stat_name, null)
		if not is_instance_valid(lbl):
			continue

		match stat_name:
			"DAMAGE":
				var base_dmg: float = cur_stats.damage
				var m_mult  := main_w.damage_multiplier       if main_w != null else 1.0
				var main_dmg := floori(base_dmg * m_mult)
				if off_w != null:
					var off_dmg := floori(base_dmg * off_w.damage_multiplier * 0.5)
					lbl.text = "%d (%d)" % [main_dmg, off_dmg]
				else:
					lbl.text = "%d" % main_dmg
			"ATK SPD":
				var base_asp: float = cur_stats.attack_speed
				var m_mult := main_w.attack_speed_multiplier if main_w != null else 1.0
				var main_asp := snappedf(base_asp * m_mult, 0.01)
				if off_w != null:
					var off_asp := snappedf(base_asp * off_w.attack_speed_multiplier * 0.5, 0.01)
					lbl.text = "%.2f (%.2f)" % [main_asp, off_asp]
				else:
					lbl.text = "%.2f" % main_asp
			_:
				var raw: Variant = cur_stats.get(prop_name)
				if raw == null:
					lbl.text = "—"
					continue
				match fmt:
					"int":     lbl.text = "%d" % int(float(raw))
					"float2":  lbl.text = "%.2f" % float(raw)
					"float1x": lbl.text = "%.1fx" % float(raw)
					"pct":     lbl.text = "%d%%" % int(float(raw) * 100.0)
					_:         lbl.text = str(raw)


func _build_tooltip_card() -> void:
	_card = PanelContainer.new()
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(210, 0)
	_card.z_index = 100

	_card_style = _make_box(Color("#0C0008F4"), Color("#B0B0B0"), 2, 5)
	_card_style.shadow_color = Color(0, 0, 0, 0.80)
	_card_style.shadow_size  = 10
	_card.add_theme_stylebox_override("panel", _card_style)
	add_child(_card)

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
	_card_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_card_stats.custom_minimum_size = Vector2(0, 0)
	_card_stats.visible             = false
	_card_stats.add_theme_font_size_override("normal_font_size", 11)
	_card_stats.add_theme_color_override("default_color", Color("#CCCCCC"))
	_card_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_stats)


func _create_slot(size: int, slot_label: String) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)

	var inner := Panel.new()
	inner.custom_minimum_size = Vector2(size, size)
	inner.mouse_filter = Control.MOUSE_FILTER_STOP
	inner.add_theme_stylebox_override("panel", _slot_style(false, false))

	var icon := TextureRect.new()
	icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6;  icon.offset_top    =  6
	icon.offset_right = -6; icon.offset_bottom = -6
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


# ── Drag & Drop ───────────────────────────────────────────────────────────────

func _on_slot_pressed(event: InputEvent, slot_type: String, slot_ref) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
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
	_drag_ghost.global_position = get_global_mouse_position() - Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
	add_child(_drag_ghost)
	_refresh()


func _make_drag_ghost(item: ItemResource) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 50

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = Color(1.0, 1.0, 1.0, 0.80)
	bg.add_theme_stylebox_override("panel", _slot_style(true, true))
	c.add_child(bg)

	var icon := TextureRect.new()
	icon.texture      = item.icon
	icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6; icon.offset_top = 6
	icon.offset_right = -6; icon.offset_bottom = -6
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.add_child(icon)
	return c


func _finish_drag() -> void:
	if _drag_ghost == null:
		return
	var ghost := _drag_ghost
	_drag_ghost = null
	ghost.queue_free()

	var target := _find_slot_at(get_global_mouse_position())
	if target.is_empty():
		# Dropped outside all slots — eject to world
		var src_item := _drag_source.get("item") as ItemResource
		if src_item != null:
			_eject_from_source(_drag_source)
			drop_requested.emit(src_item)
	else:
		_apply_drop(_drag_source, target)
	_drag_source = {}
	_refresh()


func _eject_from_source(src: Dictionary) -> void:
	match src.get("type", ""):
		"inv":
			_inventory.remove_item(src["ref"] as int)
		"equip":
			var slot: String = src["ref"] as String
			_inventory.equipped[slot] = null
			_inventory.equipment_changed.emit(slot)
			_inventory.inventory_changed.emit()


func _find_slot_at(gpos: Vector2) -> Dictionary:
	for sd: Dictionary in _all_slots:
		var p: Panel = sd["panel"]
		if is_instance_valid(p) and p.get_global_rect().has_point(gpos):
			return sd
	return {}


func _apply_drop(from: Dictionary, to: Dictionary) -> void:
	if from.is_empty() or to.is_empty():
		return
	var ft: String = from["type"]
	var tt: String = to["type"]
	var fr         = from["ref"]
	var tr         = to["ref"]

	if ft == "inv" and tt == "inv":
		if fr != tr:
			_inventory.swap_inv(fr as int, tr as int)
	elif ft == "inv" and tt == "equip":
		var item: ItemResource = from["item"]
		if _inventory.can_equip(item, tr as String):
			_inventory.equip_from_inv(fr as int, tr as String)
	elif ft == "equip" and tt == "inv":
		_inventory.move_equip_to_inv(fr as String, tr as int)
	elif ft == "equip" and tt == "equip":
		if fr != tr:
			_inventory.swap_equip(fr as String, tr as String)


# ── Floating Tooltip Card ─────────────────────────────────────────────────────

func _show_inv_tip(idx: int) -> void:
	_set_tip(_inventory.items[idx] as ItemResource)

func _show_equip_tip(slot_id: String) -> void:
	_set_tip(_inventory.equipped.get(slot_id, null) as ItemResource)

func _set_tip(item: ItemResource) -> void:
	if not is_instance_valid(_card):
		return

	# Stop relic animation whenever a new item (or no item) is shown
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null

	if item == null:
		_card.visible = false
		return

	var rarity_col: Color = RARITY_COLORS.get(item.rarity, RARITY_COLORS["common"])

	_card_style.border_color = rarity_col
	_card_sep1.add_theme_color_override("color", rarity_col.darkened(0.3))
	_card_icon.texture = item.icon
	_card_name.text    = item.item_name
	_card_name.add_theme_color_override("font_color", rarity_col)
	_card_rarity.text  = "  %s" % item.rarity.to_upper()
	_card_rarity.add_theme_color_override("font_color", rarity_col.darkened(0.15))

	var has_desc := not item.description.is_empty()
	_card_desc.text    = item.description
	_card_desc.visible = has_desc

	# Build the extras block (weapon stats + bonuses + passives)
	var extras := ""

	if item.item_type == "weapon" and not item.weapon_id.is_empty():
		var w := WeaponResource.from_id(item.weapon_id)
		if w != null:
			var base_dmg  := _stats.damage       if _stats != null else 25.0
			var base_asp  := _stats.attack_speed if _stats != null else 1.0
			var base_crit := _stats.crit_chance  if _stats != null else 0.05
			var dmg  := floori(base_dmg * w.damage_multiplier)
			var asp  := snappedf(base_asp * w.attack_speed_multiplier, 0.01)
			var rng  := int(w.range)
			var crit := int(base_crit * 100)
			extras += "[color=#555555]DMG[/color] [color=#FFCC44]%d[/color]   [color=#555555]SPD[/color] [color=#FFCC44]%.2f[/color]\n" % [dmg, asp]
			extras += "[color=#555555]RNG[/color] [color=#FFCC44]%d[/color]   [color=#555555]CRIT[/color] [color=#FFCC44]%d%%[/color]\n" % [rng, crit]

	for key: String in item.stat_bonuses:
		var val: float = float(item.stat_bonuses[key])
		var sign_str := "+" if val >= 0.0 else ""
		extras += "[color=#44FF99]%s%s %s[/color]\n" % [sign_str, _format_bonus(key, val), key.capitalize()]

	var has_passives := false
	for fx: Dictionary in item.passive_effects:
		has_passives = true
		match fx.get("type", ""):
			"hp_regen":
				var amt: float = float(fx.get("amount", 1))
				var ivl: float = float(fx.get("interval", 5))
				var amt_s := "%d" % int(amt) if amt == floorf(amt) else "%.1f" % amt
				var ivl_s := "%d" % int(ivl) if ivl == floorf(ivl) else "%.1f" % ivl
				extras += "[color=#FF6655]♥[/color] [color=#44FF99]+%s HP / %ss[/color]\n" % [amt_s, ivl_s]
			"dog_companion":
				extras += "[color=#88CCFF]Companion dog hunts nearby enemies[/color]\n"
	if has_passives:
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
		_animate_relic_color()


func _animate_relic_color() -> void:
	_relic_tween = create_tween().set_loops()
	_relic_tween.tween_method(_apply_relic_hue, 0.0, 1.0, 1.8)


func _apply_relic_hue(t: float) -> void:
	var c := Color.from_hsv(t, 0.90, 1.0)
	if is_instance_valid(_card_name):
		_card_name.add_theme_color_override("font_color", c)
	if is_instance_valid(_card_rarity):
		_card_rarity.add_theme_color_override("font_color", c.darkened(0.12))
	if _card_style != null:
		_card_style.border_color = c


func _hide_tip() -> void:
	if is_instance_valid(_relic_tween):
		_relic_tween.kill()
		_relic_tween = null
	if is_instance_valid(_card):
		_card.visible = false


func _position_card() -> void:
	var mpos    := get_viewport().get_mouse_position()
	var vp_size := get_viewport_rect().size
	var cs      := _card.size
	var x := mpos.x + 18.0
	var y := mpos.y - 10.0
	if x + cs.x > vp_size.x - 4.0:
		x = mpos.x - cs.x - 10.0
	if y + cs.y > vp_size.y - 4.0:
		y = vp_size.y - cs.y - 4.0
	if y < 4.0:
		y = 4.0
	_card.global_position = Vector2(x, y)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _inventory == null:
		return
	var drag_type: String = _drag_source.get("type", "")
	var drag_ref          = _drag_source.get("ref", null)
	var active: int       = _inventory.slot_count()

	for i in _inv_panels.size():
		_inv_wraps[i].visible = i < active
		if i < active:
			var item := _inventory.items[i] as ItemResource
			var dragging: bool = drag_type == "inv" and drag_ref == i
			_update_slot(_inv_panels[i], _inv_icons[i], null if dragging else item, false)

	for slot_id: String in _equip_panels:
		var item := _inventory.equipped.get(slot_id, null) as ItemResource
		var dragging: bool = drag_type == "equip" and drag_ref == slot_id
		_update_slot(_equip_panels[slot_id], _equip_icons[slot_id], null if dragging else item, false)

	_refresh_stats_panel()


func _update_slot(inner: Panel, icon: TextureRect, item: ItemResource, selected: bool) -> void:
	inner.add_theme_stylebox_override("panel", _slot_style(item != null, selected))
	icon.texture = item.icon if item != null else null
	icon.visible = item != null
	_sync_relic_effect(inner, item)


func _sync_relic_effect(inner: Panel, item: ItemResource) -> void:
	var existing: AnimatedSprite2D = _relic_anim_sprites.get(inner, null)
	var has_anim := item != null and item.rarity == "relic" and _relic_has_frames(item.id)
	if has_anim and not is_instance_valid(existing):
		var anim := _create_relic_anim(inner, item.id)
		if anim != null:
			_relic_anim_sprites[inner] = anim
	elif not has_anim and is_instance_valid(existing):
		existing.queue_free()
		_relic_anim_sprites.erase(inner)


func _relic_has_frames(item_id: String) -> bool:
	return ResourceLoader.exists("res://assets/sprites/items/%s/frame_0.png" % item_id)


func _create_relic_anim(parent: Panel, item_id: String) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	sf.add_animation("fire")
	sf.set_animation_speed("fire", 10.0)
	sf.set_animation_loop("fire", true)
	var n := 0
	while true:
		var path := "res://assets/sprites/items/%s/frame_%d.png" % [item_id, n]
		if not ResourceLoader.exists(path):
			break
		var tex := load(path) as Texture2D
		if tex == null:
			break
		sf.add_frame("fire", tex)
		n += 1
	if n == 0:
		return null

	var anim := AnimatedSprite2D.new()
	anim.sprite_frames  = sf
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.z_index        = 2
	# AnimatedSprite2D positions from its center — place at slot centre
	var sz := parent.custom_minimum_size
	anim.position = Vector2(sz.x * 0.5, sz.y * 0.5)
	# Scale sprite to fill the icon area (icon area = slot - 12 px padding, source = 48 px)
	var icon_px := sz.x - 12.0
	anim.scale = Vector2.ONE * (icon_px / 48.0)
	anim.play("fire")
	parent.add_child(anim)
	return anim


# ── Style helpers ─────────────────────────────────────────────────────────────

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


func _make_box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


func _format_bonus(key: String, val: float) -> String:
	match key:
		"crit_chance":     return "%d%%" % int(val * 100)
		"crit_multiplier": return "%.1fx" % val
		_:                 return "%d" % int(val) if val == floorf(val) else "%.2f" % val


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color",         Color("#BB5533"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 1)
	return lbl
