class_name StatsResource
extends Resource

@export var max_hp: float = 100.0
@export var damage: float = 20.0
@export var attack_speed: float = 1.0
@export var attack_range: float = 300.0
@export var move_speed: float = 160.0
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 2.0
@export var charisma: int = 1
@export var dodge_speed: float = 320.0
@export var dodge_duration: float = 0.18
@export var dodge_cooldown: float = 0.8
@export var projectile_speed: float = 400.0
@export var iframes_duration: float = 0.5


static func from_json(path: String) -> StatsResource:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("StatsResource: cannot open %s" % path)
		return StatsResource.new()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("StatsResource: invalid JSON at %s" % path)
		return StatsResource.new()
	var res := StatsResource.new()
	var d: Dictionary = parsed
	if d.has("max_hp"):          res.max_hp          = float(d["max_hp"])
	if d.has("damage"):          res.damage          = float(d["damage"])
	if d.has("attack_speed"):    res.attack_speed    = float(d["attack_speed"])
	if d.has("attack_range"):    res.attack_range    = float(d["attack_range"])
	if d.has("move_speed"):      res.move_speed      = float(d["move_speed"])
	if d.has("crit_chance"):     res.crit_chance     = float(d["crit_chance"])
	if d.has("crit_multiplier"): res.crit_multiplier = float(d["crit_multiplier"])
	if d.has("charisma"):        res.charisma        = int(d["charisma"])
	if d.has("dodge_speed"):     res.dodge_speed     = float(d["dodge_speed"])
	if d.has("dodge_duration"):  res.dodge_duration  = float(d["dodge_duration"])
	if d.has("dodge_cooldown"):  res.dodge_cooldown  = float(d["dodge_cooldown"])
	if d.has("projectile_speed"):res.projectile_speed= float(d["projectile_speed"])
	if d.has("iframes_duration"):res.iframes_duration= float(d["iframes_duration"])
	return res
