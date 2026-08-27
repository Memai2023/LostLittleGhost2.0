extends Node

## Purely cosmetic reaction to the checkpoint's own "checkpoint_activated"
## signal -- does not touch respawn-position logic in any way, so the
## gameplay trigger keeps working even if this node or its tween fails.

@export var portal_sprite_path: NodePath = ^"../PortalSprite"

const PULSE_SCALE := 1.3
const SETTLE_SCALE := 1.12
const ACTIVE_TINT := Color(1.35, 1.3, 1.05, 1.0)

var _activated: bool = false


func _ready() -> void:
	var checkpoint: Node = get_parent()
	if checkpoint.has_signal("checkpoint_activated"):
		checkpoint.checkpoint_activated.connect(_on_activated)


func _on_activated(_respawn_position: Vector2) -> void:
	if _activated:
		return
	_activated = true

	var portal_sprite: Sprite2D = get_node_or_null(portal_sprite_path)
	if portal_sprite == null:
		return

	var base_scale: Vector2 = portal_sprite.scale
	var tween := create_tween()
	tween.tween_property(portal_sprite, "scale", base_scale * PULSE_SCALE, 0.15)
	tween.tween_property(portal_sprite, "scale", base_scale * SETTLE_SCALE, 0.25)
	tween.parallel().tween_property(portal_sprite, "modulate", ACTIVE_TINT, 0.4)
