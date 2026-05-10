class_name AdminMenu
extends CanvasLayer

const SLOT_SIZE := 52
const ITEM_COLS := 5

const RARITY_ORDER := ["relic", "legendary", "epic", "rare", "uncommon", "common"]
const RARITY_COLORS := {
	"common":    Color("#B0B0B0"),
	"uncommon":  Color("#44CC55"),
	"rare":      Color("#4499FF"),
	"epic":      Color("#CC55FF"),
	"legendary": Color("#FF9900"),
	"relic":     Color("#FF4444"),
}

# Tier colors by base name — add entries here when new enemies need custom colors
const ENEMY_COLORS := {
	"rat":             Color("#B0B0B0"),
	"bat":             Color("#B0B0B0"),
	"slime":           Color("#44CC55"),
	"skeleton":        Color("#4499FF"),
	"imp":             Color("#4499FF"),
	"blob":            Color("#CC55FF"),
	"hellhound":       Color("#CC55FF"),
	"orc":             Color("#FF9900"),
	"lava_king_slime": Color("#FF4444"),
}

var _player:           PlayerController = null
var _all_items:        Array            = []
var _filtered_items:   Array            = []
var _all_enemies:      Array            = []
var _filtered_enemies: Array            = []

# UI refs
var _ui_root:       Control          = null
var _item_panel:    Control          = null
var _enemy_panel:   Control          = null
var _item_grid:     GridContainer    = null
var _enemy_grid:    GridContainer    = null
var _item_search:   LineEdit         = null
var _enemy_search:  LineEdit         = null
var _tab_items_btn: Button           = null
var _tab_enemy_btn: Button           = null

# Tooltip
var _card:        PanelContainer = null
var _card_style:  StyleBoxFlat   = null
var _card_icon:   TextureRect    = null
var _card_name:   Label          = null
var _card_rarity: Label          = null
var _card_desc:   Label          = null
var _card_sep:    HSeparator     = null
var _card_stats:  RichTextLabel  = null


func init(player: PlayerController) -> void:
	_player = player
	_load_all_items()
	_load_all_enemies()
	_build_ui()


func _load_all_items() -> void:
	var f := FileAccess.open("res://data/items/items.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = (parsed as Dictionary).get("items", {})
	var buckets: Dictionary = {}
	for r in RARITY_ORDER:
		buckets[r] = []
	for id: String in data.keys():
		var item := ItemResource.from_id(id)
		if item == null:
			continue
		var bucket: Array = buckets.get(item.rarity, buckets["common"])
		bucket.append(item)
	for r in RARITY_ORDER:
		var bucket: Array = buckets[r]
		bucket.sort_custom(func(a: ItemResource, b: ItemResource) -> bool:
			return a.item_name < b.item_name)
		_all_items.append_array(bucket)
	_filtered_items = _all_items.duplicate()


func _load_all_enemies() -> void:
	_all_enemies = []
	var dir := DirAccess.open("res://scenes/enemies/")
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tscn"):
			continue
		var base := file_name.get_basename()
		_all_enemies.append({
			"name":  base.capitalize(),
			"scene": "res://scenes/enemies/" + file_name,
			"color": ENEMY_COLORS.get(base, Color("#AAAAAA")) as Color,
		})
	_all_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["name"] as String) < (b["name"] as String))
	_filtered_enemies = _all_enemies.duplicate()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O or event.keycode == KEY_ESCAPE:
			queue_free()
			get_viewport().set_input_as_handled()


