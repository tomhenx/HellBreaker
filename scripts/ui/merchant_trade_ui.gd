class_name MerchantTradeUI
extends CanvasLayer

signal closed

const STOCK_PATH := "res://data/shop/merchant_stock.json"
const SLOT_SIZE  := 52
const COLS       := 4

const RARITY_COLORS := {
	"common":    Color("#B0B0B0"),
	"uncommon":  Color("#44CC55"),
	"rare":      Color("#4499FF"),
	"epic":      Color("#CC55FF"),
	"legendary": Color("#FF9900"),
	"relic":     Color("#FF4444"),
}

var _player: PlayerController

var _stock: Array = []  # Array of { item_id, price, item }

var _merchant_slots: Array = []  # Array of { inner, icon, idx }
var _player_slots:   Array = []  # Array of { inner, icon, idx }
var _player_wraps:   Array = []

var _coin_label: Label
var _backdrop:   ColorRect
var _drag_ghost: Control = null

enum DragFrom { NONE, MERCHANT, PLAYER }
var _drag_from: DragFrom      = DragFrom.NONE
var _drag_idx:  int           = -1
var _drag_item: ItemResource  = null

var _card:        PanelContainer = null
var _card_style:  StyleBoxFlat   = null
var _card_icon:   TextureRect    = null
var _card_name:   Label          = null
var _card_rarity: Label          = null
var _card_desc:   Label          = null
var _card_sep2:   HSeparator     = null
var _card_stats:  RichTextLabel  = null
var _card_price:  Label          = null

var _buy_sfx:  AudioStreamPlayer
var _sell_sfx: AudioStreamPlayer

var _search_text: String = ""
var _search_edit: LineEdit = null


func init(player: PlayerController) -> void:
	_player = player


func _ready() -> void:
	layer = 25
	add_to_group("blocks_player_input")
	_load_stock()
	_build_sfx()
	_build_ui()
	_refresh()
	if is_instance_valid(_player):
		_player.coins_changed.connect(_on_coins_changed)
		_update_coin_label(_player.coins)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_ghost != null:
			_drag_ghost.global_position = get_viewport().get_mouse_position() \
				- Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		if is_instance_valid(_card) and _card.visible:
			_position_card()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_ghost != null:
			_finish_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


# ── Data ──────────────────────────────────────────────────────────────────────

func _load_stock() -> void:
	var f := FileAccess.open(STOCK_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for entry: Variant in ((parsed as Dictionary).get("stock", []) as Array):
		var d := entry as Dictionary
		var item_id: String = d.get("item_id", "")
		var price: int      = int(d.get("price",   1))
		var item: ItemResource = ItemResource.from_id(item_id)
		if item != null:
			_stock.append({item_id = item_id, price = price, item = item})


func _build_sfx() -> void:
	_buy_sfx = AudioStreamPlayer.new()
	add_child(_buy_sfx)
	var s := load("res://assets/audio/sfx/shop_buy.mp3") as AudioStream
	if s:
		_buy_sfx.stream    = s
		_buy_sfx.volume_db = -3.0

	_sell_sfx = AudioStreamPlayer.new()
	add_child(_sell_sfx)
	var s2 := load("res://assets/audio/sfx/shop_sell.mp3") as AudioStream
	if s2:
		_sell_sfx.stream    = s2
		_sell_sfx.volume_db = -3.0


# ── UI Build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color        = Color(0, 0, 0, 0.60)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if _drag_ghost == null:
				_close())
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	var ps := _make_box(Color("#13000EF8"), Color("#882266"), 2, 6)
	ps.shadow_color = Color(0, 0, 0, 0.8)
	ps.shadow_size  = 20
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_title(root)
	_add_hsep(root)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	root.add_child(content)
	_build_merchant_panel(content)
	_add_vsep(content)
	_build_player_panel(content)

	_add_hsep(root)
	_build_coin_bar(root)

	_build_tooltip_card()

	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)


