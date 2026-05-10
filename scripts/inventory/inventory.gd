class_name Inventory
extends Node

const SLOT_COUNT      := 12
const MAX_BONUS_SLOTS := 4
const EQUIP_SLOTS := ["weapon", "offhand", "head", "chest", "legs", "hands", "feet", "necklace", "ring1", "ring2"]

signal inventory_changed
signal equipment_changed(slot_id: String)

# Array of ItemResource or null, length = SLOT_COUNT + MAX_BONUS_SLOTS (always 16)
var items: Array = []
# Dictionary: slot_id -> ItemResource or null
var equipped: Dictionary = {}

var _bonus_slots: int = 0


func _ready() -> void:
	items.resize(SLOT_COUNT + MAX_BONUS_SLOTS)
	items.fill(null)
	for slot in EQUIP_SLOTS:
		equipped[slot] = null


func slot_count() -> int:
	return SLOT_COUNT + _bonus_slots


func set_bonus_slots(n: int) -> void:
	var clamped := clampi(n, 0, MAX_BONUS_SLOTS)
	if clamped == _bonus_slots:
		return
	_bonus_slots = clamped
	inventory_changed.emit()


# ── Inventory slots ───────────────────────────────────────────────────────────

func add_item(item: ItemResource) -> bool:
	for i in slot_count():
		if items[i] == null:
			items[i] = item
			inventory_changed.emit()
			return true
	return false  # full


func remove_item(slot_idx: int) -> ItemResource:
	var item := items[slot_idx] as ItemResource
	items[slot_idx] = null
	inventory_changed.emit()
	return item


func swap_inv(from_idx: int, to_idx: int) -> void:
	var tmp: ItemResource = items[to_idx]
	items[to_idx] = items[from_idx]
	items[from_idx] = tmp
	inventory_changed.emit()


func find_item(item_id: String) -> int:
	for i in slot_count():
		if items[i] != null and (items[i] as ItemResource).id == item_id:
			return i
	return -1


# ── Equipment slots ───────────────────────────────────────────────────────────

func equip_from_inv(inv_idx: int, slot_id: String) -> void:
	if not equipped.has(slot_id):
		return
	var item := items[inv_idx] as ItemResource
	if item == null:
		return
	var old: ItemResource = equipped[slot_id]
	equipped[slot_id] = item
	items[inv_idx]    = old  # swap old equipped back (may be null)
	inventory_changed.emit()
	equipment_changed.emit(slot_id)


func unequip_slot(slot_id: String) -> bool:
	var item := equipped.get(slot_id, null) as ItemResource
	if item == null:
		return true
	if not add_item(item):
		return false  # inventory full
	equipped[slot_id] = null
	equipment_changed.emit(slot_id)
	return true


func move_equip_to_inv(slot_id: String, inv_idx: int) -> void:
	if not equipped.has(slot_id):
		return
	var equip_item: ItemResource = equipped.get(slot_id, null)
	var inv_item: ItemResource = items[inv_idx]
	equipped[slot_id] = inv_item
	items[inv_idx]    = equip_item
	inventory_changed.emit()
	equipment_changed.emit(slot_id)


func swap_equip(from_slot: String, to_slot: String) -> void:
	var tmp: ItemResource = equipped.get(to_slot, null)
	equipped[to_slot]  = equipped.get(from_slot, null)
	equipped[from_slot] = tmp
	inventory_changed.emit()
	equipment_changed.emit(from_slot)
	equipment_changed.emit(to_slot)


func can_equip(item: ItemResource, slot_id: String) -> bool:
	if item == null or item.equip_slot.is_empty():
		return false
	if item.equip_slot == slot_id:
		return true
	if item.equip_slot == "ring" and (slot_id == "ring1" or slot_id == "ring2"):
		return true
	# One-handed weapon can go into the offhand slot
	if item.equip_slot == "weapon" and slot_id == "offhand":
		if item.is_two_handed:
			return false
		var main_item := equipped.get("weapon", null) as ItemResource
		if main_item != null and main_item.is_two_handed:
			return false
		return true
	return false
