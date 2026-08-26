extends Area2D

signal checkpoint_activated(respawn_position: Vector2)

const FLAME_COLOR_INACTIVE := Color(0.55, 0.75, 0.95, 0.85)
const FLAME_COLOR_ACTIVE := Color(0.85, 0.98, 1.0, 1.0)
const GLOW_COLOR_INACTIVE := Color(0.55, 0.75, 0.95, 0.25)
const GLOW_COLOR_ACTIVE := Color(0.85, 0.98, 1.0, 0.5)

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _activated:
		return
	if not body.is_in_group("player"):
		return

	_activated = true
	_set_active_appearance()

	var respawn_position: Vector2 = $RespawnPoint.global_position
	checkpoint_activated.emit(respawn_position)

	if body.has_method("set_respawn_position"):
		body.set_respawn_position(respawn_position)


func _set_active_appearance() -> void:
	$Flame.color = FLAME_COLOR_ACTIVE
	$Glow.color = GLOW_COLOR_ACTIVE