func _build_title(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)

	var title := Label.new()
	title.text = "MERCHANT SHOP"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color",         Color("#FF3399"))
	title.add_theme_color_override("font_outline_color", Color("#1A0000"))
	title.add_theme_constant_override("outline_size", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color",         Color("#FF6644"))
	close_btn.add_theme_color_override("font_hover_color",   Color("#FFFFFF"))
	close_btn.add_theme_color_override("font_pressed_color", Color("#FF2200"))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		close_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close_btn.pressed.connect(_close)
	bar.add_child(close_btn)


func _build_merchant_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)
	vbox.add_child(_section_label("SHOP  ·  drag or right-click to buy"))

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text     = "🔍 search items..."
	_search_edit.custom_minimum_size  = Vector2(COLS * (SLOT_SIZE + 5), 30)
	_search_edit.clear_button_enabled = true
	_search_edit.add_theme_font_size_override("font_size", 12)
	_search_edit.add_theme_color_override("font_color",             Color("#FFD0A0"))
	_search_edit.add_theme_color_override("font_placeholder_color", Color("#664444"))
	_search_edit.add_theme_color_override("caret_color",            Color("#FF6633"))
	var se_style := StyleBoxFlat.new()
	se_style.bg_color     = Color("#1A0010")
	se_style.border_color = Color("#661133")
	se_style.set_border_width_all(1)
	se_style.set_corner_radius_all(3)
	se_style.content_margin_left  = 6.0
	se_style.content_margin_right = 6.0
	_search_edit.add_theme_stylebox_override("normal", se_style)
	_search_edit.add_theme_stylebox_override("focus",  se_style)
	_search_edit.text_changed.connect(_on_search_changed)
	vbox.add_child(_search_edit)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size       = Vector2(COLS * (SLOT_SIZE + 5) + 12, 260)
	scroll.horizontal_scroll_mode    = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode      = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)

	for i in _stock.size():
		var sd := _create_slot(SLOT_SIZE, "")
		grid.add_child(sd["wrap"])
		_merchant_slots.append({inner = sd["inner"], icon = sd["icon"], idx = i, wrap = sd["wrap"]})
		sd["inner"].gui_input.connect(_on_merchant_slot_pressed.bind(i))
		sd["inner"].mouse_entered.connect(_show_merchant_tip.bind(i))
		sd["inner"].mouse_exited.connect(_hide_tip)


func _build_player_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)
	vbox.add_child(_section_label("BACKPACK  ·  drag or right-click to sell"))

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(grid)

	var total := Inventory.SLOT_COUNT + Inventory.MAX_BONUS_SLOTS
	for i in total:
		var sd := _create_slot(SLOT_SIZE, "")
		grid.add_child(sd["wrap"])
		_player_slots.append({inner = sd["inner"], icon = sd["icon"], idx = i})
		_player_wraps.append(sd["wrap"])
		sd["inner"].gui_input.connect(_on_player_slot_pressed.bind(i))
		sd["inner"].mouse_entered.connect(_show_player_tip.bind(i))
		sd["inner"].mouse_exited.connect(_hide_tip)
		if i >= Inventory.SLOT_COUNT:
			sd["wrap"].visible = false


func _build_coin_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bar)

	var coin_tex := load("res://assets/sprites/ui/coin.png") as Texture2D
	if coin_tex != null:
		var coin_icon := TextureRect.new()
		coin_icon.texture             = coin_tex
		coin_icon.custom_minimum_size = Vector2(24, 24)
		coin_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin_icon.texture_filter      = CanvasItem.TEXTURE_FILTER_NEAREST
		coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		bar.add_child(coin_icon)

	_coin_label = Label.new()
	_coin_label.text = "Gold:  0"
	_coin_label.add_theme_font_size_override("font_size", 16)
	_coin_label.add_theme_color_override("font_color",         Color("#FFD700"))
	_coin_label.add_theme_color_override("font_outline_color", Color("#000000"))
	_coin_label.add_theme_constant_override("outline_size", 2)
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_coin_label)


# ── Drag & Drop ───────────────────────────────────────────────────────────────