# ── UI Construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 50

	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_ui_root)

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.45)
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
	ps.bg_color     = Color(0.07, 0.05, 0.09)
	ps.border_color = Color("#FF4444")
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.shadow_color = Color(0, 0, 0, 0.85)
	ps.shadow_size  = 20
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "  ADMIN PANEL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#FF4444"))
	title_row.add_child(title)
	var hint := Label.new()
	hint.text = "[O] / [ESC] close"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("#554444"))
	title_row.add_child(hint)

	vbox.add_child(_hsep(Color("#FF444444")))

	# Spawn chest button
	var chest_btn := Button.new()
	chest_btn.text = "  SPAWN CHEST  (spawns loot chest nearby)"
	chest_btn.add_theme_font_size_override("font_size", 13)
	chest_btn.pressed.connect(_on_spawn_chest)
	vbox.add_child(chest_btn)

	vbox.add_child(_hsep(Color("#441111")))

	# Tab bar
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_row)

	_tab_items_btn = _make_tab_btn("ITEMS", true)
	_tab_enemy_btn = _make_tab_btn("ENEMIES", false)
	_tab_items_btn.pressed.connect(_show_tab.bind("items"))
	_tab_enemy_btn.pressed.connect(_show_tab.bind("enemies"))
	tab_row.add_child(_tab_items_btn)
	tab_row.add_child(_tab_enemy_btn)

	# Items panel
	_item_panel = _build_items_panel()
	vbox.add_child(_item_panel)

	# Enemies panel
	_enemy_panel = _build_enemies_panel()
	_enemy_panel.visible = false
	vbox.add_child(_enemy_panel)

	_build_tooltip()
	_rebuild_item_grid()
	_rebuild_enemy_grid()


func _make_tab_btn(label: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = false
	btn.add_theme_font_size_override("font_size", 12)
	_style_tab(btn, active)
	return btn


func _style_tab(btn: Button, active: bool) -> void:
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color("#3A1111") if active else Color("#1A0808")
	sty.border_color = Color("#FF4444") if active else Color("#441111")
	sty.set_border_width_all(1)
	sty.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal",   sty)
	btn.add_theme_stylebox_override("hover",    sty)
	btn.add_theme_stylebox_override("pressed",  sty)
	btn.add_theme_color_override("font_color",
		Color("#FF6666") if active else Color("#885555"))


func _show_tab(tab: String) -> void:
	_item_panel.visible  = (tab == "items")
	_enemy_panel.visible = (tab == "enemies")
	_style_tab(_tab_items_btn,  tab == "items")
	_style_tab(_tab_enemy_btn,  tab == "enemies")


func _build_items_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var hint := Label.new()
	hint.text = "Click any item to add it to your inventory"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("#664433"))
	vbox.add_child(hint)

	_item_search = LineEdit.new()
	_item_search.placeholder_text    = "Search by name, rarity, type..."
	_item_search.clear_button_enabled = true
	_item_search.add_theme_font_size_override("font_size", 12)
	_item_search.text_changed.connect(_on_item_search_changed)
	vbox.add_child(_item_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = ITEM_COLS
	_item_grid.add_theme_constant_override("h_separation", 4)
	_item_grid.add_theme_constant_override("v_separation", 4)
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_grid)

	return vbox


func _build_enemies_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var hint := Label.new()
	hint.text = "Click to spawn enemy near you"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("#664433"))
	vbox.add_child(hint)

	_enemy_search = LineEdit.new()
	_enemy_search.placeholder_text    = "Search enemies..."
	_enemy_search.clear_button_enabled = true
	_enemy_search.add_theme_font_size_override("font_size", 12)
	_enemy_search.text_changed.connect(_on_enemy_search_changed)
	vbox.add_child(_enemy_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_enemy_grid = GridContainer.new()
	_enemy_grid.columns = 3
	_enemy_grid.add_theme_constant_override("h_separation", 6)
	_enemy_grid.add_theme_constant_override("v_separation", 6)
	_enemy_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_enemy_grid)

	return vbox


# ── Grid population ────────────────────────────────────────────────────────────

func _rebuild_item_grid() -> void:
	for child in _item_grid.get_children():
		child.queue_free()
	await _item_grid.get_tree().process_frame

	for item: ItemResource in _filtered_items:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var rc: Color = RARITY_COLORS.get(item.rarity, Color.WHITE) as Color
		var sty := StyleBoxFlat.new()
		sty.bg_color     = Color(0.10, 0.06, 0.14)
		sty.border_color = rc
		sty.set_border_width_all(2)
		sty.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", sty)

		var icon := TextureRect.new()
		icon.texture      = item.icon
		icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left  =  5; icon.offset_top    =  5
		icon.offset_right = -5; icon.offset_bottom = -5
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		slot.gui_input.connect(_on_item_slot_pressed.bind(item))
		slot.mouse_entered.connect(_show_item_tip.bind(item))
		slot.mouse_exited.connect(_hide_tip)
		_item_grid.add_child(slot)


