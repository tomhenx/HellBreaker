class_name ChestScreen
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

# Spin timing
const REEL_FIRST_STOP   := 2.2   # first reel stops after this many seconds
const REEL_STOP_STEP    := 0.45  # each subsequent reel stops this much later
const SPIN_FAST_RATE    := 0.055 # seconds between icon changes (fast phase)
const SPIN_SLOW_RATE    := 0.30  # seconds between icon changes (slow phase)

# Rewards: { "peer_id_str" -> "item_id" }
var _rewards:      Dictionary       = {}
var _local_peer:   int              = 1
var _server_ctrl:  PlayerController = null
var _local_player: PlayerController = null
var _inventory:    Inventory        = null
var _stats:        StatsResource    = null

# Slot machine state
var _reels:           Array   = []   # Array of per-reel Dictionaries
var _item_pool:       Array   = []   # Array[ItemResource] for cycling icons
var _spin_elapsed:    float   = 0.0
var _spinning_active: bool    = false
var _all_stopped:     bool    = false

# Audio
var _audio_tick: AudioStreamPlayer = null
var _audio_win:  AudioStreamPlayer = null

# Bottom bar
var _waiting_label: Label  = null
var _ready_btn:     Button = null

# Inventory display
var _inv_panels:        Array      = []
var _inv_icons:         Array      = []
var _inv_wraps:         Array      = []
var _equip_panels:      Dictionary = {}
var _equip_icons:       Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _all_inv_slots:     Array      = []

# Tooltip
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
var _drag_source:        Dictionary = {}
var _drag_ghost:         Control    = null
var _relic_anim_sprites: Dictionary = {}

var _ui_root: Control = null


func init(rewards: Dictionary, local_player: PlayerController,
		server_ctrl: PlayerController) -> void:
	_rewards      = rewards
	_local_player = local_player
	_server_ctrl  = server_ctrl
	_local_peer   = local_player.get_multiplayer_authority() \
					if multiplayer.has_multiplayer_peer() else 1
	_inventory    = local_player._inventory if is_instance_valid(local_player) else null
	_stats        = local_player.stats      if is_instance_valid(local_player) else null
	_load_item_pool()
	_build_ui()
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh_inventory)
		_inventory.equipment_changed.connect(func(_s: String): _refresh_inventory())
	_spinning_active = true


func _load_item_pool() -> void:
	var f := FileAccess.open("res://data/items/items.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	var items_data: Dictionary = (parsed as Dictionary).get("items", {})
	for id: String in items_data.keys():
		var item := ItemResource.from_id(id)
		if item != null and item.icon != null:
			_item_pool.append(item)
	_item_pool.shuffle()
	if _item_pool.is_empty():
		return
	# Ensure pool is large enough for smooth cycling
	while _item_pool.size() < 20:
		_item_pool.append_array(_item_pool.duplicate())


func _process(delta: float) -> void:
	if not _spinning_active:
		return
	_spin_elapsed += delta
	var all_done := true
	for i in _reels.size():
		var reel: Dictionary = _reels[i]
		if bool(reel.get("stopped", false)):
			continue
		all_done = false
		if _spin_elapsed >= float(reel.get("stop_time", 999.0)):
			_stop_reel(i)
		else:
			_tick_reel(i, delta)
	if all_done and not _all_stopped:
		_on_all_stopped()


func _tick_reel(idx: int, delta: float) -> void:
	var reel: Dictionary = _reels[idx]
	reel["cycle_timer"] = float(reel["cycle_timer"]) - delta
	if float(reel["cycle_timer"]) > 0.0:
		return
	var stop_time: float = float(reel.get("stop_time", 999.0))
	var t := clampf(_spin_elapsed / stop_time, 0.0, 1.0)
	var rate := lerpf(SPIN_FAST_RATE, SPIN_SLOW_RATE, t * t)
	reel["cycle_timer"] = rate
	var pool_idx: int = (int(reel.get("cycle_idx", 0)) + 1) % _item_pool.size()
	reel["cycle_idx"] = pool_idx
	var pool_item: ItemResource = _item_pool[pool_idx] if pool_idx < _item_pool.size() else null
	var icon: TextureRect = reel.get("icon") as TextureRect
	if is_instance_valid(icon):
		icon.texture = pool_item.icon if pool_item != null else null
	_reels[idx] = reel
	if is_instance_valid(_audio_tick):
		_audio_tick.pitch_scale = lerpf(1.15, 0.80, t * t)
		if not _audio_tick.playing:
			_audio_tick.play()


func _stop_reel(idx: int) -> void:
	var reel: Dictionary = _reels[idx]
	reel["stopped"] = true
	_reels[idx] = reel

	var item: ItemResource = reel.get("item") as ItemResource
	var icon: TextureRect  = reel.get("icon") as TextureRect
	if is_instance_valid(icon):
		icon.texture = item.icon if item != null else null

	var nl: Label = reel.get("name_label") as Label
	var rl: Label = reel.get("rarity_label") as Label
	if item != null:
		var rc: Color = RARITY_COLORS.get(item.rarity, Color.WHITE) as Color
		if is_instance_valid(nl):
			nl.text = item.item_name
			nl.add_theme_color_override("font_color", rc)
			nl.visible = true
		if is_instance_valid(rl):
			rl.text = item.rarity.to_upper()
			rl.add_theme_color_override("font_color", rc.darkened(0.1))
			rl.visible = true

	var panel: Panel = reel.get("panel") as Panel
	if is_instance_valid(panel):
		var tw := panel.create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate", Color(2.2, 1.8, 0.2, 1.0), 0.08)
		tw.chain().tween_property(panel, "modulate", Color.WHITE, 0.5)

	if is_instance_valid(_audio_win):
		_audio_win.play()

	var peer_id: int = int(reel.get("peer_id", 1))
	if peer_id == _local_peer and item != null and is_instance_valid(panel):
		_add_claim_overlay(idx, panel, item)


func _add_claim_overlay(idx: int, panel: Panel, item: ItemResource) -> void:
	var btn := Button.new()
	btn.text = "CLAIM"
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_font_size_override("font_size", 13)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	sty.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sty)
	var hover_sty := StyleBoxFlat.new()
	hover_sty.bg_color = Color(0.85, 0.62, 0.0, 0.80)
	hover_sty.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover_sty)
	btn.add_theme_color_override("font_color", Color("#FFD700"))
	btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	panel.add_child(btn)
	var reel: Dictionary = _reels[idx]
	reel["claim_btn"] = btn
	_reels[idx] = reel
	btn.pressed.connect(_on_claim_pressed.bind(idx))


