class_name MerchantNPC
extends StaticBody2D

const DIALOGUE_SCENE := "res://scenes/ui/merchant_dialogue.tscn"

var _interact_hint: Label
var _local_player_in_range := false
var _dialogue_open := false


func _ready() -> void:
	_interact_hint = $InteractHint
	_interact_hint.visible = false
	$InteractArea.body_entered.connect(_on_body_entered)
	$InteractArea.body_exited.connect(_on_body_exited)
	_style_labels()


func _style_labels() -> void:
	for lbl: Label in [$NameLabel, $InteractHint]:
		lbl.add_theme_font_size_override("font_size", 4)
		lbl.add_theme_color_override("font_outline_color", Color("#000000"))
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	$NameLabel.add_theme_color_override("font_color", Color("#CC6600"))
	$InteractHint.add_theme_color_override("font_color", Color("#FFDD88"))


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_open or not _local_player_in_range:
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_open_dialogue()


func _on_body_entered(body: Node2D) -> void:
	if not _is_local_player(body):
		return
	_local_player_in_range = true
	_interact_hint.visible = not _dialogue_open


func _on_body_exited(body: Node2D) -> void:
	if not _is_local_player(body):
		return
	_local_player_in_range = false
	_interact_hint.visible = false


func _is_local_player(body: Node2D) -> bool:
	if not body is PlayerController:
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return body.is_multiplayer_authority()


func _open_dialogue() -> void:
	_dialogue_open = true
	_interact_hint.visible = false
	var dlg := (load(DIALOGUE_SCENE) as PackedScene).instantiate() as MerchantDialogue
	get_tree().current_scene.get_node("UILayer").add_child(dlg)
	dlg.closed.connect(_on_dialogue_closed)


func _on_dialogue_closed() -> void:
	_dialogue_open = false
	if _local_player_in_range:
		_interact_hint.visible = true