func _rebuild_enemy_grid() -> void:
	for child in _enemy_grid.get_children():
		child.queue_free()
	await _enemy_grid.get_tree().process_frame

	for entry: Dictionary in _filtered_enemies:
		var col: Color = entry.get("color", Color.WHITE) as Color
		var btn := Button.new()
		btn.text = entry.get("name", "?") as String
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", col)

		var sty_n := StyleBoxFlat.new()
		sty_n.bg_color     = Color(0.08, 0.05, 0.12)
		sty_n.border_color = col.darkened(0.3)
		sty_n.set_border_width_all(1)
		sty_n.set_corner_radius_all(3)
		var sty_h := sty_n.duplicate() as StyleBoxFlat
		sty_h.bg_color     = col.darkened(0.55)
		sty_h.border_color = col
		sty_h.set_border_width_all(2)
		btn.add_theme_stylebox_override("normal", sty_n)
		btn.add_theme_stylebox_override("hover",  sty_h)
		btn.add_theme_stylebox_override("pressed", sty_h)

		btn.pressed.connect(_on_spawn_enemy.bind(entry.get("scene", "") as String))
		_enemy_grid.add_child(btn)


# ── Search ─────────────────────────────────────────────────────────────────────

func _on_item_search_changed(text: String) -> void:
	var q := text.to_lower().strip_edges()
	if q.is_empty():
		_filtered_items = _all_items.duplicate()
	else:
		_filtered_items = []
		for item: ItemResource in _all_items:
			if item.item_name.to_lower().contains(q) \
					or item.id.to_lower().contains(q) \
					or item.rarity.to_lower().contains(q) \
					or item.item_type.to_lower().contains(q):
				_filtered_items.append(item)
	_rebuild_item_grid()


func _on_enemy_search_changed(text: String) -> void:
	var q := text.to_lower().strip_edges()
	if q.is_empty():
		_filtered_enemies = _all_enemies.duplicate()
	else:
		_filtered_enemies = []
		for entry: Dictionary in _all_enemies:
			if (entry.get("name", "") as String).to_lower().contains(q):
				_filtered_enemies.append(entry)
	_rebuild_enemy_grid()


# ── Actions ────────────────────────────────────────────────────────────────────

func _on_item_slot_pressed(event: InputEvent, item: ItemResource) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var local := _find_local_player()
	if local == null:
		return
	var copy := ItemResource.from_id(item.id)
	if copy != null:
		local._inventory.add_item(copy)
	get_viewport().set_input_as_handled()


func _on_spawn_chest() -> void:
	var local := _find_local_player()
	if local == null:
		return
	var packed := load("res://scenes/items/chest_drop.tscn") as PackedScene
	if packed == null:
		return
	var chest: Node2D = packed.instantiate()
	get_tree().current_scene.add_child(chest)
	chest.global_position = local.global_position + Vector2(90, 0)