func _on_claim_pressed(idx: int) -> void:
	if _inventory == null:
		return
	var reel: Dictionary = _reels[idx]
	var item: ItemResource = reel.get("item") as ItemResource
	if item == null or bool(reel.get("claimed", false)):
		return
	_inventory.add_item(item)
	reel["claimed"] = true
	_reels[idx] = reel

	var btn: Button = reel.get("claim_btn") as Button
	if is_instance_valid(btn):
		btn.text = "✓"
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var claimed_sty := StyleBoxFlat.new()
		claimed_sty.bg_color = Color(0.0, 0.6, 0.0, 0.55)
		claimed_sty.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal",   claimed_sty)
		btn.add_theme_stylebox_override("hover",    claimed_sty)
		btn.add_theme_stylebox_override("disabled", claimed_sty)
		btn.add_theme_color_override("font_color", Color("#AAFFAA"))
		var panel: Panel = reel.get("panel") as Panel
		if is_instance_valid(panel):
			var tw := panel.create_tween().set_parallel(true)
			tw.tween_property(panel, "modulate", Color(0.6, 2.0, 0.6, 1.0), 0.10)
			tw.chain().tween_property(panel, "modulate", Color.WHITE, 0.40)
	_refresh_inventory()


func _on_all_stopped() -> void:
	_all_stopped    = true
	_spinning_active = false
	if is_instance_valid(_waiting_label):
		_waiting_label.text = "Claim your reward — or skip and click READY"
	if is_instance_valid(_ready_btn):
		_ready_btn.disabled = false


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

func _build_ui() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 10

	_audio_tick = AudioStreamPlayer.new()
	_audio_win  = AudioStreamPlayer.new()
	_audio_tick.process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_win.process_mode  = Node.PROCESS_MODE_ALWAYS
	_audio_tick.volume_db    = -6.0
	_audio_win.volume_db     = -3.0
	var tick_stream := load("res://assets/audio/sfx/slot_tick.mp3") as AudioStream
	var win_stream  := load("res://assets/audio/sfx/slot_win.mp3")  as AudioStream
	if tick_stream != null: _audio_tick.stream = tick_stream
	if win_stream  != null: _audio_win.stream  = win_stream
	add_child(_audio_tick)
	add_child(_audio_win)

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
	title.text                 = "  TREASURE CHEST  "
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#FFD700"))
	vbox.add_child(title)
	vbox.add_child(_hsep(Color("#FFD70055")))

	vbox.add_child(_build_reels_section())
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