func _on_merchant_slot_pressed(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	get_viewport().set_input_as_handled()
	if idx >= _stock.size():
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: instant buy into first free backpack slot
		_hide_tip()
		_drag_idx = idx
		var free_slot := _find_free_player_slot()
		if free_slot >= 0:
			_do_buy(free_slot)
		_drag_idx = -1
		_refresh()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		var item: ItemResource = _stock[idx]["item"]
		_hide_tip()
		_drag_from = DragFrom.MERCHANT
		_drag_idx  = idx
		_drag_item = item
		_drag_ghost = _make_drag_ghost(item)
		_drag_ghost.global_position = get_viewport().get_mouse_position() \
			- Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		_backdrop.add_child(_drag_ghost)
		_refresh()


func _on_player_slot_pressed(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	get_viewport().set_input_as_handled()
	if not is_instance_valid(_player):
		return
	if idx >= _player._inventory.slot_count():
		return
	var item := _player._inventory.items[idx] as ItemResource
	if item == null:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: instant sell
		_hide_tip()
		_drag_idx = idx
		_do_sell(idx)
		_drag_idx = -1
		_refresh()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_hide_tip()
		_drag_from = DragFrom.PLAYER
		_drag_idx  = idx
		_drag_item = item
		_drag_ghost = _make_drag_ghost(item)
		_drag_ghost.global_position = get_viewport().get_mouse_position() \
			- Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		_backdrop.add_child(_drag_ghost)
		_refresh()


func _finish_drag() -> void:
	if _drag_ghost == null:
		return
	var ghost := _drag_ghost
	_drag_ghost = null
	ghost.queue_free()

	var gpos := get_viewport().get_mouse_position()
	var target_inv_idx := _find_player_slot_at(gpos)
	var over_merchant  := _is_over_merchant(gpos)

	match _drag_from:
		DragFrom.MERCHANT:
			if target_inv_idx >= 0:
				_do_buy(target_inv_idx)
		DragFrom.PLAYER:
			if over_merchant:
				_do_sell(_drag_idx)

	_drag_from = DragFrom.NONE
	_drag_idx  = -1
	_drag_item = null
	_refresh()


func _do_buy(inv_slot: int) -> void:
	if not is_instance_valid(_player):
		return
	if _drag_idx < 0 or _drag_idx >= _stock.size():
		return
	var price: int = _stock[_drag_idx]["price"]
	if _player.coins < price:
		return
	var item: ItemResource = ItemResource.from_id(_stock[_drag_idx]["item_id"])
	if item == null:
		return
	if inv_slot >= _player._inventory.slot_count():
		return
	if _player._inventory.items[inv_slot] != null:
		return  # slot occupied
	_player._inventory.items[inv_slot] = item
	_player._inventory.inventory_changed.emit()
	_player.spend_coins(price)
	if is_instance_valid(_buy_sfx) and _buy_sfx.stream != null:
		_buy_sfx.play()


func _do_sell(inv_slot: int) -> void:
	if not is_instance_valid(_player):
		return
	var item := _player._inventory.items[inv_slot] as ItemResource
	if item == null:
		return
	var sell_price := _sell_price(item)
	_player._inventory.remove_item(inv_slot)
	_player.add_coins(sell_price)
	if is_instance_valid(_sell_sfx) and _sell_sfx.stream != null:
		_sell_sfx.play()


func _sell_price(item: ItemResource) -> int:
	match item.rarity:
		"common":    return 5
		"uncommon":  return 15
		"rare":      return 30
		"epic":      return 75
		"legendary": return 200
		"relic":     return 500
		_:           return 3


func _find_free_player_slot() -> int:
	if not is_instance_valid(_player):
		return -1
	var limit := _player._inventory.slot_count()
	for i in limit:
		if _player._inventory.items[i] == null:
			return i
	return -1


func _find_player_slot_at(gpos: Vector2) -> int:
	for sd: Dictionary in _player_slots:
		var inner: Panel = sd["inner"]
		var idx: int     = sd["idx"]
		if is_instance_valid(inner) and inner.get_global_rect().has_point(gpos):
			if is_instance_valid(_player) and idx < _player._inventory.slot_count():
				return idx
	return -1


func _is_over_merchant(gpos: Vector2) -> bool:
	for sd: Dictionary in _merchant_slots:
		var inner: Panel = sd["inner"]
		var wrap: Control = sd["wrap"]
		if is_instance_valid(inner) and wrap.visible and inner.get_global_rect().has_point(gpos):
			return true
	return false


# ── Tooltip ───────────────────────────────────────────────────────────────────

func _show_merchant_tip(idx: int) -> void:
	if idx >= _stock.size():
		return
	var entry: Dictionary = _stock[idx]
	_set_tip(entry["item"] as ItemResource, entry["price"] as int, false)


func _show_player_tip(idx: int) -> void:
	if not is_instance_valid(_player) or idx >= _player._inventory.slot_count():
		return
	var item := _player._inventory.items[idx] as ItemResource
	if item != null:
		_set_tip(item, _sell_price(item), true)
	else:
		_hide_tip()


func _set_tip(item: ItemResource, price: int, is_sell: bool) -> void:
	if not is_instance_valid(_card) or item == null:
		_hide_tip()
		return
	var rarity_col: Color = RARITY_COLORS.get(item.rarity, RARITY_COLORS["common"])
	_card_style.border_color = rarity_col
	_card_icon.texture = item.icon
	_card_name.text    = item.item_name
	_card_name.add_theme_color_override("font_color", rarity_col)
	_card_rarity.text  = "  %s" % item.rarity.to_upper()
	_card_rarity.add_theme_color_override("font_color", rarity_col.darkened(0.15))
	_card_desc.text    = item.description

	# Build extras block — weapon stats + stat bonuses + passive effects
	var extras := ""
	var p_stats: StatsResource = _player.stats if is_instance_valid(_player) else null

	if item.item_type == "weapon" and not item.weapon_id.is_empty():
		var w := WeaponResource.from_id(item.weapon_id)
		if w != null:
			var base_dmg  := p_stats.damage       if p_stats != null else 25.0
			var base_asp  := p_stats.attack_speed if p_stats != null else 1.0
			var base_crit := p_stats.crit_chance  if p_stats != null else 0.05
			var dmg  := floori(base_dmg * w.damage_multiplier)
			var asp  := snappedf(base_asp * w.attack_speed_multiplier, 0.01)
			var rng  := int(w.range)
			var crit := int(base_crit * 100)
			extras += "[color=#555555]DMG[/color] [color=#FFCC44]%d[/color]   [color=#555555]SPD[/color] [color=#FFCC44]%.2f[/color]\n" % [dmg, asp]
			extras += "[color=#555555]RNG[/color] [color=#FFCC44]%d[/color]   [color=#555555]CRIT[/color] [color=#FFCC44]%d%%[/color]\n" % [rng, crit]

	for key: String in item.stat_bonuses:
		var val: float = float(item.stat_bonuses[key])
		var sign_str := "+" if val >= 0.0 else ""
		extras += "[color=#44FF99]%s%s %s[/color]\n" % [sign_str, _fmt_bonus(key, val), key.capitalize()]

	for fx: Dictionary in item.passive_effects:
		match fx.get("type", ""):
			"hp_regen":
				var amt: float = float(fx.get("amount", 1))
				var ivl: float = float(fx.get("interval", 5))
				var amt_s := "%d" % int(amt) if amt == floorf(amt) else "%.1f" % amt
				var ivl_s := "%d" % int(ivl) if ivl == floorf(ivl) else "%.1f" % ivl
				extras += "[color=#FF6655]♥[/color] [color=#44FF99]+%s HP / %ss[/color]\n" % [amt_s, ivl_s]
			"dog_companion":
				extras += "[color=#88CCFF]Companion dog hunts nearby enemies[/color]\n"
	if not item.passive_effects.is_empty():
		var src := "while equipped" if not item.equip_slot.is_empty() else "from inventory"
		extras += "[color=#443333]— Active %s —[/color]\n" % src

	var has_extras := not extras.is_empty()
	_card_sep2.visible  = has_extras
	_card_stats.visible = has_extras
	if has_extras:
		_card_stats.clear()
		_card_stats.append_text(extras.strip_edges())

	_card_price.text = "  %s  %d gold" % ["Sell:" if is_sell else "Buy:", price]
	_card_price.add_theme_color_override("font_color",
		Color("#AAFFAA") if is_sell else Color("#FFD700"))
	_card.visible = true
	_card.reset_size()
	_position_card()


func _fmt_bonus(key: String, val: float) -> String:
	match key:
		"crit_chance":     return "%d%%" % int(val * 100)
		"crit_multiplier": return "%.1fx" % val
		_: return "%d" % int(val) if val == floorf(val) else "%.2f" % val


func _hide_tip() -> void:
	if is_instance_valid(_card):
		_card.visible = false


func _position_card() -> void:
	var mpos    := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
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


func _build_tooltip_card() -> void:
	_card = PanelContainer.new()
	_card.visible             = false
	_card.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(200, 0)
	_card.z_index             = 100

	_card_style = _make_box(Color("#0C0010F4"), Color("#B0B0B0"), 2, 5)
	_card_style.shadow_color = Color(0, 0, 0, 0.80)
	_card_style.shadow_size  = 10
	_card.add_theme_stylebox_override("panel", _card_style)
	_backdrop.add_child(_card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   8)
	m.add_theme_constant_override("margin_right",  8)
	m.add_theme_constant_override("margin_top",    6)
	m.add_theme_constant_override("margin_bottom", 6)
	_card.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	m.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_card_icon = TextureRect.new()
	_card_icon.custom_minimum_size = Vector2(36, 36)
	_card_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_card_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_icon.texture_filter      = CanvasItem.TEXTURE_FILTER_NEAREST
	_card_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_card_icon)

	var name_col := VBoxContainer.new()
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
	_card_rarity.add_theme_color_override("font_color", Color("#888888"))
	_card_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_card_rarity)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color("#333333"))
	vbox.add_child(sep)

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

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("color", Color("#333333"))
	vbox.add_child(sep3)

	_card_price = Label.new()
	_card_price.add_theme_font_size_override("font_size", 12)
	_card_price.add_theme_color_override("font_color",         Color("#FFD700"))
	_card_price.add_theme_color_override("font_outline_color", Color("#000000"))
	_card_price.add_theme_constant_override("outline_size", 1)
	_card_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_price)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _item_matches_search(item: ItemResource) -> bool:
	if _search_text.is_empty():
		return true
	var q := _search_text.to_lower()
	return item.item_name.to_lower().contains(q) \
		or item.item_type.to_lower().contains(q) \
		or item.rarity.to_lower().contains(q)


