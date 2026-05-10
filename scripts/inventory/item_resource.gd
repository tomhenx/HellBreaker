class_name ItemResource
extends Resource

@export var id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var item_type: String = "misc"  # weapon, head, chest, legs, hands, feet, ring, necklace, offhand, consumable, misc
@export var rarity: String = "common"   # common, uncommon, rare, epic, legendary
@export var equip_slot: String = ""     # weapon, offhand, head, chest, legs, hands, feet, necklace, ring1/ring2
@export var weapon_id: String = ""      # WeaponResource id, filled for weapon-type items
@export var is_two_handed: bool = false
@export var max_stack: int = 1
@export var icon: Texture2D = null
@export var stat_bonuses: Dictionary = {}
@export var passive_effects: Array = []

const ITEMS_PATH := "res://data/items/items.json"


static func from_id(item_id: String) -> ItemResource:
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		push_error("ItemResource: cannot open %s" % ITEMS_PATH)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return null
	var items: Dictionary = (parsed as Dictionary).get("items", {})
	if not items.has(item_id):
		push_error("ItemResource: unknown item id '%s'" % item_id)
		return null
	return _from_dict(item_id, items[item_id])


static func _from_dict(iid: String, d: Dictionary) -> ItemResource:
	var r := ItemResource.new()
	r.id          = iid
	r.item_name   = d.get("name", iid)
	r.description = d.get("description", "")
	r.item_type   = d.get("type", "misc")
	r.rarity      = d.get("rarity", "common")
	r.equip_slot    = d.get("equip_slot", "")
	r.weapon_id     = d.get("weapon_id", "")
	r.is_two_handed = d.get("is_two_handed", false)
	r.max_stack     = d.get("max_stack", 1)
	r.stat_bonuses   = d.get("stat_bonuses", {})
	r.passive_effects = d.get("passive_effects", [])
	var icon_path: String = d.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		r.icon = load(icon_path)
	return r