func _build_reels_section() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	var sub := Label.new()
	sub.text                  = "Each player spins a reward..."
	sub.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("#888888"))
	sub.add_theme_font_size_override("font_size", 11)
	wrap.add_child(sub)

	var reels_row := HBoxContainer.new()
	reels_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reels_row.add_theme_constant_override("separation", 16)
	wrap.add_child(reels_row)

	var peer_order: Array[int] = []
	if not multiplayer.has_multiplayer_peer():
		peer_order.append(1)
	else:
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node is PlayerController:
				peer_order.append((node as PlayerController).get_multiplayer_authority())
		peer_order.sort()

	for i in peer_order.size():
		var peer_id: int = peer_order[i]
		var item_id: String = _rewards.get(str(peer_id), "")
		var item := ItemResource.from_id(item_id)

		var reel_vbox := VBoxContainer.new()
		reel_vbox.add_theme_constant_override("separation", 3)
		reel_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		reels_row.add_child(reel_vbox)

		var player_lbl := Label.new()
		player_lbl.text = "Player %d" % peer_id \
			if multiplayer.has_multiplayer_peer() else "You"
		if peer_id == _local_peer:
			player_lbl.text += "  (you)"
			player_lbl.add_theme_color_override("font_color", Color("#FFD700"))
		else:
			player_lbl.add_theme_color_override("font_color", Color("#AAAAAA"))
		player_lbl.add_theme_font_size_override("font_size", 11)
		player_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reel_vbox.add_child(player_lbl)

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(72, 72)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sty := StyleBoxFlat.new()
		sty.bg_color     = Color(0.05, 0.03, 0.08)
		sty.border_color = Color("#FFD700")
		sty.set_border_width_all(2)
		sty.set_corner_radius_all(4)
		sty.shadow_color = Color(0, 0, 0, 0.6)
		sty.shadow_size  = 6
		panel.add_theme_stylebox_override("panel", sty)
		reel_vbox.add_child(panel)

		var icon := TextureRect.new()
		icon.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left    =  8;  icon.offset_top    =  8
		icon.offset_right   = -8;  icon.offset_bottom = -8
		panel.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text                 = ""
		name_lbl.visible              = false
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_lbl.custom_minimum_size = Vector2(80, 0)
		reel_vbox.add_child(name_lbl)

		var rarity_lbl := Label.new()
		rarity_lbl.text                 = ""
		rarity_lbl.visible              = false
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_lbl.add_theme_font_size_override("font_size", 9)
		rarity_lbl.add_theme_color_override("font_color", Color("#888888"))
		reel_vbox.add_child(rarity_lbl)

		var reel_data := {
			"peer_id":      peer_id,
			"item":         item,
			"icon":         icon,
			"panel":        panel,
			"name_label":   name_lbl,
			"rarity_label": rarity_lbl,
			"stop_time":    REEL_FIRST_STOP + i * REEL_STOP_STEP,
			"stopped":      false,
			"cycle_timer":  randf_range(0.0, SPIN_FAST_RATE),
			"cycle_idx":    randi() % maxi(1, _item_pool.size()),
		}
		_reels.append(reel_data)

		# Seed first icon
		if not _item_pool.is_empty():
			var first_item: ItemResource = _item_pool[int(reel_data["cycle_idx"])]
			icon.texture = first_item.icon if first_item != null else null

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
	_waiting_label.text                  = "Spinning...  — click READY when done"
	_waiting_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_color_override("font_color", Color("#AAAAAA"))
	hbox.add_child(_waiting_label)

	_ready_btn = Button.new()
	_ready_btn.text                = "READY"
	_ready_btn.custom_minimum_size = Vector2(120, 36)
	_ready_btn.add_theme_font_size_override("font_size", 15)
	_ready_btn.disabled            = true
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
	icon.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left   =  5;  icon.offset_top    =  5
	icon.offset_right  = -5;  icon.offset_bottom = -5
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
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
	_card_icon.expand_mode    = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_card_icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	_card_stats.bbcode_enabled  = true
	_card_stats.fit_content     = true
	_card_stats.scroll_active   = false
	_card_stats.visible         = false
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

	var rc: Color = RARITY_COLORS.get(item.rarity, RARITY_COLORS["common"]) as Color
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
	var dt: String  = _drag_source.get("type", "")
	var dr: Variant = _drag_source.get("ref", null)
	var active      := _inventory.slot_count()

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
		var sn:  String = rd[0]
		var pn:  String = rd[1]
		var fmt: String = rd[2]
		var lbl: Label  = _stat_value_labels.get(sn, null)
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
					"int":     lbl.text = "%d"    % int(float(raw))
					"float2":  lbl.text = "%.2f"  % float(raw)
					"float1x": lbl.text = "%.1fx" % float(raw)
					"pct":     lbl.text = "%d%%"  % int(float(raw) * 100.0)
					_:         lbl.text = str(raw)


# ── Network callbacks ──────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	_ready_btn.disabled = true
	_ready_btn.text     = "WAITING..."
	if not multiplayer.has_multiplayer_peer():
		if is_instance_valid(_server_ctrl):
			_server_ctrl._process_chest_ready(_local_peer)
	else:
		_server_ctrl.rpc_chest_ready.rpc_id(1)


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