func _on_spawn_enemy(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var local := _find_local_player()
	if local == null:
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var enemy: Node2D = packed.instantiate()
	get_tree().current_scene.add_child(enemy)
	var angle := randf() * TAU
	enemy.global_position = local.global_position + Vector2(cos(angle), sin(angle)) * 160.0


func _find_local_player() -> PlayerController:
	if not multiplayer.has_multiplayer_peer():
		return _player
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController and (node as PlayerController).is_multiplayer_authority():
			return node as PlayerController
	return null


# ── Tooltip ────────────────────────────────────────────────────────────────────

func _build_tooltip() -> void:
	_card = PanelContainer.new()
	_card.visible      = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(190, 0)
	_card.z_index      = 150

	_card_style = StyleBoxFlat.new()
	_card_style.bg_color     = Color("#0C0008F4")
	_card_style.border_color = Color("#B0B0B0")
	_card_style.set_border_width_all(2)
	_card_style.set_corner_radius_all(5)
	_card_style.shadow_color = Color(0, 0, 0, 0.8)
	_card_style.shadow_size  = 10
	_card.add_theme_stylebox_override("panel", _card_style)
	_ui_root.add_child(_card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   8)
	m.add_theme_constant_override("margin_right",  8)
	m.add_theme_constant_override("margin_top",    6)
	m.add_theme_constant_override("margin_bottom", 6)
	_card.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	m.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_card_icon = TextureRect.new()
	_card_icon.custom_minimum_size = Vector2(34, 34)
	_card_icon.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_card_icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card_icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_card_icon)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	name_col.add_theme_constant_override("separation", 2)
	hbox.add_child(name_col)

	_card_name = Label.new()
	_card_name.add_theme_font_size_override("font_size", 12)
	_card_name.add_theme_color_override("font_color", Color("#CCCCCC"))
	_card_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_card_name.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_card_name)

	_card_rarity = Label.new()
	_card_rarity.add_theme_font_size_override("font_size", 10)
	_card_rarity.add_theme_color_override("font_color", Color("#888888"))
	_card_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_card_rarity)

	_card_sep = HSeparator.new()
	_card_sep.add_theme_color_override("color", Color("#333333"))
	_card_sep.visible = false
	vbox.add_child(_card_sep)

	_card_desc = Label.new()
	_card_desc.add_theme_font_size_override("font_size", 10)
	_card_desc.add_theme_color_override("font_color", Color("#888888"))
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_card_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_card_desc.visible       = false
	vbox.add_child(_card_desc)

	_card_stats = RichTextLabel.new()
	_card_stats.bbcode_enabled  = true
	_card_stats.fit_content     = true
	_card_stats.scroll_active   = false
	_card_stats.visible         = false
	_card_stats.add_theme_font_size_override("normal_font_size", 10)
	_card_stats.add_theme_color_override("default_color", Color("#CCCCCC"))
	_card_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_stats)


func _show_item_tip(item: ItemResource) -> void:
	if not is_instance_valid(_card) or item == null:
		return
	var rc: Color = RARITY_COLORS.get(item.rarity, Color.WHITE) as Color
	_card_style.border_color = rc
	_card_icon.texture = item.icon
	_card_name.text    = item.item_name
	_card_name.add_theme_color_override("font_color", rc)
	_card_rarity.text  = item.rarity.to_upper() + "  •  " + item.item_type.to_upper()
	_card_rarity.add_theme_color_override("font_color", rc.darkened(0.15))

	var has_desc := not item.description.is_empty()
	_card_desc.text    = item.description
	_card_desc.visible = has_desc
	_card_sep.visible  = has_desc

	var extras := ""
	for key: String in item.stat_bonuses:
		var v: float = float(item.stat_bonuses[key])
		extras += "[color=#44FF99]%s%g %s[/color]\n" \
			% ["+" if v >= 0.0 else "", v, key.capitalize()]
	for fx: Dictionary in item.passive_effects:
		if fx.get("type", "") == "hp_regen":
			extras += "[color=#FF6655]♥[/color] [color=#44FF99]+%g HP / %gs[/color]\n" \
				% [float(fx.get("amount", 1)), float(fx.get("interval", 5))]
		elif fx.get("type", "") == "dog_companion":
			extras += "[color=#88CCFF]Companion dog hunts nearby enemies[/color]\n"

	_card_stats.visible = not extras.is_empty()
	_card_stats.clear()
	if not extras.is_empty():
		_card_stats.append_text(extras.strip_edges())

	_card.visible = true
	_card.reset_size()
	_position_card()


func _hide_tip() -> void:
	if is_instance_valid(_card):
		_card.visible = false


func _position_card() -> void:
	var mp  := get_viewport().get_mouse_position()
	var vp  := get_viewport().get_visible_rect().size
	var cs  := _card.size
	var x   := mp.x + 16.0
	var y   := mp.y - 8.0
	if x + cs.x > vp.x - 4.0: x = mp.x - cs.x - 8.0
	if y + cs.y > vp.y - 4.0: y = vp.y - cs.y - 4.0
	if y < 4.0: y = 4.0
	_card.global_position = Vector2(x, y)


func _process(_delta: float) -> void:
	if is_instance_valid(_card) and _card.visible:
		_position_card()


func _hsep(col: Color) -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_color_override("color", col)
	return s
