## Manages layered character visuals: body sprite + weapon attachment.
## Driven by direction + animation name; caller never touches Sprite2D directly.
class_name CharacterVisual
extends Node2D

# Sprite sheet layout produced by PixelLab:
# 8 rows (one per direction), N columns (frames per animation).
# Direction order: S, SW, W, NW, N, NE, E, SE  (row 0-7)
const DIR_ROW := {
	"south":      0,
	"south-west": 1,
	"west":        2,
	"north-west": 3,
	"north":       4,
	"north-east": 5,
	"east":        6,
	"south-east": 7,
}

# Each animation entry: { "texture": Texture2D, "frames": int, "fps": float }
var _animations: Dictionary = {}
var _current_anim: String = ""
var _current_dir:  String = "south"
var _frame:        int    = 0
var _timer:        float  = 0.0

var _body:         Sprite2D
var _weapon:       Sprite2D
var _weapon_anchor: Marker2D

# Weapon offsets per direction (pixels, tuned after art arrives)
const WEAPON_OFFSETS := {
	"south":      Vector2( 6,  4),
	"south-west": Vector2(-4,  4),
	"west":        Vector2(-8,  0),
	"north-west": Vector2(-4, -6),
	"north":       Vector2(-6, -6),
	"north-east": Vector2( 4, -6),
	"east":        Vector2( 8,  0),
	"south-east": Vector2( 4,  4),
}


func _ready() -> void:
	_body          = $Body
	_weapon        = $WeaponAnchor/Weapon
	_weapon_anchor = $WeaponAnchor


func _process(delta: float) -> void:
	if _animations.is_empty() or _current_anim == "":
		return
	var anim: Dictionary = _animations[_current_anim]
	_timer += delta
	if _timer >= 1.0 / anim["fps"]:
		_timer = 0.0
		_frame = (_frame + 1) % anim["frames"]
		_update_sprite()


# ── Public API ────────────────────────────────────────────────────────────────

func get_current_anim() -> String: return _current_anim
func get_current_dir()  -> String: return _current_dir


func register_animation(name: String, texture: Texture2D, frames: int, fps: float = 8.0) -> void:
	_animations[name] = {"texture": texture, "frames": frames, "fps": fps}


func play(anim_name: String, reset: bool = false) -> void:
	if not _animations.has(anim_name):
		return
	if _current_anim == anim_name and not reset:
		return
	_current_anim = anim_name
	_frame = 0
	_timer = 0.0
	_update_sprite()


func set_direction(dir: String) -> void:
	if _current_dir == dir:
		return
	_current_dir = dir
	_weapon_anchor.position = WEAPON_OFFSETS.get(dir, Vector2.ZERO)
	_update_sprite()


func equip_weapon(texture: Texture2D) -> void:
	_weapon.texture = texture
	_weapon.visible = texture != null


func unequip_weapon() -> void:
	_weapon.texture = null
	_weapon.visible = false


# ── Internal ──────────────────────────────────────────────────────────────────

func _update_sprite() -> void:
	if _current_anim == "" or not _animations.has(_current_anim):
		return
	var anim: Dictionary = _animations[_current_anim]
	var tex: Texture2D   = anim["texture"]
	if not is_instance_valid(tex):
		return
	var row: int = DIR_ROW.get(_current_dir, 0)
	_body.texture         = tex
	_body.region_enabled  = true
	var fw: int = tex.get_width()  / anim["frames"]
	var fh: int = tex.get_height() / 8
	_body.region_rect = Rect2(
		_frame * fw,
		row    * fh,
		fw, fh
	)