func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges()
	_refresh()


func _refresh() -> void:
	for sd: Dictionary in _merchant_slots:
		var idx: int          = sd["idx"]
		var inner: Panel      = sd["inner"]
		var icon: TextureRect = sd["icon"]
		var wrap: Control     = sd["wrap"]
		var is_dragging := _drag_from == DragFrom.MERCHANT and _drag_idx == idx
		if idx < _stock.size():
			var item: ItemResource = _stock[idx]["item"]
			var visible := _item_matches_search(item)
			wrap.visible = visible
			if visible and not is_dragging:
				_update_slot(inner, icon, item, false)
			else:
				_update_slot(inner, icon, null, false)
		else:
			wrap.visible = false
			_update_slot(inner, icon, null, false)

	if not is_instance_valid(_player):
		return
	var active := _player._inventory.slot_count()
	for i in _player_slots.size():
		var sd: Dictionary    = _player_slots[i]
		var idx: int          = sd["idx"]
		var inner: Panel      = sd["inner"]
		var icon: TextureRect = sd["icon"]
		_player_wraps[i].visible = idx < active
		if idx < active:
			var item := _player._inventory.items[idx] as ItemResource
			var is_dragging := _drag_from == DragFrom.PLAYER and _drag_idx == idx
			_update_slot(inner, icon, null if is_dragging else item, false)


func _update_slot(inner: Panel, icon: TextureRect, item: ItemResource, selected: bool) -> void:
	inner.add_theme_stylebox_override("panel", _slot_style(item != null, selected))
	icon.texture = item.icon if item != null else null
	icon.visible = item != null


func _update_coin_label(amount: int) -> void:
	if is_instance_valid(_coin_label):
		_coin_label.text = "Gold:  %d" % amount


func _on_coins_changed(amount: int) -> void:
	_update_coin_label(amount)


# ── Close ─────────────────────────────────────────────────────────────────────

func close() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


# ── Style helpers ─────────────────────────────────────────────────────────────

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
	icon.offset_left   =  6
	icon.offset_top    =  6
	icon.offset_right  = -6
	icon.offset_bottom = -6
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.add_child(icon)
	return c


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
	icon.offset_left   =  6
	icon.offset_top    =  6
	icon.offset_right  = -6
	icon.offset_bottom = -6
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
		s.bg_color     = Color("#4A1530")
		s.border_color = Color("#FF88CC")
		s.set_border_width_all(2)
	elif has_item:
		s.bg_color     = Color("#2B0820")
		s.border_color = Color("#882266")
		s.set_border_width_all(1)
	else:
		s.bg_color     = Color("#160410")
		s.border_color = Color("#441133")
		s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size  = 4
	return s


func _make_box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color",         Color("#BB5599"))
	lbl.add_theme_color_override("font_outline_color", Color("#000000"))
	lbl.add_theme_constant_override("outline_size", 1)
	return lbl


func _add_hsep(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color("#4A0828"))
	parent.add_child(sep)


func _add_vsep(parent: HBoxContainer) -> void:
	var sep := VSeparator.new()
	sep.add_theme_color_override("color", Color("#4A0828"))
	parent.add_child(sep)
